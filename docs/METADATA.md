# Track metadata and embedded artwork

Increment 9 reads local common title, artist, album, and embedded artwork asynchronously through AVFoundation. An embedded title replaces the filename in native and Classic main/queue labels. Hover a track label or queue row for available artist/album information. **Window → Show / Hide Track Info (⌘I)** opens a native read-only panel with the loaded track's tags, original filename, and cover thumbnail. This panel works with every skin, stays synchronized while hidden, and survives skin replacement. Closing it leaves transport untouched; closing the primary player also closes it.

Queue browsing does not change Track Info; playing a different row does. Missing/blank/unreadable titles retain the filename. Missing artist/album and rejected/missing artwork have explicit placeholders. Changing to an untagged track clears the previous cover immediately. No tag is edited, no audio file is rewritten, and metadata completion never loads, seeks, pauses, or starts the playback graph.

## Reader and cache profile

| Constraint | Behavior |
| --- | --- |
| Local input | File URLs with an empty/localhost host and a readable regular file; no remote metadata, linked image URLs, sidecars, or artwork lookup. |
| Audio inspection ceiling | Files over 256 MiB keep filename fallback. This ceiling limits metadata inspection only; normal audio playback is unchanged. |
| Reader scheduling | At most two scheduled workers. The loaded entry is prioritized, followed by the first queue entries, up to 64 identities total. Entries beyond that window keep filename fallback until selected. |
| Cancellation | Removing/clearing/evicting identities cancels their work. Per-job tokens plus live UUID/URL validation reject late results, including clear/requeue of the same path. |
| Deadline | After ten seconds, cancel pending native property loading and return fallback. Cancellation depends on the native framework responding; it is not process termination or a parser sandbox. |
| Common metadata | Inspect at most the first 64 native common items; retain the first usable value for each supported field. |
| Text | Each field is limited to a 256-Unicode-scalar prefix, control characters become spaces, and surrounding whitespace is removed. Unicode labels remain supported. |
| Embedded image | PNG/JPEG only; at most 4 MiB compressed, source dimensions 1–4096 pixels per edge. Inspect the header before decoding, orient/downsample the first image, and recheck the result. |
| Thumbnail | At most 256 pixels per edge and 512 KiB PNG. A cache of 64 results retains at most 32 MiB of PNG data, plus bounded text/bookkeeping. |
| Durable state | Tags and covers are derived memory-only data. They are absent from session JSON, are reread after restart, and do not trigger autosave. Track Info visibility/placement is not persisted. |

AVFoundation may allocate native item values before Ampi checks their lengths, and Image I/O is a native decoder. These post-load/result limits do not establish a hard bound on all native parsing allocations. This increment introduces neither a parser subprocess nor App Sandbox/file bookmarks.

Verified metadata input is an original synthesized AAC/M4A containing Unicode common tags and embedded PNG. Native image checks cover PNG downsampling, malformed data, oversized payloads, and oversized headers. Other containers/tag variants, JPEG covers, language-specific tag selection, tag editing, additional fields, and format-specific diagnostics need further fixtures/acceptance work; do not infer broad MP3/FLAC tag compatibility from this check. Image layout primitives in JSON are still future work; artwork currently appears in the shared native panel.

Apple references: [asynchronous common metadata](https://developer.apple.com/documentation/avfoundation/avpartialasyncproperty/commonmetadata-3j3n4), [metadata key spaces](https://developer.apple.com/documentation/avfoundation/avmetadataitem), and [Image I/O thumbnail dimension limit](https://developer.apple.com/documentation/imageio/kcgimagesourcethumbnailmaxpixelsize).

## Original developer fixture and smoke check

The generator creates a ten-second quiet 330-Hz mono signal, Unicode title `Ampi · موسیقی test`, original artist/album text, and original orange/blue geometric artwork. It uses no downloaded music or legacy artwork. Original generated fixture content is GPL-3.0-only like its generator. It refuses to overwrite an existing destination. Use a fresh filename if `/tmp` already contains one:

```sh
dist/Ampi.app/Contents/MacOS/Ampi --create-metadata-fixture /tmp/ampi-original-tags.m4a
dist/Ampi.app/Contents/MacOS/Ampi --metadata-smoke-test /tmp/ampi-original-tags.m4a Tests/AmpiUITests/Fixtures/playable-classic.wsz /tmp/ampi-track-info.png
```

The smoke check runs the real reader, muted audio graph, native/Classic surfaces, retained metadata panel, and optional native panel PNG export. It never attaches a persistence observer or uses the owner's Application Support state. It does not certify physical listening or VoiceOver. Follow [increment 9 manual checks](TESTING.md).
