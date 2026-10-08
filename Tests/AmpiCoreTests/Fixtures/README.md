# Original Classic inspection fixtures

All pixel artwork in this directory was generated specifically for Ampi on 2026-10-08. No Winamp or third-party skin artwork is copied. These fixtures are original repository content under GPL-3.0-only.

`OriginalClassic` contains two uncompressed 24-bit Windows BMPs: a 275 × 116 main background and a 136 × 36 button sheet. They use original geometric blocks and an RGB palette of (24, 35, 47), (74, 219, 158), and (9, 19, 26). The drawings exercise decoding and scaling, not a complete usable Classic skin.

`original-stored.wsz` contains those files at the archive root with ZIP method 0. `nested-deflated.wsz` contains the same bytes under `Ampi Original/` with uppercase filenames and ZIP method 8. ZIP timestamps are fixed to 2026-10-08 00:00:00; Unix permissions mark both entries as regular files. The tests derive malformed archives in memory from these original bytes rather than publishing historical skin material.

Expected behavior: both archives and the extracted folder produce the same main background at an integer scale. Reports list two assets, warn about missing optional sprites, and state that the preview does not activate controls, the playlist, or equalizer. A nested root and mixed filename casing normalize successfully.
