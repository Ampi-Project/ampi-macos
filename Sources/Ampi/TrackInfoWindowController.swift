// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Native metadata panel shared by every skin, following the loaded entry rather than the browse highlight.
@MainActor final class TrackInfoView: NSView {
    /// Queue owns derived metadata; displaying this panel never loads or starts the audio decoder.
    private let session: PlaybackSession
    /// Single-line title has a full bounded tooltip for names wider than the panel.
    let titleLabel = NSTextField(labelWithString: "No track selected")
    /// Artist fallback is explicit when the local file provides no usable tag.
    let artistLabel = NSTextField(labelWithString: "Artist unavailable")
    /// Album fallback is explicit when the local file provides no usable tag.
    let albumLabel = NSTextField(labelWithString: "Album unavailable")
    /// Original local filename distinguishes tag titles from the actual media file.
    let fileLabel = NSTextField(labelWithString: "")
    /// Proportionally scaled reader-produced PNG; no remote image or full-resolution cover is decoded here.
    let artworkView = NSImageView()
    /// Visible and accessible placeholder remains available for untagged/invalid artwork.
    let artworkPlaceholder = NSTextField(wrappingLabelWithString: "No embedded artwork")
    /// Last rendered identity avoids repeatedly decoding the same thumbnail on every playback timer tick.
    private var renderedTrack: UUID?
    /// Last tag revision also causes a refresh when asynchronous extraction finishes for this identity.
    private var renderedRevision: UInt?
    /// Top-left panel geometry uses the same coordinate convention as native skins.
    override var isFlipped: Bool { true }

    /// Creates native selectable labels and an accessible cover/fallback area without changing playback.
    init(session: PlaybackSession) {
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: 680, height: 330))
        artworkView.frame = NSRect(x: 24, y: 24, width: 256, height: 256)
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.setAccessibilityLabel("Embedded cover artwork")
        addSubview(artworkView)
        artworkPlaceholder.frame = NSRect(x: 40, y: 128, width: 224, height: 52)
        artworkPlaceholder.alignment = .center; artworkPlaceholder.textColor = .secondaryLabelColor
        addSubview(artworkPlaceholder)
        /// Label, vertical origin, and accessibility name define the panel's native text controls.
        for (label, y, name) in [(titleLabel, 32.0, "Track title"), (artistLabel, 98.0, "Artist"),
                                (albumLabel, 146.0, "Album"), (fileLabel, 212.0, "Audio filename")] {
            label.frame = NSRect(x: 312, y: y, width: 344, height: label === titleLabel ? 48 : 32)
            label.font = .systemFont(ofSize: label === titleLabel ? 20 : 14)
            label.lineBreakMode = .byTruncatingTail; label.isSelectable = true
            label.maximumNumberOfLines = 1; label.setAccessibilityLabel(name)
            addSubview(label)
        }
        /// Panel explains that fields follow transport selection, independent of queue browsing and tag editing.
        let hint = NSTextField(labelWithString: "Current track · Read-only local tags and embedded artwork")
        hint.frame = NSRect(x: 24, y: 296, width: 632, height: 20)
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        addSubview(hint)
        refresh()
    }

    /// Rejects archive/storyboard construction; a live session is required.
    required init?(coder: NSCoder) { fatalError("Use init(session:)") }

    /// Draws the native window background so on-screen content and exported PNGs have the same readable contrast.
    /// - Parameter dirtyRect: AppKit invalidation region; the small fixed-size panel redraws its full background.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
    }

    /// Refreshes fields after selection/tag changes, clears stale cover art, and keeps the filename on missing title.
    func refresh() {
        guard renderedRevision != session.metadataRevision || renderedTrack != session.currentTrack?.id else { return }
        renderedRevision = session.metadataRevision; renderedTrack = session.currentTrack?.id
        /// Current transport entry can be nil after clear/removal even if a browsed row remains highlighted.
        let track = session.currentTrack
        /// Optional bounded result is unavailable until the asynchronous reader finishes or after cache eviction.
        let metadata = track.flatMap { session.metadata(for: $0) }
        titleLabel.stringValue = track.map { session.displayTitle(for: $0) } ?? "No track selected"
        artistLabel.stringValue = metadata?.artist ?? "Artist unavailable"
        albumLabel.stringValue = metadata?.album ?? "Album unavailable"
        fileLabel.stringValue = track?.url.lastPathComponent ?? ""
        fileLabel.toolTip = track?.url.path
        /// Bounded text fields expose their complete values through native accessibility and tooltips.
        for label in [titleLabel, artistLabel, albumLabel, fileLabel] {
            label.setAccessibilityValue(label.stringValue)
            if label !== fileLabel { label.toolTip = label.stringValue }
        }
        artworkView.image = metadata?.artwork.flatMap { NSImage(data: $0) }
        artworkView.isHidden = artworkView.image == nil
        artworkPlaceholder.isHidden = artworkView.image != nil
        artworkView.setAccessibilityValue("Cover for \(titleLabel.stringValue)")
    }
}

/// Reusable detachable panel whose close button hides metadata without stopping the player.
@MainActor final class TrackInfoWindowController: NSWindowController {
    /// Actual native panel content used by interactive controls and rendering/integration tests.
    let content: TrackInfoView

    /// Constructs a titled fixed-size panel showing metadata for the same persistent session as the player.
    init(session: PlaybackSession) {
        content = TrackInfoView(session: session)
        /// AppKit owns a normal accessible child window; no historical skin geometry is modified.
        let window = NSWindow(contentRect: content.bounds, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Ampi Track Info"; window.contentView = content; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
    }

    /// Rejects archive/storyboard construction; a live session is required.
    required init?(coder: NSCoder) { fatalError("Use init(session:)") }
}
