// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AmpiCore

/// Deterministic audio substitute that records transport calls without opening audio output.
@MainActor private final class FakeAudioBackend: EqualizerAudioBackend {
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
    /// Retained EQ settings verify that queue editing leaves DSP unchanged.
    var settings = EqualizerSettings()
    /// Stop calls detect unintended output interruption during noncurrent edits.
    var stopCount = 0
    /// Records the bounded curve without changing fake transport or output volume.
    func applyEqualizer(_ settings: EqualizerSettings) { self.settings = settings }
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
    func stop() { playing = false; position = 0; stopCount += 1 }
}

/// Verifies queue/transport behavior and failure recovery independently of native audio.
final class PlaybackSessionTests: XCTestCase {
    /// Removing either side of the loaded entry preserves its identity, offset, state, volume, and EQ.
    func testRemovingOtherEntriesPreservesDuplicateLoadedIdentity() async throws {
        try await MainActor.run {
            /// Each transport state is preserved when the removed entry is not loaded.
            for state in [PlaybackSession.State.playing, .paused, .stopped] {
                /// Backend counts decoder and stop calls independently of presentation.
                let backend = FakeAudioBackend()
                /// Duplicate URLs must retain distinct queue identities.
                let session = PlaybackSession(backend: backend)
                session.enqueue([URL(fileURLWithPath: "/first.wav"), URL(fileURLWithPath: "/same.wav"),
                                 URL(fileURLWithPath: "/same.wav"), URL(fileURLWithPath: "/last.wav")])
                try session.play(index: 2)
                if state == .paused { session.pause() }
                if state == .stopped { session.stop() }
                session.seek(to: 42); session.setVolume(0.3)
                session.setEqualizerEnabled(true); session.applyEqualizerPreset(.voice)
                /// Current duplicate retains this ID even after the preceding duplicate is removed.
                let identity = session.currentTrack?.id
                /// Stop baseline accounts for deliberately stopped setup rather than queue edits.
                let stops = backend.stopCount
                session.removeTrack(at: 3)
                session.removeTrack(at: 0)
                XCTAssertEqual(session.selectedIndex, 1)
                session.removeTrack(at: 0)
                XCTAssertEqual(session.currentTrack?.id, identity); XCTAssertEqual(session.selectedIndex, 0)
                XCTAssertEqual(session.position, 42); XCTAssertEqual(session.state, state)
                XCTAssertEqual(session.volume, 0.3); XCTAssertEqual(session.equalizer, backend.settings)
                XCTAssertEqual(session.equalizer.gains, EqualizerPreset.voice.gains)
                XCTAssertEqual(backend.stopCount, stops); XCTAssertEqual(backend.loadCount, 1)
                session.removeTrack(at: -1); session.removeTrack(at: 9)
                XCTAssertEqual(session.tracks.count, 1)
            }
        }
    }

    /// Removing the loaded entry stops rather than implicitly playing another row; explicit resume prepares a new track.
    func testRemovingLoadedEntryClearsSelectionUntilExplicitPlay() async throws {
        try await MainActor.run {
            /// Both advancing and paused output must stop when its queue entry is removed.
            for paused in [false, true] {
                /// Fake output exposes the prepared old duration even after stopping.
                let backend = FakeAudioBackend()
                /// Remaining rows cannot be mistaken for the now-removed decoder's selection.
                let session = PlaybackSession(backend: backend)
                session.enqueue([URL(fileURLWithPath: "/one.wav"), URL(fileURLWithPath: "/two.wav")])
                try session.play(index: 0); session.seek(to: 42)
                if paused { session.pause() }
                session.removeTrack(at: 0)
                XCTAssertNil(session.currentTrack); XCTAssertNil(session.selectedIndex)
                XCTAssertEqual(session.state, .stopped); XCTAssertFalse(backend.playing)
                XCTAssertEqual(session.position, 0); XCTAssertEqual(session.duration, 0)
                XCTAssertEqual(backend.loadCount, 1); XCTAssertEqual(backend.stopCount, 1)
                session.finished(successfully: true)
                XCTAssertNil(session.currentTrack)
                try session.resume()
                XCTAssertEqual(session.currentTrack?.title, "two")
                XCTAssertEqual(backend.loadCount, 2); XCTAssertEqual(session.state, .playing)
            }
        }
    }

    /// Reordering follows final-index semantics and current identity; completion uses the updated successor.
    func testReorderingLoadedTrackAndNeighborsPreservesStream() async throws {
        try await MainActor.run {
            /// Call counts ensure moving rows never reloads or stops the decoder.
            let backend = FakeAudioBackend()
            /// Four distinct entries establish moves in both directions and a new completion successor.
            let session = PlaybackSession(backend: backend)
            session.enqueue(["a", "b", "c", "d"].map { name in URL(fileURLWithPath: "/\(name).wav") })
            try session.play(index: 2); session.seek(to: 73)
            /// Stable loaded identity survives its own movement and movement across its old index.
            let identity = session.currentTrack?.id
            session.moveTrack(from: 0, to: 3)
            XCTAssertEqual(session.tracks.map(\.title), ["b", "c", "d", "a"])
            XCTAssertEqual(session.selectedIndex, 1)
            session.moveTrack(from: 1, to: 0)
            XCTAssertEqual(session.tracks.map(\.title), ["c", "b", "d", "a"])
            XCTAssertEqual(session.currentTrack?.id, identity); XCTAssertEqual(session.selectedIndex, 0)
            XCTAssertEqual(session.position, 73); XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(backend.loadCount, 1); XCTAssertEqual(backend.stopCount, 0)
            /// Invalid/no-op moves emit no model changes or decoder calls.
            var notifications = 0
            session.onChange = { notifications += 1 }
            session.moveTrack(from: -1, to: 0); session.moveTrack(from: 0, to: 4); session.moveTrack(from: 0, to: 0)
            XCTAssertEqual(notifications, 0)
            session.finished(successfully: true)
            XCTAssertEqual(session.currentTrack?.title, "b"); XCTAssertEqual(backend.loadCount, 2)
        }
    }

    /// Clearing drops all selections and cancels output while preserving gain/EQ; completion cannot restart appended entries.
    func testClearQueueRetainsAudioSettingsAndIgnoresOldCompletion() async throws {
        try await MainActor.run {
            /// Prepared fake decoder intentionally keeps its old duration to exercise session masking.
            let backend = FakeAudioBackend()
            /// Paused session with nondefault audio controls.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/one.wav")]); try session.resume()
            session.seek(to: 31); session.pause(); session.setVolume(0.6)
            session.setEqualizerEnabled(true); session.applyEqualizerPreset(.bass)
            /// Empty no-op clearing should not repeatedly notify or stop the decoder.
            var notifications = 0
            session.onChange = { notifications += 1 }
            session.clearQueue(); session.clearQueue()
            XCTAssertEqual(notifications, 1); XCTAssertEqual(backend.stopCount, 1)
            XCTAssertTrue(session.tracks.isEmpty); XCTAssertNil(session.currentTrack)
            XCTAssertEqual(session.state, .stopped); XCTAssertEqual(session.position, 0); XCTAssertEqual(session.duration, 0)
            XCTAssertEqual(session.volume, 0.6); XCTAssertEqual(session.equalizer.gains, EqualizerPreset.bass.gains)
            XCTAssertTrue(session.equalizer.isEnabled)
            session.enqueue([URL(fileURLWithPath: "/new.wav")])
            session.finished(successfully: true)
            XCTAssertNil(session.currentTrack); XCTAssertFalse(backend.playing)
            try session.resume()
            XCTAssertEqual(session.currentTrack?.title, "new"); XCTAssertEqual(backend.loadCount, 2)
        }
    }
    /// Separate Classic Play/Pause commands never toggle unexpectedly or reload a paused track.
    func testDedicatedPlayAndPauseAreIdempotent() async throws {
        try await MainActor.run {
            /// Backend recording whether repeated commands disturb its selection or offset.
            let backend = FakeAudioBackend()
            /// Empty session first verifies that Play/Pause cannot fabricate a selection.
            let session = PlaybackSession(backend: backend)
            try session.resume(); session.pause()
            XCTAssertEqual(session.state, .stopped)
            XCTAssertEqual(backend.loadCount, 0)
            session.enqueue([URL(fileURLWithPath: "/tmp/track.wav")])
            session.pause()
            XCTAssertEqual(session.state, .stopped)
            try session.resume()
            session.seek(to: 42)
            try session.resume()
            XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(session.position, 42)
            session.pause(); session.pause()
            XCTAssertEqual(session.state, .paused)
            XCTAssertEqual(session.position, 42)
            XCTAssertFalse(backend.playing)
            try session.resume()
            XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(backend.loadCount, 1)
            session.stop(); session.pause()
            XCTAssertEqual(session.state, .stopped)
            try session.resume()
            XCTAssertEqual(session.position, 0)
            XCTAssertEqual(backend.loadCount, 1)
        }
    }

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
