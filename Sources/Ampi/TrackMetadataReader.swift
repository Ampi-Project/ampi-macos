// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import AmpiCore
import ImageIO
import UniformTypeIdentifiers

/// Reads Apple's common tags asynchronously from local files; no sidecar or remote artwork requests.
enum TrackMetadataReader {
    /// Audio files beyond this 256-MiB inspection ceiling retain filename fallback but can still play normally.
    static let maximumFileBytes = 256 * 1024 * 1024
    /// Maximum compressed embedded image accepted before Image I/O inspection and thumbnail creation.
    static let maximumSourceArtworkBytes = 4 * 1024 * 1024
    /// Maximum source width/height in pixels; oversized image headers are rejected before decoding.
    static let maximumImageDimension = 4096
    /// Maximum output edge in pixels, limiting retained decoded image memory as well as PNG bytes.
    static let thumbnailSize = 256

    /// Returns sanitized tags or empty fallback on unsupported/corrupt/missing input, cancellation, or a ten-second deadline.
    /// Native framework property loads may allocate before Ampi applies its result limits; this is not a parser sandbox.
    static func read(_ url: URL) async -> TrackMetadata {
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { return TrackMetadata() }
        /// Local regular-file metadata bounds the file exposed to the native metadata parser.
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= maximumFileBytes else { return TrackMetadata() }
        /// Local AVFoundation object exists only in this background operation and never touches the playback graph.
        let asset = AVURLAsset(url: url)
        do {
            return try await withTaskCancellationHandler(operation: {
                /// Group contains the metadata worker and deadline; its first completion cancels the other child.
                try await withThrowingTaskGroup(of: TrackMetadata.self) { group in
                    group.addTask { try await extract(asset) }
                    group.addTask {
                        try await Task.sleep(for: .seconds(10))
                        asset.cancelLoading()
                        throw CancellationError()
                    }
                    defer { group.cancelAll(); asset.cancelLoading() }
                    /// First result wins; timeout/cancellation forwards to pending native property loads.
                    return try await group.next() ?? TrackMetadata()
                }
            }, onCancel: { asset.cancelLoading() })
        } catch { return TrackMetadata() }
    }

    /// Loads at most 64 common items, retaining the first usable title/artist/album/image; individual bad values are skipped.
    private static func extract(_ asset: AVURLAsset) async throws -> TrackMetadata {
        /// Native common-key normalization supports tags without a format-specific parser in Ampi.
        let items = try await asset.load(.commonMetadata)
        /// Optional title remains nil when its common tag is missing, blank, or fails to load.
        var title: String?
        /// Optional artist remains nil when its common tag is missing, blank, or fails to load.
        var artist: String?
        /// Optional album remains nil when its common tag is missing, blank, or fails to load.
        var album: String?
        /// Validated small PNG kept independently from potentially large embedded compressed data.
        var artwork: Data?
        /// Bounded common item has a format-normalized key and an asynchronously loaded value.
        for item in items.prefix(64) {
            try Task.checkCancellation()
            switch item.commonKey {
            case .commonKeyTitle where title == nil:
                title = TrackMetadata(title: try? await item.load(.stringValue)).title
            case .commonKeyArtist where artist == nil:
                artist = TrackMetadata(artist: try? await item.load(.stringValue)).artist
            case .commonKeyAlbumName where album == nil:
                album = TrackMetadata(album: try? await item.load(.stringValue)).album
            case .commonKeyArtwork where artwork == nil:
                /// Compressed embedded payload is size-checked before image decoding; URLs are never fetched.
                if let data = try? await item.load(.dataValue) { artwork = thumbnail(data) }
            default: break
            }
        }
        try Task.checkCancellation()
        return TrackMetadata(title: title, artist: artist, album: album, artwork: artwork)
    }

    /// Validates the first image header, downsamples with orientation, and returns a bounded PNG or nil.
    /// Source must be PNG/JPEG within 4 MiB and dimensions 1...4096; only the first image is used.
    static func thumbnail(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= maximumSourceArtworkBytes else { return nil }
        /// Lazy source avoids decoding the full image just to discover its dimensions.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source), [UTType.png.identifier, UTType.jpeg.identifier].contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              (1...maximumImageDimension).contains(width.intValue), (1...maximumImageDimension).contains(height.intValue) else { return nil }
        /// Image I/O creates an oriented thumbnail with both edges bounded to 256 pixels.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
            kCGImageSourceShouldCacheImmediately: true]
        /// Decoder result is checked again instead of trusting the thumbnail options alone.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width <= thumbnailSize, image.height <= thumbnailSize else { return nil }
        /// Mutable destination accumulates only the small decoded thumbnail's PNG encoding.
        let output = NSMutableData()
        /// PNG encoder never writes an image or tag back to the source audio file.
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= TrackMetadata.maximumArtworkBytes else { return nil }
        return output as Data
    }
}
