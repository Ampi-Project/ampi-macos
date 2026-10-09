// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Developer-only real-decoder restart checks use copies in a disposable directory, never the owner's saved session.
@MainActor enum PersistenceSmokeCheck {
    /// Saves/restores muted native playback, then challenges missing assets and corrupt state without touching inputs.
    /// - Parameters: audio is a readable track longer than 1.5 seconds; skin is an optional supported original Classic fixture.
    /// - Throws: File, renderer, playback, or invariant failure; all temporary copies are removed on return.
    static func run(audio: URL, skin: URL?) async throws {
        /// Isolated workspace contains every state file and copied media/skin used by the check.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ampi-restart-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        /// First local copy is represented by two distinct queue identities.
        let localAudio = folder.appendingPathComponent(audio.lastPathComponent)
        try FileManager.default.copyItem(at: audio, to: localAudio)
        /// Separate source is removed later to test pruning an unavailable nonselected entry.
        let unavailable = folder.appendingPathComponent("offline-" + audio.lastPathComponent)
        try FileManager.default.copyItem(at: audio, to: unavailable)
        /// Optional copied Classic path may be removed without altering the supplied fixture.
        let localSkin = folder.appendingPathComponent("skin.wsz")
        /// Actor writes only within this temporary namespace.
        let store = SessionStateStore(url: folder.appendingPathComponent("session.json"))
        /// Real graph starts muted before any file is decoded or played.
        let backend = NativeAudioBackend()
        /// Live duplicate selection and nondefault policies will be recovered by a fresh backend/controller.
        let session = PlaybackSession(backend: backend)
        session.setVolume(0); session.enqueue([localAudio, localAudio, unavailable])
        try session.play(index: 1)
        guard session.duration > 1.5 else { throw ThemeError.invalid("Persistence smoke audio must exceed 1.5 seconds.") }
        session.seek(to: 0.5); session.pause()
        session.setShuffleEnabled(true); session.setRepeatMode(.one)
        session.setEqualizerEnabled(true); session.applyEqualizerPreset(.voice)
        /// Native layout has different geometry from the initial default.
        let first = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
        defer { first.close() }
        try first.apply(ThemeCatalog.builtin("minimal"))
        /// Provided Classic input is copied, boundedly parsed, and fully checked before becoming the saved choice.
        if let skin {
            try FileManager.default.copyItem(at: skin, to: localSkin)
            try first.applyClassic(ClassicSkinPackage.load(localSkin))
        }
        /// Durable values are compared by identity/settings, never by matching repeated filenames.
        let original = session.savedState(skin: first.savedSkin)
        try await PlayerPersistence(controller: first, store: store).flush()
        first.close()

        /// Independent native decoder approximates a fresh process with no inherited output clock or random history.
        let restarted = PlaybackSession(backend: NativeAudioBackend())
        /// Startup fallback remains ready until valid saved state has restored.
        let second = PlayerWindowController(session: restarted, theme: try ThemeCatalog.builtin("retro"))
        defer { second.close() }
        /// New actor proves recovery comes from disk, not a retained snapshot object.
        let recovery = PlayerPersistence(controller: second, store: SessionStateStore(url: store.url))
        /// Successful restart must not announce any skipped or corrupt input.
        let notices = await recovery.restore()
        guard notices.isEmpty, restarted.tracks == original.tracks,
              restarted.currentTrack?.id == original.selectedTrackID, restarted.volume == 0,
              restarted.equalizer == original.equalizer, restarted.isShuffleEnabled, restarted.repeatMode == .one,
              restarted.state == .stopped, restarted.position == 0,
              second.surface.presentationID == (skin == nil ? "ampi.minimal" : "ampi.classic.main") else {
            throw ThemeError.invalid("Restart lost durable identity/settings/skin or started output.")
        }
        try await Task.sleep(for: .milliseconds(100))
        guard restarted.position == 0 else { throw ThemeError.invalid("Restored decoder advanced before explicit Play.") }
        try restarted.resume()
        try await Task.sleep(for: .milliseconds(150))
        guard restarted.state == .playing, restarted.position > 0 else { throw PlaybackError.couldNotStart }
        second.close()
        print("PASS: disk restart restored duplicate identity, layout, volume, EQ, shuffle/repeat, and stopped clock; explicit muted Play started normally.")

        try FileManager.default.removeItem(at: unavailable)
        if skin != nil { try FileManager.default.removeItem(at: localSkin) }
        /// Remaining two duplicate entries are retained after the third source goes offline.
        let partial = PlaybackSession(backend: NativeAudioBackend())
        /// Default native layout is retained if the copied Classic source can no longer be reopened.
        let third = PlayerWindowController(session: partial, theme: try ThemeCatalog.builtin("retro"))
        defer { third.close() }
        /// Missing paths produce a partial-recovery notice while leaving original input files untouched.
        let missing = await PlayerPersistence(controller: third, store: SessionStateStore(url: store.url)).restore()
        guard missing.count == (skin == nil ? 1 : 2), partial.tracks == Array(original.tracks.prefix(2)),
              partial.currentTrack?.id == original.selectedTrackID, partial.state == .stopped,
              partial.equalizer == original.equalizer, partial.volume == 0,
              third.surface.presentationID == (skin == nil ? "ampi.minimal" : "ampi.retro") else {
            throw ThemeError.invalid("Missing-file/skin recovery discarded valid queue or audio settings.")
        }
        third.close()
        try Data("{broken".utf8).write(to: store.url)
        /// Structurally corrupt state cannot supply trusted values to a fourth fresh player.
        let defaults = PlaybackSession(backend: NativeAudioBackend())
        /// Corruption fallback uses the same default native initialization as interactive launch.
        let fourth = PlayerWindowController(session: defaults, theme: try ThemeCatalog.builtin("retro"))
        defer { fourth.close() }
        /// Invalid JSON is diagnosed without overwriting it during the read itself.
        let corrupt = await PlayerPersistence(controller: fourth, store: SessionStateStore(url: store.url)).restore()
        guard corrupt.count == 1, defaults.tracks.isEmpty, defaults.currentTrack == nil,
              defaults.state == .stopped, !defaults.isShuffleEnabled, defaults.repeatMode == .off,
              defaults.equalizer == EqualizerSettings(), fourth.surface.presentationID == "ampi.retro",
              FileManager.default.fileExists(atPath: audio.path),
              skin == nil || FileManager.default.fileExists(atPath: skin!.path) else {
            throw ThemeError.invalid("Corrupt-state recovery did not preserve safe defaults and original inputs.")
        }
        print("PASS: unavailable audio was skipped, \(skin == nil ? "embedded native layout was retained" : "missing Classic source fell back safely"), corrupt JSON restored defaults, and source files remained intact.")
    }
}
