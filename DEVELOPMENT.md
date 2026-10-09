# macOS development checklist

Increments 1–9: native playback/layout prototype, Classic inspection, partial main sprites, detachable playlist, ten-band DSP, queue editing, shuffle/repeat, stopped restart recovery, and bounded local metadata/embedded artwork implemented. Every increment includes [manual actions and expected results](docs/TESTING.md). This is not the final increment; complete compatibility and release acceptance remain pending.

## Foundation

- [x] Document handwritten functions and variables with `///` and record the convention in contributor instructions.
- [x] Select macOS 13 deployment target, Swift Package Manager, AppKit, and AVAudioEngine with native file decoding/EQ.
- [x] Create the native app, local `.app` packaging script, and standalone build instructions.
- [x] Implement native menus, custom drawing, labelled controls, keyboard transport actions, and different fixed-size layouts.
- [x] Record prototype window constraints: native title bars, opaque rectangular surfaces, fixed sizes; Classic playlist is detachable but not dockable.
- [ ] Verify older supported macOS versions and Intel hardware; Apple Silicon is locally tested.
- [ ] Complete full keyboard/screen-reader review and investigate custom-shaped/detached windows.
- [ ] Pin the published theme contract and cleared fixture versions when available.

## Player and skins

- [x] Implement local file playback, play/pause/stop, seek, volume, previous/next, editable queue, and automatic advance.
- [x] Implement single-entry remove, clear, and Up/Down reordering through shared native menus, context/keyboard input, and Classic buttons.
- [x] Preserve loaded identity, offset, transport state, volume, and EQ when moving/removing other entries; stop and clear selection on loaded removal/clear.
- [x] Implement local file picker and audio-file drop handling.
- [x] Implement an experimental JSON layout reader with two original built-in layouts and safe replacement.
- [x] Preserve the playback session, queue, position, and volume during layout replacement.
- [x] Provide native-menu and shortcut actions to restore the default layout.
- [x] Implement identity-based shuffle with bounded Previous/forward history and Repeat Off/All/One; preserve policies during edits/skin switches.
- [x] Persist ordered identities/selection, gain/EQ, modes, and native/Classic choice; restore stopped with bounded validation and unavailable-file/default-skin recovery.
- [x] Read bounded asynchronous common title/artist/album and embedded PNG/JPEG thumbnails, retaining filename fallback and queue identity.
- [x] Share metadata titles across native/Classic controls and a native Track Info panel (⌘I); exclude derived cache from saved state.
- [ ] Expand metadata/container/artwork fixture coverage and add in-layout artwork primitives/tag fields.
- [ ] Implement multi-selection/drag editing, undo/sorting/saved playlists.
- [ ] Handle native file access, media keys, output changes, and lifecycle interruptions.
- [ ] Implement Classic package detection, validation, rendering, scaling, and tested panel behavior.
  - [x] Validate ZIP32 stored/DEFLATE archives and extracted folders with bounded reads and CRC checks.
  - [x] Preview the main bitmap at 2× integer scale with an asset/compatibility report.
  - [x] Add original flat/nested Classic fixtures and malformed-package tests.
  - [x] Compose and activate the partial Classic main player at 2×, including native transport and sprite seek/volume with optional fallbacks.
  - [x] Render optional Classic playlist borders/colors with native queue browsing/activation, scrolling, and shared transport.
  - [x] Validate main/playlist/EQ replacements together; preserve panel visibility between skins and close child windows with the primary player.
  - [ ] Implement full historical playlist controls/scrollbars, saving, compact/resizable/docked panel behavior.
  - [x] Activate optional Classic EQ backgrounds with native ten-band/preamp/bypass/preset controls and functioning DSP.
  - [ ] Implement historical EQ control sprites, response graph, Auto mode, and preset interchange.
- [x] Connect the implemented main, playlist, and equalizer controls to functioning playback/DSP.
- [ ] Implement native theme layouts and three substantially different original examples.
- [x] Switch prototype native/Classic skins while preserving audio session, queue, position, gain, and EQ curve/bypass state.
- [x] Restore embedded native layout or revalidate the original Classic source; retain default layout if saved geometry/assets fail.
- [ ] Implement library scanning and search after the skin foundation works.
- [ ] Implement the declared Modern XML/MAKI compatibility profile, including bounded script execution and diagnostics.

## Acceptance and release

- [x] Configure published-release builds for Apple Silicon/Intel, gated asset upload, checksums, and corresponding app/pinned dependency source.
- [x] Add a manual tagged build path that retains Actions artifacts without publishing/uploading to a release.
- [ ] Verify the first GitHub-hosted matrix/upload run and clean downloaded installation on both architectures.

- [x] Pass 94 metadata/bounds/callback-race/cache/UI/persistence/playback/shuffle/repeat/queue/JSON/Classic/backend/DSP tests.
- [x] Verify original tagged Unicode AAC/PNG, shared native/Classic titles, retained Track Info, and uninterrupted muted playback.
- [x] Visually inspect native metadata panel and check live ⌘I, tagged/untagged fallback, old-cover clearing, and empty-state cleanup.
- [x] Verify fresh muted decoder restart, stopped clock, explicit Play, missing audio/skin, corrupt state, and original-file preservation.
- [x] Verify live Quit/relaunch retains a muted test queue, Quiet Space, and modes at zero; clear test state and restore defaults afterward.
- [x] Verify full-source muted Repeat One replay and two stereo shuffle/Repeat All cycles, with retained EQ.
- [x] Inspect native/Classic mode-control previews and verify live native toggles, Repeat menu selection, and layout-switch state retention.
- [x] Verify muted real completion follows edited order and clear/requeue rejects old completion callbacks.
- [x] Measure actual offline band/preamp/bypass output and verify real muted pause/seek clocks and automatic track advancement.
- [x] Verify Classic preview during playback preserves the active layout and session.
- [x] Verify explicit Classic activation, native sprite Play/Pause, and restoring the default during muted real playback.
- [x] Verify playlist selection, transport, hide/reopen, and native restoration share the real muted audio session.
- [x] Check double-click and Return queue activation and panel shortcuts in the running app; full accessibility acceptance remains pending.
- [x] Fix and regression-test content sizing during replacement and native paused seeking at the final audio sample.
- [x] Render and visually inspect both original layouts; launch the app and verify native theme shortcuts and the file picker.
- [ ] Run legacy-package fixture checks and complete accessibility conformance checks.
- [ ] Verify real playback, clean installation, restart recovery, and theme switching on supported Macs.
- [ ] Document actual format and native/Classic/Modern profile support.
- [ ] Produce release binaries, applicable signing/notarization procedures, source, and license notices.

A Classic-compatible release must not claim Modern support merely because it recognizes `.wal`. This application owns its implementation and releases; it must build from its own checkout.
