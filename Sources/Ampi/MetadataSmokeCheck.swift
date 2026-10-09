// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AVFoundation
import AmpiCore
import ImageIO
import UniformTypeIdentifiers

/// Developer checks use original synthesized audio/tags/artwork and the actual asynchronous reader and native graph.
@MainActor enum MetadataSmokeCheck {
    /// Original Unicode title distinguishes successful tag reading from the output file's basename.
    static let fixtureTitle = "Ampi · موسیقی test"
    /// Original test artist is not the attribution of any third-party recording.
    static let fixtureArtist = "Ampi contributors"
    /// Original album value exercises common album-name normalization.
    static let fixtureAlbum = "Original test signals"

    /// Writes a ten-second quiet AAC/M4A signal with common Unicode tags and original geometric PNG artwork.
    /// - Parameter url: New destination file; existing files are rejected rather than overwritten.
    /// - Throws: Native encoder/file/export failures; only the disposable intermediate CAF is removed.
    static func createFixture(at url: URL) async throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw ThemeError.invalid("Fixture output already exists.") }
        /// Original lossless intermediate exists only in the temporary directory during AAC encoding.
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("ampi-tags-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: source) }
        /// One mono channel at 44.1 kHz supplies a short quiet original sine wave.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 441_000),
              let samples = buffer.floatChannelData?[0] else { throw PlaybackError.couldNotStart }
        buffer.frameLength = buffer.frameCapacity
        /// Sample index determines the 330-Hz signal phase; amplitude 0.02 avoids a loud fixture if opened manually.
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0.02 * sin(Float(index) * 2 * .pi * 330 / 44_100) }
        do {
            /// Scoped writer closes and finalizes the CAF before the exporter opens the intermediate.
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
        }
        /// Local exporter maps common tags into the MPEG-4 audio container's native metadata.
        guard let exporter = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetAppleM4A) else {
            throw ThemeError.invalid("Native AAC fixture exporter is unavailable.")
        }
        exporter.outputURL = url; exporter.outputFileType = .m4a
        exporter.metadata = [item(.commonIdentifierTitle, value: fixtureTitle as NSString),
            item(.commonIdentifierArtist, value: fixtureArtist as NSString),
            item(.commonIdentifierAlbumName, value: fixtureAlbum as NSString),
            item(.commonIdentifierArtwork, value: try artwork() as NSData)]
        // The completion-based API retains compatibility with the macOS 13 deployment target.
        await exporter.export()
        guard exporter.status == .completed else { throw exporter.error ?? PlaybackError.couldNotStart }
    }

    /// Creates an immutable common-key item with an original string or PNG value for the native exporter.
    private static func item(_ identifier: AVMetadataIdentifier, value: any NSCopying & NSObjectProtocol) -> AVMetadataItem {
        /// Mutable builder is copied before it is handed to AVFoundation.
        let item = AVMutableMetadataItem()
        item.identifier = identifier; item.value = value
        return item.copy() as! AVMetadataItem
    }

    /// Creates original 512×512 orange/blue geometric artwork without external assets or typography dependencies.
    static func artwork(width: Int = 512, height: Int = 512) throws -> Data {
        /// RGB bitmap is used only for original test inputs, including deliberately oversized header tests.
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ThemeError.invalid("Could not create original cover fixture.")
        }
        context.setFillColor(CGColor(red: 0.08, green: 0.16, blue: 0.28, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0.48, blue: 0.12, alpha: 1))
        context.fillEllipse(in: CGRect(x: Double(width) * 0.2, y: Double(height) * 0.2,
                                      width: Double(width) * 0.6, height: Double(height) * 0.6))
        /// Small PNG destination encodes the original bitmap; no source media or user paths are opened.
        let output = NSMutableData()
        /// Native image and encoder are required to produce a portable fixture with accurate dimensions.
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ThemeError.invalid("Could not encode original cover fixture.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ThemeError.invalid("Original cover encoding failed.") }
        return output as Data
    }

    /// Verifies actual tag extraction, selected native/Classic UI, panel continuity, and muted playback without durable state writes.
    /// - Parameters: Tagged original audio path, optional original Classic package, and optional panel preview PNG path.
    static func run(audio: URL, skin: URL?, preview: URL?) async throws {
        /// Common tags and small cover must survive actual AVFoundation metadata normalization.
        let metadata = await TrackMetadataReader.read(audio)
        guard metadata.title == fixtureTitle, metadata.artist == fixtureArtist,
              metadata.album == fixtureAlbum, metadata.artwork != nil else { throw ThemeError.invalid("Original tagged fixture did not return all expected metadata.") }
        /// Actual playback graph remains muted throughout every surface and metadata operation.
        let backend = NativeAudioBackend()
        /// Session and skin controller follow the same asynchronous reader used by the interactive app.
        let session = PlaybackSession(backend: backend)
        session.setVolume(0); session.enqueue([audio, audio]); try session.resume()
        /// One native controller hosts both skins and the shared Track Info panel; no persistence observer is installed.
        let controller = PlayerWindowController(session: session, theme: try ThemeCatalog.builtin("retro"))
        defer { controller.close(); session.stop() }
        /// Bounded wait lets background metadata jobs publish on the main actor without blocking audio clocks.
        let deadline = Date().addingTimeInterval(4)
        while session.metadata(for: session.tracks[0]) == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        controller.toggleTrackInfo()
        /// Same retained panel must show the selected metadata across replacements and close/reopen.
        guard let panel = controller.trackInfoPanel,
              panel.content.titleLabel.stringValue == fixtureTitle, panel.content.artworkView.image != nil,
              session.state == .playing, session.position > 0, session.volume == 0 else { throw PlaybackError.couldNotStart }
        /// Loaded identity remains stable while metadata arrives and different skins install.
        let identity = session.currentTrack?.id
        try controller.apply(ThemeCatalog.builtin("minimal"))
        /// Optional Classic renderer exposes the same cached title in its main view and playlist.
        if let skin {
            try controller.applyClassic(ClassicSkinPackage.load(skin))
            /// Actual Classic surface is required before inspecting its native Unicode track label.
            guard let classic = controller.surface as? ClassicPlayerView,
                  classic.subviews.compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue == fixtureTitle }) else {
                throw ThemeError.invalid("Classic title did not reflect embedded metadata.")
            }
        }
        guard controller.trackInfoPanel === panel, session.currentTrack?.id == identity,
              session.state == .playing, session.position > 0, session.volume == 0 else { throw PlaybackError.couldNotStart }
        /// Optional artifact uses the actual AppKit panel renderer, with no synthetic web representation.
        if let preview {
            /// Bitmap captures the full native content view after layout, preserving its current image and text.
            guard let bitmap = panel.content.bitmapImageRepForCachingDisplay(in: panel.content.bounds) else { throw ThemeError.invalid("Could not allocate metadata preview.") }
            panel.content.cacheDisplay(in: panel.content.bounds, to: bitmap)
            /// PNG representation is written only to the explicit developer output path.
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ThemeError.invalid("Could not encode metadata preview.") }
            try png.write(to: preview)
        }
        print("PASS: Unicode title/artist/album, embedded PNG thumbnail, native/Classic metadata, retained Track Info, and uninterrupted muted playback.")
    }
}
