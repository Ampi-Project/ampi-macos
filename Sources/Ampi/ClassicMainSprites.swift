// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore
import ImageIO

/// One transport button's source artwork, command, label, and destination in Classic pixels.
@MainActor struct ClassicTransportSprite {
    /// Command dispatched through the persistent player controller.
    let action: String
    /// Accessible English label independent of the bitmap's icon.
    let label: String
    /// Top-left destination rectangle before integer display scaling.
    let frame: NSRect
    /// Cropped idle sprite with its original pixel dimensions.
    let normal: NSImage
    /// Cropped pressed sprite with its original pixel dimensions.
    let pressed: NSImage
}

/// Validates and composes the deliberately partial Classic main-player sprite profile.
@MainActor struct ClassicMainSprites {
    /// Original 275-by-116 background, already validated by the bounded package reader.
    let background: NSImage
    /// Six mandatory transport icons, ordered Previous, Play, Pause, Stop, Next, Open.
    let transport: [ClassicTransportSprite]
    /// Optional active and inactive title strips; native window chrome remains available.
    let titleBars: [NSImage]
    /// Optional seek background and idle/pressed thumb; empty means native slider fallback.
    let position: [NSImage]
    /// Optional 28 gain-dependent backgrounds followed by idle/pressed volume thumbs.
    let volume: [NSImage]

    /// Checks required dimensions before any crop; malformed present optional sheets fail activation.
    /// Missing optional artwork uses native controls. No third-party scripts or code are executed.
    /// - Throws: A missing, undecodable, or undersized sprite error; package inspection stays usable.
    init(package: ClassicSkinPackage) throws {
        /// Decoded main background, whose exact dimensions were checked during inspection.
        let main = try Self.decode(package, name: "main.bmp", minimum: NSSize(width: 275, height: 116))
        background = NSImage(cgImage: main, size: NSSize(width: 275, height: 116))
        /// Required sheet containing normal and pressed transport states.
        let buttons = try Self.decode(package, name: "cbuttons.bmp", minimum: NSSize(width: 136, height: 36))
        /// Command, accessible label, source rectangle, and historical destination coordinates.
        let specifications: [(String, String, NSRect, NSPoint)] = [
            ("previous", "Previous", NSRect(x: 0, y: 0, width: 23, height: 18), NSPoint(x: 16, y: 88)),
            ("play", "Play", NSRect(x: 23, y: 0, width: 23, height: 18), NSPoint(x: 39, y: 88)),
            ("pause", "Pause", NSRect(x: 46, y: 0, width: 23, height: 18), NSPoint(x: 62, y: 88)),
            ("stop", "Stop", NSRect(x: 69, y: 0, width: 23, height: 18), NSPoint(x: 85, y: 88)),
            ("next", "Next", NSRect(x: 92, y: 0, width: 22, height: 18), NSPoint(x: 108, y: 88)),
            ("open", "Open music", NSRect(x: 114, y: 0, width: 22, height: 16), NSPoint(x: 136, y: 89))
        ]
        /// Collected mandatory sprites, attached only after all crops succeed.
        var composed: [ClassicTransportSprite] = []
        /// Each source and destination is expressed in unscaled, top-left bitmap pixels.
        for (action, label, source, origin) in specifications {
            composed.append(ClassicTransportSprite(action: action, label: label,
                frame: NSRect(origin: origin, size: source.size),
                normal: try Self.crop(buttons, rect: source),
                pressed: try Self.crop(buttons, rect: source.offsetBy(dx: 0, dy: source.height))))
        }
        transport = composed
        if package.assets["titlebar.bmp"] != nil {
            /// Optional title sheet must cover both complete title strips.
            let title = try Self.decode(package, name: "titlebar.bmp", minimum: NSSize(width: 302, height: 29))
            titleBars = try [0.0, 15.0].map { y in try Self.crop(title, rect: NSRect(x: 27, y: y, width: 275, height: 14)) }
        } else { titleBars = [] }
        if package.assets["posbar.bmp"] != nil {
            /// Optional seek sheet includes the track and both 29-pixel thumbs.
            let sheet = try Self.decode(package, name: "posbar.bmp", minimum: NSSize(width: 307, height: 10))
            position = try [NSRect(x: 0, y: 0, width: 248, height: 10),
                            NSRect(x: 248, y: 0, width: 29, height: 10),
                            NSRect(x: 278, y: 0, width: 29, height: 10)].map { rect in try Self.crop(sheet, rect: rect) }
        } else { position = [] }
        if package.assets["volume.bmp"] != nil {
            /// This initial profile requires a 68-pixel-wide volume strip including both thumbs.
            let sheet = try Self.decode(package, name: "volume.bmp", minimum: NSSize(width: 68, height: 433))
            /// Gain backgrounds ordered low to high, cropped from 15-pixel-spaced rows.
            var frames = try (0..<28).map { row in try Self.crop(sheet, rect: NSRect(x: 0, y: row * 15, width: 68, height: 13)) }
            frames.append(try Self.crop(sheet, rect: NSRect(x: 15, y: 422, width: 14, height: 11)))
            frames.append(try Self.crop(sheet, rect: NSRect(x: 0, y: 422, width: 14, height: 11)))
            volume = frames
        } else { volume = [] }
    }

    /// Decodes a previously bounded BMP and checks the dimensions needed by this renderer.
    /// - Parameters: package contains immutable original bytes; name is normalized; minimum is pixels.
    static func decode(_ package: ClassicSkinPackage, name: String, minimum: NSSize) throws -> CGImage {
        /// Required asset bytes and ImageIO image; the importer already checked BMP identity and limits.
        guard let data = package.assets[name], let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ThemeError.invalid("Classic player requires a decodable \(name).")
        }
        guard image.width >= Int(minimum.width), image.height >= Int(minimum.height) else {
            throw ThemeError.invalid("\(name) must be at least \(Int(minimum.width)) × \(Int(minimum.height)) pixels for Classic activation.")
        }
        return image
    }

    /// Crops a top-left pixel rectangle without allowing out-of-bounds or interpolated source pixels.
    /// - Throws: A checked crop error instead of force-unwrapping external artwork.
    static func crop(_ image: CGImage, rect: NSRect) throws -> NSImage {
        /// Full bitmap extent used to prove the crop lies inside the source.
        let extent = NSRect(x: 0, y: 0, width: image.width, height: image.height)
        /// Complete crop produced only after its coordinates pass the bounds check.
        guard extent.contains(rect), let result = image.cropping(to: rect) else {
            throw ThemeError.invalid("Classic sprite rectangle exceeds its bitmap.")
        }
        return NSImage(cgImage: result, size: rect.size)
    }
}

/// Shared nearest-neighbor sprite drawing; coordinates follow the destination view's orientation.
@MainActor func drawClassicSprite(_ image: NSImage, in rect: NSRect, opacity: CGFloat = 1) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current?.imageInterpolation = .none
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: opacity, respectFlipped: true, hints: nil)
}
