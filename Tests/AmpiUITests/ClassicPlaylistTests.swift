// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import XCTest
@testable import Ampi

/// Deterministic output for shared-queue and playlist lifecycle checks without audible playback.
@MainActor private final class PlaylistTestBackend: AudioBackend {
    /// Simulated duration in seconds for selection/seek preservation checks.
    var duration = 120.0
    /// Simulated current offset; loading a different row resets it.
    var position = 0.0
    /// Simulated gain retained through panel and theme changes.
    var volume: Float = 0.7
    /// Count of successful track loads, exposing unintended audio recreation during window changes.
    var loads = 0
    /// Prepares a selected queue entry and resets its fake offset.
    func load(_ url: URL) throws { position = 0; loads += 1 }
    /// Simulates a successful start/resume without opening audio output.
    func play() -> Bool { true }
    /// Preserves the simulated position when paused.
    func pause() {}
    /// Stops fake playback at the beginning of the selected track.
    func stop() { position = 0 }
}

/// Exercises playlist behavior through actual AppKit table/button callbacks and window replacement.
final class ClassicPlaylistTests: XCTestCase {
    /// Resolves original fixture resources without depending on the test's working directory.
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }

    /// Browsing alone cannot start playback; Play Selected and Enter must choose the highlighted entry.
    func testBrowseSelectedPlayAndKeyboardActivation() async throws {
        /// Complete original green border/palette package.
        let package = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Backend detecting unintended selection loads while merely browsing rows.
            let backend = PlaylistTestBackend()
            /// Shared session with a Unicode title in the second queue entry.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/tmp/first.wav"), URL(fileURLWithPath: "/tmp/♫ موسیقی.wav")])
            try session.play(index: 0); session.seek(to: 42)
            /// Real controller supplies the one observer and all native toolbar/queue callbacks.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(package)
            /// Queue panel connected to the already playing session.
            let view = try XCTUnwrap(controller.classicPlaylist?.content)
            XCTAssertEqual(view.table.numberOfRows, 2)
            XCTAssertEqual(view.table.selectedRow, 0)
            view.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            view.refresh()
            XCTAssertEqual(session.selectedIndex, 0)
            XCTAssertEqual(session.position, 42)
            XCTAssertEqual(view.table.selectedRow, 1)
            XCTAssertEqual(backend.loads, 1)
            view.buttons["pause"]?.performClick(nil)
            XCTAssertEqual(session.state, .paused)
            XCTAssertEqual(view.table.selectedRow, 1)
            view.buttons["selected"]?.performClick(nil)
            XCTAssertEqual(session.selectedIndex, 1)
            XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(session.currentTrack?.title, "♫ موسیقی")
            /// Actual native table text shows the current marker and retains the full accessible Unicode title.
            let cell = try XCTUnwrap(view.tableView(view.table, viewFor: view.table.tableColumns.first, row: 1) as? NSTableCellView)
            XCTAssertTrue(cell.textField?.stringValue.contains("▶") == true)
            XCTAssertTrue(cell.textField?.accessibilityLabel()?.contains("♫ موسیقی") == true)
            view.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            /// Synthetic Return event invokes the table's native key handler without running a mouse tracking loop.
            let enter = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            view.table.keyDown(with: enter)
            XCTAssertEqual(session.selectedIndex, 0)
            view.buttons["stop"]?.performClick(nil)
            XCTAssertEqual(session.state, .stopped)
            XCTAssertEqual(session.position, 0)
        }
    }

    /// Appends preserve browse selection; advancing transport synchronizes both surfaces and reveals the current row.
    func testQueueAppendAndAdvanceStaySynchronized() async throws {
        /// Original package with the full partial-playlist border profile.
        let package = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Empty session initially exercises empty-table control availability.
            let session = PlaybackSession(backend: PlaylistTestBackend())
            /// Controller binds queue mutations to both surfaces rather than replacing the observer.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(package)
            /// Empty playlist whose selected-row command must initially be disabled.
            let view = try XCTUnwrap(controller.classicPlaylist?.content)
            XCTAssertEqual(view.table.numberOfRows, 0)
            XCTAssertFalse(try XCTUnwrap(view.buttons["selected"]).isEnabled)
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav"), URL(fileURLWithPath: "/tmp/two.wav")])
            try session.play(index: 0)
            view.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            session.enqueue([URL(fileURLWithPath: "/tmp/three.wav")])
            XCTAssertEqual(view.table.numberOfRows, 3)
            XCTAssertEqual(session.status, "Playing · 3 tracks in queue")
            XCTAssertEqual(view.table.selectedRow, 1)
            XCTAssertEqual(session.selectedIndex, 0)
            session.finished(successfully: true)
            XCTAssertEqual(session.selectedIndex, 1)
            XCTAssertEqual(view.table.selectedRow, 1)
            view.buttons["next"]?.performClick(nil)
            XCTAssertEqual(session.selectedIndex, 2)
            XCTAssertEqual(view.table.selectedRow, 2)
            /// Main and playlist retain exactly the same model rather than copying queues.
            let main = try XCTUnwrap(controller.surface as? ClassicPlayerView)
            XCTAssertTrue(main.session === view.session)
            view.buttons["previous"]?.performClick(nil)
            XCTAssertEqual(view.table.selectedRow, 1)
            XCTAssertEqual(session.selectedIndex, 1)
        }
    }

    /// Imported Text colors apply; malformed/duplicate/oversized values safely fall back with diagnostics.
    func testPaletteParsingAndBoundedFallbacks() async throws {
        /// Original extracted fixture copied for isolated color-profile mutations.
        let source = try fixture("PlayableClassic")
        /// Unique temporary folder removed after the bounded parser assertions.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Known original green profile passes without palette warnings.
        let original = try ClassicSkinPackage.load(folder)
        try await MainActor.run {
            /// Original colors are decoded into the documented sRGB values.
            let style = try ClassicPlaylistStyle(package: original)
            XCTAssertEqual(style.current.greenComponent, 224.0 / 255, accuracy: 0.001)
            XCTAssertEqual(style.titles.count, 2)
            XCTAssertEqual(style.borders.count, 4)
        }
        /// Restricted INI rejects duplicate Normal and invalid Current while accepting a case-insensitive background.
        let ini = "[Other]\nCurrent=FF0000\n[Text]\nNormal=FF0000\nNormal=00FF00\nCurrent=GGGGGG\nnormalbg=#102030 ; comment\nSelectedBG=112233\n"
        try Data(ini.utf8).write(to: folder.appendingPathComponent("pledit.txt"))
        /// Structurally valid package; only the restricted color parser reports fallbacks.
        let malformed = try ClassicSkinPackage.load(folder)
        try await MainActor.run {
            /// Duplicate and invalid colors use the original readable defaults instead of ambiguous values.
            let style = try ClassicPlaylistStyle(package: malformed)
            XCTAssertEqual(style.normal.redComponent, 180.0 / 255, accuracy: 0.001)
            XCTAssertEqual(style.current.greenComponent, 224.0 / 255, accuracy: 0.001)
            XCTAssertEqual(style.background.redComponent, 16.0 / 255, accuracy: 0.001)
            XCTAssertTrue(style.diagnostics.contains { message in message.contains("Duplicate") })
            XCTAssertTrue(style.diagnostics.contains { message in message.contains("Invalid") })
        }
        try Data(repeating: 65, count: 16 * 1024 + 1).write(to: folder.appendingPathComponent("pledit.txt"))
        /// File is within importer limits but beyond the stricter main-thread color-profile budget.
        let oversized = try ClassicSkinPackage.load(folder)
        try await MainActor.run {
            /// Oversized text is ignored before string splitting and generates an explicit inspector warning.
            let style = try ClassicPlaylistStyle(package: oversized)
            XCTAssertTrue(style.diagnostics.contains { message in message.contains("16 KiB") })
        }
    }

    /// An unusable present playlist sheet rejects activation atomically; absent optional artwork remains usable.
    func testRejectedPlaylistAndMissingBorderFallback() async throws {
        /// Valid active package and inspectable invalid playlist border.
        let valid = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        /// One-pixel playlist BMP cannot satisfy the renderer's checked border crops.
        let invalid = try ClassicSkinPackage.load(fixture("invalid-playlist-border.wsz"))
        /// Temporary copy allows removal of both optional playlist resources.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture("PlayableClassic"), to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("pledit.bmp"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("pledit.txt"))
        /// Required main resources still permit a useful native playlist fallback.
        let fallback = try ClassicSkinPackage.load(folder)
        try await MainActor.run {
            _ = NSApplication.shared
            /// Already playing session must survive a failed two-window replacement.
            let session = PlaybackSession(backend: PlaylistTestBackend())
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav")]); try session.resume(); session.seek(to: 41)
            /// Actual controller hosting the initially valid Classic pair.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(valid)
            /// Surface identity proves neither half of a rejected activation was installed.
            let oldMain = controller.surface.view
            /// Panel identity proves the existing playlist survived validation failure.
            let oldPanel = try XCTUnwrap(controller.classicPlaylist)
            XCTAssertThrowsError(try controller.applyClassic(invalid))
            XCTAssertTrue(controller.surface.view === oldMain)
            XCTAssertTrue(controller.classicPlaylist === oldPanel)
            XCTAssertEqual(session.position, 41)
            XCTAssertEqual(session.state, .playing)
            /// Inspector applies the same validation as activation, preventing an enabled-but-failing button.
            let inspector = try ClassicSkinPreviewController(package: invalid)
            defer { inspector.close() }
            XCTAssertFalse(inspector.activateButton.isEnabled)
            try controller.applyClassic(fallback)
            XCTAssertTrue(try XCTUnwrap(controller.classicPlaylist).content.style.borders.isEmpty)
            XCTAssertEqual(controller.classicPlaylist?.content.table.numberOfRows, 1)
            XCTAssertEqual(session.position, 41)
            XCTAssertEqual(session.state, .playing)
        }
    }

    /// Closing/reopening the panel preserves output; theme changes preserve its visibility; closing the player stops all windows.
    func testPanelLifecycleAndThemeReplacement() async throws {
        /// Original alternate-palette skins test whole-window replacement and visibility preservation.
        let green = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        /// Nested uppercase blue package uses the same playlist resource profile.
        let blue = try ClassicSkinPackage.load(fixture("playable-classic-nested.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Backend load count detects audio recreation during window operations.
            let backend = PlaylistTestBackend()
            /// Playing session with non-default offset/gain to preserve through replacements.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav")]); try session.resume()
            session.seek(to: 39); session.setVolume(0.25)
            /// One native player controller owns and retires every Classic child panel.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            try controller.applyClassic(green)
            /// First panel and main view expose the visible-state indicator.
            let panel = try XCTUnwrap(controller.classicPlaylist)
            /// Main PL state must mirror both menu toggles and native title-bar closing.
            let main = try XCTUnwrap(controller.surface as? ClassicPlayerView)
            XCTAssertTrue(try XCTUnwrap(panel.window).isVisible)
            XCTAssertEqual(main.playlistButton.state, .on)
            panel.close()
            XCTAssertEqual(main.playlistButton.state, .off)
            XCTAssertEqual(session.state, .playing)
            controller.togglePlaylist()
            XCTAssertTrue(panel.window?.isVisible == true)
            XCTAssertTrue(controller.classicPlaylist === panel)
            controller.togglePlaylist()
            try controller.applyClassic(blue)
            XCTAssertFalse(controller.classicPlaylist?.window?.isVisible == true)
            controller.togglePlaylist()
            XCTAssertTrue(controller.classicPlaylist?.window?.isVisible == true)
            try controller.apply(ThemeCatalog.builtin("minimal"))
            XCTAssertNil(controller.classicPlaylist)
            XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(session.position, 39)
            XCTAssertEqual(session.volume, 0.25)
            XCTAssertEqual(backend.loads, 1)
            try controller.applyClassic(green)
            /// Last active panel must close with the primary player rather than leaving hidden audio running.
            let finalPanel = try XCTUnwrap(controller.classicPlaylist)
            controller.close()
            XCTAssertFalse(finalPanel.window?.isVisible == true)
            XCTAssertEqual(session.state, .stopped)
        }
    }
}
