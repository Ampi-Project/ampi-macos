# Manual tests for each development increment

Build the local app with `bash scripts/build-app.sh`, then run `open dist/Ampi.app`. Quit any older running Ampi instance before testing a new build. Xcode users can run the `Ampi` executable scheme instead. Automated tests and muted smoke checks complement these checks; they cannot verify what you hear or full accessibility behavior.

## Increment 5 — Equalizer and audio-engine regression

Build the updated app and quit the older instance. Start with two local tracks at a comfortable volume; use one with both bass and treble to hear the differences. Activate `Tests/AmpiUITests/Fixtures/playable-classic.wsz` with **Use Classic Skin**. First activation now opens main, playlist, and equalizer windows. The EQ controls are native, with the imported background; full historical sprite compatibility remains pending.

| Action | Expected result |
| --- | --- |
| Press ⌘E from Retro Stereo or Quiet Space before importing a skin | Original native EQ panel opens with eleven sliders, EQ off, Flat curve, and zero gains. No music starts merely from opening EQ. |
| While playing, enable EQ, select Bass, then Voice | Music continues at the same position. Bass/voice character changes; sliders and preamp reflect the preset. Presets leave the checkbox state unchanged. |
| Select Flat, then lower the 1k band and preamp; adjust the main volume too | Tone balance and loudness change. Each EQ gain stays within ±12 dB; main volume stays independent from preamp. Changed curves show Custom. Lower preamp when boosting bands to preserve headroom. |
| Turn EQ off, then on | Bypass restores the original signal, including bypassing preamp. Slider values stay unchanged; enabling reapplies the curve. |
| Click Reset Flat while EQ is on, then repeat while off | All eleven gains return to zero; enabled/bypassed state remains unchanged. |
| Close EQ, then reopen using main EQ, Window menu, or ⌘E | Only the panel hides. Its current DSP curve continues; reopening restores values and the main visibility indicator. |
| Change green → blue Classic → Quiet Space → Retro Stereo while playing with a custom curve | Track, queue, time, volume, curve, and bypass state persist. Classic backgrounds change; native layouts use the original EQ backdrop. EQ panel position/visibility persist within the session. |
| Pause for several seconds, seek while paused (including the far end), then resume; Stop and Play | Paused time stays frozen. Seeking does not resume paused audio. Play resumes at the chosen sample; final-position playback finishes normally. Stop rewinds and retains EQ. Check for audible dropouts or unintended clicks. |
| Queue two short tracks and let them finish with EQ on; also use Previous/Next while playing | Exactly one automatic advance per track; the queue ends stopped at zero. EQ stays applied across new tracks. No extra advance from a canceled seek/stop schedule. |
| Inspect `Tests/AmpiUITests/Fixtures/invalid-equalizer.wsz` while music plays | Activation is disabled with an eqmain.bmp dimension diagnostic. Current main, playlist, EQ, music, and values remain intact. |
| Activate the older `Tests/AmpiCoreTests/Fixtures/original-stored.wsz` | Missing EQ artwork uses a usable original native backdrop, reported in the inspector. Ten-band controls still work. |
| Tab through EQ and use arrow keys; inspect slider names with VoiceOver | Bypass, presets, reset, preamp, and all ten frequency sliders have usable native focus/labels and bounded gain values. Full human accessibility acceptance remains pending. |
| Close the primary player with the EQ and playlist open, then restart | Child windows close and output stops. Restart still begins with the default layout, empty queue, and bypassed flat EQ; persistence is future work. |

Automated verification includes actual offline DSP sample measurements, native EQ selector/lifecycle tests, and muted real-device pause, seek, completion, and playback/skin smoke checks. Physical listening, mouse/keyboard feel, and full VoiceOver review require these manual checks. Historical EQ control sprites/response graph, Auto mode, preset file interchange, persistence, and output-device/interruption recovery remain unavailable. See [the equalizer profile](CLASSIC-EQUALIZER.md).

## Increment 4 — Classic playlist

Use the updated `Tests/AmpiUITests/Fixtures/playable-classic.wsz` and `playable-classic-nested.wsz`: both now contain original playlist borders and colors. Open through **File → Open Skin / Layout…** (⌘⇧O), then choose **Use Classic Skin**. First activation now opens main, playlist, and EQ windows.

| Action | Expected result |
| --- | --- |
| Activate the green fixture with an empty queue | Main player and separate **Ampi Playlist** appear. Playlist shows an empty hint; Play Selected is disabled and visibly dimmed. |
| Click playlist **Add…** and select at least two local tracks | First track starts when nothing is loaded. Both surfaces share the queue; a triangle marks the current track, with the correct queue count. |
| Pause, then single-click or use arrows to highlight another row; wait a few seconds | Highlight changes while the triangle/current track and offset remain unchanged. Timer refresh must not steal your browse selection. |
| Double-click a row, select another and press Return/keypad Enter, then try **Play Selected** | Each action plays that highlighted entry and updates the main title/current-row marker. Unicode filenames should remain readable; row numbers stay at the left. |
| Use playlist Play, Pause, Stop, Previous, and Next | Same behavior as the main controls. Repeated Play stays playing, Pause retains position, Stop rewinds, Previous restarts after three seconds or moves back near the start. Next moves the current-row marker and scrolls to it. |
| Add more tracks during playback; add enough to require scrolling | Existing track/offset/gain continue. New rows appear and counts update in both windows. Browsing/scrolling works without starting a new row; ordinary timer ticks do not jump the list. At track completion, the following row becomes current. |
| Close only the playlist or use **PL / ⌘L**, then reopen it | Music continues; PL visibility indicator changes. The same queue and current row return. |
| Activate the blue nested fixture while playing, once with the playlist visible and once hidden | Both skin palettes/borders change. Track/queue/position/volume remain; playlist visibility and position are preserved between Classic packages. |
| Restore Quiet Space (⌘⇧1) or Retro Stereo (⌘⇧0) | Classic playlist closes, native embedded queue appears, music continues. The Classic playlist menu command is disabled in native layouts. |
| Inspect `Tests/AmpiUITests/Fixtures/invalid-playlist-border.wsz` while music plays | Background/report can be inspected, activation is disabled with `pledit.bmp` dimensions, and the active main/playlist windows and music remain intact. |
| Activate `Tests/AmpiCoreTests/Fixtures/original-stored.wsz` | Missing playlist artwork/colors use a usable original native fallback, explicitly reported by the inspector. Abstract main transport icons are intentional in this older fixture. |
| Close the primary player while its playlist/inspector is open | Child windows close and audio stops. Restart begins with the default layout and empty queue. |

Queue editing/saving/sorting, metadata durations, skinned scrollbars/menus, resizing, shade, docking, and Modern skins remain unavailable. Equalizer is now covered above. See [the playlist profile](CLASSIC-PLAYLIST.md). Test keyboard navigation and VoiceOver too; full accessibility acceptance has not been certified.

## Increment 3 — Classic main player regressions

Use two or more local tracks long enough to seek comfortably. The original skins below are bundled source fixtures, not copyrighted historical skins. Open skins with **File → Open Skin / Layout…** (⌘⇧O), or drag the archive onto the player. Fixture paths are relative to the macOS repository.

Increments 4–5 open the playlist and EQ on first activation; earlier main-player checks still apply.

| Action | Expected result |
| --- | --- |
| Open `Tests/AmpiUITests/Fixtures/playable-classic.wsz` without loading music | Inspector appears; default player stays unchanged. Choose **Use Classic Skin**; player becomes a compact green interface. Play/Pause on an empty queue causes no crash or fake playback. Seek is disabled. |
| Click the eject-shaped Open button; select two local audio files | First track starts, title and clock update. The separate playlist also shows the queue. |
| Click Play while already playing; click Pause twice; click Play | Play does not pause. Pause retains the offset; the second Pause does not resume. Play resumes from that offset. Verify audible output and silence on pause. |
| Drag seek near the middle, then near both ends; adjust volume to zero, middle, and full | Offset follows the slider and clock; thumb stays on the track. Volume changes audibly, zero mutes, gain stays bounded. Avoid leaving full volume louder than comfortable. |
| Hold a transport button down, then release; Tab between controls and use arrow keys on sliders | Pressed artwork differs from idle. Buttons retain native activation; sliders accept keyboard input. Verify visible focus and readable VoiceOver names; report any focus/accessibility issue. macOS keyboard-navigation settings may affect Tab traversal. |
| Use Next, then seek beyond three seconds and press Previous; press Previous again near the start | Next selects the following track. Previous first rewinds the current track, then selects its predecessor. Stop rewinds to 00:00; Play restarts it. Pause after Stop stays stopped. |
| While playing, inspect `playable-classic-nested.wsz`, then activate it; restore Quiet Space (⌘⇧1), then Retro Stereo (⌘⇧0) | Inspection alone changes nothing. Activation switches to blue, then native layouts change both geometry and arrangement. Track, queue, position, playback, and volume persist through every switch. |
| Inspect `invalid-main-controls.wsz` while playing | Background/report still open; activation is disabled and reports `cbuttons.bmp` dimensions. Active skin and music continue unchanged. |
| Open the extracted `Tests/AmpiUITests/Fixtures/PlayableClassic` folder | Same activation as the green archive. |
| Open `Tests/AmpiCoreTests/Fixtures/original-stored.wsz` and activate | Required geometric transport sprites work; missing optional seek/volume artwork uses native slider fallback. This older fixture has intentionally abstract icons. |
| Close the inspector after activation; use native playback/theme shortcuts | Active player remains available. Space toggles Play/Pause; ⌘. stops; ⌘←/⌘→ navigate; ⌘⇧0 restores the default. |

Do not expect balance, shuffle/repeat, visualization, shade mode, docking, installation, or remembered skin selection yet. The app starts with its default layout after restart. Imported Classic support is limited to the documented [main](CLASSIC-MAIN.md), [playlist](CLASSIC-PLAYLIST.md), and [equalizer](CLASSIC-EQUALIZER.md) profiles.

## Earlier regression checks

Increment 1: play local music, pause/resume/stop, seek/adjust volume, double-click or press Return on queue rows, add audio by drag/drop, and switch the two native layouts during playback. Invalid JSON should leave the current interface unchanged. Titles with Unicode characters must draw without the reported font-attribute crash.

Increment 2: inspect `original-stored.wsz`, `nested-deflated.wsz`, and the `OriginalClassic` folder. Background artwork should agree and nested uppercase names should normalize. Opening a Modern XML package or malformed input must report an error while the valid active player continues. The importer's existing automated tests cover corruption, unsafe paths, checksums, symlinks, and size limits; do not modify third-party packages to repeat those tests manually.

For reports, include the build/commit, macOS version, test action, expected/actual result, and whether the skin is one of the original fixtures or your own package. Do not redistribute third-party artwork without permission.
