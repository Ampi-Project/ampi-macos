// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import Darwin

/// Native application instance used by interactive mode and developer rendering checks.
let app = NSApplication.shared
app.setActivationPolicy(.regular)
/// Process arguments, including the executable path and optional developer-check mode.
let arguments = CommandLine.arguments

// Developer checks exercise the real native renderer/backend without interactive dialogs.
if arguments.count == 4 && arguments[1] == "--classic-preview" {
    do {
        /// Validated package read from the developer-supplied archive or folder.
        let package = try ClassicSkinPackage.load(URL(fileURLWithPath: arguments[2]))
        /// Inspector using the same bitmap rendering and diagnostic report as the live app.
        let controller = try ClassicSkinPreviewController(package: package)
        try controller.exportPreview(to: URL(fileURLWithPath: arguments[3]))
        print("PASS: Classic background preview, \(package.assets.count) assets, root '\(package.root)'. Preview only; controls are not activated.")
        exit(0)
    } catch { print("Classic inspection failed: \(error)"); exit(1) }
}

if arguments.count == 3 && arguments[1] == "--preview" {
    do {
        /// Output folder in which each bundled layout receives a PNG preview.
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        /// Empty session displayed in both preview layouts without starting audio.
        let session = PlaybackSession(backend: NativeAudioBackend())
        /// Bundled resource name used to select the layout and name its preview file.
        for name in ThemeCatalog.builtins {
            /// Temporary window controller whose native surface is rendered to PNG.
            let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin(name))
            try controller.exportPreview(to: directory.appendingPathComponent(name + ".png"))
        }
        print("Rendered both native layout previews.")
        exit(0)
    } catch { print("Preview failed: \(error)"); exit(1) }
}

if (3...4).contains(arguments.count) && arguments[1] == "--smoke-test" {
    do {
        /// Real native audio implementation used for the muted playback smoke check.
        let backend = NativeAudioBackend()
        /// Test session that exercises transport while the native layout is replaced.
        let session = PlaybackSession(backend: backend)
        session.setVolume(0)
        session.enqueue([URL(fileURLWithPath: arguments[2])])
        try session.play(index: 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard session.state == .playing, session.position > 0 else { throw PlaybackError.couldNotStart }
        session.seek(to: 0.5)
        /// Track identity captured before replacement to detect accidental session resets.
        let originalTrack = session.currentTrack?.id
        /// Player initially using Retro Stereo, then switched to Quiet Space during playback.
        let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
        try controller.apply(ThemeCatalog.builtin("minimal"))
        guard session.currentTrack?.id == originalTrack, session.state == .playing,
              session.volume == 0, session.position >= 0.5 else { throw PlaybackError.couldNotStart }
        if arguments.count == 4 {
            controller.open([URL(fileURLWithPath: arguments[3])])
            /// Bounded wait for the same asynchronous inspector invoked by file-open and drop handling.
            let deadline = Date().addingTimeInterval(5)
            while controller.classicPreview == nil && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            /// Completed visible inspector whose layer-backed drawing is checked during playback.
            guard let preview = controller.classicPreview else { throw ThemeError.invalid("Classic inspection did not open its preview within five seconds.") }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            guard controller.surface.theme.id == "ampi.minimal", session.currentTrack?.id == originalTrack,
                  session.state == .playing, session.volume == 0, session.position >= 0.5 else {
                throw ThemeError.invalid("Classic inspection changed the active playback session.")
            }
            preview.close()
            print("PASS: Classic inspection preserved the active layout, track, playback, position, and volume.")
        }
        try session.togglePlayback()
        guard session.state == .paused else { throw PlaybackError.couldNotStart }
        session.stop()
        guard session.state == .stopped, session.position == 0 else { throw PlaybackError.couldNotStart }
        print("PASS: muted native audio output, seek, layout replacement, pause, and stop.")
        exit(0)
    } catch { print("Smoke test failed: \(error)"); exit(1) }
}

/// Strongly retained lifecycle delegate because AppKit's delegate reference is weak.
let delegate = AppDelegate()
app.delegate = delegate
app.run()
