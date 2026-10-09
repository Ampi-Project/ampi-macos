// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AmpiCore

/// Fake output exposes whether restoration accidentally calls Play or changes a live session before validation.
@MainActor private final class RestoreTestBackend: EqualizerAudioBackend {
    /// Constant simulated duration in seconds; hidden by the session without a selected decoder.
    var duration = 120.0
    /// Offset retained during pause, reset during load/stop.
    var position = 0.0
    /// Output gain used to check restore of a nondefault saved value.
    var volume: Float = 0.7
    /// Actual starts, which must remain zero throughout restoration.
    var plays = 0
    /// Successfully prepared decoders, independent of duplicate file names.
    var loads = 0
    /// Filename to reject before replacing the current decoder.
    var rejectedName: String?
    /// Last applied DSP values, including bypass state.
    var settings = EqualizerSettings()
    /// Prepares a supported fake candidate at zero, or rejects the injected corrupt file.
    func load(_ url: URL) throws {
        guard url.lastPathComponent != rejectedName else { throw PlaybackError.unsupportedDecodedFormat }
        loads += 1; position = 0
    }
    /// Counts explicit output starts; restore must never call this method.
    func play() -> Bool { plays += 1; return true }
    /// Retains offset while suspended.
    func pause() {}
    /// Cancels output and rewinds the simulated decoder.
    func stop() { position = 0 }
    /// Retains restored ten-band settings without starting output.
    func applyEqualizer(_ settings: EqualizerSettings) { self.settings = settings }
}

/// Checks durable identity/settings, stopped recovery, storage bounds, and preservation of a previous valid save.
final class SavedSessionTests: XCTestCase {
    /// Creates three independent duplicate entries, selecting the middle identity with nondefault audio settings.
    private func snapshot(skin: SavedSkin? = nil, version: Int = 1, volume: Float = 0.3) throws -> SavedSession {
        /// Repeated file URL intentionally has a fresh UUID for each saved row.
        let tracks = (0..<3).map { _ in Track(url: URL(fileURLWithPath: "/same.wav")) }
        /// Bypassed Voice curve tests retaining settings independently from processing state.
        var equalizer = EqualizerSettings()
        equalizer.apply(.voice); equalizer.setEnabled(true); equalizer.setGain(-7, at: 5)
        return SavedSession(tracks: tracks, selectedTrackID: tracks[1].id, volume: volume, shuffle: true,
            repeatMode: .one, equalizer: equalizer, skin: try skin ?? .native(ThemeCatalog.builtin("minimal")),
            schemaVersion: version)
    }

    /// Each store test has an isolated temporary parent and never reads/writes the owner's application support state.
    private func directory() throws -> URL {
        /// Fresh workspace removed by the calling test after all actor work completes.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Saved duplicate IDs, output values, custom curve, policy, and native geometry survive encode/read in a new store.
    func testAtomicRoundTripThroughFreshStore() async throws {
        /// Per-test state directory prevents dependence on native user settings.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Application-like nested path is created only on the first save.
        let url = folder.appendingPathComponent("Ampi/session-v1.json")
        /// Original snapshot includes a selected duplicate rather than the first matching file URL.
        let original = try snapshot()
        /// Independent actor writes complete valid state.
        let writer = SessionStateStore(url: url)
        try await writer.save(original)
        /// A new process would use a new actor, without relying on writer memory or byte caching.
        let loaded = try await SessionStateStore(url: url).load()
        /// XCTest unwrapping runs after the actor read, without an asynchronous autoclosure.
        let restored = try XCTUnwrap(loaded)
        XCTAssertEqual(restored.tracks, original.tracks); XCTAssertEqual(restored.selectedTrackID, original.tracks[1].id)
        XCTAssertEqual(restored.volume, 0.3); XCTAssertTrue(restored.shuffle); XCTAssertEqual(restored.repeatMode, .one)
        XCTAssertEqual(restored.equalizer, original.equalizer)
        /// Embedded geometry is inspected without reopening an original JSON layout file.
        guard case .native(let theme) = restored.skin else { return XCTFail("Native layout was not retained") }
        XCTAssertEqual(theme.id, "ampi.minimal"); XCTAssertEqual(theme.height, 550)
    }

    /// First launch is nil and read-only; it must not create an empty state file or parent directory.
    func testFirstLaunchDoesNotWriteDefaults() async throws {
        /// Existing outer folder contains no application-specific state directory yet.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Missing path should be indistinguishable from the app's first launch.
        let url = folder.appendingPathComponent("missing/session.json")
        /// Await outside an XCTest autoclosure because the actor operation is asynchronous.
        let saved = try await SessionStateStore(url: url).load()
        XCTAssertNil(saved); XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    /// Unknown versions, malformed JSON, oversized bytes, and symbolic state files cannot reach session restoration.
    func testUnreadableFormatsAndBoundsAreRejectedWithoutModification() async throws {
        /// Store directory includes a separate valid target for the symbolic-link case.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// State file is intentionally overwritten only within this disposable workspace.
        let url = folder.appendingPathComponent("state.json")
        /// Three invalid payload shapes exercise decoding, version validation, and the pre-read size guard.
        let invalid = [Data("{broken".utf8), try JSONEncoder().encode(snapshot(version: 99)),
                       Data(repeating: 32, count: SessionStateStore.maximumBytes + 1)]
        /// Each malformed payload must remain byte-for-byte unchanged after a rejected read.
        for data in invalid {
            try data.write(to: url)
            do { _ = try await SessionStateStore(url: url).load(); XCTFail("Invalid state was accepted") } catch {}
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
        try FileManager.default.removeItem(at: url)
        /// Regular target makes the symlink's existence/type check meaningful.
        let target = folder.appendingPathComponent("target.json")
        try JSONEncoder().encode(snapshot()).write(to: target)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        do { _ = try await SessionStateStore(url: url).load(); XCTFail("Symbolic state file was accepted") } catch {}
    }

    /// Invalid replacements must fail before touching the last valid saved file.
    func testFailedSaveKeepsPreviousSnapshot() async throws {
        /// Temporary state workspace hosts both successful and rejected writes.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// One actor serializes the original save and rejected replacement.
        let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
        try await store.save(snapshot())
        /// Bytes provide a direct assertion that validation did not damage the on-disk state.
        let original = try Data(contentsOf: store.url)
        do { try await store.save(snapshot(volume: 2)); XCTFail("Invalid gain was saved") } catch {}
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    /// Final forced save repairs external corruption; an ordinary unchanged save recreates a removed state file.
    func testFinalSaveRepairsChangedOrRemovedFile() async throws {
        /// Disposable state directory is the only location modified by this test.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Durable values remain identical while their on-disk bytes are changed independently.
        let saved = try snapshot()
        /// Same actor retains its successful-save cache through corruption/removal challenges.
        let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
        try await store.save(saved)
        try Data("{broken".utf8).write(to: store.url)
        try await store.save(saved, force: true)
        /// Final write must replace actual disk bytes even though cached durable state did not change.
        let repaired = try await SessionStateStore(url: store.url).load()
        XCTAssertEqual(repaired?.tracks, saved.tracks)
        try FileManager.default.removeItem(at: store.url)
        try await store.save(saved)
        /// Missing-file recreation prevents a cache hit from silently losing the entire saved session.
        let recreated = try await SessionStateStore(url: store.url).load()
        XCTAssertEqual(recreated?.tracks, saved.tracks)
    }

    /// Duplicate identities, a foreign selected identity, remote URLs, and invalid EQ arrays are rejected.
    func testQueueAndAudioInvariantsAreValidatedAfterDecoding() throws {
        /// Valid snapshot is mutated through JSON to exercise fields whose normal setters enforce bounds.
        let original = try snapshot()
        /// Encoded JSON values are independent from the original immutable model.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        /// Separate fixtures isolate one malformed invariant per decoding pass.
        for mode in 0..<4 {
            /// Mutable copy avoids one malformed case contaminating another.
            var changed = json
            /// Mutable rows permit duplicate identities and an explicit nonlocal file source.
            var rows = try XCTUnwrap(changed["tracks"] as? [[String: Any]])
            switch mode {
            case 0: rows[1]["id"] = rows[0]["id"]; changed["tracks"] = rows
            case 1: changed["selectedTrackID"] = UUID().uuidString
            case 2: rows[0]["url"] = "https://example.invalid/song.wav"; changed["tracks"] = rows
            default:
                /// Too few EQ values must not reach a ten-band processor's indexed access.
                var eq = try XCTUnwrap(changed["equalizer"] as? [String: Any])
                eq["gains"] = [0, 0]; changed["equalizer"] = eq
            }
            /// Wire-decoded state bypasses property setters, requiring an explicit validation boundary.
            let decoded = try JSONDecoder().decode(SavedSession.self, from: JSONSerialization.data(withJSONObject: changed))
            XCTAssertThrowsError(try decoded.validate())
        }
    }

    /// Validation permits independent skin fallback during reads, while saving invalid native geometry is refused.
    func testBadNativeGeometryPreservesReadableQueueButCannotBeSaved() async throws {
        /// Structurally decoded geometry is invalid even though the rest of the state is usable.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ThemeCatalog.builtin("retro"))) as? [String: Any])
        json["width"] = 1
        /// Decode without Theme.decode so the fixture represents malformed persisted geometry.
        let badTheme = try JSONDecoder().decode(Theme.self, from: JSONSerialization.data(withJSONObject: json))
        /// Isolated file can be edited to mimic an external corrupting change.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Valid queue/audio with a bad layout is still recoverable by the native default surface.
        let saved = try snapshot(skin: .native(badTheme))
        /// Independent actor should return the state for partial recovery, without trusting its geometry.
        let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
        try JSONEncoder().encode(saved).write(to: store.url)
        /// Await read returns valid durable audio values despite invalid optional presentation.
        let loaded = try await store.load()
        XCTAssertEqual(loaded?.tracks, saved.tracks)
        do { try await store.save(saved); XCTFail("Invalid geometry was written") } catch {}
    }

    /// Restoration prepares the exact selected duplicate and settings at zero, with no Play call or inherited history.
    @MainActor func testRestorationIsStoppedAndRetainsDuplicateIdentity() throws {
        /// Fake graph counts output starts independently of decoder preparation.
        let backend = RestoreTestBackend()
        /// Pruned snapshot still includes the original selected middle duplicate.
        let saved = try snapshot()
        /// Empty session receives durable values through the public validation boundary.
        let session = PlaybackSession(backend: backend)
        XCTAssertNil(try session.restore(saved))
        XCTAssertEqual(session.tracks, saved.tracks); XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertEqual(session.currentTrack?.id, saved.selectedTrackID); XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(session.position, 0); XCTAssertEqual(backend.plays, 0); XCTAssertEqual(backend.loads, 1)
        XCTAssertEqual(session.volume, saved.volume); XCTAssertEqual(backend.settings, saved.equalizer)
        XCTAssertTrue(session.isShuffleEnabled); XCTAssertEqual(session.repeatMode, .one)
        session.finished(successfully: true); XCTAssertEqual(backend.plays, 0)
        try session.resume(); XCTAssertEqual(backend.plays, 1); XCTAssertEqual(backend.loads, 1)
    }

    /// A readable but unsupported selected decoder leaves the queue/settings restored and the selection safely empty.
    @MainActor func testFailedSelectedDecoderDoesNotDiscardSettingsOrStartAnotherRow() throws {
        /// Decoder deliberately refuses the filename used by every saved entry.
        let backend = RestoreTestBackend()
        backend.rejectedName = "same.wav"
        /// Session must mask the backend's duration when preparation fails.
        let session = PlaybackSession(backend: backend)
        /// Valid durable values remain usable even after its selected file fails native decoding.
        let saved = try snapshot()
        XCTAssertNotNil(try session.restore(saved)); XCTAssertNil(session.currentTrack)
        XCTAssertEqual(session.tracks, saved.tracks); XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(session.duration, 0); XCTAssertEqual(session.position, 0); XCTAssertEqual(backend.plays, 0)
        XCTAssertEqual(session.volume, 0.3); XCTAssertEqual(session.equalizer, saved.equalizer)
    }

    /// Invalid restoration must leave an already playing session completely intact.
    @MainActor func testInvalidRestoreDoesNotStopExistingPlayback() throws {
        /// Current output can expose accidental validation-after-stop behavior.
        let backend = RestoreTestBackend()
        /// Prepared live session uses a different filename from the saved fixture.
        let session = PlaybackSession(backend: backend)
        session.enqueue([URL(fileURLWithPath: "/live.wav")]); try session.resume(); session.seek(to: 42)
        /// Current identity remains authoritative when the schema is rejected.
        let identity = session.currentTrack?.id
        XCTAssertThrowsError(try session.restore(snapshot(version: 99)))
        XCTAssertEqual(session.currentTrack?.id, identity); XCTAssertEqual(session.position, 42)
        XCTAssertEqual(session.state, .playing); XCTAssertEqual(backend.plays, 1)
    }
}
