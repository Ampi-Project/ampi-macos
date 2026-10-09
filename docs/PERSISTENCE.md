# Restart persistence — increment 8

Ampi now remembers queue order and stable entry UUIDs, the selected duplicate entry, main volume, EQ curve/preamp/bypass, shuffle/repeat, and the last successfully activated interface. Restoration begins **stopped at 00:00**. It prepares the saved selection when possible but never calls Play. Elapsed time, playing/paused state, random visitation/history, panel visibility/positions, and browsing selection are not saved.

## Storage and lifecycle

The local app uses `~/Library/Application Support/org.ampi-project.macos/session-v1.json`. This private native state is separate from any project repository or published theme contract. Version one is currently the only supported schema. Reads are bounded to 2 MiB; queues are limited to 10,000 entries and must fit that byte limit. URLs must be local absolute paths, UUIDs unique, and selected identity part of the saved queue. Gains/volume are validated after decoding. The actual opened descriptor must be a regular nonsymlink file; a limit-plus-one read also catches growth after opening.

Queue/settings/interface changes use a 400-ms debounce. A serial storage actor encodes and atomically replaces the complete file away from the main actor. Transport-only changes with identical durable bytes avoid another write. Quit and primary-window close cancel the pending delay and await a forced final save after any older writes. A final save failure offers **Cancel** or **Quit Without Saving**, leaving the previous completed snapshot available. Autosave errors appear in player status without repeatedly scheduling their own error notification. First-launch reads do not create a state file.

Native layouts are embedded as the last validated experimental JSON layout, so moving or editing the original JSON file does not alter the saved interface. Reimport that file to apply later edits. Classic skins retain their original archive/folder URL, not their assets. Startup reopens the source with the existing bounded importer and checks main, playlist, and EQ before replacing the default. Imported skin assets and audio files are never modified by persistence.

## Recovery

| Condition | Result |
| --- | --- |
| Missing/offline/unreadable audio | Skip unavailable regular files, preserving surviving identities/order. Status reports how many were skipped. |
| Missing saved selected entry | Clear selection and show zero time; do not substitute the same filename or start another row. Explicit Play chooses according to the restored shuffle policy. |
| Selected decoder fails despite readable file | Retain queue and settings, clear selection, and show a notice. A user can select another entry; corrupt audio is not silently played or removed. |
| Missing/invalid Classic source or undersized sprite sheet | Keep the default Retro Stereo interface and recovered queue/audio settings; report the fallback. |
| Structurally decoded native geometry fails validation | Keep default interface with valid recovered queue/settings. |
| Malformed JSON, unsupported version, invalid queue/audio values, oversized or nonregular state file | Use first-launch defaults with a notice. Read does not alter the bad file; a subsequent successful save replaces it with valid current state. |
| Old completion from a stopped decoder | Cannot start recovered or newly queued entries. Native cancellation generations and session transport guards still apply. |

To reset saved state manually, quit Ampi first, then move `session-v1.json` to a backup location before relaunching. Keep the backup until the reset is verified. Editing or moving state while Ampi is running is unsupported: final Quit saves the current session again. Automatic saves protect completed snapshots, but edits inside the debounce interval can be lost on a crash or forced termination. This is local state, without backup history or cross-device sync.

## Verification and limits

85 tests pass on the local Apple Silicon/macOS 26 environment. They cover durable duplicate identity, stopped decoder preparation, bounds/corruption, actor storage, previous-save preservation, forced repair, native/Classic startup, missing selection/source, malformed geometry, debounced/final saves, and nonrecursive write-error feedback. Original muted WAV smoke checks exercise a fresh real decoder, stopped clock, explicit playback, offline source pruning, Classic fallback, and corrupt-state defaults in disposable directories. Existing playback/queue/EQ/skin/mode smoke checks also pass. Live Quit/relaunch restored Quiet Space, a test queue, mute, and shuffle/repeat at zero; test entries/settings were then cleared/restored.

The current local ad-hoc app is not App Sandbox-enabled. It stores paths under the user's normal filesystem access; it does not restore permissions or locate moved files. Security-scoped bookmarks, sandboxed distribution, output-device/interruption recovery, supported-version/Intel validation, and full VoiceOver acceptance remain pending. Panel visibility/positions, elapsed-time resumption, saved playlist interchange, and Modern XML/MAKI are later increments. [Local metadata/artwork](METADATA.md) is a derived memory-only cache, omitted from this file and reread after restart. See [manual actions](TESTING.md).
