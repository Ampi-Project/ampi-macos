# macOS development checklist

Increments 1–2: native playback/layout prototype and Classic package inspection implemented. This checklist distinguishes the working foundation from features needed for a complete player.

## Foundation

- [x] Document handwritten functions and variables with `///` and record the convention in contributor instructions.
- [x] Select macOS 13 deployment target, Swift Package Manager, AVAudioPlayer, and AppKit for the prototype.
- [x] Create the native app, local `.app` packaging script, and standalone build instructions.
- [x] Implement native menus, custom drawing, labelled controls, keyboard transport actions, and different fixed-size layouts.
- [x] Record prototype window constraints: native title bar, opaque rectangular surface, fixed size, and no detached panels.
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
  - [ ] Compose sprites and activate the Classic main, playlist, and equalizer controls.
- [ ] Connect the main, playlist, and equalizer controls to functioning playback/DSP.
- [ ] Implement native theme layouts and three substantially different original examples.
- [ ] Switch skins while preserving the same audio session and music state.
- [ ] Persist theme selection and recover safely from a bad saved theme at startup.
- [ ] Implement library scanning and search after the skin foundation works.
- [ ] Implement the declared Modern XML/MAKI compatibility profile, including bounded script execution and diagnostics.

## Acceptance and release

- [x] Pass 29 playback/JSON/Classic/native-rendering tests and a muted real-backend playback/layout smoke test.
- [x] Verify Classic preview during playback preserves the active layout and session.
- [x] Render and visually inspect both original layouts; launch the app and verify native theme shortcuts and the file picker.
- [ ] Run legacy-package fixture checks and complete accessibility conformance checks.
- [ ] Verify real playback, clean installation, restart recovery, and theme switching on supported Macs.
- [ ] Document actual format and native/Classic/Modern profile support.
- [ ] Produce release binaries, applicable signing/notarization procedures, source, and license notices.

A Classic-compatible release must not claim Modern support merely because it recognizes `.wal`. This application owns its implementation and releases; it must build from its own checkout.
