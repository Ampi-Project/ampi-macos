# Classic playlist — increment 4

Classic activation now prepares both the main player and a detachable playlist before replacing either window. The first activation opens the playlist. **PL**, **Window → Show / Hide Classic Playlist**, or **⌘L** hides/reopens the same panel. Closing only the playlist preserves music. Closing the primary player closes its child windows, cancels imports, stops output, and retires the refresh timer.

Increments 5–6 also validate the EQ before any replacement and add [single-entry remove, clear, and Up/Down reordering](QUEUE-EDITING.md). Classic editing buttons occupy the row above transport; native Queue menus, row context menus, Delete, and Option-Up/Down provide the same actions. Their bounds/selection availability stays synchronized without changing the fixed panel size.

The playlist shares the exact `PlaybackSession` used by the main player. There is one queue, audio backend, observer, and refresh timer. Add Audio and local file drops append entries through the common importer. Filenames, including Unicode, appear with a one-based number. A triangle and imported Current color identify the loaded entry. A single click or arrow-key navigation only browses; double-click, Return/keypad Enter, or **Play Selected** starts the highlighted entry. Native toolbar buttons provide Previous, Play, Pause, Stop, and Next. Transport and completion changes update/reveal the current row; pause/seek and ordinary timer ticks preserve a browsed selection.

## Partial rendering profile

The content is fixed at 550×464 logical points, corresponding to a 275×232 Classic window at 2×. Border sprites tile at nearest-neighbor scale. Native window chrome provides move/close/minimize. Native Unicode text, table navigation, scrolling, and transport controls are intentional fallbacks; no full historical playlist rendering claim is made.

| Resource | Supported profile | Missing or invalid behavior |
| --- | --- | --- |
| `pledit.bmp` | At least 276×110 pixels; active/inactive top corners/title/tile, side tiles, bottom corners | Missing: original native border. Present but undersized: activation disabled; current windows/music remain intact. |
| `pledit.txt` | At most 16 KiB; UTF-8 or Windows-1252; `[Text]` keys Normal, Current, NormalBG, SelectedBG | Missing, undecodable, or oversized: original palette with diagnostics. Malformed/duplicate known colors: per-key default with diagnostics. |
| INI color values | Six ASCII hexadecimal RGB digits, optional `#`, optional trailing semicolon comment; case-insensitive keys | Unknown sections/settings, including Font, are ignored; no script content executes. |

All package bytes first pass the existing [bounded importer](CLASSIC-INSPECTION.md). The border-only crop geometry was checked against [Webamp's primary sprite definitions](https://github.com/captbaritone/webamp/blob/master/packages/webamp/js/skinSprites.ts); the AppKit implementation and fixture pixels are original. The original default palette uses Normal `B4C8DD`, Current `4BE0A8`, NormalBG `050B12`, SelectedBG `294766`. Native scrollbar appearance follows the background brightness. Row numbering stays left-to-right while title text retains native bidirectional shaping.

Embedded titles now replace filenames when usable [local metadata](METADATA.md) arrives. Row tooltips include available artist/album, and tag refreshes preserve the user's browsed identity. ⌘I opens shared Track Info for the loaded entry without requiring separate historical playlist metadata/artwork geometry.

## Verification

[Manual tests](TESTING.md) cover empty/long queues, browsing versus activation, toolbar actions, append/advance synchronization, hiding/reopening, whole-skin switching, invalid borders, and primary-window closure. Automated tests cover those model/control bindings, Unicode titles, imported colors and bounded fallback diagnostics, three-surface activation safety, missing optional resources, and window/session lifecycle. The native smoke check uses muted real audio to select a second entry through the playlist, return to the first, hide/reopen the panel, and restore the default layout.

```sh
swift build
swift test
bash scripts/build-app.sh
dist/Ampi.app/Contents/MacOS/Ampi --classic-playlist-preview Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-classic-playlist.png
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-long-enough.wav Tests/AmpiUITests/Fixtures/playable-classic.wsz
```

The preview uses illustrative filenames and never decodes or plays those files. Fixtures are documented under [Tests/AmpiUITests/Fixtures](../Tests/AmpiUITests/Fixtures/README.md).

## Remaining work

Single-entry removal, clear, and Up/Down reordering work with native controls. Multi-selection, drag reordering, undo/cropping/sorting, duration/metadata columns, saved playlists/interchange, historical playlist menus/scrollbar sprites, resizing, shade, docking/snapping, and remembered panel state remain pending. Closing/reopening during one session works. [Restart persistence](PERSISTENCE.md) restores queue/settings and revalidates the saved source; panel visibility/positions are not remembered. The [equalizer](CLASSIC-EQUALIZER.md) has native controls and real DSP. Historical EQ sprites/presets, historical shuffle/repeat artwork, balance, visualization, and Modern XML/MAKI remain later work. Full VoiceOver and supported-platform review remain human acceptance tasks.
