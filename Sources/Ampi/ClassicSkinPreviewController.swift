// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Displays validated Classic background artwork at an integer scale without activating it.
@MainActor final class ClassicSkinPreviewController: NSWindowController {
    /// Package whose original bytes and inspection diagnostics are displayed.
    let package: ClassicSkinPackage
    /// Native content used by the window and developer preview export.
    private let content: NSView

    /// Creates a preview containing the raw main background and an honest feature report.
    /// - Throws: A bitmap decoding error; the active playback surface is unaffected.
    init(package: ClassicSkinPackage) throws {
        self.package = package
        self.content = ClassicPreviewContentView(frame: NSRect(x: 0, y: 0, width: 590, height: 430))
        /// Decoded background, previously checked by the importer for BMP identity and dimensions.
        guard let image = NSImage(data: package.mainBitmap) else { throw ThemeError.invalid("Cannot display the Classic background.") }
        /// Pixel-preserving image view showing the historical 275-by-116 image at two-times scale.
        let artwork = ClassicBitmapView(image: image, frame: NSRect(x: 20, y: 178, width: 550, height: 232))
        artwork.setAccessibilityLabel("Classic main-window background preview")
        content.addSubview(artwork)
        /// Explicit compatibility status displayed above the asset report.
        let status = NSTextField(labelWithString: "Preview only · Your active player and playback stay unchanged")
        status.frame = NSRect(x: 20, y: 145, width: 550, height: 20)
        status.font = .systemFont(ofSize: 12, weight: .semibold)
        content.addSubview(status)
        /// Scrollable diagnostic text, including normalized root, assets, and missing sprites.
        let scroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: 550, height: 115))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        /// Read-only selectable report, allowing users to copy the import findings.
        let report = NSTextView(frame: scroll.bounds)
        report.isEditable = false
        report.isSelectable = true
        report.font = .systemFont(ofSize: 12)
        report.textContainerInset = NSSize(width: 8, height: 8)
        report.isVerticallyResizable = true
        report.autoresizingMask = [.width]
        report.textContainer?.widthTracksTextView = true
        report.string = "Root: \(package.root.isEmpty ? "archive/folder root" : package.root)\nAssets (\(package.assets.count)): \(package.assetNames.joined(separator: ", "))\n\n" + package.warnings.joined(separator: "\n\n")
        report.setAccessibilityLabel("Classic skin inspection report")
        scroll.documentView = report
        content.addSubview(scroll)
        /// Independent preview window; closing it leaves the player session intact.
        let window = NSWindow(contentRect: content.bounds, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Classic skin preview — \(package.name)"
        window.contentView = content
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    /// Rejects archive/storyboard construction because a validated package is required.
    required init?(coder: NSCoder) { fatalError("Use init(package:)") }

    /// Exports the same native content as the visible inspector to a PNG for visual checks.
    /// - Parameter url: Destination preview file, overwritten on success.
    /// - Throws: A bitmap creation, PNG encoding, or file-writing error.
    func exportPreview(to url: URL) throws {
        content.layoutSubtreeIfNeeded()
        /// Bitmap covering both artwork and the compatibility report.
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw ThemeError.invalid("Cannot create a Classic preview bitmap.") }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        /// Encoded preview suitable for fixture review.
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ThemeError.invalid("Cannot encode the Classic preview.") }
        try png.write(to: url)
    }
}

/// Supplies an opaque adaptive background for both native windows and exported previews.
@MainActor private final class ClassicPreviewContentView: NSView {
    /// Fills the content surface so labels remain legible when cached without a window backdrop.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

/// Draws a Classic bitmap with nearest-neighbor sampling, preserving integer-scale pixels.
@MainActor private final class ClassicBitmapView: NSView {
    /// Original background decoded from validated package bytes.
    private let image: NSImage

    /// Retains the image and configures its fixed logical display rectangle.
    init(image: NSImage, frame: NSRect) { self.image = image; super.init(frame: frame) }

    /// Rejects archive/storyboard construction because a decoded image is required.
    required init?(coder: NSCoder) { fatalError("Use init(image:frame:)") }

    /// Renders the background without smoothing; saves and restores caller graphics state.
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
