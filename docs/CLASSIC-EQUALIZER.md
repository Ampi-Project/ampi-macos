# Equalizer — increment 5

The detachable equalizer works in both native layouts and imported Classic skins. **Window → Show / Hide Equalizer (⌘E)** opens it; the Classic main **EQ** button does the same. First Classic activation opens the playlist and EQ. Closing the EQ hides controls without bypassing DSP. Changing skins preserves the session's curve, enabled state, volume, track, and playback position; panel visibility and position persist during that session.

Ten nominal centers are **31, 62, 125, 250, 500, 1,000, 2,000, 4,000, 8,000, and 16,000 Hz**. Each uses Apple's one-octave parametric filter. Bands and preamp range from −12 to +12 dB. EQ starts bypassed and flat. The checkbox bypasses the whole audio unit, including preamp, without clearing values. Output volume remains independent. Flat, Bass, and Voice are original Ampi starter curves; selecting a preset retains bypass state, and Reset Flat restores zero preamp/band gains. They are not historical Winamp preset files.

## Audio path

`AVAudioFile → AVAudioPlayerNode → AVAudioUnitEQ → main mixer/output volume → device`

Playback now uses AVAudioEngine instead of AVAudioPlayer. Files stream through the native decoder; mono/stereo noninterleaved Float32 decoded output with sample rate at least 1 kHz is the current graph profile. A candidate file is opened, its first block decoded, and its graph prepared before stopping the old track. Decoder failures at this stage preserve the old output. Output-device changes, interruptions, later streaming errors, and broader channel/format support still need recovery work.

The player clock excludes paused intervals. Seeking cancels old segments, retains playing/paused state, and clamps to the final valid sample. Completion uses Apple's played-back notification and dispatches to the main actor; a generation token rejects callbacks from replaced, stopped, or sought schedules. Very long streams are divided into UInt32-sized frame segments. EQ edits update the existing processor, without rescheduling music or changing volume.

For low-rate sources, bands whose nominal center is at or above half the decoded sample rate are bypassed; their stored slider values remain intact for higher-rate tracks. There is no automatic limiter or gain compensation. Lower the preamp when boosting to leave headroom. This is an initial native parametric implementation, not a claim of identical historical Winamp DSP response.

The implementation follows Apple's [player-node scheduling and clock documentation](https://developer.apple.com/documentation/avfaudio/avaudioplayernode), [filter parameters](https://developer.apple.com/documentation/avfaudio/avaudiouniteqfilterparameters), and [EQ gain API](https://developer.apple.com/documentation/avfaudio/avaudiouniteq/globalgain).

## Classic artwork profile

An optional `eqmain.bmp` must be at least **275×116** pixels. The renderer crops its top-left 275×116 background and draws at 2× nearest-neighbor scale. Native sliders, labels, bypass, and preset controls overlay it; an original footer provides state and Reset Flat. The fixed content is 550×282 logical points with native window chrome. Missing artwork gives a usable original native backdrop. Present undersized artwork disables activation with a diagnostic, preserving all three active surfaces and music. Main, playlist, and EQ are validated before installation.

Historical EQ slider/button/title-state sprites, the response graph, Auto mode, shade/docking/resizing, Winamp preset interchange, and remembered panel geometry are not implemented. [Increment 8](PERSISTENCE.md) restores the curve, preamp, and bypass across restart. Fixtures are independently drawn GPL artwork, including an EQ dimension-failure package; they do not certify every historical skin.

## Verification

Automated checks measure actual offline filtered tone samples: −12 dB at 1 kHz attenuates its amplitude by approximately four times, −6 dB preamp by approximately two times, a distant 31-Hz cut leaves a 1-kHz tone largely intact, and bypass restores the unity signal even with nonzero preamp. Real muted device tests check pause/seek clocks, cancellation, corrupt replacement, and automatic queue advancement. Native-control tests cover sliders, presets, bypass, reset, hidden/reopened panels, skin replacement, missing artwork, and atomic failure.

Local increment verification: 48 tests pass on Apple Silicon/macOS 26; original WAV, mono/stereo CAF, and generated AAC/M4A exercise the native output path. WAV/green and AAC/blue nested-skin smoke checks pass. Imported and missing-artwork EQ PNGs were visually inspected. Live mouse/keyboard checks were unavailable because the Mac was locked; physical listening and VoiceOver have not been performed for this increment.

```sh
swift build
swift test
bash scripts/build-app.sh
dist/Ampi.app/Contents/MacOS/Ampi --classic-equalizer-preview Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-equalizer.png
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-three-second-or-longer.wav Tests/AmpiUITests/Fixtures/playable-classic.wsz
```

Follow [the increment 5 listening and interaction checklist](TESTING.md). Sample measurements and muted output checks do not certify physical listening quality, full VoiceOver behavior, every codec, older macOS, or Intel hardware.
