// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Checked border artwork and bounded playlist colors for the partial Classic playlist profile.
@MainActor struct ClassicPlaylistStyle {
    /// Normal queue text; malformed/missing INI values use readable original defaults.
    let normal: NSColor
    /// Text marking the currently loaded track, independently of the browsed selection.
    let current: NSColor
    /// Queue recess background.
    let background: NSColor
    /// Row background for the user's current browse selection.
    let selected: NSColor
    /// Active/inactive title strips: left corner, fill tile, center, right corner in that order.
    let titles: [[NSImage]]
    /// Left side, right side, bottom-left corner, and bottom-right corner; empty for native fallback.
    let borders: [NSImage]
    /// Visible report describing fallback colors, border support, and remaining features.
    let diagnostics: [String]

    /// Validates optional border extents and reads a restricted, non-executable INI color profile.
    /// Missing artwork yields a usable native border; a present undersized bitmap rejects activation.
    /// - Throws: Bitmap decoding or crop errors; never reads resources outside the bounded package.
    init(package: ClassicSkinPackage) throws {
        /// Color values parsed only from the Text section, alongside diagnostic fallbacks.
        let palette = Self.readColors(package.assets["pledit.txt"])
        normal = palette.values["normal"] ?? NSColor(hex: "#B4C8DD")
        current = palette.values["current"] ?? NSColor(hex: "#4BE0A8")
        background = palette.values["normalbg"] ?? NSColor(hex: "#050B12")
        selected = palette.values["selectedbg"] ?? NSColor(hex: "#294766")
        /// Accumulated feature report includes unsupported controls instead of promising full compatibility.
        var report = palette.warnings
        if package.assets["pledit.bmp"] != nil {
            /// Border-only profile requires the full crop extent, not the unimplemented menu sprites below it.
            let sheet = try ClassicMainSprites.decode(package, name: "pledit.bmp", minimum: NSSize(width: 276, height: 110))
            titles = try [0.0, 21.0].map { y in
                try [NSRect(x: 0, y: y, width: 25, height: 20),
                     NSRect(x: 127, y: y, width: 25, height: 20),
                     NSRect(x: 26, y: y, width: 100, height: 20),
                     NSRect(x: 153, y: y, width: 25, height: 20)].map { rect in try ClassicMainSprites.crop(sheet, rect: rect) }
            }
            borders = try [NSRect(x: 0, y: 42, width: 12, height: 29),
                           NSRect(x: 31, y: 42, width: 20, height: 29),
                           NSRect(x: 0, y: 72, width: 125, height: 38),
                           NSRect(x: 126, y: 72, width: 150, height: 38)].map { rect in try ClassicMainSprites.crop(sheet, rect: rect) }
            report.append("Playlist border sprites available at 2×; native queue, scrollbar, text, and transport toolbar are used.")
        } else {
            titles = []; borders = []
            report.append("Missing pledit.bmp: playlist uses an original native border and controls.")
        }
        report.append("Playlist is append-only. Editing, sorting, saved playlists, skinned menus/scrollbars, shade, resizing, and docking remain unavailable.")
        diagnostics = report
    }

    /// Parses at most 16 KiB of UTF-8/Windows-1252 INI; individual invalid colors use defaults.
    /// Duplicate color keys and malformed known values are reported; unrelated keys are ignored.
    private static func readColors(_ data: Data?) -> (values: [String: NSColor], warnings: [String]) {
        /// Optional bounded input; oversized data never enters string splitting on the main actor.
        guard let data else { return ([:], ["Missing pledit.txt: playlist uses original default colors."]) }
        guard data.count <= 16 * 1024 else { return ([:], ["pledit.txt exceeds 16 KiB; original default colors are used."]) }
        /// Legacy skins may use Windows-1252; supported color keys and values themselves are ASCII.
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else {
            return ([:], ["Cannot decode pledit.txt; original default colors are used."])
        }
        /// Supported normalized Text-section color bindings.
        let supported = Set(["normal", "current", "normalbg", "selectedbg"])
        /// Successfully decoded colors; missing keys are supplied by the caller's original palette.
        var values: [String: NSColor] = [:]
        /// Keys already encountered, preventing ambiguous duplicate values.
        var seen = Set<String>()
        /// Current INI section, with any leading Unicode BOM removed during line normalization.
        var section = ""
        /// Individual invalid values reported in the inspector while retaining a usable fallback.
        var warnings: [String] = []
        /// Each line is normalized, with blank and comment lines ignored.
        for raw in text.components(separatedBy: .newlines) {
            /// Whitespace/BOM-trimmed INI line; script or executable content is never interpreted.
            let line = raw.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{FEFF}")))
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") { section = String(line.dropFirst().dropLast()).lowercased(); continue }
            /// Only explicit key/value pairs in the Text section may influence the palette.
            guard section == "text", let separator = line.firstIndex(of: "=") else { continue }
            /// Case-normalized known binding, ignoring font and unrelated historical settings.
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            guard supported.contains(key) else { continue }
            guard seen.insert(key).inserted else {
                values.removeValue(forKey: key)
                warnings.append("Duplicate pledit.txt \(key); default color is used.")
                continue
            }
            /// Six hexadecimal RGB digits, optionally prefixed with # and followed by a semicolon comment.
            let value = line[line.index(after: separator)...].split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            /// Normalized RGB digits accepted only when every character is an ASCII hexadecimal digit.
            let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
            guard digits.utf8.count == 6, digits.utf8.allSatisfy({ byte in
                (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
            }) else { warnings.append("Invalid pledit.txt \(key); default color is used."); continue }
            values[key] = NSColor(hex: "#" + digits)
        }
        return (values, warnings)
    }
}
