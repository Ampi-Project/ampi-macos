# Queue editing — increment 6

Both built-in native layouts and the partial Classic playlist support single-entry removal, clearing, and reordering. No action deletes or modifies audio files. Use **Queue → Remove Selected Track / Move Selected Up / Move Selected Down / Clear Queue**, or right-click a queue row. The Classic playlist also has **Remove / Up / Down / Clear** buttons above its transport row. When a queue has keyboard focus, **Delete/backspace** removes its highlighted entry, and **Option-Up/Down** moves it. Return/keypad Enter remains explicit playback activation.

Right-click selects the clicked row before presenting its commands. Right-clicking empty space clears the browse highlight; only Clear Queue remains available. Row edits are disabled without a valid highlight. Up is disabled at the first entry; Down at the last; Clear is disabled when empty. Global Queue commands use the active presentation's highlighted row, including its hidden Classic playlist; a native JSON layout without a queue can still use Clear Queue.

A context menu retains the clicked UUID until its command runs. Playback advancing or queue indices moving while that menu is open cannot redirect an edit to another entry. If that entry is removed elsewhere, its pending row commands become unavailable.

## Playback and browsing rules

| Edit | Result |
| --- | --- |
| Remove an entry other than the loaded one | Same loaded UUID, audio stream, position, transport state, volume, and EQ. Its index adjusts if earlier entries disappeared. |
| Move any entry | Existing UUIDs are retained, including repeated URLs. The loaded index follows its identity without decoder reload or seek. Sequential Next/Previous and completion follow the new order; shuffled traversal follows retained identities/history (see [playback policies](SHUFFLE-REPEAT.md)). |
| Remove the loaded entry | Cancel output, stop, clear loaded selection, and show zero duration/position. Remaining rows stay queued; none starts automatically. |
| Clear Queue | Stop and clear all entries/selection. Volume and EQ remain. Files stay on disk. |
| Explicit Play after removal/clear | Prepare the selected entry, or the first entry when no track is loaded. An old retained decoder cannot represent a new row without loading it. |

Browsing remains separate from the loaded-track marker. Native and Classic tables preserve the browsed UUID through queue-only changes and timer refreshes. Moving a highlighted entry follows it; removing it highlights the following row or the preceding row at the end, without playing that row. Explicit track changes select/reveal the loaded entry. Skin switches preserve queue order and current identity; browse highlights are local to each newly constructed table.

The core model uses final-index move semantics: moving index 0 to index 2 in `[A, B, C]` produces `[B, C, A]`. Invalid indices, unchanged moves, and clearing an already empty queue are ignored. Each actual edit sends one model notification. The native backend's cancellation generations reject old completion events after stop/removal/clear; the session also ignores completion without a loaded queue selection. Duration/position are masked to zero when unselected, even if the backend retains a prepared stopped decoder.

## Verification and limits

Unit checks cover duplicate identities, removal on both sides of a loaded entry, playing/paused/stopped preservation, loaded-entry removal, final-index moves, no-op bounds, observer counts, clear/requeue, EQ/volume retention, and updated completion order. Native UI tests invoke actual keyboard/context actions and Classic buttons, including context targeting, bounds, browse selection, and empty-queue recovery. Muted device checks verify reordered completion and rejection of a cleared stream's callback after immediately rebuilding the queue. The developer smoke command exercises real output while moving/removing entries, then confirms current removal/clear stops safely and leaves its source file intact.

Local verification: 57 tests pass on Apple Silicon/macOS 26, and the packaged WAV/Classic playback/editing smoke check passes. The Classic playlist PNG was visually inspected. Live app checks verified adding a second file while paused, Option-Up preserving the paused loaded entry, Delete removing the browsed entry, menu boundary validation, and Clear producing stopped empty state with disabled seek. Output was muted; listening and full VoiceOver acceptance remain pending.

```sh
swift build
swift test
bash scripts/build-app.sh
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-three-second-or-longer.wav Tests/AmpiUITests/Fixtures/playable-classic.wsz
```

Follow [the increment 6 checklist](TESTING.md) for listening, mouse/keyboard, and VoiceOver checks. Multi-selection, row drag reordering, undo, sort/crop, saved playlists/interchange remain future work. [Increment 8](PERSISTENCE.md) restores durable queue/settings after restart. Edits do not introduce new JSON action bindings or a published cross-platform theme contract. Classic input controls remain the documented native fallback.
