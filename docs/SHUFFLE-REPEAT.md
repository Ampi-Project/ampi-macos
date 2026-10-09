# Shuffle and repeat — increment 7

Playback policies belong to the main-actor `PlaybackSession`, independently of native/Classic layouts and EQ. Both built-in layouts expose **Shuffle: On/Off** and **Repeat: Off/All/One**. The Classic main exposes original native **SHUF** and **R:OFF / R:ALL / R:1** controls. Click Repeat to cycle Off → All → One → Off. **Playback → Shuffle** (⌘⇧S) and **Playback → Repeat → Off / All / One** work with every layout; menu checkmarks follow the shared session. Legacy shuffle/repeat sprite artwork is not interpreted in this increment.

## Transport rules

| Situation | Behavior |
| --- | --- |
| Shuffle off | Next and successful completion follow visible queue order. Previous restarts after three seconds, otherwise moves back without wrapping. |
| Shuffle on | Randomly choose an unvisited queue identity. Visible rows stay in place. Duplicate files have different UUIDs and are visited independently. |
| Enable/disable shuffle | Preserve stream, position, paused/stopped/playing state, gain, EQ, and queue order. Reset traversal/history; enabling counts the loaded identity as the first visit. With no loaded entry, explicit Play chooses a random entry. |
| Repeat Off | Stop and rewind after the last sequential entry or final unvisited shuffle entry. Retain the loaded selection and traversal for explicit replay. |
| Repeat All | Start another sequential/shuffle cycle. Every shuffled entry becomes eligible again; with multiple entries, the first new visit differs from the preceding cycle's last entry. A one-entry queue rewinds and replays its full source. |
| Repeat One | Successful completion rewinds and replays the loaded identity without preparing another decoder. Manual Next overrides One; at the queue/cycle end it stops, as with Off. |
| Shuffle Previous | After three seconds, rewind. Otherwise retrace played identities, with Next retracing the forward history. Retain at most 200 visits; at the earliest retained visit, rewind the current entry. Previous does not create another shuffle cycle. |
| Play a particular row | Select that identity explicitly, counting it as visited. A different direct selection after Previous replaces the unused forward path. Manual selection/history may revisit entries; the remaining random choices exclude visited identities. |
| Stop / pause / resume | Preserve policy and traversal. Stop rewinds the loaded entry; pause retains offset; resume keeps selection. Replaying a completed decoder starts at zero. Toggling shuffle starts a fresh traversal if desired. |
| Playback/load failure | Failed preparation preserves current output, selection, and traversal, so manual Next can retry. Failure during automatic advancement stops and reports the error; corrupt entries are not silently skipped. Failed/paused/stopped completion never begins a repeat loop. |

## Queue edits

- Appending adds fresh identities to the current cycle's remaining candidates without changing the stream.
- Moving rows preserves visited identities and playback history. Subsequent unvisited choices use the remaining identities in the edited queue; shuffle is still random. Turning shuffle off restores sequential navigation from the loaded entry's new index.
- Removing another entry prunes it from visits/history without interrupting output. Previous/forward history skips that removed identity.
- Removing the loaded entry stops and clears selection/history. Remaining cycle visits are retained. Explicit Play chooses an unvisited remaining entry, or opens a fresh traversal if all survivors were visited.
- Clear stops, drops queue/visits/history, and retains shuffle/repeat, volume, and EQ. An old completion cannot start newly appended entries before explicit playback.

## Verification and limits

69 tests pass locally on Apple Silicon/macOS 26: deterministic policy tests cover distinct duplicate identities, per-cycle visits, history, edits, failures, empty queues, and offset preservation. Native selector tests cover mode controls and skin replacement. Muted real-device tests measure a full-source Repeat One replay and complete two stereo shuffle/Repeat All cycles while retaining EQ. Packaged playback/layout/Classic/EQ/editing smoke checks pass with mode controls enabled. PNGs of both native layouts and the Classic main were visually inspected. Live app checks verified Shuffle toggling, Repeat cycling, direct Repeat One selection from the menu, and policy retention after switching to Quiet Space. Build and manual actions are recorded in [TESTING.md](TESTING.md).

[Increment 8](PERSISTENCE.md) restores modes, queue/settings, and interface stopped at zero. Shuffle begins a fresh traversal from the restored selection; history remains limited to 200 session-only visits. Metadata/artwork, multi-selection/drag edits, undo/sorting, and saved playlist interchange remain future work. Physical listening and full VoiceOver review remain human acceptance checks. Full historical Classic controls and Modern XML/MAKI remain later compatibility work.
