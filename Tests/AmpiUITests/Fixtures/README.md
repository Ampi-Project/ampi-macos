# Original Classic main/playlist/equalizer fixtures

Generated specifically for Ampi on 2026-10-08 by [the reproducible generator](../../../scripts/generate-classic-fixtures.py). All artwork and glyphs are original GPL-3.0-only repository content. No historical Winamp or third-party skin pixels were copied. Classic sheet coordinates are compatibility facts; they do not identify copied artwork.

Run `python3 scripts/generate-classic-fixtures.py` from the repository root to reproduce the bytes. The generator uses only Python's standard library. ZIP entries use fixed timestamps and regular-file Unix permissions.

| Fixture | Purpose | Expected result |
| --- | --- | --- |
| `playable-classic.wsz` | Flat stored ZIP with green accents | Inspect, then activate main controls, playlist border/colors, and EQ background at 2× |
| `playable-classic-nested.wsz` | Nested DEFLATE ZIP, uppercase filenames, blue accents | Same functionality after path/case normalization; replacing green preserves playback |
| `PlayableClassic/` | Extracted green version | Same inspection and activation as the flat archive |
| `invalid-main-controls.wsz` | Valid main BMP with a decodable 1×1 button BMP | Inspection succeeds; activation is disabled with a dimension diagnostic |
| `invalid-playlist-border.wsz` | Otherwise usable green skin with a decodable 1×1 playlist BMP | Inspection succeeds; main/playlist activation is disabled atomically |
| `invalid-equalizer.wsz` | Otherwise usable green skin with a decodable 1×1 EQ BMP | Inspection succeeds; all three surfaces retain the old skin and activation is disabled |

The complete fixtures contain `main.bmp` (275×116), `cbuttons.bmp` (136×36), `titlebar.bmp` (302×29), `posbar.bmp` (307×10), `volume.bmp` (68×433), `pledit.bmp` (280×186), `eqmain.bmp` (275×116), and an original ASCII `pledit.txt` palette. Idle transport faces are RGB (41,60,81); pressed green faces are (75,224,168). Separate pressed seek/volume thumbs use (235,244,255). This makes crop, orientation, state, gain-row, and panel-color errors visible.

Increment 4 adds independently drawn playlist frame sprites and PLAYLIST glyphs; increment 5 adds an independently drawn EQ background and its malformed-dimension fixture. EQ sliders, labels, and buttons are native controls. Historical playlist menu/scrollbar regions are intentionally empty. These fixtures certify only the documented partial main/playlist/EQ profiles; they do not certify historical EQ sprites/preset files, bitmap fonts, visualization, compact panels, balance, shuffle/repeat, docking, or all historical packages. Earlier inspection fixtures remain under `Tests/AmpiCoreTests/Fixtures`.
