// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import XCTest
@testable import Ampi

/// Deterministic output records unwanted reloads while real native queue controls perform edits.
@MainActor private final class QueueEditingBackend: EqualizerAudioBackend {
    /// Fake duration remains nonzero after stop to test masking when selection is cleared.
    var duration: Double = 100
    /// Fake playback clock, retained by edits to unrelated rows.
    var position: Double = 0
    /// Independent output gain retained across all queue edits.
    var volume: Float = 0.7
    /// Decoder load count detects accidental activation from browsing or moving rows.
    var loads = 0
    /// Current curve delivered by the session, independent of its presentation.
    var settings = EqualizerSettings()
    /// Records fake preparation and rewinds only when a new entry is explicitly loaded.
    func load(_ url: URL) throws { loads += 1; position = 0 }
    /// Reports successful output without opening a hardware device.
    func play() -> Bool { true }
    /// Keeps the fake offset when output is paused.
    func pause() {}
    /// Rewinds the fake decoder when stopping or removing its loaded entry.
    func stop() { position = 0 }
    /// Records delivered DSP values without changing transport.
    func applyEqualizer(_ settings: EqualizerSettings) { self.settings = settings }
}

/// Exercises keyboard, context menu, Classic buttons, and browse/current identity synchronization.
final class QueueEditingTests: XCTestCase {
    /// Constructs a focused native keyboard event; keyCode identifies the command, modifiers distinguish row movement.
    @MainActor private static func key(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
    }

    /// Native browsing survives appends and moves; Delete edits the highlighted row without activating it.
    func testNativeKeyboardEditsPreserveBrowseIdentityAndAudio() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            /// Shared capable fake detects recreation and retains EQ.
            let backend = QueueEditingBackend()
            /// Two duplicate filenames remain distinct queue entries.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/one.wav"), URL(fileURLWithPath: "/same.wav"), URL(fileURLWithPath: "/same.wav")])
            try session.resume(); session.seek(to: 42); session.setVolume(0.35)
            session.setEqualizerEnabled(true); session.applyEqualizerPreset(.bass)
            /// Native layout is refreshed through the same controller used by the running app.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            /// Active native queue is also the source of global Queue menu selection.
            let table = try XCTUnwrap(controller.editingTable)
            /// Loaded and browsed IDs must remain independent throughout the edits.
            let loaded = session.currentTrack?.id
            /// Browse the first duplicate without playing it.
            let browsed = session.tracks[1].id
            table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            session.enqueue([URL(fileURLWithPath: "/last.wav")])
            XCTAssertEqual(table.selectedRow, 1)
            table.keyDown(with: try Self.key(125, modifiers: [.option]))
            XCTAssertEqual(table.selectedRow, 2); XCTAssertEqual(session.tracks[2].id, browsed)
            XCTAssertEqual(session.currentTrack?.id, loaded); XCTAssertEqual(session.position, 42)
            table.keyDown(with: try Self.key(51))
            XCTAssertEqual(session.tracks.count, 3); XCTAssertEqual(table.selectedRow, 2)
            XCTAssertFalse(session.tracks.contains { track in track.id == browsed })
            XCTAssertEqual(session.currentTrack?.id, loaded); XCTAssertEqual(backend.loads, 1)
            XCTAssertEqual(session.volume, 0.35); XCTAssertEqual(session.equalizer.gains, EqualizerPreset.bass.gains)
            controller.editQueue(.remove)
            XCTAssertEqual(session.tracks.count, 2); XCTAssertEqual(table.selectedRow, 1)
            table.keyDown(with: try Self.key(36))
            XCTAssertEqual(session.selectedIndex, 1); XCTAssertEqual(backend.loads, 2)
            table.keyDown(with: try Self.key(117))
            XCTAssertNil(session.currentTrack); XCTAssertEqual(session.state, .stopped)
            XCTAssertEqual(session.duration, 0); XCTAssertEqual(session.position, 0)
            XCTAssertEqual(table.selectedRow, 0)
            table.keyDown(with: try Self.key(36))
            XCTAssertEqual(session.currentTrack?.title, "one"); XCTAssertEqual(backend.loads, 3)
        }
    }

    /// Classic editing buttons follow bounds and manipulate the same queue while preserving the loaded duplicate.
    func testClassicEditingButtonsAndClear() async throws {
        /// Original Classic resources include main, playlist, and EQ backgrounds.
        let package = try ClassicSkinPackage.load(XCTUnwrap(Bundle.module.url(forResource: "playable-classic", withExtension: "wsz", subdirectory: "Fixtures")))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Fake output is not reconstructed by moving or removing unrelated rows.
            let backend = QueueEditingBackend()
            /// Loaded second duplicate differs from the browsed first entry.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/one.wav"), URL(fileURLWithPath: "/same.wav"),
                             URL(fileURLWithPath: "/same.wav"), URL(fileURLWithPath: "/last.wav")])
            try session.play(index: 2); session.seek(to: 42)
            /// All panels share this controller's single observer.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(package)
            /// Actual Classic buttons edit the native table through selector dispatch.
            let view = try XCTUnwrap(controller.classicPlaylist?.content)
            /// Loaded identity is stable even when another entry crosses its position.
            let loaded = session.currentTrack?.id
            view.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            XCTAssertFalse(try XCTUnwrap(view.buttons["moveUp"]).isEnabled)
            view.buttons["moveDown"]?.performClick(nil); view.buttons["moveDown"]?.performClick(nil)
            XCTAssertEqual(view.table.selectedRow, 2); XCTAssertEqual(session.selectedIndex, 1)
            XCTAssertEqual(session.currentTrack?.id, loaded); XCTAssertEqual(session.position, 42)
            view.buttons["remove"]?.performClick(nil)
            XCTAssertEqual(session.tracks.count, 3); XCTAssertEqual(backend.loads, 1)
            view.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
            view.buttons["remove"]?.performClick(nil)
            XCTAssertNil(session.currentTrack); XCTAssertEqual(session.state, .stopped)
            XCTAssertEqual(view.table.selectedRow, 1)
            view.buttons["selected"]?.performClick(nil)
            XCTAssertEqual(session.currentTrack?.title, "last"); XCTAssertEqual(backend.loads, 2)
            view.buttons["moveUp"]?.performClick(nil)
            XCTAssertEqual(session.selectedIndex, 0)
            XCTAssertTrue(controller.canEditQueue(.clear)); XCTAssertFalse(controller.canEditQueue(.moveUp))
            view.buttons["clear"]?.performClick(nil)
            XCTAssertTrue(session.tracks.isEmpty); XCTAssertEqual(view.table.numberOfRows, 0)
            XCTAssertEqual(view.table.selectedRow, -1); XCTAssertEqual(session.duration, 0)
            /// Every editing control and row activation is disabled for an empty queue.
            for action in ["remove", "moveUp", "moveDown", "clear", "selected"] {
                XCTAssertFalse(try XCTUnwrap(view.buttons[action]).isEnabled)
            }
            session.enqueue([URL(fileURLWithPath: "/new.wav")]); try session.resume()
            XCTAssertEqual(view.table.numberOfRows, 1); XCTAssertEqual(view.table.selectedRow, 0)
            XCTAssertEqual(session.currentTrack?.title, "new")
        }
    }

    /// Context menus select the clicked row, disable row edits over empty space, and never delete music files.
    func testNativeContextMenuTargetsClickedRowAndValidatesEmptySpace() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            /// Three entries leave visible table space below the last row.
            let session = PlaybackSession(backend: QueueEditingBackend())
            session.enqueue(["one", "two", "three"].map { name in URL(fileURLWithPath: "/\(name).wav") }); try session.resume()
            /// Native queue receives right-click events through AppKit's contextual-menu override.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            /// Selected row intentionally differs from the subsequent right-clicked row.
            let table = try XCTUnwrap(controller.editingTable)
            table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
            /// Row-one midpoint transformed to the window coordinate system expected by NSEvent.
            let point = table.convert(NSPoint(x: 20, y: table.rect(ofRow: 1).midY), to: nil)
            /// Native right-click event targets the second row.
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            /// Context items are shared native editing actions, validated against the clicked selection.
            let menu = try XCTUnwrap(table.menu(for: event))
            XCTAssertEqual(table.selectedRow, 1)
            /// First context item removes the selected row through its actual native target/action.
            let remove = menu.items[0]
            XCTAssertTrue(table.validateMenuItem(remove))
            // Playback can change the highlighted row while a context menu is open; its clicked UUID remains the target.
            try session.play(index: 2)
            XCTAssertEqual(table.selectedRow, 2)
            XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(remove.action), to: remove.target, from: remove))
            XCTAssertEqual(session.tracks.map(\.title), ["one", "three"])
            XCTAssertEqual(session.currentTrack?.title, "three"); XCTAssertEqual(session.state, .playing)
            /// Empty-space point lies below the remaining rows inside the table's visible viewport.
            let emptyPoint = table.convert(NSPoint(x: 20, y: 140), to: nil)
            /// Right-clicking empty space cannot remove a previously highlighted row.
            let emptyEvent = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: emptyPoint, modifierFlags: [], timestamp: 0,
                windowNumber: controller.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            _ = table.menu(for: emptyEvent)
            XCTAssertEqual(table.selectedRow, -1); XCTAssertFalse(table.validateMenuItem(remove))
            XCTAssertTrue(table.validateMenuItem(menu.items[3]))
        }
    }
}
