// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Derived local tags and a small PNG thumbnail; never encoded into a saved session.
public struct TrackMetadata: Equatable, Sendable {
    /// Maximum Unicode scalars retained in each single-line text field.
    public static let maximumTextLength = 256
    /// Maximum PNG bytes accepted from the native thumbnail reader, limiting cache storage.
    public static let maximumArtworkBytes = 512 * 1024
    /// Nonempty embedded title, or nil to use the queue entry's filename.
    public let title: String?
    /// Embedded artist, if available; controls and surrounding whitespace are removed.
    public let artist: String?
    /// Embedded album name, if available; controls and surrounding whitespace are removed.
    public let album: String?
    /// Reader-produced PNG no larger than 256 pixels on either edge; nil without usable artwork.
    public let artwork: Data?

    /// Bounds text and thumbnail storage without changing or opening the original media file.
    /// - Parameters:
    ///   - title: Raw embedded title; blank input becomes nil for filename fallback.
    ///   - artist: Raw embedded artist; scalar prefix and control sanitization match title.
    ///   - album: Raw embedded album; scalar prefix and control sanitization match title.
    ///   - artwork: Already validated/downsampled PNG, discarded if its byte count exceeds the cache limit.
    public init(title: String? = nil, artist: String? = nil, album: String? = nil, artwork: Data? = nil) {
        self.title = Self.clean(title); self.artist = Self.clean(artist); self.album = Self.clean(album)
        /// Optional thumbnail payload is retained only when it fits the documented storage ceiling.
        self.artwork = artwork.flatMap { $0.count <= Self.maximumArtworkBytes ? $0 : nil }
    }

    /// Returns bounded single-line text, or nil for a missing or whitespace-only tag.
    private static func clean(_ raw: String?) -> String? {
        /// Existing raw field is sanitized before it can reach a label or accessibility value.
        guard let raw else { return nil }
        /// Prefix limits scanning work; controls become spaces so words across newlines remain separated.
        let scalars = raw.unicodeScalars.prefix(maximumTextLength).map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return scalars.isEmpty ? nil : scalars
    }
}
