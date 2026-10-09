// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Experimental JSON layout; validate before constructing native controls from it.
public struct Theme: Codable, Sendable {
    /// Draft format version; currently only version one is supported.
    public let schemaVersion: Int
    /// Nonempty theme identifier, limited to 100 characters.
    public let id: String
    /// Display name, limited to 100 characters.
    public let name: String
    /// Player surface width in logical points, from 320 through 1200.
    public let width: Double
    /// Player surface height in logical points, from 240 through 1000.
    public let height: Double
    /// Control and decorative panel corner radius in points, from zero through 24.
    public let cornerRadius: Double
    /// Colors used by native drawing and text controls.
    public let palette: Palette
    /// One through 64 controls, ordered by their placement in the view hierarchy.
    public let elements: [Element]

    /// Opaque sRGB colors encoded as six hexadecimal digits prefixed with `#`.
    public struct Palette: Codable, Sendable {
        /// Base color of the player surface.
        public let background: String
        /// Fill color for the track panel, queue, and secondary buttons.
        public let panel: String
        /// Primary text and secondary button foreground color.
        public let text: String
        /// Status and empty-queue hint text color.
        public let muted: String
        /// Emphasis color for transport controls, selected tracks, and decoration.
        public let accent: String
    }

    /// Declarative native control with geometry and an optional playback connection.
    public struct Element: Codable, Sendable {
        /// Native control families supported by the current layout renderer.
        public enum Kind: String, Codable, Sendable {
            /// Static text or a text field bound to track, time, or status.
            case label
            /// Transport or file-opening action with a visible, accessible label.
            case button
            /// Continuous seek or volume control.
            case slider
            /// Scrollable track queue; at most one is allowed per layout.
            case queue
        }
        /// Nonempty identifier unique within the layout.
        public let id: String
        /// Native control family to construct.
        public let kind: Kind
        /// `[x, y, width, height]` in points, measured from the surface's top-left.
        public let frame: [Double]
        /// Visible text or accessibility label, limited to 200 characters.
        public let label: String
        /// Text/slider session field; nil for unbound labels, buttons, and queues.
        public let binding: String?
        /// Button operation: open, previous, playPause, stop, next, shuffle, or repeat; nil otherwise.
        public let action: String?
        /// Optional label font size in points, from ten through 40.
        public let fontSize: Double?
    }

    /// Decodes and validates a JSON layout before it can reach the native renderer.
    /// - Parameter data: UTF-8 JSON payload of at most 256 KiB.
    /// - Returns: A layout satisfying the current draft's safety and control rules.
    /// - Throws: A decoding error or `ThemeError` for an unsupported or invalid layout.
    public static func decode(_ data: Data) throws -> Theme {
        guard data.count <= 256 * 1024 else { throw ThemeError.invalid("Theme files must be smaller than 256 KiB.") }
        /// Decoded candidate; validation must succeed before it is returned.
        let theme = try JSONDecoder().decode(Theme.self, from: data)
        try theme.validate()
        return theme
    }

    /// Checks version, colors, finite geometry, unique IDs, and usable playback controls.
    /// - Throws: `ThemeError.invalid` describing the first constraint that failed.
    public func validate() throws {
        guard schemaVersion == 1 else { throw ThemeError.invalid("Unsupported theme draft version: \(schemaVersion).") }
        guard !id.isEmpty, !name.isEmpty, id.count <= 100, name.count <= 100 else {
            throw ThemeError.invalid("A theme needs a short identifier and name.")
        }
        guard width.isFinite, height.isFinite, (320...1200).contains(width), (240...1000).contains(height),
              cornerRadius.isFinite, (0...24).contains(cornerRadius) else {
            throw ThemeError.invalid("Invalid window dimensions or corner radius.")
        }
        /// Each palette color must be an opaque six-digit hexadecimal value.
        for color in [palette.background, palette.panel, palette.text, palette.muted, palette.accent] {
            guard color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
                throw ThemeError.invalid("Colors must use six-digit hexadecimal notation.")
            }
        }
        guard (1...64).contains(elements.count) else { throw ThemeError.invalid("A theme needs between 1 and 64 elements.") }
        /// Identifiers already encountered, used to reject duplicate controls.
        var ids = Set<String>()
        /// Valid button actions encountered, used to require Open and Play/Pause.
        var actions = Set<String>()
        /// Whether a queue has already been seen, enforcing the single-queue limit.
        var hasQueue = false
        /// Current control whose geometry and playback connection are being checked.
        for element in elements {
            guard !element.id.isEmpty, ids.insert(element.id).inserted, element.label.count <= 200 else {
                throw ThemeError.invalid("Element identifiers must be nonempty and unique, with short labels.")
            }
            /// Four-component frame, checked before indexing or native conversion.
            let f = element.frame
            guard f.count == 4, f.allSatisfy(\.isFinite), f[0] >= 0, f[1] >= 0,
                  f[2] > 0, f[3] > 0, f[0] + f[2] <= width, f[1] + f[3] <= height else {
                throw ThemeError.invalid("Element \(element.id) is outside the player surface.")
            }
            /// Optional font size must be finite and within the readable point range.
            if let size = element.fontSize, !size.isFinite || !(10...40).contains(size) {
                throw ThemeError.invalid("Invalid font size for \(element.id).")
            }
            switch element.kind {
            case .button:
                /// Validated operation; only the fixed action allowlist can be dispatched.
                guard let action = element.action, ["open", "previous", "playPause", "stop", "next", "shuffle", "repeat"].contains(action),
                      element.binding == nil, !element.label.isEmpty, f[2] >= 32, f[3] >= 28 else {
                    throw ThemeError.invalid("Invalid button action or hit target for \(element.id).")
                }
                actions.insert(action)
            case .slider:
                /// Validated session field; sliders may control only position or volume.
                guard let binding = element.binding, ["position", "volume"].contains(binding),
                      element.action == nil, !element.label.isEmpty, f[2] >= 60, f[3] >= 20 else {
                    throw ThemeError.invalid("Invalid slider binding for \(element.id).")
                }
            case .label:
                guard element.action == nil, element.binding == nil || ["track", "time", "status"].contains(element.binding!) else {
                    throw ThemeError.invalid("Invalid text binding for \(element.id).")
                }
            case .queue:
                guard !hasQueue, element.binding == nil, element.action == nil, f[3] >= 60 else {
                    throw ThemeError.invalid("Only one queue is supported, with a height of at least 60 points.")
                }
                hasQueue = true
            }
        }
        guard actions.contains("open"), actions.contains("playPause") else {
            throw ThemeError.invalid("Every theme must expose Open and Play/Pause.")
        }
    }
}

/// Layout failures suitable for display in a native warning sheet.
public enum ThemeError: LocalizedError {
    /// Unsupported or invalid layout with a user-facing explanation.
    case invalid(String)
    /// Explanation supplied by the decoder, validator, or resource loader.
    public var errorDescription: String? {
        /// Message carried by the invalid-layout error.
        switch self { case .invalid(let message): return message }
    }
}

/// Loads original bundled layouts or an external experimental JSON layout.
public enum ThemeCatalog {
    /// Resource names for the original layouts shipped with the macOS prototype.
    public static let builtins = ["retro", "minimal"]

    /// Loads and validates an allowlisted layout from this package's resource bundle.
    /// - Parameter name: A resource name from `builtins`, without an extension.
    /// - Throws: A resource-reading, decoding, or validation error.
    public static func builtin(_ name: String) throws -> Theme {
        /// Resource URL resolved only after the requested name passes the allowlist.
        guard builtins.contains(name), let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw ThemeError.invalid("Built-in theme was not found.")
        }
        return try Theme.decode(Data(contentsOf: url))
    }

    /// Loads an external JSON layout after checking its file size, then validates it.
    /// - Parameter url: Readable local layout file.
    /// - Throws: A file-access, decoding, or validation error.
    public static func load(_ url: URL) throws -> Theme {
        /// Reported file size in bytes, checked before reading the payload into memory.
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 256 * 1024 else { throw ThemeError.invalid("Theme files must be smaller than 256 KiB.") }
        return try Theme.decode(Data(contentsOf: url))
    }
}
