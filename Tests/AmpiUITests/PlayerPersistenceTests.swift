// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import XCTest
@testable import Ampi

/// Native restore substitute counts actual starts while filesystem preparation uses real temporary files.
@MainActor private final class PersistenceTestBackend: EqualizerAudioBackend {
    /// Fixed decoded length in seconds for a restored selection.
    var duration = 60.0
    /// Offset reset by load/stop, retained on pause.
    var position = 0.0
    /// Output gain used by saved-setting assertions.
    var volume: Float = 0.7
    /// Starts counted to distinguish decoder preparation from audible output.
    var starts = 0
    /// Last applied DSP curve and bypass state.
    var settings = EqualizerSettings()
    /// Prepares a fake decoder for a readable file without producing output.
    func load(_ url: URL) throws { position = 0 }
    /// Counts only explicitly requested starts.
    func play() -> Bool { starts += 1; return true }
    /// Retains the simulated offset.
    func pause() {}
    /// Resets the simulated output position.
    func stop() { position = 0 }
    /// Records the restored curve independently from transport.
    func applyEqualizer(_ settings: EqualizerSettings) { self.settings = settings }
}

/// Checks restart integration, bounded Classic revalidation, missing-file pruning, and asynchronous final saves.
final class PlayerPersistenceTests: XCTestCase {
    /// Storage errors retain in-memory settings and never alter a conflicting file; resumed observation reports without recursion.
    @MainActor func testWriteFailureKeepsLiveSessionAndReportsOnce() async throws {
        _ = NSApplication.shared
        /// Disposable workspace contains a regular file where an application-support directory would be required.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Conflicting file is original test data, never an owner settings or music file.
        let blocker = folder.appendingPathComponent("blocked-parent")
        try Data("Keep this file intact".utf8).write(to: blocker)
        /// Immutable player/session values must survive failure to create the store parent directory.
        let controller = PlayerWindowController(session: PlaybackSession(backend: PersistenceTestBackend()), theme: try ThemeCatalog.builtin("minimal"))
        defer { controller.close() }
        controller.session.setVolume(0.3); controller.session.setShuffleEnabled(true)
        /// Native coordinator cannot create a directory below this regular-file path.
        let persistence = PlayerPersistence(controller: controller, store: SessionStateStore(url: blocker.appendingPathComponent("state.json")))
        persistence.startSaving()
        do { try await persistence.flush(); XCTFail("Conflicting directory write unexpectedly succeeded") } catch {}
        XCTAssertEqual(controller.session.volume, 0.3); XCTAssertTrue(controller.session.isShuffleEnabled)
        XCTAssertEqual(controller.surface.presentationID, "ampi.minimal")
        /// Existing weak rendering/persistence observer remains connected while counting failure notifications.
        let originalObserver = controller.session.onChange
        /// A recursive save/status cycle would emit further notifications after its first 400-ms retry interval.
        var notifications = 0
        controller.session.onChange = { notifications += 1; originalObserver?() }
        persistence.resumeSaving()
        /// Bounded wait permits one failed debounce and its nonrecursive feedback callback.
        let deadline = Date().addingTimeInterval(3)
        while !controller.session.status.contains("could not be saved"), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(controller.session.status.contains("could not be saved"))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(try Data(contentsOf: blocker), Data("Keep this file intact".utf8))
        XCTAssertEqual(controller.session.state, .stopped)
    }

    /// Creates a disposable workspace with one readable regular placeholder file for the fake decoder.
    private func directory() throws -> URL {
        /// Fresh workspace contains no real owner media or application settings.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("Original test placeholder".utf8).write(to: folder.appendingPathComponent("audio.wav"))
        return folder
    }

    /// Locates an original cleared Classic fixture in the native test resource bundle.
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }

    /// Creates a snapshot with two duplicate identities, a selected second row, and nondefault DSP/policies.
    private func snapshot(folder: URL, skin: SavedSkin) -> SavedSession {
        /// Duplicate local paths retain different UUIDs after a restart.
        let tracks = [Track(url: folder.appendingPathComponent("audio.wav")), Track(url: folder.appendingPathComponent("audio.wav"))]
        /// Nondefault Voice curve is enabled to test backend delivery at startup.
        var equalizer = EqualizerSettings()
        equalizer.apply(.voice); equalizer.setEnabled(true)
        return SavedSession(tracks: tracks, selectedTrackID: tracks[1].id, volume: 0.2, shuffle: true,
                            repeatMode: .all, equalizer: equalizer, skin: skin)
    }

    /// Fresh controllers restore the exact selected duplicate and embedded native geometry without starting output.
    @MainActor func testNativeRestartRestoresDuplicateSelectionAndCurveStopped() async throws {
        _ = NSApplication.shared
        /// Local state/file workspace is removed after controller and actor work finish.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Embedded Quiet Space does not depend on an external JSON source remaining on disk.
        let saved = snapshot(folder: folder, skin: .native(try ThemeCatalog.builtin("minimal")))
        /// Store writes the initial state independently from the controller under test.
        let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
        try await store.save(saved)
        /// Fake output proves restore prepares but never starts the selected entry.
        let backend = PersistenceTestBackend()
        /// Native session and player begin with first-launch defaults before restore.
        let session = PlaybackSession(backend: backend)
        /// Default geometry is replaced only after saved native validation succeeds.
        let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
        defer { controller.close() }
        /// Independent coordinator models a new application launch.
        let persistence = PlayerPersistence(controller: controller, store: SessionStateStore(url: store.url))
        /// Successful recovery needs no startup notice or automatic Play.
        let notices = await persistence.restore()
        XCTAssertTrue(notices.isEmpty); XCTAssertEqual(controller.surface.presentationID, "ampi.minimal")
        XCTAssertEqual(session.tracks, saved.tracks); XCTAssertEqual(session.currentTrack?.id, saved.selectedTrackID)
        XCTAssertEqual(session.state, .stopped); XCTAssertEqual(session.position, 0); XCTAssertEqual(backend.starts, 0)
        XCTAssertEqual(session.volume, 0.2); XCTAssertEqual(backend.settings, saved.equalizer)
        XCTAssertTrue(session.isShuffleEnabled); XCTAssertEqual(session.repeatMode, .all)
    }

    /// Missing selection clears loaded identity; surviving duplicate rows/settings remain and a missing Classic source falls back.
    @MainActor func testMissingSelectedAudioAndSkinRecoverIndependently() async throws {
        _ = NSApplication.shared
        /// Readable first row remains while a second selected path is deliberately absent.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Original duplicates are augmented with one absent selected entry.
        let base = snapshot(folder: folder, skin: .classic(folder.appendingPathComponent("missing.wsz")))
        /// Missing entry has its own durable identity, distinct from both surviving duplicate files.
        let missing = Track(url: folder.appendingPathComponent("missing.wav"))
        /// Valid durable references are allowed to go offline before the next launch.
        let saved = SavedSession(tracks: base.tracks + [missing], selectedTrackID: missing.id,
            volume: base.volume, shuffle: base.shuffle, repeatMode: base.repeatMode, equalizer: base.equalizer, skin: base.skin)
        /// File store preserves a valid snapshot even if its referenced paths are no longer present.
        let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
        try await store.save(saved)
        /// Fake graph must not inherit a selection from a different surviving duplicate.
        let backend = PersistenceTestBackend()
        /// Default player remains installed when its saved Classic file cannot be reopened.
        let controller = PlayerWindowController(session: PlaybackSession(backend: backend), theme: try ThemeCatalog.builtin("retro"))
        defer { controller.close() }
        /// Combined notices distinguish unavailable media from presentation recovery.
        let notices = await PlayerPersistence(controller: controller, store: store).restore()
        XCTAssertEqual(notices.count, 2); XCTAssertEqual(controller.surface.presentationID, "ampi.retro")
        XCTAssertEqual(controller.session.tracks, base.tracks); XCTAssertNil(controller.session.currentTrack)
        XCTAssertEqual(controller.session.duration, 0); XCTAssertEqual(controller.session.state, .stopped)
        XCTAssertEqual(controller.session.equalizer, base.equalizer); XCTAssertEqual(controller.session.volume, 0.2)
        XCTAssertEqual(backend.starts, 0)
    }

    /// Startup revalidates both archive structure and renderer crops, retaining defaults for malformed optional control sheets.
    @MainActor func testClassicRestorationRevalidatesAllPanels() async throws {
        _ = NSApplication.shared
        /// Both original positive and structurally inspectable negative fixtures use fresh temporary state files.
        for name in ["playable-classic.wsz", "invalid-main-controls.wsz"] {
            /// Disposable folder holds copied skin bytes rather than editing repository fixtures.
            let folder = try directory()
            defer { try? FileManager.default.removeItem(at: folder) }
            /// Local copied source remains available for the bounded startup importer.
            let source = folder.appendingPathComponent("skin.wsz")
            try FileManager.default.copyItem(at: fixture(name), to: source)
            /// Saved Classic choice stores the source path, never embeds third-party assets in the state file.
            let saved = snapshot(folder: folder, skin: .classic(source))
            /// Actual actor read/write is shared with interactive startup.
            let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
            try await store.save(saved)
            /// Decoder cannot produce output without an explicit Play.
            let backend = PersistenceTestBackend()
            /// Fresh default player hosts atomic Classic main/playlist/EQ replacement.
            let controller = PlayerWindowController(session: PlaybackSession(backend: backend), theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            /// Valid source shows panels; undersized crops produce a nonfatal fallback notice.
            let notices = await PlayerPersistence(controller: controller, store: store).restore()
            XCTAssertEqual(controller.surface.presentationID, name == "playable-classic.wsz" ? "ampi.classic.main" : "ampi.retro")
            XCTAssertEqual(notices.isEmpty, name == "playable-classic.wsz")
            XCTAssertEqual(controller.session.tracks, saved.tracks); XCTAssertEqual(controller.session.volume, saved.volume)
            XCTAssertEqual(controller.session.state, .stopped); XCTAssertEqual(backend.starts, 0)
        }
    }

    /// Invalid embedded geometry falls back independently; malformed JSON restores safe first-launch defaults.
    @MainActor func testInvalidNativeLayoutAndCorruptStateUseSafeDefaults() async throws {
        _ = NSApplication.shared
        /// Isolated file can be deliberately corrupted without touching real app settings.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Structurally decoded native theme bypasses the normal Theme.decode validation for this negative fixture.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ThemeCatalog.builtin("minimal"))) as? [String: Any])
        json["width"] = 1
        /// Impossible geometry must never reach AppKit content replacement.
        let badTheme = try JSONDecoder().decode(Theme.self, from: JSONSerialization.data(withJSONObject: json))
        /// Valid settings remain recoverable despite that one presentation problem.
        let saved = snapshot(folder: folder, skin: .native(badTheme))
        /// Actor file is externally edited only in the disposable test directory.
        let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
        try JSONEncoder().encode(saved).write(to: store.url)
        /// Fresh player defaults must remain available through both kinds of corruption.
        let controller = PlayerWindowController(session: PlaybackSession(backend: PersistenceTestBackend()), theme: try ThemeCatalog.builtin("retro"))
        defer { controller.close() }
        /// Geometry error retains recovered audio while leaving the default native layout installed.
        let notices = await PlayerPersistence(controller: controller, store: store).restore()
        XCTAssertEqual(notices.count, 1); XCTAssertEqual(controller.surface.presentationID, "ampi.retro")
        XCTAssertEqual(controller.session.tracks, saved.tracks); XCTAssertEqual(controller.session.volume, 0.2)
        try Data("{broken".utf8).write(to: store.url)
        /// Independent first-launch session must not inherit values from a previous in-process recovery.
        let fresh = PlayerWindowController(session: PlaybackSession(backend: PersistenceTestBackend()), theme: try ThemeCatalog.builtin("retro"))
        defer { fresh.close() }
        /// Malformed JSON cannot supply any trusted queue/settings.
        let failures = await PlayerPersistence(controller: fresh, store: store).restore()
        XCTAssertEqual(failures.count, 1); XCTAssertTrue(fresh.session.tracks.isEmpty)
        XCTAssertEqual(fresh.session.volume, 0.7); XCTAssertFalse(fresh.session.isShuffleEnabled)
        XCTAssertEqual(fresh.session.repeatMode, .off); XCTAssertEqual(fresh.session.state, .stopped)
    }

    /// Debounced observation writes latest values; immediate Quit cancels stale delay, and canceled Quit can resume saving.
    @MainActor func testDebouncedEditsAndFinalFlushKeepLatestSnapshot() async throws {
        _ = NSApplication.shared
        /// No audio source is required for changes to presentation and playback policies.
        let folder = try directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Actual actor serializes every delayed and final write.
        let store = SessionStateStore(url: folder.appendingPathComponent("state.json"))
        /// Real controller owns the rendering observer independently of persistence.
        let controller = PlayerWindowController(session: PlaybackSession(backend: PersistenceTestBackend()), theme: try ThemeCatalog.builtin("retro"))
        defer { controller.close() }
        /// Retained coordinator attaches a weak save observer and coalesces a rapid edit burst.
        let persistence = PlayerPersistence(controller: controller, store: store)
        persistence.startSaving()
        controller.session.setVolume(0.1); controller.session.setVolume(0.2)
        controller.session.setShuffleEnabled(true); controller.session.setRepeatMode(.one)
        try controller.apply(ThemeCatalog.builtin("minimal"))
        try await persistence.flush()
        try await Task.sleep(for: .milliseconds(500))
        /// Fresh actor read ensures a canceled older delay did not overwrite the final state.
        let flushed = try await SessionStateStore(url: store.url).load()
        XCTAssertEqual(flushed?.volume, 0.2); XCTAssertEqual(flushed?.repeatMode, .one); XCTAssertEqual(flushed?.shuffle, true)
        /// Native choice follows the latest successful replacement, independent from playback changes.
        guard case .native(let theme) = flushed?.skin else { return XCTFail("Final native layout missing") }
        XCTAssertEqual(theme.id, "ampi.minimal")
        controller.session.setVolume(0.4); persistence.resumeSaving()
        /// Bounded wait allows the resumed 400-ms debounce plus local disk scheduling time.
        let deadline = Date().addingTimeInterval(3)
        /// Read snapshots expose when resumed observation completed without assuming exact scheduling latency.
        var resumed: SavedSession?
        repeat {
            try await Task.sleep(for: .milliseconds(50))
            resumed = try await SessionStateStore(url: store.url).load()
        } while resumed?.volume != 0.4 && Date() < deadline
        XCTAssertEqual(resumed?.volume, 0.4)
        try await persistence.flush()
    }
}
