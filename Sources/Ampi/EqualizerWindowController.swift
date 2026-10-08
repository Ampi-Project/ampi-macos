// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Optional Classic background and explicit native-control fallback for the current EQ profile.
@MainActor struct ClassicEqualizerStyle {
    /// First 275-by-116 pixels of eqmain.bmp, absent when the package omits that optional asset.
    let background: NSImage?
    /// Inspection report distinguishing native input controls from historical EQ sprite rendering.
    let diagnostics: [String]

    /// Validates any supplied EQ bitmap before skin activation; missing artwork uses an original backdrop.
    init(package: ClassicSkinPackage?) throws {
        /// Optional imported artwork must fit the declared background profile when present.
        if let package, package.assets["eqmain.bmp"] != nil {
            /// Checked source image; malformed optional artwork rejects the entire replacement skin.
            let image = try ClassicMainSprites.decode(package, name: "eqmain.bmp", minimum: NSSize(width: 275, height: 116))
            background = try ClassicMainSprites.crop(image, rect: NSRect(x: 0, y: 0, width: 275, height: 116))
            diagnostics = ["Equalizer: imported eqmain.bmp background at 2×; sliders, bypass, presets, and text use native controls. Historical EQ graph/control sprites and preset files are not implemented."]
        } else {
            background = nil
            diagnostics = ["Equalizer: no eqmain.bmp; original native backdrop and controls provide the same ten-band DSP."]
        }
    }
}

/// Native, keyboard-accessible equalizer that edits the shared session rather than owning audio output.
@MainActor final class EqualizerView: NSView {
    /// Session curve survives closing this view and switching themes or tracks.
    let session: PlaybackSession
    /// Validated optional artwork; controls remain native for both Classic and JSON layouts.
    let style: ClassicEqualizerStyle
    /// Explicit whole-effect bypass, including the preamp.
    let enabledButton = NSButton(checkboxWithTitle: "EQ on", target: nil, action: nil)
    /// Eleven vertical native sliders, preamp first followed by the ten nominal bands.
    private(set) var sliders: [NSSlider] = []
    /// Per-control gain labels in decibels, synchronized from the model.
    private var gainLabels: [NSTextField] = []
    /// Original preset picker; Custom indicates a curve edited with individual sliders.
    let presets = NSPopUpButton(frame: .zero, pullsDown: false)
    /// Restores unity preamp and a flat curve without changing bypass.
    let flatButton = NSButton(title: "Reset Flat", target: nil, action: nil)
    /// Native readable status with the bypass and headroom behavior made explicit.
    private let status = NSTextField(labelWithString: "EQ bypassed · values retained")
    /// Uses top-left artwork coordinates, matching the Classic player.
    override var isFlipped: Bool { true }

    /// Builds fixed-size controls with bounded gain and explicit accessibility labels.
    init(session: PlaybackSession, style: ClassicEqualizerStyle) {
        self.session = session; self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 550, height: 282))
        appearance = NSAppearance(named: .darkAqua)
        enabledButton.frame = NSRect(x: 20, y: 30, width: 150, height: 24)
        enabledButton.target = self; enabledButton.action = #selector(changeEnabled(_:))
        enabledButton.setAccessibilityLabel("Enable equalizer and preamp")
        addSubview(enabledButton)
        presets.frame = NSRect(x: 324, y: 29, width: 204, height: 26)
        presets.addItems(withTitles: ["Custom"] + EqualizerPreset.allCases.map(\.rawValue))
        presets.target = self; presets.action = #selector(changePreset(_:))
        presets.setAccessibilityLabel("Equalizer preset")
        addSubview(presets)
        /// Labels correspond to the same frequency ordering used by the audio backend.
        let names = ["Preamp", "31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        /// Every slider has native tracking and arrow-key input; band tags are zero-based, preamp is minus one.
        for (index, name) in names.enumerated() {
            /// Center in logical points separates the preamp from the ten-band curve.
            let x: CGFloat = index == 0 ? 60 : 166 + CGFloat(index - 1) * 36
            /// Readable label above the native slider; the full frequency is also its accessible name.
            let heading = label(name, frame: NSRect(x: x - 25, y: 60, width: 50, height: 18))
            addSubview(heading)
            /// Vertical native control ranges from minus twelve to plus twelve decibels.
            let slider = NSSlider(value: 0, minValue: -12, maxValue: 12, target: self, action: #selector(changeGain(_:)))
            slider.frame = NSRect(x: x - 12, y: 82, width: 24, height: 110)
            (slider.cell as? NSSliderCell)?.isVertical = true
            slider.isContinuous = true; slider.tag = index - 1
            slider.setAccessibilityLabel(index == 0 ? "Equalizer preamp, decibels" :
                "Equalizer \(Int(EqualizerSettings.frequencies[index - 1])) hertz, decibels")
            addSubview(slider); sliders.append(slider)
            /// Current gain label remains readable independently of a skin's historical bitmap font.
            let gain = label("0.0", frame: NSRect(x: x - 25, y: 194, width: 50, height: 18))
            gain.setAccessibilityElement(false)
            addSubview(gain); gainLabels.append(gain)
        }
        /// Units and nominal centers describe the audio controls without implying an imported response graph.
        let units = label("±12 dB     ·     Band centers in Hz", frame: NSRect(x: 126, y: 216, width: 394, height: 16))
        addSubview(units)
        flatButton.frame = NSRect(x: 414, y: 244, width: 114, height: 28)
        flatButton.bezelStyle = .rounded
        flatButton.target = self; flatButton.action = #selector(resetFlat(_:))
        addSubview(flatButton)
        status.frame = NSRect(x: 20, y: 248, width: 382, height: 20)
        status.textColor = .white; status.font = .systemFont(ofSize: 11)
        status.setAccessibilityLabel("Equalizer state")
        addSubview(status)
        refresh()
    }

    /// Rejects construction without a shared model and checked artwork.
    required init?(coder: NSCoder) { fatalError("Use init(session:style:)") }

    /// Creates a centered, opaque label so imported artwork cannot obscure control values.
    private func label(_ text: String, frame: NSRect) -> NSTextField {
        /// Native Unicode label with explicit typography and contrast.
        let result = NSTextField(labelWithString: text)
        result.frame = frame; result.alignment = .center
        result.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        result.textColor = .white; result.backgroundColor = NSColor(white: 0.06, alpha: 1)
        result.drawsBackground = true
        return result
    }

    /// Draws optional Classic background above an original footer; native controls overlay both profiles.
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 1).setFill(); bounds.fill()
        /// Imported background is already bounded and cropped before installing the panel.
        if let background = style.background {
            drawClassicSprite(background, in: NSRect(x: 0, y: 0, width: 550, height: 232))
        }
    }

    /// Updates all controls from the session without resetting a slider during mouse tracking.
    func refresh() {
        enabledButton.isEnabled = session.supportsEqualizer
        enabledButton.state = session.equalizer.isEnabled ? .on : .off
        presets.isEnabled = session.supportsEqualizer; flatButton.isEnabled = session.supportsEqualizer
        /// Preamp and band gains match the ordered slider array.
        let values = [session.equalizer.preamp] + session.equalizer.gains
        /// Each native slider retains its bounded decibel value even while bypassed.
        for (index, slider) in sliders.enumerated() {
            slider.isEnabled = session.supportsEqualizer
            if slider.cell?.isHighlighted != true { slider.doubleValue = Double(values[index]) }
            gainLabels[index].stringValue = String(format: "%+.1f", values[index])
            slider.toolTip = String(format: "%+.1f dB", values[index])
        }
        /// Exact original curves resolve back to their preset names; any edited curve is Custom.
        let matching = EqualizerPreset.allCases.first { preset in
            preset.preamp == session.equalizer.preamp && preset.gains == session.equalizer.gains
        }
        presets.selectItem(withTitle: matching?.rawValue ?? "Custom")
        status.stringValue = !session.supportsEqualizer ? "Equalizer unavailable for this audio backend" :
            session.equalizer.isEnabled ? "EQ on · lower preamp for headroom when boosting" : "EQ bypassed · values retained"
    }

    /// Enables or bypasses all EQ processing, retaining the curve for later reactivation.
    @objc private func changeEnabled(_ sender: NSButton) {
        session.setEqualizerEnabled(sender.state == .on); refresh()
    }
    /// Writes a tagged preamp or band slider value in bounded decibels.
    @objc private func changeGain(_ sender: NSSlider) {
        if sender.tag == -1 { session.setEqualizerPreamp(Float(sender.doubleValue)) }
        else { session.setEqualizerGain(Float(sender.doubleValue), at: sender.tag) }
        refresh()
    }
    /// Applies a named original preset; the non-actionable Custom row leaves the curve alone.
    @objc private func changePreset(_ sender: NSPopUpButton) {
        /// Only a recognized preset name changes values.
        if let title = sender.titleOfSelectedItem, let preset = EqualizerPreset(rawValue: title) {
            session.applyEqualizerPreset(preset)
        }
        refresh()
    }
    /// Resets preamp and every band to zero while retaining enabled or bypassed state.
    @objc private func resetFlat(_ sender: NSButton) { session.applyEqualizerPreset(.flat); refresh() }
}

/// Detachable equalizer available with native layouts and imported Classic skins.
@MainActor final class EqualizerWindowController: NSWindowController, NSWindowDelegate {
    /// Controls that read and write the existing playback session.
    let content: EqualizerView
    /// Receives false on native close; controller uses it to synchronize the main EQ indicator.
    var onVisibilityChange: ((Bool) -> Void)?

    /// Validates artwork before constructing the native window; nil package uses an original backdrop.
    init(package: ClassicSkinPackage?, session: PlaybackSession) throws {
        content = EqualizerView(session: session, style: try ClassicEqualizerStyle(package: package))
        /// Opaque native window with the same fixed-width footprint as the Classic player.
        let window = NSWindow(contentRect: content.bounds, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Ampi — Equalizer"
        window.contentView = content; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.initialFirstResponder = content.enabledButton
    }
    /// Rejects archive construction because the session is required.
    required init?(coder: NSCoder) { fatalError("Use init(package:session:)") }
    /// Hiding the EQ leaves its settings and audio processing untouched.
    func windowWillClose(_ notification: Notification) { onVisibilityChange?(false) }
    /// Exports the actual native controls and background to PNG for fixture inspection.
    func exportPreview(to url: URL) throws {
        content.layoutSubtreeIfNeeded()
        /// Bitmap sized for the actual panel content.
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw ThemeError.invalid("Cannot create the equalizer preview.")
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        /// Encoded panel pixels for visual verification.
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ThemeError.invalid("Cannot encode the equalizer preview.")
        }
        try png.write(to: url)
    }
}
