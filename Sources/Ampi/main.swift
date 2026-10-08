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
if arguments.count == 4 && arguments[1] == "--classic-equalizer-preview" {
    do {
        /// Bounded original or user-supplied package provides the optional EQ background.
        let package = try ClassicSkinPackage.load(URL(fileURLWithPath: arguments[2]))
        /// Live EQ model uses the real backend but renders without loading or playing audio.
        let session = PlaybackSession(backend: NativeAudioBackend())
        session.setEqualizerEnabled(true); session.applyEqualizerPreset(.bass)
        /// Same native controls and checked background used by interactive activation.
        let controller = try EqualizerWindowController(package: package, session: session)
        try controller.exportPreview(to: URL(fileURLWithPath: arguments[3]))
        print("PASS: rendered equalizer with native ten-band, preamp, bypass, and preset controls.")
        exit(0)
    } catch { print("Equalizer preview failed: \(error)"); exit(1) }
}

if arguments.count == 4 && arguments[1] == "--classic-playlist-preview" {
    do {
        /// Original or user-supplied bounded Classic package used by the actual playlist renderer.
        let package = try ClassicSkinPackage.load(URL(fileURLWithPath: arguments[2]))
        /// Illustrative queue filenames exercise native Unicode drawing without decoding or playing files.
        let session = PlaybackSession(backend: NativeAudioBackend())
        session.enqueue([URL(fileURLWithPath: "/preview/First song.wav"),
                         URL(fileURLWithPath: "/preview/♫ موسیقی.wav"), URL(fileURLWithPath: "/preview/Third song.wav")])
        /// Same border/palette and native table/toolbar used by the activated app.
        let controller = try ClassicPlaylistWindowController(package: package, session: session)
        try controller.exportPreview(to: URL(fileURLWithPath: arguments[3]))
        print("PASS: rendered partial Classic playlist with native queue, scrolling, Unicode text, and transport toolbar.")
        exit(0)
    } catch { print("Classic playlist preview failed: \(error)"); exit(1) }
}

if arguments.count == 4 && arguments[1] == "--classic-player-preview" {
    do {
        /// Validated input passed through the same activation profile as the interactive inspector.
        let package = try ClassicSkinPackage.load(URL(fileURLWithPath: arguments[2]))
        /// Empty persistent session; rendering this developer preview never starts audio.
        let session = PlaybackSession(backend: NativeAudioBackend())
        /// Native window whose content is replaced by the activated Classic main renderer.
        let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
        try controller.applyClassic(package)
        try controller.exportPreview(to: URL(fileURLWithPath: arguments[3]))
        print("PASS: rendered Classic main player with native transport, seek, and volume. Full Classic support remains incomplete.")
        exit(0)
    } catch { print("Classic activation failed: \(error)"); exit(1) }
}

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
        session.setEqualizerEnabled(true)
        session.applyEqualizerPreset(.bass)
        session.setEqualizerGain(-6, at: 5)
        /// Non-flat curve must survive all subsequent transport and presentation operations.
        let originalEqualizer = session.equalizer
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
            guard controller.surface.presentationID == "ampi.minimal", session.currentTrack?.id == originalTrack,
                  session.state == .playing, session.volume == 0, session.position >= 0.5 else {
                throw ThemeError.invalid("Classic inspection changed the active playback session.")
            }
            preview.close()
            print("PASS: Classic inspection preserved the active layout, track, playback, position, and volume.")
            if preview.activateButton.isEnabled {
                preview.activateButton.performClick(nil)
                guard controller.surface.presentationID == "ampi.classic.main",
                      session.currentTrack?.id == originalTrack, session.state == .playing,
                      session.volume == 0, session.position >= 0.5 else {
                    throw ThemeError.invalid("Classic activation changed the persistent playback session.")
                }
                /// Actual bitmap controls route through native selectors to the real audio backend.
                guard let classic = controller.surface as? ClassicPlayerView else { throw PlaybackError.couldNotStart }
                classic.buttons[2].performClick(nil)
                guard session.state == .paused else { throw PlaybackError.couldNotStart }
                session.seek(to: session.duration)
                guard session.position > session.duration - 0.05, session.position < session.duration else {
                    throw ThemeError.invalid("Paused endpoint seek wrapped to zero instead of the final audio sample.")
                }
                session.seek(to: 0.5)
                classic.buttons[1].performClick(nil)
                guard session.state == .playing else { throw PlaybackError.couldNotStart }
                /// Active queue panel shares the exact session and is populated without another decoder/model.
                guard let playlist = controller.classicPlaylist, playlist.content.session === session else {
                    throw ThemeError.invalid("Classic playlist did not share the active session.")
                }
                session.enqueue([URL(fileURLWithPath: arguments[2])])
                playlist.content.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
                playlist.content.buttons["selected"]?.performClick(nil)
                guard session.selectedIndex == 1, session.currentTrack?.id != originalTrack,
                      session.state == .playing, session.volume == 0 else { throw PlaybackError.couldNotStart }
                playlist.content.buttons["previous"]?.performClick(nil)
                guard session.currentTrack?.id == originalTrack, playlist.content.table.selectedRow == 0 else {
                    throw ThemeError.invalid("Playlist transport failed to synchronize the main queue.")
                }
                controller.togglePlaylist()
                guard playlist.window?.isVisible == false, session.state == .playing else { throw PlaybackError.couldNotStart }
                controller.togglePlaylist()
                guard playlist.window?.isVisible == true, session.state == .playing else { throw PlaybackError.couldNotStart }
                try controller.apply(ThemeCatalog.builtin("retro"))
                guard controller.classicPlaylist == nil, playlist.window?.isVisible == false,
                      session.currentTrack?.id == originalTrack, session.state == .playing, session.volume == 0,
                      session.equalizer == originalEqualizer, controller.equalizerPanel?.content.session === session else {
                    throw ThemeError.invalid("Restoring the native layout changed playback.")
                }
                print("PASS: Classic activation, sprite Play/Pause, playlist selection/transport/hide/reopen, endpoint seek, and default restoration preserved the real audio session.")
            }
        }
        try session.togglePlayback()
        guard session.state == .paused else { throw PlaybackError.couldNotStart }
        session.stop()
        guard session.state == .stopped, session.position == 0 else { throw PlaybackError.couldNotStart }
        guard session.equalizer == originalEqualizer else { throw ThemeError.invalid("Transport reset the EQ curve.") }
        print("PASS: muted AVAudioEngine output through EQ, seek, layout replacement, pause, stop, and curve retention.")
        exit(0)
    } catch { print("Smoke test failed: \(error)"); exit(1) }
}

/// Strongly retained lifecycle delegate because AppKit's delegate reference is weak.
let delegate = AppDelegate()
app.delegate = delegate
app.run()
