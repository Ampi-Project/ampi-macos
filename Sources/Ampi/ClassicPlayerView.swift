// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Native button whose normal/pressed artwork comes from a validated Classic sprite sheet.
@MainActor final class ClassicSpriteButton: NSButton {
    /// Command delivered to the common player controller.
    let command: String
    /// Original normal-state bitmap, displayed at the surface's integer scale.
    private let normal: NSImage
    /// Original pressed-state bitmap selected by AppKit's standard button tracking.
    private let pressed: NSImage
    /// Allows Tab traversal even though the bitmap has no textual title.
    override var acceptsFirstResponder: Bool { true }

    /// Configures native input/accessibility and retains already checked artwork.
    init(sprite: ClassicTransportSprite, scale: CGFloat) {
        command = sprite.action; normal = sprite.normal; pressed = sprite.pressed
        super.init(frame: NSRect(x: sprite.frame.minX * scale, y: sprite.frame.minY * scale,
                                width: sprite.frame.width * scale, height: sprite.frame.height * scale))
        title = ""
        isBordered = false
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        setAccessibilityLabel(sprite.label)
        toolTip = sprite.label
    }

    /// Rejects construction without validated sprite artwork.
    required init?(coder: NSCoder) { fatalError("Use init(sprite:scale:)") }

    /// Uses AppKit's pressed state and draws a contrasting visible keyboard focus indicator.
    override func draw(_ dirtyRect: NSRect) {
        drawClassicSprite(isHighlighted ? pressed : normal, in: bounds, opacity: isEnabled ? 1 : 0.45)
        if window?.firstResponder === self {
            NSColor.white.setStroke()
            /// Inner focus rectangle kept inside the small historical hit area.
            let ring = NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3))
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

/// Skins a native linear slider cell while retaining AppKit tracking, keyboard, and accessibility.
@MainActor final class ClassicSliderCell: NSSliderCell {
    /// Ordered backgrounds; seek has one, volume has 28 corresponding to increasing gain.
    let backgrounds: [NSImage]
    /// Idle slider thumb cropped from the source strip.
    let normal: NSImage
    /// Pressed slider thumb selected during native tracking.
    let pressed: NSImage
    /// Integer scale shared with the main background and transport buttons.
    let scale: CGFloat
    /// Thumb width used by native slider tracking to bound the value's travel distance.
    override var knobThickness: CGFloat { normal.size.width * scale }

    /// Retains validated frames: at least one background followed by idle/pressed thumbs.
    /// Callers use only ClassicMainSprites output; scale is a positive integer point multiplier.
    init(frames: [NSImage], scale: CGFloat) {
        backgrounds = Array(frames.dropLast(2)); normal = frames[frames.count - 2]; pressed = frames[frames.count - 1]
        self.scale = scale
        super.init()
        sliderType = .linear
        isVertical = false
    }

    /// Rejects construction without the checked track and thumb frames.
    required init(coder: NSCoder) { fatalError("Use init(frames:scale:)") }

    /// Normalized slider position; a disabled or zero-length range renders at its start.
    private var fraction: CGFloat {
        maxValue > minValue ? CGFloat(min(1, max(0, (doubleValue - minValue) / (maxValue - minValue)))) : 0
    }

    /// Uses the complete control bounds as the sprite track in either coordinate orientation.
    override func barRect(flipped: Bool) -> NSRect { controlView?.bounds ?? .zero }

    /// Matches rendered thumb travel to the native slider's bounded value range.
    override func knobRect(flipped: Bool) -> NSRect {
        /// Current native track bounds, expressed in logical points.
        let track = barRect(flipped: flipped)
        /// Source thumb height multiplied by the fixed display scale.
        let height = normal.size.height * scale
        return NSRect(x: track.minX + fraction * max(0, track.width - knobThickness),
                      y: track.midY - height / 2, width: knobThickness, height: height)
    }

    /// Draws the gain-dependent background without AppKit's default rounded slider bar.
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        /// Closest volume frame; seek always selects its single background.
        let index = Int((fraction * CGFloat(backgrounds.count - 1)).rounded())
        drawClassicSprite(backgrounds[index], in: barRect(flipped: flipped), opacity: isEnabled ? 1 : 0.45)
    }

    /// Draws the thumb at the same rectangle used by hit testing and tracking.
    override func drawKnob(_ knobRect: NSRect) {
        drawClassicSprite(isHighlighted ? pressed : normal, in: knobRect, opacity: isEnabled ? 1 : 0.45)
    }
}

/// Partial Classic main player with real transport and native slider/text fallbacks.
@MainActor final class ClassicPlayerView: NSView, PlayerSurface {
    /// Main content view installed in the existing native window.
    var view: NSView { self }
    /// Distinct Classic presentation identity for developer verification.
    var presentationID: String { "ampi.classic.main" }
    /// Package name and precise support scope displayed by native window chrome.
    var displayName: String { "\(package.name) · Classic main" }
    /// Common controller command callback; its String parameter identifies a transport action.
    var onAction: ((String) -> Void)?
    /// Common importer callback; its URLs are local dropped files.
    var onDrop: (([URL]) -> Void)?
    /// Immutable validated source package; no managed installation is performed yet.
    let package: ClassicSkinPackage
    /// Playback state retained across native/Classic replacements.
    let session: PlaybackSession
    /// Checked artwork and independently cropped control states.
    private let sprites: ClassicMainSprites
    /// Fixed integer display scale; this increment supports 2× only.
    private let scale: CGFloat = 2
    /// Native transport controls, exposed internally for meaningful interaction checks.
    private(set) var buttons: [ClassicSpriteButton] = []
    /// Native seek slider; optional source artwork changes drawing, not transport semantics.
    private(set) var seekSlider = NSSlider()
    /// Native volume slider with bounded zero-through-one gain.
    private(set) var volumeSlider = NSSlider()
    /// Original native PL toggle controlling the detachable Classic queue window.
    let playlistButton = SkinButton()
    /// Native EQ toggle shows the detachable equalizer without changing its bypass state.
    let equalizerButton = SkinButton()
    /// Unicode filename label using system typography rather than an incomplete bitmap font.
    private let trackLabel = NSTextField(labelWithString: "Open music")
    /// Minutes/seconds label refreshed from the common session.
    private let timeLabel = NSTextField(labelWithString: "00:00")
    /// Native text transport state; no decorative status is presented as live audio data.
    private let stateLabel = NSTextField(labelWithString: "Stopped")
    /// Classic assets use top-left destination coordinates.
    override var isFlipped: Bool { true }

    /// Composes all sprites before attaching any content; invalid artwork leaves the old skin intact.
    /// - Throws: Missing/undersized sprite errors from the main-player profile.
    init(package: ClassicSkinPackage, session: PlaybackSession) throws {
        self.package = package; self.session = session
        sprites = try ClassicMainSprites(package: package)
        super.init(frame: NSRect(x: 0, y: 0, width: 550, height: 232))
        registerForDraggedTypes([.fileURL])
        /// Each sprite supplies a distinct command, native hit region, and accessible label.
        for sprite in sprites.transport {
            /// Native bitmap button connected to this surface's forwarding action.
            let button = ClassicSpriteButton(sprite: sprite, scale: scale)
            button.target = self; button.action = #selector(activate(_:))
            addSubview(button); buttons.append(button)
        }
        configure(seekSlider, frame: NSRect(x: 16, y: 72, width: 248, height: 10),
                  frames: sprites.position, label: "Playback position", action: #selector(seek(_:)))
        configure(volumeSlider, frame: NSRect(x: 107, y: 57, width: 68, height: 13),
                  frames: sprites.volume, label: "Volume", action: #selector(changeVolume(_:)))
        volumeSlider.minValue = 0; volumeSlider.maxValue = 1
        configure(trackLabel, frame: NSRect(x: 111, y: 23, width: 153, height: 10), size: 7, label: "Current track")
        configure(timeLabel, frame: NSRect(x: 45, y: 25, width: 60, height: 19), size: 16, label: "Playback time")
        configure(stateLabel, frame: NSRect(x: 111, y: 42, width: 153, height: 10), size: 7, label: "Player status")
        playlistButton.frame = scaled(NSRect(x: 242, y: 58, width: 23, height: 12))
        playlistButton.title = "PL"; playlistButton.actionName = "playlist"
        playlistButton.fill = .black; playlistButton.ink = .white
        playlistButton.target = self; playlistButton.action = #selector(togglePlaylist(_:))
        playlistButton.setAccessibilityLabel("Show or hide Classic playlist")
        playlistButton.toolTip = "Show or hide playlist (⌘L)"
        addSubview(playlistButton)
        equalizerButton.frame = scaled(NSRect(x: 219, y: 58, width: 23, height: 12))
        equalizerButton.title = "EQ"; equalizerButton.actionName = "equalizer"
        equalizerButton.fill = .black; equalizerButton.ink = .white
        equalizerButton.target = self; equalizerButton.action = #selector(toggleEqualizer(_:))
        equalizerButton.setAccessibilityLabel("Show or hide equalizer")
        equalizerButton.toolTip = "Show or hide equalizer (⌘E)"
        addSubview(equalizerButton)
        refresh()
    }

    /// Rejects construction without a validated package and playback session.
    required init?(coder: NSCoder) { fatalError("Use init(package:session:)") }

    /// Installs native slider behavior, optionally substituting validated sprite-based drawing.
    /// - Parameters: frame uses Classic pixels; frames is empty for fallback; action receives NSSlider.
    private func configure(_ slider: NSSlider, frame: NSRect, frames: [NSImage], label: String, action: Selector) {
        slider.frame = scaled(frame)
        if !frames.isEmpty { slider.cell = ClassicSliderCell(frames: frames, scale: scale) }
        slider.isContinuous = true
        slider.target = self; slider.action = action
        slider.setAccessibilityLabel(label)
        slider.toolTip = label
        addSubview(slider)
    }

    /// Places readable Unicode text in a Classic display region with an explicit accessible name.
    private func configure(_ label: NSTextField, frame: NSRect, size: CGFloat, label accessibleName: String) {
        label.frame = scaled(frame)
        label.font = .monospacedSystemFont(ofSize: size * scale, weight: .medium)
        label.textColor = .white
        label.backgroundColor = NSColor(white: 0.03, alpha: 1)
        label.drawsBackground = true
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setAccessibilityLabel(accessibleName)
        addSubview(label)
    }

    /// Converts source-pixel coordinates to the surface's fixed integer point scale.
    private func scaled(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    /// Draws the main background and optional focused/unfocused title strip at nearest-neighbor scale.
    override func draw(_ dirtyRect: NSRect) {
        drawClassicSprite(sprites.background, in: bounds)
        if !sprites.titleBars.isEmpty {
            drawClassicSprite(sprites.titleBars[window?.isKeyWindow == true ? 0 : 1],
                              in: scaled(NSRect(x: 0, y: 0, width: 275, height: 14)))
        }
    }

    /// Refreshes state without resetting a thumb during native mouse tracking.
    func refresh() {
        trackLabel.stringValue = session.currentTrack?.title ?? "Open music to start"
        trackLabel.toolTip = session.currentTrack?.title
        /// Whole elapsed seconds for the compact native clock, bounded by the loaded duration.
        let seconds = Int(min(session.duration, max(0, session.position)))
        timeLabel.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        stateLabel.stringValue = session.status
        stateLabel.toolTip = session.status
        seekSlider.isEnabled = session.currentTrack != nil && session.duration > 0
        seekSlider.minValue = 0; seekSlider.maxValue = max(1, session.duration)
        if seekSlider.cell?.isHighlighted != true { seekSlider.doubleValue = session.position }
        if volumeSlider.cell?.isHighlighted != true { volumeSlider.doubleValue = Double(session.volume) }
        needsDisplay = true
    }

    /// Sends the native button's command to the controller; artwork never contains executable actions.
    @objc private func activate(_ sender: ClassicSpriteButton) { onAction?(sender.command) }

    /// Toggles the queue panel through the shared controller without changing transport.
    @objc private func togglePlaylist(_ sender: SkinButton) { onAction?("playlist") }
    /// Shows or hides EQ through the controller while retaining DSP settings and transport.
    @objc private func toggleEqualizer(_ sender: SkinButton) { onAction?("equalizer") }

    /// Applies the seek slider's seconds value to the loaded track.
    @objc private func seek(_ sender: NSSlider) { session.seek(to: sender.doubleValue) }

    /// Applies the volume slider's zero-through-one gain to the persistent audio backend.
    @objc private func changeVolume(_ sender: NSSlider) { session.setVolume(Float(sender.doubleValue)) }

    /// Advertises local file drop support over the Classic main surface.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    /// Extracts local file URLs and forwards them to the same importer as the native layouts.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        /// Valid local files from the drag pasteboard; remote URLs and empty drags are rejected.
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
