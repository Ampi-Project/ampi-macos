// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AmpiCore

/// Deterministic audio substitute that records transport calls without opening audio output.
@MainActor private final class FakeAudioBackend: AudioBackend {
    /// Simulated track length in seconds, used to check seek clamping.
    var duration = 120.0
    /// Simulated offset in seconds, retained during pause and reset during load/stop.
    var position = 0.0
    /// Simulated output gain inspected by the volume bounds test.
    var volume: Float = 0.7
    /// Last successfully loaded file, used to detect unwanted replacement after failures.
    var loadedURL: URL?
    /// Successful load count, used to verify resume and replay reuse the loaded track.
    var loadCount = 0
    /// Whether the fake currently claims to produce output.
    var playing = false
    /// Configurable start result used to simulate an audio-output failure.
    var canStart = true
    /// Loads a fake file, rejecting the corrupt fixture before mutating existing state.
    func load(_ url: URL) throws {
        if url.lastPathComponent == "corrupt.wav" { throw PlaybackError.couldNotStart }
        loadedURL = url; position = 0; loadCount += 1
    }
    /// Records the configured start result and returns it to the session.
    func play() -> Bool { playing = canStart; return canStart }
    /// Suspends simulated output without changing its offset.
    func pause() { playing = false }
    /// Stops simulated output and rewinds to zero seconds.
    func stop() { playing = false; position = 0 }
}

/// Verifies queue/transport behavior and failure recovery independently of native audio.
final class PlaybackSessionTests: XCTestCase {
    /// An empty queue must leave transport stopped and never start the backend.
    func testEmptyQueueDoesNotStartPlayback() async throws {
        try await MainActor.run {
            /// Fake output whose start state proves no track was played.
            let backend = FakeAudioBackend()
            /// Empty session under test.
            let session = PlaybackSession(backend: backend)
            try session.togglePlayback()
            XCTAssertNil(session.currentTrack)
            XCTAssertFalse(backend.playing)
            XCTAssertEqual(session.state, .stopped)
        }
    }

    /// Pause/resume preserves offset, and stop/replay reuses the already loaded track.
    func testPauseResumeAndStopReuseTheLoadedTrack() async throws {
        try await MainActor.run {
            /// Fake output recording the number of successful track loads.
            let backend = FakeAudioBackend()
            /// Session exercised through pause, resume, stop, and replay.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/tmp/track.wav")])
            try session.togglePlayback()
            session.seek(to: 30)
            try session.togglePlayback()
            XCTAssertEqual(session.state, .paused)
            XCTAssertEqual(session.position, 30)
            try session.togglePlayback()
            XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(backend.loadCount, 1)
            session.stop()
            XCTAssertEqual(session.position, 0)
            try session.togglePlayback()
            XCTAssertEqual(backend.loadCount, 1)
        }
    }

    /// Failure to load a replacement must preserve the current track, offset, and output.
    func testCorruptReplacementPreservesCurrentPlayback() async throws {
        try await MainActor.run {
            /// Fake output configured to reject the specially named corrupt fixture.
            let backend = FakeAudioBackend()
            /// Session containing a playable entry followed by a failing replacement.
            let session = PlaybackSession(backend: backend)
            /// Successfully loaded fixture URL expected to remain selected after failure.
            let good = URL(fileURLWithPath: "/tmp/good.wav")
            session.enqueue([good, URL(fileURLWithPath: "/tmp/corrupt.wav")])
            try session.play(index: 0)
            session.seek(to: 45)
            XCTAssertThrowsError(try session.play(index: 1))
            XCTAssertEqual(session.currentTrack?.url, good)
            XCTAssertEqual(backend.loadedURL, good)
            XCTAssertEqual(session.position, 45)
            XCTAssertEqual(session.state, .playing)
            XCTAssertTrue(backend.playing)
        }
    }

    /// Successful completion advances within the queue and stops at its final entry.
    func testTrackCompletionAdvancesAndStopsAtQueueEnd() async throws {
        try await MainActor.run {
            /// Two-entry session receiving simulated successful completion callbacks.
            let session = PlaybackSession(backend: FakeAudioBackend())
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav"), URL(fileURLWithPath: "/tmp/two.wav")])
            try session.play(index: 0)
            session.finished(successfully: true)
            XCTAssertEqual(session.selectedIndex, 1)
            XCTAssertEqual(session.state, .playing)
            session.finished(successfully: true)
            XCTAssertEqual(session.state, .stopped)
        }
    }

    /// Previous first restarts an advanced track, then moves back when already at its start.
    func testPreviousRestartsCurrentTrackBeforeMovingBack() async throws {
        try await MainActor.run {
            /// Fake output exposing its playback position for restart checks.
            let backend = FakeAudioBackend()
            /// Two-entry session used to exercise both Previous behaviors.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav"), URL(fileURLWithPath: "/tmp/two.wav")])
            try session.play(index: 1)
            session.seek(to: 30)
            try session.previous()
            XCTAssertEqual(session.selectedIndex, 1)
            XCTAssertEqual(session.position, 0)
            try session.previous()
            XCTAssertEqual(session.selectedIndex, 0)
        }
    }

    /// Seek and gain clamp finite out-of-range values and ignore NaN/infinite input.
    func testSeekAndVolumeRejectNonFiniteAndClampOutOfRangeValues() async throws {
        try await MainActor.run {
            /// Loaded session whose fake duration defines the upper seek bound.
            let session = PlaybackSession(backend: FakeAudioBackend())
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav")])
            try session.play(index: 0)
            session.seek(to: 999)
            XCTAssertEqual(session.position, 120)
            session.seek(to: .nan)
            XCTAssertEqual(session.position, 120)
            session.seek(to: -5)
            XCTAssertEqual(session.position, 0)
            session.setVolume(2)
            XCTAssertEqual(session.volume, 1)
            session.setVolume(.infinity)
            XCTAssertEqual(session.volume, 1)
            session.setVolume(-1)
            XCTAssertEqual(session.volume, 0)
        }
    }

    /// A failed start must throw and leave the session paused rather than reporting playback.
    func testFailedAudioStartDoesNotClaimPlaying() async throws {
        try await MainActor.run {
            /// Fake output configured below to fail its start attempt.
            let backend = FakeAudioBackend()
            backend.canStart = false
            /// Session expected to report the injected output failure.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav")])
            XCTAssertThrowsError(try session.play(index: 0))
            XCTAssertEqual(session.state, .paused)
            XCTAssertFalse(backend.playing)
        }
    }
}
