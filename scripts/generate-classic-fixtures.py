# SPDX-License-Identifier: GPL-3.0-only
"""Reproduce original main-player artwork; no historical skin images are used."""
import pathlib
import struct
import zipfile

# /// Repository root resolved from this script, independent of the caller's directory.
ROOT = pathlib.Path(__file__).resolve().parent.parent
# /// UI test resources also available to contributors for interactive acceptance checks.
DESTINATION = ROOT / "Tests" / "AmpiUITests" / "Fixtures"


# /// Builds an editable, row-major RGB canvas with a solid original background.
def canvas(width, height, color):
    # /// Each row and pixel index creates an independent list so drawing cannot alias rows.
    return [[color for _ in range(width)] for _ in range(height)]


# /// Fills a bounded pixel rectangle; image is mutable, bounds are integer source pixels.
def rectangle(image, x, y, width, height, color):
    # /// Destination rows are clipped to the generated canvas, never to external artwork.
    for row in range(max(0, y), min(len(image), y + height)):
        # /// Destination columns are clipped to the generated row.
        for column in range(max(0, x), min(len(image[0]), x + width)):
            image[row][column] = color


# /// Draws a ten-row triangular transport icon pointing horizontally in the given direction.
def triangle(image, x, y, color, right=True):
    # /// Symmetric triangle rows expand then contract around the middle.
    for row in range(10):
        # /// Half-height line length forms an original geometric icon.
        length = min(row + 1, 10 - row)
        rectangle(image, x if right else x + 5 - length, y + row, length, 1, color)


# /// Encodes the supplied RGB canvas as a deterministic bottom-up, uncompressed 24-bit BMP.
def bitmap(image):
    # /// Integer bitmap axes derived from the internally generated pixel array.
    height, width = len(image), len(image[0])
    # /// Four-byte row alignment required by Windows BMP's uncompressed pixel format.
    stride = (width * 3 + 3) & ~3
    # /// Complete BGR payload, padded per row and stored from bottom to top.
    pixels = bytearray()
    # /// Each RGB row is reversed vertically for BMP's positive-height convention.
    for row in reversed(image):
        # /// Pixel channels are serialized in the BMP-required blue/green/red order.
        for red, green, blue in row:
            pixels.extend((blue, green, red))
        pixels.extend(bytes(stride - width * 3))
    # /// Standard 14-byte file header plus 40-byte BITMAPINFOHEADER.
    header = struct.pack("<2sIHHI", b"BM", 54 + len(pixels), 0, 0, 54)
    header += struct.pack("<IiiHHIIiiII", 40, width, height, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    return header + pixels


# /// Creates a small original skin corpus in the factual Classic main-sheet geometry.
def assets(accent):
    # /// Original dark blue background; no copyrighted reference artwork is sampled.
    dark = (18, 28, 42)
    # /// Original lighter panel color used for normal transport button faces.
    panel = (41, 60, 81)
    # /// Original near-black display recess.
    recess = (5, 11, 18)
    # /// Main background with framed displays and unobtrusive visual texture.
    main = canvas(275, 116, dark)
    rectangle(main, 0, 0, 275, 2, accent)
    rectangle(main, 0, 114, 275, 2, accent)
    rectangle(main, 0, 0, 2, 116, accent)
    rectangle(main, 273, 0, 2, 116, accent)
    rectangle(main, 18, 22, 87, 28, recess)
    rectangle(main, 109, 21, 157, 32, recess)
    # /// Short original equal-height decorative bars; these are deliberately static artwork.
    for column in range(20, 100, 5):
        rectangle(main, column, 54, 2, 12, panel)
    # /// Source sheet packing the six idle and pressed transport buttons.
    controls = canvas(136, 36, dark)
    # /// Each command occupies its factual Classic source rectangle.
    for index, (x, width, height) in enumerate([(0, 23, 18), (23, 23, 18), (46, 23, 18), (69, 23, 18), (92, 22, 18), (114, 22, 16)]):
        # /// Pressed sprites start below their idle counterpart; icons reverse contrast.
        for pressed in (False, True):
            # /// Vertical source position, face color, and contrasting icon color.
            y, face, ink = (height if pressed else 0), (accent if pressed else panel), (recess if pressed else accent)
            rectangle(controls, x, y, width, height, face)
            rectangle(controls, x + 1, y + 1, width - 2, 1, ink)
            if index == 0:
                rectangle(controls, x + 6, y + 4, 2, 10, ink)
                triangle(controls, x + 9, y + 4, ink, right=False)
            elif index == 1:
                triangle(controls, x + 9, y + 4, ink)
            elif index == 2:
                rectangle(controls, x + 7, y + 4, 3, 10, ink)
                rectangle(controls, x + 13, y + 4, 3, 10, ink)
            elif index == 3:
                rectangle(controls, x + 7, y + 5, 9, 8, ink)
            elif index == 4:
                triangle(controls, x + 6, y + 4, ink)
                rectangle(controls, x + 13, y + 4, 2, 10, ink)
            else:
                # /// Eject icon's pyramid rows widen toward its base.
                for row in range(5):
                    rectangle(controls, x + 10 - row, y + 3 + row, 1 + 2 * row, 1, ink)
                rectangle(controls, x + 6, y + 10, 9, 2, ink)
    # /// Original title sheet with two state strips and hand-defined AMPI glyphs.
    title = canvas(302, 29, dark)
    # /// Five-column glyphs generated for this fixture, not copied from a bitmap font.
    letters = {"A": [14, 17, 17, 31, 17, 17, 17], "M": [17, 27, 21, 21, 17, 17, 17],
               "P": [30, 17, 17, 30, 16, 16, 16], "I": [31, 4, 4, 4, 4, 4, 31],
               "L": [16, 16, 16, 16, 16, 16, 31], "Y": [17, 17, 10, 4, 4, 4, 4],
               "S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4]}
    # /// Active and inactive title strips differ in foreground intensity.
    for y, ink in [(0, accent), (15, (115, 133, 154))]:
        rectangle(title, 27, y, 275, 14, panel)
        # /// Each hand-defined letter is placed near the center of the strip.
        for index, letter in enumerate("AMPI"):
            # /// Seven bit-pattern rows define each five-pixel glyph.
            for row, bits in enumerate(letters[letter]):
                # /// Each set bit becomes one original title pixel.
                for column in range(5):
                    if bits & (1 << (4 - column)):
                        rectangle(title, 150 + index * 7 + column, y + 3 + row, 1, 1, ink)
    # /// Seek strip contains a 248-pixel track and two distinctly colored thumbs.
    position = canvas(307, 10, recess)
    rectangle(position, 0, 4, 248, 2, panel)
    rectangle(position, 248, 0, 29, 10, accent)
    rectangle(position, 278, 0, 29, 10, (235, 244, 255))
    # /// Volume strip contains 28 original gain backgrounds and both thumb states.
    volume = canvas(68, 433, recess)
    # /// Increasing row fill makes value-to-sprite selection visible during manual checks.
    for level in range(28):
        rectangle(volume, 0, level * 15 + 5, 68, 3, panel)
        rectangle(volume, 0, level * 15 + 5, round(68 * level / 27), 3, accent)
    rectangle(volume, 15, 422, 14, 11, accent)
    rectangle(volume, 0, 422, 14, 11, (235, 244, 255))
    # /// Original playlist border sheet; unused historical menu regions contain no fake buttons.
    playlist = canvas(280, 186, dark)
    # /// Active/inactive title pieces use original glyphs and distinct accent intensities.
    for y, ink in [(0, accent), (21, (115, 133, 154))]:
        # /// Left corner, repeat tile, center title, and right corner match the border-only profile.
        for x, width in [(0, 25), (127, 25), (26, 100), (153, 25)]:
            rectangle(playlist, x, y, width, 20, panel)
            rectangle(playlist, x, y, width, 2, ink)
        # /// Original PLAYLIST lettering is placed in the center strip, without external font artwork.
        for index, letter in enumerate("PLAYLIST"):
            # /// Each seven-row glyph is expanded into five original binary pixel columns.
            for row, bits in enumerate(letters[letter]):
                # /// Set glyph bits create original text pixels within the validated title rectangle.
                for column in range(5):
                    if bits & (1 << (4 - column)):
                        rectangle(playlist, 48 + index * 7 + column, y + 7 + row, 1, 1, ink)
    rectangle(playlist, 0, 42, 12, 29, panel)
    rectangle(playlist, 0, 42, 2, 29, accent)
    rectangle(playlist, 31, 42, 20, 29, panel)
    rectangle(playlist, 49, 42, 2, 29, accent)
    rectangle(playlist, 0, 72, 125, 38, panel)
    rectangle(playlist, 0, 108, 125, 2, accent)
    rectangle(playlist, 126, 72, 150, 38, panel)
    rectangle(playlist, 126, 108, 150, 2, accent)
    # /// Original equalizer background; native sliders overlay it, without imitating unsupported legacy controls.
    equalizer = canvas(275, 116, dark)
    rectangle(equalizer, 0, 0, 275, 14, panel)
    rectangle(equalizer, 0, 0, 275, 2, accent)
    rectangle(equalizer, 0, 114, 275, 2, accent)
    rectangle(equalizer, 0, 0, 2, 116, accent)
    rectangle(equalizer, 273, 0, 2, 116, accent)
    # /// Centered original AMPI pixels identify this fixture's EQ title without third-party artwork.
    for index, letter in enumerate("AMPI"):
        # /// Original glyph rows reuse only hand-authored shapes above.
        for row, bits in enumerate(letters[letter]):
            # /// Five binary glyph columns are drawn into the EQ title strip.
            for column in range(5):
                if bits & (1 << (4 - column)):
                    rectangle(equalizer, 124 + index * 7 + column, 3 + row, 1, 1, accent)
    # /// INI color profile generated from the same original palette; unrelated font keys are not interpreted.
    ini = "[Text]\nNormal=B4C8DD\nCurrent=" + "".join(f"{value:02X}" for value in accent)
    ini += "\nNormalBG=050B12\nSelectedBG=294766\nFont=Original fixture uses native Unicode text\n"
    return {"main.bmp": bitmap(main), "cbuttons.bmp": bitmap(controls), "titlebar.bmp": bitmap(title),
            "posbar.bmp": bitmap(position), "volume.bmp": bitmap(volume),
            "pledit.bmp": bitmap(playlist), "pledit.txt": ini.encode("ascii"), "eqmain.bmp": bitmap(equalizer)}


# /// Writes deterministic regular-file ZIP entries; prefix/casing/compression exercise normalization.
def archive(name, files, prefix="", uppercase=False, method=zipfile.ZIP_STORED):
    # /// ZIP writer overwrites only this generated fixture under the test-resource directory.
    with zipfile.ZipFile(DESTINATION / name, "w", compression=method) as writer:
        # /// Asset names and bytes come exclusively from the original generator above.
        for filename, data in sorted(files.items()):
            # /// Fixed timestamp and ordinary Unix permissions preserve reproducible output.
            entry = zipfile.ZipInfo(prefix + (filename.upper() if uppercase else filename), (2026, 10, 8, 0, 0, 0))
            entry.compress_type = method
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            writer.writestr(entry, data)


# /// First palette supplies the extracted folder and a flat stored archive.
green = assets((75, 224, 168))
# /// Second original palette makes replacing the active Classic skin visually obvious.
blue = assets((103, 170, 255))
DESTINATION.mkdir(parents=True, exist_ok=True)
(DESTINATION / "PlayableClassic").mkdir(exist_ok=True)
# /// Each generated file is written into the folder fixture with its normalized name.
for filename, data in green.items():
    (DESTINATION / "PlayableClassic" / filename).write_bytes(data)
archive("playable-classic.wsz", green)
archive("playable-classic-nested.wsz", blue, prefix="Ampi Blue/", uppercase=True, method=zipfile.ZIP_DEFLATED)
archive("invalid-main-controls.wsz", {"main.bmp": green["main.bmp"], "cbuttons.bmp": bitmap(canvas(1, 1, (0, 0, 0)))})
archive("invalid-playlist-border.wsz", {**green, "pledit.bmp": bitmap(canvas(1, 1, (0, 0, 0)))})
archive("invalid-equalizer.wsz", {**green, "eqmain.bmp": bitmap(canvas(1, 1, (0, 0, 0)))})
print("Generated original Classic main, playlist, and equalizer fixtures.")
