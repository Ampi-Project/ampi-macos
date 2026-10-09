// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import XCTest
@testable import Ampi

/// Deterministic output recording transport behavior reached through native Classic controls.
@MainActor private final class ClassicTestBackend: AudioBackend {
    /// Fixed track duration in seconds for seek endpoint checks.
    var duration = 120.0
    /// Simulated offset updated by the actual slider callback.
    var position = 0.0
    /// Simulated gain retained when the presentation changes.
    var volume: Float = 0.7
    /// Number of decoded selections, proving skin replacement does not reload audio.
    var loads = 0
    /// Prepares the next fake track and resets only its position.
    func load(_ url: URL) throws { loads += 1; position = 0 }
    /// Reports successful output without opening an audio device.
    func play() -> Bool { true }
    /// Simulates suspension without changing position.
    func pause() {}
    /// Rewinds the simulated current track.
    func stop() { position = 0 }
}

/// Checks real native control dispatch, replacement safety, sprite geometry, and activation diagnostics.
final class ClassicPlayerTests: XCTestCase {
    /// Native and Classic mode buttons share checked state without altering stream/queue during replacements.
    func testModeControlsAndSkinReplacementRetainPlaybackPolicy() async throws {
        /// Original artwork supports the Classic main/playlist/EQ profiles.
        let package = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Decoder count and offset expose any accidental reset from mode control actions.
            let backend = ClassicTestBackend()
            /// Persistent session starts paused so policy changes cannot hide unintended transport changes.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/one.wav"), URL(fileURLWithPath: "/two.wav")])
            try session.resume(); session.seek(to: 42); session.pause()
            /// Controller connects all supported button actions to the shared model.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            /// Native built-in controls must be present rather than only accessible from menus.
            let native = try XCTUnwrap(controller.surface as? SkinView)
            XCTAssertEqual(native.modeButtons.count, 2)
            native.modeButtons[0].performClick(nil); native.modeButtons[1].performClick(nil)
            XCTAssertTrue(session.isShuffleEnabled); XCTAssertEqual(session.repeatMode, .all)
            XCTAssertEqual(native.modeButtons[0].title, "Shuffle: On")
            XCTAssertEqual(native.modeButtons[1].accessibilityValue() as? String, "All")
            try controller.applyClassic(package)
            /// Original native Classic controls expose the same live state and checked appearance.
            let classic = try XCTUnwrap(controller.surface as? ClassicPlayerView)
            XCTAssertEqual(classic.shuffleButton.state, .on); XCTAssertEqual(classic.repeatButton.title, "R:ALL")
            classic.repeatButton.performClick(nil)
            XCTAssertEqual(session.repeatMode, .one); XCTAssertEqual(classic.repeatButton.title, "R:1")
            classic.repeatButton.performClick(nil); classic.shuffleButton.performClick(nil)
            XCTAssertEqual(session.repeatMode, .off); XCTAssertFalse(session.isShuffleEnabled)
            try controller.apply(ThemeCatalog.builtin("minimal"))
            /// Second layout has distinct geometry but still reflects modes set in the Classic surface.
            let minimal = try XCTUnwrap(controller.surface as? SkinView)
            XCTAssertEqual(minimal.modeButtons[0].title, "Shuffle: Off")
            XCTAssertEqual(minimal.modeButtons[1].title, "Repeat: Off")
            XCTAssertEqual(session.state, .paused); XCTAssertEqual(session.position, 42)
            XCTAssertEqual(backend.loads, 1); XCTAssertEqual(session.tracks.count, 2)
        }
    }

    /// Locates a bundled original fixture independent of the test process's working directory.
    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }

    /// Native button and slider actions must affect playback with separate Play and Pause behavior.
    func testNativeClassicControlsDrivePersistentPlayback() async throws {
        /// Original complete main-window profile, parsed by the same bounded importer as user skins.
        let package = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Fake backend records unintended audio reloads across button actions.
            let backend = ClassicTestBackend()
            /// Session shared by the initial native and subsequent Classic surface.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav"), URL(fileURLWithPath: "/tmp/♫ موسیقی.wav")])
            /// Actual controller connects native selectors to the common playback model.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(package)
            /// Active Classic view with real NSButton/NSSlider instances.
            let view = try XCTUnwrap(controller.surface as? ClassicPlayerView)
            XCTAssertEqual(view.bounds.size, NSSize(width: 550, height: 232))
            XCTAssertEqual(view.buttons.count, 6)
            XCTAssertFalse(view.seekSlider.isEnabled)
            view.buttons[1].performClick(nil)
            XCTAssertEqual(session.state, .playing)
            XCTAssertTrue(view.seekSlider.isEnabled)
            session.seek(to: 42)
            view.buttons[1].performClick(nil)
            XCTAssertEqual(session.state, .playing)
            view.buttons[2].performClick(nil)
            XCTAssertEqual(session.state, .paused)
            XCTAssertEqual(session.position, 42)
            view.buttons[1].performClick(nil)
            XCTAssertEqual(backend.loads, 1)
            view.seekSlider.doubleValue = 77
            _ = view.seekSlider.sendAction(view.seekSlider.action, to: view.seekSlider.target)
            XCTAssertEqual(session.position, 77)
            view.volumeSlider.doubleValue = 0.25
            _ = view.volumeSlider.sendAction(view.volumeSlider.action, to: view.volumeSlider.target)
            XCTAssertEqual(session.volume, 0.25)
            view.buttons[3].performClick(nil)
            XCTAssertEqual(session.state, .stopped)
            XCTAssertEqual(session.position, 0)
            view.buttons[2].performClick(nil)
            XCTAssertEqual(session.state, .stopped)
            view.buttons[4].performClick(nil)
            XCTAssertEqual(session.selectedIndex, 1)
            XCTAssertEqual(session.currentTrack?.title, "♫ موسیقی")
            view.buttons[0].performClick(nil)
            XCTAssertEqual(session.selectedIndex, 0)
            XCTAssertEqual(view.buttons[1].accessibilityLabel(), "Play")
            XCTAssertEqual(view.seekSlider.accessibilityLabel(), "Playback position")
        }
    }

    /// Valid and invalid native/Classic replacements must preserve the selected queue and playback.
    func testReplacementAndRejectedActivationPreserveSession() async throws {
        /// Original flat and mixed-case nested skins plus an inspectable but undersized control sheet.
        let green = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        /// Different palette proves a second Classic package can replace the first.
        let blue = try ClassicSkinPackage.load(fixture("playable-classic-nested.wsz"))
        /// Main bitmap is valid, but a one-pixel transport sheet cannot be activated.
        let invalid = try ClassicSkinPackage.load(fixture("invalid-main-controls.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Backend load count detects a reset even if track titles happen to match.
            let backend = ClassicTestBackend()
            /// Playing session with non-default offset and gain.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/tmp/one.wav")])
            try session.resume(); session.seek(to: 53); session.setVolume(0.2)
            /// Queue identity retained across every presentation change.
            let ids = session.tracks.map(\.id)
            /// Window hosting all replacements while keeping a single observer/timer.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
            defer { controller.close() }
            try controller.applyClassic(green)
            try controller.applyClassic(blue)
            /// Valid surface identity captured before the failed activation attempt.
            let previous = controller.surface.view
            XCTAssertThrowsError(try controller.applyClassic(invalid))
            XCTAssertTrue(controller.surface.view === previous)
            try controller.apply(ThemeCatalog.builtin("minimal"))
            XCTAssertEqual(controller.surface.presentationID, "ampi.minimal")
            XCTAssertEqual(controller.surface.view.bounds.size, NSSize(width: 460, height: 550))
            XCTAssertEqual(session.tracks.map(\.id), ids)
            XCTAssertEqual(session.position, 53)
            XCTAssertEqual(session.volume, 0.2)
            XCTAssertEqual(session.state, .playing)
            XCTAssertEqual(backend.loads, 1)
            /// Inspector presents the same failed activation as an unavailable button, without closing playback.
            let preview = try ClassicSkinPreviewController(package: invalid)
            defer { preview.close() }
            XCTAssertFalse(preview.activateButton.isEnabled)
        }
    }

    /// Missing optional sprites use native sliders; all present sheets must cover their required crops.
    func testOptionalFallbackAndUndersizedSheets() async throws {
        /// Extracted fixture copied to a unique temporary folder for safe mutation.
        let source = try fixture("PlayableClassic")
        /// Per-test workspace outside the repository, removed after the assertions.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        /// Valid tiny BMP from the negative transport fixture, reused to challenge each optional sheet.
        let tiny = try XCTUnwrap(ClassicSkinPackage.load(fixture("invalid-main-controls.wsz")).assets["cbuttons.bmp"])
        /// Each optional filename is tested independently, restoring its original data afterward.
        for name in ["posbar.bmp", "volume.bmp", "titlebar.bmp"] {
            /// Original optional bytes retained to keep the other cases independent.
            let url = folder.appendingPathComponent(name)
            /// Original fixture data restored after the undersized-sheet check.
            let original = try Data(contentsOf: url)
            try tiny.write(to: url)
            /// Package still passes structural inspection but not renderer-specific cropping.
            let invalid = try ClassicSkinPackage.load(folder)
            try await MainActor.run { XCTAssertThrowsError(try ClassicMainSprites(package: invalid)) }
            try original.write(to: url)
        }
        /// Removing all optional sheets must keep the required main transport profile usable.
        for name in ["posbar.bmp", "volume.bmp", "titlebar.bmp"] { try FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        /// Required main/cbuttons package exercises documented native slider fallbacks.
        let fallback = try ClassicSkinPackage.load(folder)
        try await MainActor.run {
            _ = NSApplication.shared
            /// Composed fallback view must retain functional native input controls.
            let view = try ClassicPlayerView(package: fallback, session: PlaybackSession(backend: ClassicTestBackend()))
            XCTAssertFalse(view.seekSlider.cell is ClassicSliderCell)
            XCTAssertFalse(view.volumeSlider.cell is ClassicSliderCell)
            XCTAssertEqual(view.buttons.count, 6)
        }
    }

    /// Real sprite drawing must distinguish idle/pressed colors and keep slider endpoints inside the view.
    func testSpriteRenderingAndSliderGeometry() async throws {
        /// Complete original sprite profile used for exact source-pixel assertions.
        let package = try ClassicSkinPackage.load(fixture("playable-classic.wsz"))
        try await MainActor.run {
            _ = NSApplication.shared
            /// Native renderer and controls with a deterministic empty audio session.
            let view = try ClassicPlayerView(package: package, session: PlaybackSession(backend: ClassicTestBackend()))
            /// Normal and pressed states both use real bitmap cropping/drawing.
            for pressed in [false, true] {
                view.buttons[1].highlight(pressed)
                /// Native drawing context covering the Play button's complete hit rectangle.
                let bitmap = try XCTUnwrap(view.buttons[1].bitmapImageRepForCachingDisplay(in: view.buttons[1].bounds))
                view.buttons[1].cacheDisplay(in: view.buttons[1].bounds, to: bitmap)
                /// Pixel away from the icon/border must match the known original face color.
                let color = try XCTUnwrap(bitmap.colorAt(x: 4, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
                XCTAssertEqual(color.redComponent, CGFloat(pressed ? 75 : 41) / 255, accuracy: 0.02)
                XCTAssertEqual(color.greenComponent, CGFloat(pressed ? 224 : 60) / 255, accuracy: 0.02)
            }
            /// Volume cell uses the original 14-pixel thumb at 2× display scale.
            let cell = try XCTUnwrap(view.volumeSlider.cell as? ClassicSliderCell)
            view.volumeSlider.doubleValue = 0
            XCTAssertEqual(cell.knobRect(flipped: true).minX, 0)
            view.volumeSlider.doubleValue = 1
            XCTAssertEqual(cell.knobRect(flipped: true).maxX, view.volumeSlider.bounds.maxX)
            /// Full surface render also exercises Unicode-ready text and both sprite sliders.
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            XCTAssertNotNil(bitmap.representation(using: .png, properties: [:]))
        }
    }
}
