# macOS development checklist

All implementation items are pending. This repository is documentation-only.

## Foundation

- [ ] Choose the minimum macOS version, supported architectures, build system, audio dependencies, and renderer.
- [ ] Create the native app and standalone build instructions.
- [ ] Prototype AppKit custom drawing, native menus, custom windows, input hit testing, focus, and accessibility.
- [ ] Record transparency and detached-window behavior, including usable fallbacks.
- [ ] Pin the published theme contract and cleared fixture versions when available.

## Player and skins

- [ ] Implement local audio, transport controls, metadata/artwork, queue editing, shuffle/repeat, and restart persistence.
- [ ] Handle native file access, media keys, output changes, and lifecycle interruptions.
- [ ] Implement Classic package detection, validation, rendering, scaling, and tested panel behavior.
- [ ] Connect the main, playlist, and equalizer controls to functioning playback/DSP.
- [ ] Implement native theme layouts and three substantially different original examples.
- [ ] Switch skins while preserving the same audio session and music state.
- [ ] Provide a permanent native-menu/shortcut recovery action for broken skins.
- [ ] Implement library scanning and search after the skin foundation works.
- [ ] Implement the declared Modern XML/MAKI compatibility profile, including bounded script execution and diagnostics.

## Acceptance and release

- [ ] Run meaningful behavior, visual, accessibility, and malformed-package checks with cleared fixtures.
- [ ] Verify real playback, clean installation, restart recovery, and theme switching on supported Macs.
- [ ] Document actual format and native/Classic/Modern profile support.
- [ ] Produce release binaries, applicable signing/notarization procedures, source, and license notices.

A Classic-compatible release must not claim Modern support merely because it recognizes `.wal`. This application owns its implementation and releases; it must build from its own checkout.
