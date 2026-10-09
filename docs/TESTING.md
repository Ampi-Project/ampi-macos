# Manual tests for each development increment

Build the local app with `bash scripts/build-app.sh`, then run `open dist/Ampi.app`. Quit any older running Ampi instance before testing a new build. Xcode users can run the `Ampi` executable scheme instead. Automated tests and muted smoke checks complement these checks; they cannot verify what you hear or full accessibility behavior.

## Release automation — Published tags

See [release instructions](RELEASING.md). Push the workflow/packaging commit before testing GitHub automation. Use an early prerelease such as `v0.1.0-beta.1`; the tag must include the scripts. No release has been published as part of configuring this workflow.

| Action | Expected result |
| --- | --- |
| Actions → Build macOS release → Run workflow; supply an existing version tag | Both architecture jobs build the chosen tag. Downloadable Actions artifacts appear; release upload is skipped. |
| Publish a GitHub prerelease for a tag containing the workflow/scripts | Apple Silicon and Intel builds run, then the upload job attaches both app ZIPs, source tarball, and three SHA-256 companions to that release. |
| Save a release as a draft or push a tag without publishing a release | No automatic release upload. Use the manual workflow to inspect a build privately within Actions. |
| Check each build's log and downloaded ZIP | Core tests pass; actual executable architecture matches its filename. Bundle version matches tag numeric components; the full tag is retained in `AmpiReleaseTag`. App includes production/dependency resource bundles and license notices, without unit-test fixture bundles. |
| Verify the archive's `.sha256`, extract the app, and launch on the matching Mac | Checksum matches; packaged themes load. Opening audio, EQ, metadata, skin switching, and stopped restart behave as in the other checklists. Run on both real architectures before broader release claims. |
| Inspect source tarball and `SOURCE-COMMIT.txt` | Tagged app/build sources and exact pinned ZIPFoundation source/license are included; commit marker matches the released source. No build caches, `.git`, music, or user settings are included. |
| Retry a failed release workflow after correcting an external runner/permission problem | Matching assets are replaced by the successful upload; source/build failures prevent the upload job. Upload-network failures may need rerun to complete partially attached assets. |

Local automated verification: all 94 tests pass with the optimized release configuration. actionlint 1.7.12 validates the workflow; Bash syntax and six invalid input cases pass. The arm64 ZIP, checksum, signature, version/full tag, production resources, dependency notices, metadata/native/Classic playback, and temporary restart smoke checks pass. Source packaging is checked from the clean committed tree. A GitHub-hosted run, Intel runtime acceptance, clean downloaded installation, and Apple Developer ID signing/notarization are not established by local checks. Physical listening/full VoiceOver remain manual. Full Classic/Modern compatibility, saved playlist/library, bookmarks/media keys, and output recovery remain pending.

## Increment 9 — Local metadata and embedded artwork

Build with `bash scripts/build-app.sh`, quit an older instance, and open `dist/Ampi.app`. Use tagged local audio plus an untagged WAV/CAF. **Window → Show / Hide Track Info (⌘I)** works in native and Classic skins. See [the bounded reader/cache profile](METADATA.md). Generate an original tagged test file without downloaded music:

```sh
dist/Ampi.app/Contents/MacOS/Ampi --create-metadata-fixture /tmp/ampi-original-tags.m4a
```

Use a fresh path if it already exists. The fixture contains a quiet ten-second tone. Set your preferred volume before opening it: opening the first audio entry starts playback.

| Action | Expected result |
| --- | --- |
| Open the original fixture with ⌘O; wait for tags | Main label and queue row show `Ampi · موسیقی test` instead of the basename. Playback continues as the title updates. |
| Press ⌘I while that entry is selected | Track Info shows the title, artist `Ampi contributors`, album `Original test signals`, actual filename, and the orange circle on a blue cover. |
| Add an untagged track, single-click its row, then double-click/press Return to play it | Browsing alone keeps Track Info on the loaded entry. Activation changes it to the new filename, artist/album placeholders, and “No embedded artwork”; the previous cover disappears. |
| Add duplicates and move/remove another row while tags load | Tags follow queue identities. Browsing stays on its surviving row; late results do not attach to removed/requeued entries. Playback follows the existing queue-edit rules. |
| Keep Track Info open; switch Retro Stereo → Quiet Space → original Classic fixture | Same panel/title/cover and transport state remain. Classic main and playlist show the embedded title. Hover labels/rows for artist/album details. |
| Hide/reopen Track Info with ⌘I or its close button | Panel reopens with current metadata. Closing it never stops playback. |
| Clear Queue with Track Info visible | Output stops; panel says “No track selected” and clears cover/filename. |
| Quit/relaunch a tagged queue | Restore remains stopped at zero. Tags are reread asynchronously. Reopen Track Info; its visibility is not persisted. |
| Try untagged/unsupported metadata, an invalid embedded image, or audio over 256 MiB | Existing playback decoder rules apply. Filename/cover placeholders remain safe. Files over 256 MiB skip tag inspection, not audio playback. |
| Use more than 64 queued entries and explicitly play a later row | Selected later entry is prioritized for tags; entries outside the bounded initial target window otherwise retain filename fallback. |
| Inspect with VoiceOver; copy selectable panel text | Labels distinguish title, artist, album, audio filename, and cover/fallback. Complete human screen-reader acceptance is pending. |

Automated verification: 94 tests (57 core, 37 native/UI) pass on Apple Silicon/macOS 26.6.2. Native build/package, metadata/skin/panel, existing playback/queue/EQ/mode, and Classic restart smoke checks pass. Bounds, cancellation races, two-worker scheduling, cache/persistence exclusion, and native/Classic browse retention are covered. The actual native panel PNG was visually inspected. Live muted file-picker/⌘I checks verified tagged title/cover, untagged WAV fallback and old-cover clearing, panel hide/reopen, and queue clear; test entries were cleared and the original volume restored. Physical listening, full VoiceOver, older macOS/Intel, wider tag/container coverage, and JPEG acceptance remain manual/future checks. Tag editing, remote/sidecar artwork, in-layout artwork primitives, playlist interchange/library, full historical controls, and Modern skins are unavailable.

Developer check (generator output, no real Application Support writes):

```sh
dist/Ampi.app/Contents/MacOS/Ampi --metadata-smoke-test /tmp/ampi-original-tags.m4a Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-track-info.png
```

## Increment 8 — Restart persistence

Build with `bash scripts/build-app.sh`, quit an older instance, and open `dist/Ampi.app`. Use disposable copies of local tracks and skins for the missing-file tests. Restore always begins stopped at 00:00; playing/paused state and elapsed offset are intentionally omitted. See [storage and recovery rules](PERSISTENCE.md).

| Action | Expected result |
| --- | --- |
| Add three entries, including a duplicate file; select the second duplicate. Move/remove another row, then quit and relaunch | Surviving queue order returns with that exact duplicate selected. No output starts; time is 00:00. Press Play to start it normally. |
| Change volume, EQ curve/preamp/bypass, Shuffle, and Repeat; quit immediately after a change | Latest values survive even before the debounce expires, because Quit waits for its final save. EQ settings apply when playback is explicitly started. |
| Pause midway through a track, choose Quiet Space, quit and relaunch | Quiet Space and selected track return. Transport is stopped at zero rather than resuming the paused offset. |
| Import a valid custom native JSON layout, then quit; move the original JSON file and relaunch | Last validated layout restores from embedded state. Later edits to the original file require reimport. |
| Activate the original green or blue Classic fixture, set audio controls, quit and relaunch | Source is revalidated; main, playlist, and EQ return with shared stopped queue/settings. Playlist/EQ open on first activation after restart; prior panel visibility/positions are not persisted. |
| Quit, move one disposable queued file away, then relaunch | Unavailable entry is skipped and status reports the count. Other identities/settings stay intact. If the missing entry was selected, no other entry is silently selected or started. |
| Quit, move a disposable Classic source away or replace its copied controls with malformed fixture data, then relaunch | Retro Stereo appears with recovered queue/settings and a skin fallback notice. Use a valid source to reactivate Classic. |
| Close the main player with its native close button immediately after editing | App saves and quits through the same final-save path. Relaunch restores the latest durable state; child panels cannot keep output alive. |
| Clear Queue, restore Retro Stereo, set modes Off, then quit and relaunch | Empty queue and those settings stay cleared; old entries do not reappear. |
| Quit, back up the state file, and replace only that test state with malformed JSON; relaunch | Safe defaults and a readable status notice. No crash or automatic output. A later successful save writes current valid state. Preserve/restore your backup if you want the prior session. |
| Test an unwritable state directory only in an isolated development environment | Autosave reports failure. Quit offers Cancel or Quit Without Saving; Cancel leaves the player available and restores previously playing output. No claim of live acceptance of this error dialog is made. |

Automated verification: 85 tests pass, native build/package succeeds, and existing muted playback/skin/queue/EQ/mode smoke plus native/Classic persistence smoke checks pass. Restart smoke creates disposable copies and state files and never uses the owner's Application Support state. Live muted Quit/relaunch verified queue, layout, volume, mode retention, and stopped zero offset. Physical listening, full VoiceOver, older macOS/Intel, and the live unwritable-directory Quit dialog remain manual acceptance checks. Metadata/artwork, playlist interchange, full historical control artwork, and Modern skins remain pending.

Developer command (audio longer than 1.5 seconds):

```sh
dist/Ampi.app/Contents/MacOS/Ampi --persistence-smoke-test /path/to/original-test.wav
dist/Ampi.app/Contents/MacOS/Ampi --persistence-smoke-test /path/to/original-test.wav Tests/AmpiUITests/Fixtures/playable-classic.wsz
```

## Increment 7 — Shuffle and repeat

Build with `bash scripts/build-app.sh`, quit the older Ampi instance, and open `dist/Ampi.app`. Start with three queue entries, including two additions of the same short local file to check independent entries. Modes start Off. Repeat buttons cycle Off → All → One → Off; the Playback menu selects a policy directly. Native buttons and Classic SHUF/R controls reflect the same state. See [the policy and queue-edit rules](SHUFFLE-REPEAT.md).

| Action | Expected result |
| --- | --- |
| Toggle Shuffle and Repeat with an empty queue; try Play, Next, Previous | Values change, but no track starts and seek stays disabled. No crash or fake playback. |
| Pause midway through a track; toggle Shuffle with the button and ⌘⇧S; select Repeat One in the Playback menu | Same loaded identity, offset, gain, EQ, and paused state. Button labels and menu checkmarks agree. No policy change starts audio. |
| Enable Shuffle, set Repeat Off, and let a three-entry queue finish | Every entry plays once, including duplicate files as separate entries. Visible queue order remains unchanged. Stop at the end. Random order can coincidentally match visible order. |
| While shuffled, use Next twice; seek beyond three seconds and press Previous, then Previous again near zero | First Previous rewinds; the next retraces the previously played identity. Next then returns along that forward history. |
| Set Repeat All with Shuffle off; play the last entry to completion | First queue entry starts. With a single-entry queue, the whole track replays from the beginning. Stop cancels the loop. |
| Set Repeat One and let a short track finish twice; then press Next | Entire current track replays, rather than only its last sample. Next advances to another entry; at the end it stops. Select Repeat Off to stop future looping on completion. |
| Enable Shuffle and Repeat All; let two complete cycles finish | Each cycle visits every queue identity. With multiple entries, a new cycle does not immediately replay the preceding last entry. Stop ends playback. |
| During shuffle, append music, reorder rows, and remove a different past/unvisited entry | Current stream/offset continue. Added entries join remaining random candidates; removed entries cannot reappear in history or future choices. Reordering does not discard visits. |
| Remove the current entry; then use Play. Clear, add new music, and use Play again | Removal/clear stops and clears selection. Explicit playback chooses a surviving/new entry safely. Shuffle/repeat, gain, and EQ remain set. Audio files remain on disk. |
| Enable both modes while paused, activate green → blue Classic, restore Quiet Space and Retro Stereo | Modes and paused offset survive; Classic SHUF and R:ALL/R:1 reflect state. Click Classic Repeat to cycle; native menu checkmarks update. |
| Quit and relaunch | Saved layout/queue/selection, modes, volume, and EQ return stopped at zero. Fresh unsaved state still starts with defaults; see increment 8. |
| Tab through mode controls and inspect them with VoiceOver | Spoken labels distinguish Shuffle and Cycle repeat mode; values identify On/Off or Off/All/One. Full human accessibility acceptance remains pending. |

Automated verification: 69 tests pass, including deterministic traversal/failure/edit tests, real native button dispatch and skin replacement, full-source muted Repeat One timing, and two real stereo shuffle/Repeat All cycles with retained EQ. Native build/package and playback smoke checks also pass. Physical listening and full VoiceOver acceptance require the manual actions above. Metadata/artwork, saved playlist interchange, full historical control artwork, and Modern skins remain unavailable; increment 8 covers persistence.

## Increment 6 — Queue editing

Quit an older Ampi instance, build/reopen the updated app, and queue at least four local tracks. Add the same file twice too, so identical filenames can be checked as distinct entries. Use native Retro Stereo/Quiet Space first, then activate `Tests/AmpiUITests/Fixtures/playable-classic.wsz`. Set a non-flat enabled EQ and a comfortable volume.

| Action | Expected result |
| --- | --- |
| Play a middle entry; highlight another row and add more files | Highlight stays on the browsed entry. Triangle/current marker and music stay on the loaded entry; timers must not steal browsing. |
| Remove an entry before the loaded one, then one after it, using Queue menu or right-click | Queue numbering/count changes, but the same loaded file keeps playing at its current position with the same EQ/volume. Its index/marker follow the new row. Files remain on disk. |
| In Classic playlist, use Remove / Up / Down / Clear buttons | Same semantics as the menu/context commands. The new buttons fit above the transport controls without overlapping count text or scrolling content. |
| Focus the native or Classic queue; press Option-Up/Down on a duplicate entry | Only that entry moves one row, and its highlight follows it. The other identical filename remains distinct. Moving at either end is disabled/ignored. Moving the loaded entry must not restart audio. |
| Right-click a row different from the current highlight; then right-click empty space | Row commands target the clicked row. Empty space deselects; row commands are disabled and Clear stays available for a nonempty queue. |
| Press Delete/backspace with queue focus | Only the highlighted queue entry is removed. Highlight falls to the following row, or previous row at the end; browsing alone never starts it. Delete in the file picker's text input must remain ordinary native text editing. |
| Remove the loaded entry while playing, then repeat while paused | Audio stops; current marker/selection clears, time/duration become zero, and seek is disabled. Remaining rows stay queued. Play or Return explicitly starts a new entry. |
| Reorder the loaded entry and its successor, then use Next/Previous or let it finish | Transport and automatic advancement follow the new order exactly once, without unwanted skips. |
| Clear while playing; immediately add music again | Output stops, queue is empty, and row commands are disabled. Adding music through Open/Add starts the first new entry. No old completion callback should skip it. EQ and volume stay unchanged. |
| Edit while paused/stopped; hide/reopen the Classic playlist and switch native/Classic skins | The same queue order and loaded identity persist. Editing other entries preserves paused/stopped state and offset. New skin tables initially highlight the loaded entry. |
| Clear an empty queue; try Play/Pause, Delete, and movement with no row | No crash or fake playback. Context/buttons remain appropriately disabled. |
| Use keyboard navigation and VoiceOver to inspect Queue commands and Classic buttons | Action names identify removal, movement, and clearing; row numbering/current marker remain readable. Full human accessibility acceptance is still pending. |

Automated tests cover identity/bounds/transport rules, actual native keyboard/context and Classic button selectors, and muted real-device completion after editing. The native smoke command additionally checks that audio files are retained. Listening quality, physical mouse/keyboard behavior, and VoiceOver remain manual checks. Multi-selection, drag reordering, undo, sorting, playlist interchange remains unavailable; increments 7–8 cover shuffle/repeat and restart persistence. See [the editing profile](QUEUE-EDITING.md).

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
| Close the primary player with the EQ and playlist open, then restart | Child windows close and output stops. Restart restores saved queue/selection, layout, and audio settings stopped at zero; see increment 8. |

Automated verification includes actual offline DSP sample measurements, native EQ selector/lifecycle tests, and muted real-device pause, seek, completion, and playback/skin smoke checks. Physical listening, mouse/keyboard feel, and full VoiceOver review require these manual checks. Historical EQ control sprites/response graph, Auto mode, preset file interchange and output-device/interruption recovery remain unavailable. Increment 8 adds restart recovery. See [the equalizer profile](CLASSIC-EQUALIZER.md).

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
| Close the primary player while its playlist/inspector is open | Child windows close and audio stops. Restart restores saved layout/queue/audio values stopped at zero (increment 8). |

Playlist saving/sorting, metadata durations, skinned scrollbars/menus, resizing, shade, docking, and Modern skins remain unavailable. Queue editing and equalizer are now covered above. See [the playlist profile](CLASSIC-PLAYLIST.md). Test keyboard navigation and VoiceOver too; full accessibility acceptance has not been certified.

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

Do not expect balance, historical shuffle/repeat artwork, visualization, shade mode, docking, installation, yet. Increment 8 restores saved selection with a default-layout fallback. Imported Classic support is limited to the documented [main](CLASSIC-MAIN.md), [playlist](CLASSIC-PLAYLIST.md), and [equalizer](CLASSIC-EQUALIZER.md) profiles.

## Earlier regression checks

Increment 1: play local music, pause/resume/stop, seek/adjust volume, double-click or press Return on queue rows, add audio by drag/drop, and switch the two native layouts during playback. Invalid JSON should leave the current interface unchanged. Titles with Unicode characters must draw without the reported font-attribute crash.

Increment 2: inspect `original-stored.wsz`, `nested-deflated.wsz`, and the `OriginalClassic` folder. Background artwork should agree and nested uppercase names should normalize. Opening a Modern XML package or malformed input must report an error while the valid active player continues. The importer's existing automated tests cover corruption, unsafe paths, checksums, symlinks, and size limits; do not modify third-party packages to repeat those tests manually.

For reports, include the build/commit, macOS version, test action, expected/actual result, and whether the skin is one of the original fixtures or your own package. Do not redistribute third-party artwork without permission.
