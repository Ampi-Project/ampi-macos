// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import XCTest
@testable import Ampi

/// Deterministic capable backend detecting transport changes during panel actions.
@MainActor private final class EqualizerViewTestBackend: EqualizerAudioBackend {
    /// Fixed duration in seconds for the virtual selected track.
    var duration: Double = 100
    /// Current fake offset in seconds, unaffected by EQ actions.
    var position: Double = 0
    /// Independent output gain retained during curve changes.
    var volume: Float = 0.7
    /// Most recently delivered curve for synchronization assertions.
    var settings = EqualizerSettings()
    /// Decoder replacements counted to detect unintended audio reconstruction by UI actions.
    var loads = 0
    /// Records track preparation, resetting only the fake offset.
    func load(_ url: URL) throws { loads += 1; position = 0 }
    /// Reports a successful start without hardware output.
    func play() -> Bool { true }
    /// Pauses without changing the offset.
    func pause() {}
    /// Rewinds stopped output to zero seconds.
    func stop() { position = 0 }
    /// Records actual delivery from the model to its capable backend.
    func applyEqualizer(_ settings: EqualizerSettings) { self.settings = settings }
}

/// Exercises actual native controls, shared-model ownership, fallback artwork, and atomic activation.
final class EqualizerWindowTests: XCTestCase {
    /// Resolves a bundled original fixture independent of the test runner's current directory.
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }

    /// Bypass, preamp/band sliders, presets, reset, and panel hiding all preserve playback.
    func testNativeControlsAndPanelLifecycle() async throws {
        /// Original green and blue backgrounds exercise window replacement.
        let green = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        /// Nested package has different artwork but the same supported EQ profile.
        let blue = try ClassicSkinPackage.load(fixture("playable-classic-nested.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Backend verifies native selectors deliver changes without reloading audio.
            let backend = EqualizerViewTestBackend()
            /// Persistent playback state includes non-default position and volume.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/one.wav")]); try session.resume()
            session.seek(to: 39); session.setVolume(0.25)
            /// Controller owns the only observer and synchronizes its detachable EQ window.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(green)
            /// First activation opens a full native EQ panel backed by the exact existing session.
            let panel = try XCTUnwrap(controller.equalizerPanel)
            /// Native controls receive the same model; no secondary playback session is created.
            let view = panel.content
            XCTAssertTrue(view.session === session); XCTAssertEqual(view.sliders.count, 11)
            XCTAssertNotNil(view.style.background)
            XCTAssertEqual(view.enabledButton.state, .off)
            view.enabledButton.performClick(nil)
            XCTAssertTrue(session.equalizer.isEnabled)
            view.sliders[6].doubleValue = -7
            XCTAssertTrue(view.sliders[6].sendAction(view.sliders[6].action, to: view.sliders[6].target))
            XCTAssertEqual(session.equalizer.gains[5], -7)
            view.sliders[0].doubleValue = -3
            XCTAssertTrue(view.sliders[0].sendAction(view.sliders[0].action, to: view.sliders[0].target))
            XCTAssertEqual(session.equalizer.preamp, -3)
            XCTAssertEqual(view.presets.titleOfSelectedItem, "Custom")
            view.enabledButton.performClick(nil)
            XCTAssertFalse(session.equalizer.isEnabled)
            XCTAssertEqual(session.equalizer.gains[5], -7)
            view.presets.selectItem(withTitle: "Bass")
            XCTAssertTrue(view.presets.sendAction(view.presets.action, to: view.presets.target))
            XCTAssertEqual(backend.settings.gains, EqualizerPreset.bass.gains)
            XCTAssertFalse(backend.settings.isEnabled)
            view.flatButton.performClick(nil)
            XCTAssertEqual(session.equalizer.preamp, 0)
            XCTAssertEqual(view.sliders[6].doubleValue, 0)
            session.setEqualizerEnabled(true); session.applyEqualizerPreset(.voice)
            /// Edited curve survives native close, hidden Classic replacement, and native-theme restoration.
            let curve = session.equalizer
            panel.close()
            XCTAssertEqual((controller.surface as? ClassicPlayerView)?.equalizerButton.state, .off)
            try controller.applyClassic(blue)
            XCTAssertFalse(controller.equalizerPanel?.window?.isVisible == true)
            XCTAssertEqual(session.equalizer, curve)
            try controller.apply(ThemeCatalog.builtin("minimal"))
            XCTAssertNil(controller.equalizerPanel?.content.style.background)
            controller.toggleEqualizer()
            XCTAssertTrue(controller.equalizerPanel?.window?.isVisible == true)
            XCTAssertEqual(session.equalizer, curve)
            XCTAssertEqual(session.position, 39); XCTAssertEqual(session.volume, 0.25)
            XCTAssertEqual(session.state, .playing); XCTAssertEqual(backend.loads, 1)
            /// Main close must retire the EQ as well as the queue and stop output.
            let finalPanel = try XCTUnwrap(controller.equalizerPanel)
            controller.close()
            XCTAssertFalse(finalPanel.window?.isVisible == true)
            XCTAssertEqual(session.state, .stopped)
        }
    }

    /// Present undersized artwork rejects all three surfaces; missing artwork provides functioning native controls.
    func testInvalidEqualizerIsAtomicAndMissingArtworkFallsBack() async throws {
        /// Valid package, inspectable one-pixel EQ, and older package without optional EQ artwork.
        let valid = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        /// Structurally valid input cannot satisfy the EQ background rendering profile.
        let invalid = try ClassicSkinPackage.load(fixture("invalid-equalizer.wsz"))
        /// A temporary extracted folder allows removing exactly the optional EQ background.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture("PlayableClassic"), to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("eqmain.bmp"))
        /// Required main resources remain intact after omitting only the EQ background.
        let fallback = try ClassicSkinPackage.load(folder)
        try await MainActor.run {
            _ = NSApplication.shared
            /// Playback must remain unchanged when a skin fails EQ validation.
            let session = PlaybackSession(backend: EqualizerViewTestBackend())
            session.enqueue([URL(fileURLWithPath: "/one.wav")]); try session.resume(); session.seek(to: 21)
            session.setEqualizerEnabled(true); session.applyEqualizerPreset(.bass)
            /// Already active set of valid windows must survive the rejected replacement.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(valid)
            /// Main, playlist, and EQ identities are checked independently after failure.
            let oldMain = controller.surface.view
            /// Existing queue panel cannot be replaced by a half-activated skin.
            let oldPlaylist = controller.classicPlaylist
            /// Existing EQ panel retains its controls and current settings.
            let oldEQ = controller.equalizerPanel
            XCTAssertThrowsError(try controller.applyClassic(invalid))
            XCTAssertTrue(controller.surface.view === oldMain)
            XCTAssertTrue(controller.classicPlaylist === oldPlaylist)
            XCTAssertTrue(controller.equalizerPanel === oldEQ)
            XCTAssertEqual(session.position, 21); XCTAssertEqual(session.state, .playing)
            /// Inspector disables activation using the same EQ validation as the actual renderer.
            let inspector = try ClassicSkinPreviewController(package: invalid)
            defer { inspector.close() }
            XCTAssertFalse(inspector.activateButton.isEnabled)
            try controller.applyClassic(fallback)
            XCTAssertNil(controller.equalizerPanel?.content.style.background)
            XCTAssertTrue(controller.equalizerPanel?.content.enabledButton.isEnabled == true)
            XCTAssertEqual(session.equalizer.gains, EqualizerPreset.bass.gains)
            XCTAssertEqual(session.position, 21)
        }
    }
}
