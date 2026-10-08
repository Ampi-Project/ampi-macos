# Classic skin inspection — increment 2

This macOS increment validates and previews Classic assets. It displays the raw `main.bmp` background at 2× nearest-neighbor scale alongside a compatibility report. It does not activate a Classic playback interface, compose sprite sheets, install packages, or interpret scripts. Audio and the active Ampi layout remain in their existing session.

## Inputs and current profile

Open **File → Open Skin / Layout…** (⌘⇧O), drop one `.wsz`/ZIP archive, or select an extracted folder. A single JSON file still applies the experimental Ampi layout. Package contents determine the family; the extension alone does not prove compatibility. Selections mixing audio and skin input are rejected.

Supported archive profile: single-disk ZIP32, stored or DEFLATE files, normal/data-descriptor entries, CP437 or UTF-8 paths, flat or nested roots. Backslashes, filename casing, and Unicode normalization are handled before asset lookup. ZIP64, encryption, special Unix file types, symbolic links, duplicate normalized paths, ambiguous multiple `main.bmp` roots, and packages containing `skin.xml` are rejected.

The unique `main.bmp` must be a decodable Windows BMP of exactly 275 × 116 pixels. Other BMPs directly beside it must also decode within the resource limits. Missing common sprites are reported without blocking background inspection; their dimensions and interactions are not yet certified. [Alpha-II's original skin-template documentation](https://www.alpha-ii.com/Info/Template.html) supplies the historical background dimensions and asset roles; no template artwork was copied.

## Validation and resource limits

| Resource | Current limit |
| --- | --- |
| Archive input bytes | 16 MiB |
| Uncompressed bytes per file | 8 MiB |
| Total expanded bytes | 64 MiB |
| Entries, including directories | 512 |
| Path length / component depth | 1,024 characters / 16 components |
| Bitmap dimensions / pixel count | 4,096 per axis / 4,194,304 pixels |

Checked ZIP directory/local-header bounds precede library iteration. All file output is held in bounded memory; checksums and actual sizes are verified. No archive paths are extracted to disk. Folder inputs reject symlinks and special files, and file handles refuse final-component symlinks. Image dimensions are checked before raster decoding. Inspection runs off the main actor, checks cancellation between entries/chunks, and a newer request cancels the previous inspection. Failed or cancelled inspection leaves the active skin unchanged.

## Fixtures and checks

Original GPL fixtures and provenance live in [Tests/AmpiCoreTests/Fixtures](../Tests/AmpiCoreTests/Fixtures/README.md). Tests cover flat/stored and nested/DEFLATE archives, extracted folders, path/case handling, duplicates, Modern detection, missing/corrupt bitmaps, checksums, inconsistent headers, symlinks, and declared/actual expansion limits. ZIPFoundation 0.9.20 is pinned; see [third-party notices](../THIRD-PARTY-NOTICES.md).

```sh
swift build
swift test
bash scripts/build-app.sh
dist/Ampi.app/Contents/MacOS/Ampi --classic-preview Tests/AmpiCoreTests/Fixtures/nested-deflated.wsz /tmp/ampi-classic-preview.png
dist/Ampi.app/Contents/MacOS/Ampi --smoke-test /path/to/a-three-second-or-longer.wav Tests/AmpiCoreTests/Fixtures/original-stored.wsz
```

The optional second smoke-test input opens a visible Classic preview while muted native playback continues, then verifies that the active layout, track, transport, position, and gain remain intact.

## Remaining Classic work

Compose sprite sheets and connect main-window controls, render playlist and equalizer panels with functioning DSP, support compact modes and panel behavior, test pixel scaling and accessibility, add managed installation/recovery, and expand the original/cleared corpus. Full Classic support remains a roadmap milestone; Modern XML/MAKI remains later work. The published cross-platform theme contract is still pending.
