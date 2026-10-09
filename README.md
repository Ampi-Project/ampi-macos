# Ampi for macOS

A free native music player with an original retro interface, whole-interface themes, and planned Winamp Classic and Modern skin import.

## Current state

The native prototype is a standalone Swift package with local playback, native menus, two replaceable JSON layouts, partial Classic panels, and ten-band EQ with real DSP. Increments 6–9 add queue editing, shuffle/repeat, safe stopped restart recovery, and asynchronous track metadata/embedded artwork. Full historical Classic controls and Modern support remain pending. See [DEVELOPMENT.md](DEVELOPMENT.md) and [what to test](docs/TESTING.md).

macOS is the first implementation. Independent native Windows and Linux versions are planned. Contributors are welcome to help with code, themes, testing, accessibility, documentation, or platform development; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Build and run

Requirements: macOS 13 or later as the deployment target, Swift 6 or later, and Xcode or an appropriate macOS command-line SDK. Development checks have run on the local Apple Silicon Mac; older macOS versions and Intel hardware have not yet been verified.

```sh
swift build
swift test
bash scripts/build-app.sh
open dist/Ampi.app
```

The script produces an ad-hoc signed local application, not a notarized distribution. Use `bash scripts/build-app.sh release` for an optimized local build. Publishing a GitHub release triggers separate Apple Silicon/Intel builds and attaches app ZIPs, corresponding source, and checksums; see [release steps and limitations](docs/RELEASING.md). Open `Package.swift` in Xcode to work on the Swift package. SwiftPM fetches pinned ZIPFoundation 0.9.20 on the first build; subsequent builds use the local cache. There are no sibling-project build requirements. See [dependency notices](THIRD-PARTY-NOTICES.md).

## Using the prototype

- **Open audio:** Open button or ⌘O; selecting files adds them to the queue and starts the first track if nothing is loaded. Drop audio files onto the player to add them too.
- **Playback:** Play/Pause, Stop, Previous, Next, seek, and volume. Space toggles playback; ⌘. stops; ⌘←/⌘→ change tracks. Previous restarts the current track after its first three seconds.
- **Shuffle / repeat:** buttons in both native layouts and Classic SHUF/R controls; Playback menu offers Shuffle (⌘⇧S) and Repeat Off/All/One. Settings preserve playback position. Next overrides Repeat One; shuffle retains visible queue order and Previous retraces history. See [playback policies](docs/SHUFFLE-REPEAT.md).
- **Queue:** double-click or Return plays a highlighted row. **Queue menu / right-click** provides Remove, Move Up/Down, and Clear; Classic playlist also has buttons. With queue focus, Delete/backspace removes and Option-Up/Down moves. Other-entry edits preserve music; removing the loaded entry or clearing stops and waits for explicit Play. Files are never deleted. See [queue editing](docs/QUEUE-EDITING.md). Multi-selection, drag reordering, undo, and saved playlist interchange remain pending.
- **Restart:** queue order, selected duplicate, volume, EQ, modes, and active interface are saved automatically and on Quit/primary close. Restore begins stopped at 00:00; unavailable files are skipped and bad skins fall back to Retro Stereo. A loaded restored selection keeps Open in append mode; use Play or select a row to start. See [persistence and recovery](docs/PERSISTENCE.md).
- **Layouts:** Themes → Quiet Space (⌘⇧1) replaces the compact horizontal layout with a taller arrangement. Restore Default (⌘⇧0) returns to Retro Stereo. Playback is not recreated during a switch.
- **Custom layouts:** File → Open Skin / Layout… (⌘⇧O), or drop one JSON file. See [the experimental format](docs/THEME-DRAFT.md). Invalid layouts leave the current interface intact.
- **Classic skins:** open or drop one `.wsz`/ZIP archive or extracted folder to inspect its artwork/report. Choose **Use Classic Skin** when activation is available. Main, playlist, and EQ share one session and validate before replacement. See the [main](docs/CLASSIC-MAIN.md), [playlist](docs/CLASSIC-PLAYLIST.md), [equalizer](docs/CLASSIC-EQUALIZER.md), and [inspection](docs/CLASSIC-INSPECTION.md) profiles.
- **Classic playlist:** first activation opens it. **PL**, **Window → Show / Hide Classic Playlist**, or **⌘L** hides/reopens it without stopping music. Single-click/arrow keys browse; double-click, Return, or Play Selected plays a row. Add… appends audio; the native toolbar shares transport with the main window. Closing the primary player closes child windows and stops output.

- **Equalizer:** **EQ**, **Window → Show / Hide Equalizer**, or **⌘E** shows/hides the panel. Enable the checkbox to apply preamp and ten nominal bands (31 Hz–16 kHz, ±12 dB). Closing the panel retains DSP. Presets preserve enabled/bypassed state; Reset Flat zeros gains. Native layouts and skins without `eqmain.bmp` use an original backdrop. Curve, preamp, and bypass are restored across restart.

**Track metadata:** local common title/artist/album load asynchronously; native and Classic labels use tagged titles with filename fallback. **Window → Show / Hide Track Info (⌘I)** displays the selected track's tags, actual filename, and embedded cover thumbnail in any skin. Browsing does not activate another entry. See [reader/cache limits and original fixture commands](docs/METADATA.md).

Original WAV, mono/stereo CAF, and generated AAC/M4A playback are verified by muted native checks. Files must decode through AVAudioFile into the documented mono/stereo floating-point graph profile; there is no broad codec-support claim yet. Tagged AAC/M4A with embedded PNG is verified; wider tag/container/JPEG coverage remains pending. Scanning, tag editing, in-layout artwork, media keys, and output-device/interruption recovery remain future work.

**Classic support is partial.** Main transport, seek, volume, playlist borders/editable queue, and the EQ background work at 2× scale. Native text, table, scrollbar, playlist toolbar, EQ controls, and panel toggles provide the documented fallbacks. Historical EQ sprites/response graph/preset files, playlist saving/sorting, historical shuffle/repeat sprites, balance, visualization, bitmap fonts/numbers, historical playlist menus/scrollbars, shade, docking, other scales, and installation remain pending. Modern XML/MAKI packages are rejected. JSON is an experimental repository-local draft.

## Verification

`swift test` currently runs 94 tests covering common tags/artwork, metadata bounds/cache/callback races, native/Classic browse retention, durable state/recovery, saves, playback/modes/queue editing, JSON/Classic rendering, native controls, and actual DSP/muted clocks/cancellation/completion. Developer commands render previews and exercise muted native audio. Persistence and metadata smoke checks preserve inputs and avoid the real Application Support session:

```sh
dist/Ampi.app/Contents/MacOS/Ampi --preview /tmp/ampi-previews
dist/Ampi.app/Contents/MacOS/Ampi --create-metadata-fixture /tmp/ampi-original-tags.m4a
dist/Ampi.app/Contents/MacOS/Ampi --metadata-smoke-test /tmp/ampi-original-tags.m4a Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-track-info.png
dist/Ampi.app/Contents/MacOS/Ampi --persistence-smoke-test /path/to/a-three-second-or-longer.wav Tests/AmpiUITests/Fixtures/playable-classic.wsz
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-three-second-or-longer.wav
dist/Ampi.app/Contents/MacOS/Ampi --classic-preview Tests/AmpiCoreTests/Fixtures/nested-deflated.wsz /tmp/ampi-classic-preview.png
dist/Ampi.app/Contents/MacOS/Ampi --classic-player-preview Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-classic-player.png
dist/Ampi.app/Contents/MacOS/Ampi --classic-playlist-preview Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-classic-playlist.png
dist/Ampi.app/Contents/MacOS/Ampi --classic-equalizer-preview Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-equalizer.png
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-three-second-or-longer.wav Tests/AmpiUITests/Fixtures/playable-classic.wsz
```

The smoke test plays at zero volume through a non-flat EQ, seeks, changes layouts, pauses, and stops. With a usable Classic fixture, it activates during playback, uses sprite Play/Pause, checks a paused final-sample seek, selects another queue entry, hides/reopens that panel, and restores the default while retaining EQ. It then reorders/removes entries during real output, removes the loaded entry, and clears a rebuilt queue, checking settings and source-file retention. Offline DSP tests measure actual response; muted device tests verify clocks, corrupt replacement, canceled callbacks, and completion following edited queue order. Physical listening, full screen-reader review, and older/Intel Mac checks remain necessary before release. Follow [the manual guide](docs/TESTING.md).

## Repository

[Ampi-Project/ampi-macos on GitHub](https://github.com/Ampi-Project/ampi-macos) is the `origin` remote. The local `main` branch tracks `origin/main` and builds on the existing GitHub initial commit.

To push local commits from this repository:

```sh
git push origin main
```

GitHub authentication must use an account with write access to the organization repository. Git author information identifies commit authors; it does not authenticate a push.

## Stack and responsibilities

Swift 6 and AppKit provide native rendering/input. AVAudioEngine streams AVAudioFile segments through AVAudioPlayerNode, AVAudioUnitEQ, and the output mixer; [the EQ profile](docs/CLASSIC-EQUALIZER.md) documents the audio path and limits. The `AmpiCore` target is internal to this repository, not a required cross-project engine. This project owns its music state, skins, legacy adapters, persistence, macOS integration, and packaging.

Implement a versioned Ampi theme contract independently. Building or running this player must not require the Windows, Linux, or theme authoring repositories. Pin published specification artifacts when they exist.

## Development order

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributor conventions. Every handwritten Swift function and variable, including private code and tests, requires `///` documentation.

Contract and cleared fixtures → native drawing/input prototype → local playback → Classic skins and equalizer → native theme switching → platform parity → library → Modern XML/MAKI compatibility → release preparation.

The local workspace has an [unversioned overall plan](../ampi-flow/README.md). That link is optional coordination context and is not available in a standalone clone. Keep this repository's instructions self-contained as implementation begins.

## License

Original repository content is licensed under GPL-3.0-only; see [LICENSE](LICENSE). Official Ampi downloads will be free. Independently authored themes retain their own licenses; GPL redistribution requirements still apply to copied GPL material. Winamp skin support is a compatibility goal, not a claim of affiliation.
