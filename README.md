# Ampi for macOS

A free native music player with an original retro interface, whole-interface themes, and planned Winamp Classic and Modern skin import.

## Current state

The native prototype is a standalone Swift package with local audio playback, queue and transport controls, native menus, and two replaceable JSON layouts. Increment 2 adds bounded Classic `.wsz`/ZIP/folder inspection and a bitmap preview with diagnostics. Full Classic activation and Modern support remain pending. No public application release has been created. See [DEVELOPMENT.md](DEVELOPMENT.md) for remaining work.

## Build and run

Requirements: macOS 13 or later as the deployment target, Swift 6 or later, and Xcode or an appropriate macOS command-line SDK. Development checks have run on the local Apple Silicon Mac; older macOS versions and Intel hardware have not yet been verified.

```sh
swift build
swift test
bash scripts/build-app.sh
open dist/Ampi.app
```

The script produces an ad-hoc signed local application, not a notarized distribution. Use `bash scripts/build-app.sh release` for an optimized local build. Open `Package.swift` in Xcode to work on the Swift package. SwiftPM fetches pinned ZIPFoundation 0.9.20 on the first build; subsequent builds use the local cache. There are no sibling-project build requirements. See [dependency notices](THIRD-PARTY-NOTICES.md).

## Using the prototype

- **Open audio:** Open button or ⌘O; selecting files adds them to the queue and starts the first track if nothing is loaded. Drop audio files onto the player to add them too.
- **Playback:** Play/Pause, Stop, Previous, Next, seek, and volume. Space toggles playback; ⌘. stops; ⌘←/⌘→ change tracks. Previous restarts the current track after its first three seconds.
- **Queue:** double-click a track, or select it and press Return, to play it. Queue editing, shuffle, repeat, and persistence are not implemented yet.
- **Layouts:** Themes → Quiet Space (⌘⇧1) replaces the compact horizontal layout with a taller arrangement. Restore Default (⌘⇧0) returns to Retro Stereo. Playback is not recreated during a switch.
- **Custom layouts:** File → Open Skin / Layout… (⌘⇧O), or drop one JSON file. See [the experimental format](docs/THEME-DRAFT.md). Invalid layouts leave the current interface intact.
- **Classic inspection:** open or drop one `.wsz`/ZIP archive or extracted folder to preview its main background and asset report. Inspection leaves playback and the active layout intact. See [the supported inspection profile](docs/CLASSIC-INSPECTION.md).

WAV playback is verified by a muted native smoke test. Other audio files are accepted only when Apple's AVAudioPlayer can decode them; there is no broad codec-support claim yet. Track titles currently come from filenames. Metadata/artwork, folder scanning, equalizer, detached panels, media keys, and device/interruption recovery remain future work.

**Classic preview is partial compatibility.** It shows raw background artwork; sprites and Classic controls, playlist/equalizer windows, and managed installation are not implemented. Modern XML/MAKI packages are rejected. The prototype JSON draft is not the final cross-platform theme package format.

## Verification

`swift test` currently runs 29 tests covering playback, JSON validation, native button drawing, and original/malformed Classic packages. Developer commands render previews and exercise muted native audio:

```sh
dist/Ampi.app/Contents/MacOS/Ampi --preview /tmp/ampi-previews
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-three-second-or-longer.wav
dist/Ampi.app/Contents/MacOS/Ampi --classic-preview Tests/AmpiCoreTests/Fixtures/nested-deflated.wsz /tmp/ampi-classic-preview.png
```

The smoke test plays at zero volume, seeks, replaces the layout, pauses, and stops. Append a Classic fixture path to verify visible inspection during playback too. It checks the real Apple audio backend, while playback unit tests use a deterministic fake. A physical listening check, full screen-reader review, and testing the deployment target on other Macs remain necessary before a release.

## Repository

[Ampi-Project/ampi-macos on GitHub](https://github.com/Ampi-Project/ampi-macos) is the `origin` remote. The local `main` branch tracks `origin/main` and builds on the existing GitHub initial commit.

To push local commits from this repository:

```sh
git push origin main
```

GitHub authentication must use an account with write access to the organization repository. Git author information identifies commit authors; it does not authenticate a push.

## Stack and responsibilities

Swift 6, AppKit, and AVAudioPlayer form the initial prototype. Custom AppKit drawing supplies the backgrounds and buttons; native sliders and tables provide the remaining controls. The `AmpiCore` target is internal to this repository, not a required cross-project engine. This project owns future playback integration, music state, skins, legacy adapters, persistence, macOS integration, and packaging.

Implement a versioned Ampi theme contract independently. Building or running this player must not require the Windows, Linux, or theme authoring repositories. Pin published specification artifacts when they exist.

## Development order

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor conventions. Every handwritten Swift function and variable, including private code and tests, requires `///` documentation.

Contract and cleared fixtures → native drawing/input prototype → local playback → Classic skins and equalizer → native theme switching → platform parity → library → Modern XML/MAKI compatibility → release preparation.

The local workspace has an [unversioned overall plan](../ampi-flow/README.md). That link is optional coordination context and is not available in a standalone clone. Keep this repository's instructions self-contained as implementation begins.

## License

Original repository content is licensed under GPL-3.0-only; see [LICENSE](LICENSE). Official Ampi downloads will be free. Independently authored themes retain their own licenses; GPL redistribution requirements still apply to copied GPL material. Winamp skin support is a compatibility goal, not a claim of affiliation.
