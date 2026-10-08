# macOS development checklist

Increments 1–5: native playback/layout prototype, Classic inspection, partial main sprites, detachable playlist, and ten-band EQ with real DSP implemented. Every increment includes [manual actions and expected results](docs/TESTING.md). This checklist distinguishes the working foundation from a complete player.

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

- [x] Implement local file playback, play/pause/stop, seek, volume, previous/next, append-only queue, and automatic advance.
- [x] Implement local file picker and audio-file drop handling.
- [x] Implement an experimental JSON layout reader with two original built-in layouts and safe replacement.
- [x] Preserve the playback session, queue, position, and volume during layout replacement.
- [x] Provide native-menu and shortcut actions to restore the default layout.
- [ ] Implement metadata/artwork, queue editing, shuffle/repeat, and restart persistence.
- [ ] Handle native file access, media keys, output changes, and lifecycle interruptions.
- [ ] Implement Classic package detection, validation, rendering, scaling, and tested panel behavior.
  - [x] Validate ZIP32 stored/DEFLATE archives and extracted folders with bounded reads and CRC checks.
  - [x] Preview the main bitmap at 2× integer scale with an asset/compatibility report.
  - [x] Add original flat/nested Classic fixtures and malformed-package tests.
  - [x] Compose and activate the partial Classic main player at 2×, including native transport and sprite seek/volume with optional fallbacks.
  - [x] Render optional Classic playlist borders/colors with native queue browsing/activation, scrolling, and shared transport.
  - [x] Validate main/playlist/EQ replacements together; preserve panel visibility between skins and close child windows with the primary player.
  - [ ] Implement full historical playlist controls/scrollbars, editing/saving, compact/resizable/docked panel behavior.
  - [x] Activate optional Classic EQ backgrounds with native ten-band/preamp/bypass/preset controls and functioning DSP.
  - [ ] Implement historical EQ control sprites, response graph, Auto mode, and preset interchange.
- [x] Connect the implemented main, playlist, and equalizer controls to functioning playback/DSP.
- [ ] Implement native theme layouts and three substantially different original examples.
- [x] Switch prototype native/Classic skins while preserving audio session, queue, position, gain, and EQ curve/bypass state.
- [ ] Persist theme selection and recover safely from a bad saved theme at startup.
- [ ] Implement library scanning and search after the skin foundation works.
- [ ] Implement the declared Modern XML/MAKI compatibility profile, including bounded script execution and diagnostics.

## Acceptance and release

- [x] Pass 48 playback/JSON/Classic/native-control/backend/DSP tests and a muted playback/layout/playlist/EQ smoke test.
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
