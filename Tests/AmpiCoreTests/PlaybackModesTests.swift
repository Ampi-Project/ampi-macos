// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AmpiCore

/// Deterministic output whose load failures and offset expose navigation effects without a device.
@MainActor private final class ModeTestBackend: AudioBackend {
    /// Every simulated entry lasts one minute.
    var duration = 60.0
    /// Offset is reset by load/stop and explicitly rewound by completion loops.
    var position = 0.0
    /// Retained output gain verifies changing playback policies does not alter audio settings.
    var volume: Float = 0.4
    /// Decoder preparations counted independently of repeated starts of the same entry.
    var loads = 0
    /// Filename rejected before replacing the existing simulated decoder, or nil for all playable files.
    var rejectedName: String?
    /// Prepares a candidate unless it matches the injected corrupt filename; successful loads rewind.
    func load(_ url: URL) throws {
        guard url.lastPathComponent != rejectedName else { throw PlaybackError.couldNotStart }
        loads += 1; position = 0
    }
    /// Reports a successful simulated output start.
    func play() -> Bool { true }
    /// Retains the current offset while paused.
    func pause() {}
    /// Rewinds the simulated decoder.
    func stop() { position = 0 }
}

/// Exercises shuffle identity/history, completion policies, and edits with deterministic candidate selection.
final class PlaybackModesTests: XCTestCase {
    /// Constructs count duplicate-file entries and always chooses the first remaining candidate for reproducibility.
    @MainActor private func session(_ backend: ModeTestBackend, count: Int) -> PlaybackSession {
        /// Repeated URLs deliberately challenge identity-based traversal rather than filename comparisons.
        let session = PlaybackSession(backend: backend, chooseShuffleIndex: { _ in 0 })
        session.enqueue(Array(repeating: URL(fileURLWithPath: "/same.wav"), count: count))
        return session
    }

    /// Shuffle leaves queue order intact and completes exactly one visit per duplicate identity before stopping.
    @MainActor func testShuffleOffCompletesDistinctEntriesOnce() throws {
        /// Decoder substitute reused by every duplicate-file entry.
        let backend = ModeTestBackend()
        /// Four entries permit a start away from the first row.
        let session = session(backend, count: 4)
        /// Original queue identities must retain their visible order.
        let ids = session.tracks.map(\.id)
        try session.play(index: 2); session.setShuffleEnabled(true)
        /// Completion order is observable independently of visible row order.
        var played = [try XCTUnwrap(session.currentTrack?.id)]
        /// Each completion should select a previously unvisited duplicate.
        for _ in 0..<3 {
            session.finished(successfully: true)
            played.append(try XCTUnwrap(session.currentTrack?.id))
        }
        XCTAssertEqual(played, [ids[2], ids[0], ids[1], ids[3]])
        XCTAssertEqual(Set(played), Set(ids)); XCTAssertEqual(session.tracks.map(\.id), ids)
        session.finished(successfully: true)
        XCTAssertEqual(session.state, .stopped); XCTAssertEqual(session.position, 0)
        XCTAssertEqual(backend.loads, 4)
    }

    /// Previous rewinds after three seconds, then retraces played identities; Next follows the forward history.
    @MainActor func testShuffleHistorySurvivesReorderingAndNeighborRemoval() throws {
        /// Simulated stream makes restart and reload assertions exact.
        let backend = ModeTestBackend()
        /// Five rows leave enough unvisited entries after removing a past visit.
        let session = session(backend, count: 5)
        session.setShuffleEnabled(true)
        /// Stable identities resolve history after visible queue movement.
        let ids = session.tracks.map(\.id)
        try session.play(index: 3); try session.next(); try session.next()
        XCTAssertEqual(session.currentTrack?.id, ids[1])
        session.seek(to: 12); try session.previous()
        XCTAssertEqual(session.currentTrack?.id, ids[1]); XCTAssertEqual(session.position, 0)
        try session.previous(); XCTAssertEqual(session.currentTrack?.id, ids[0])
        session.moveTrack(from: 1, to: 4)
        try session.next(); XCTAssertEqual(session.currentTrack?.id, ids[1])
        session.removeTrack(at: 0)
        try session.previous(); XCTAssertEqual(session.currentTrack?.id, ids[3])
        try session.next(); XCTAssertEqual(session.currentTrack?.id, ids[1])
        try session.next(); XCTAssertEqual(session.currentTrack?.id, ids[2])
    }

    /// Repeat All wraps sequential queues, while Repeat One only affects automatic completion.
    @MainActor func testSequentialRepeatAndManualNextOverride() throws {
        /// Counts preparations to detect unnecessary reloads during Repeat One.
        let backend = ModeTestBackend()
        /// Two entries exercise same-entry looping and a different-entry manual successor.
        let session = session(backend, count: 2)
        try session.resume(); session.setRepeatMode(.one); session.seek(to: 60)
        session.finished(successfully: true)
        XCTAssertEqual(session.selectedIndex, 0); XCTAssertEqual(session.position, 0)
        XCTAssertEqual(backend.loads, 1); XCTAssertEqual(session.state, .playing)
        try session.next(); XCTAssertEqual(session.selectedIndex, 1)
        try session.next(); XCTAssertEqual(session.state, .stopped)
        session.setRepeatMode(.all); try session.resume(); session.finished(successfully: true)
        XCTAssertEqual(session.selectedIndex, 0); XCTAssertEqual(session.state, .playing)
        session.setRepeatMode(.off); session.finished(successfully: true); session.finished(successfully: true)
        XCTAssertEqual(session.state, .stopped)
    }

    /// A one-entry Repeat All queue must rewind for manual Next as well as automatic completion, with or without shuffle.
    @MainActor func testSingleEntryAllAlwaysRewindsWithoutReloading() throws {
        /// Both policies must work even when there is no different shuffle candidate.
        for shuffle in [false, true] {
            /// Decoder call count proves the same stream can safely be rescheduled.
            let backend = ModeTestBackend()
            /// Single duplicate entry has nowhere else to advance.
            let session = session(backend, count: 1)
            session.setShuffleEnabled(shuffle); session.setRepeatMode(.all); try session.resume()
            session.seek(to: 21); try session.next()
            XCTAssertEqual(session.position, 0)
            session.seek(to: 60); session.finished(successfully: true)
            XCTAssertEqual(session.position, 0); XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(backend.loads, 1)
        }
    }

    /// Shuffle Repeat All visits each entry per cycle and avoids immediately repeating the prior cycle's last entry.
    @MainActor func testShuffleAllStartsFreshCycleWithoutImmediateDuplicate() throws {
        /// Test chooser makes cycle boundaries deterministic.
        let backend = ModeTestBackend()
        /// Three duplicate-file entries must each appear once per cycle.
        let session = session(backend, count: 3)
        session.setShuffleEnabled(true); session.setRepeatMode(.all); try session.play(index: 1)
        /// First cycle records identities before completion changes the selected entry.
        var first: [UUID] = []
        /// Simulate three full successful completions to reach the next cycle.
        for _ in 0..<3 { first.append(try XCTUnwrap(session.currentTrack?.id)); session.finished(successfully: true) }
        /// Second cycle begins at the new selected entry after the preceding loop.
        var second: [UUID] = []
        /// Each entry in the second cycle must again be distinct.
        for _ in 0..<3 { second.append(try XCTUnwrap(session.currentTrack?.id)); session.finished(successfully: true) }
        XCTAssertEqual(Set(first), Set(session.tracks.map(\.id)))
        XCTAssertEqual(Set(second), Set(first)); XCTAssertNotEqual(first.last, second.first)
    }

    /// Toggling policies preserves paused output; turning shuffle off immediately restores current visible queue order.
    @MainActor func testModeChangesPreserveOffsetAndRestoreSequentialOrder() throws {
        /// Offset/load count detect any policy-induced audio reset.
        let backend = ModeTestBackend()
        /// Three queue entries allow a current entry with a sequential successor.
        let session = session(backend, count: 3)
        try session.play(index: 1); session.seek(to: 24); session.pause()
        session.setShuffleEnabled(true); session.setRepeatMode(.all); session.cycleRepeatMode()
        XCTAssertEqual(session.repeatMode, .one)
        XCTAssertEqual(session.state, .paused); XCTAssertEqual(session.position, 24)
        XCTAssertEqual(session.volume, 0.4); XCTAssertEqual(backend.loads, 1)
        session.cycleRepeatMode(); XCTAssertEqual(session.repeatMode, .off)
        session.setShuffleEnabled(false); try session.next()
        XCTAssertEqual(session.selectedIndex, 2)
    }

    /// Appends join the remaining cycle, removals prune visits, and clearing retains policy while resetting history.
    @MainActor func testEditsAndClearDoNotLeaveStaleShuffleIdentities() throws {
        /// Decoder substitute supports immediate edited navigation.
        let backend = ModeTestBackend()
        /// Initial two-entry traversal gets a newly appended candidate after playback starts.
        let session = session(backend, count: 2)
        session.setShuffleEnabled(true); session.setRepeatMode(.one); try session.resume()
        session.removeTrack(at: 1); session.enqueue([URL(fileURLWithPath: "/added.wav")])
        try session.next(); XCTAssertEqual(session.currentTrack?.title, "added")
        session.removeTrack(at: 1); XCTAssertNil(session.currentTrack); XCTAssertEqual(session.state, .stopped)
        try session.resume(); XCTAssertEqual(session.currentTrack?.title, "same")
        session.clearQueue(); session.enqueue([URL(fileURLWithPath: "/new.wav")])
        session.finished(successfully: true); XCTAssertNil(session.currentTrack)
        XCTAssertTrue(session.isShuffleEnabled); XCTAssertEqual(session.repeatMode, .one)
        try session.resume(); try session.previous()
        XCTAssertEqual(session.currentTrack?.title, "new"); XCTAssertEqual(session.state, .playing)
    }

    /// A rejected shuffle destination remains unvisited and retryable without damaging live playback or history.
    @MainActor func testFailedShuffleLoadDoesNotConsumeDestinationOrHistory() throws {
        /// Corruption is injected only after the first entry starts successfully.
        let backend = ModeTestBackend()
        /// Two filenames separate the rejected destination from the preserved stream.
        let session = PlaybackSession(backend: backend, chooseShuffleIndex: { _ in 0 })
        session.enqueue([URL(fileURLWithPath: "/good.wav"), URL(fileURLWithPath: "/bad.wav")])
        session.setShuffleEnabled(true); try session.resume(); session.seek(to: 19)
        backend.rejectedName = "bad.wav"
        XCTAssertThrowsError(try session.next())
        XCTAssertEqual(session.currentTrack?.title, "good"); XCTAssertEqual(session.position, 19)
        XCTAssertEqual(session.state, .playing); XCTAssertEqual(backend.loads, 1)
        backend.rejectedName = nil; try session.next()
        XCTAssertEqual(session.currentTrack?.title, "bad")
        try session.previous(); XCTAssertEqual(session.currentTrack?.title, "good")
    }

    /// Late completion while paused/stopped and unsuccessful completion must never start a repeat loop.
    @MainActor func testInactiveAndFailedCompletionsDoNotRepeat() throws {
        /// One loaded entry allows Repeat One without requiring another decoder.
        let backend = ModeTestBackend()
        /// Empty modes and navigation are also safe no-ops.
        let session = session(backend, count: 0)
        session.setShuffleEnabled(true); session.setRepeatMode(.one)
        try session.next(); try session.previous(); try session.resume()
        XCTAssertNil(session.currentTrack); XCTAssertEqual(backend.loads, 0)
        session.enqueue([URL(fileURLWithPath: "/same.wav")]); try session.resume()
        session.seek(to: 24); session.pause(); session.finished(successfully: true)
        XCTAssertEqual(session.state, .paused); XCTAssertEqual(session.position, 24)
        try session.resume(); session.finished(successfully: false)
        XCTAssertEqual(session.state, .stopped)
        session.finished(successfully: true); XCTAssertEqual(session.state, .stopped)
    }
}
