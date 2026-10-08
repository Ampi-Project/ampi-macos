// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

extension NSColor {
    /// Converts a validated `#RRGGBB` palette entry into opaque sRGB; bad digits fall back to black.
    convenience init(hex: String) {
        /// Packed RGB components extracted from the hexadecimal digits after the prefix.
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 255) / 255,
                  green: CGFloat((value >> 8) & 255) / 255,
                  blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

/// Native actionable button with palette-based drawing and a visible keyboard focus ring.
@MainActor final class SkinButton: NSButton {
    /// Validated theme action forwarded to the window controller on activation.
    var actionName = ""
    /// Normal button fill; the highlighted state blends this color with the foreground.
    var fill = NSColor.controlColor
    /// Text, outline, and keyboard-focus color.
    var ink = NSColor.labelColor
    /// Rounded corner radius in logical points.
    var radius: CGFloat = 3
    /// Retained font shared by title measurement and drawing for this button's lifetime.
    private let titleFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    /// Draws the themed fill, centered title, outline, and current keyboard-focus indicator.
    /// - Parameter dirtyRect: AppKit invalidation region; the button redraws its full bounds.
    override func draw(_ dirtyRect: NSRect) {
        (isHighlighted ? fill.blended(withFraction: 0.18, of: ink) ?? fill : fill).setFill()
        /// Inset outline path that keeps its stroke inside the button bounds.
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        shape.fill()
        ink.withAlphaComponent(0.4).setStroke()
        shape.stroke()
        /// Cocoa-owned title whose attributes avoid a lazily bridged Swift dictionary in Core Text.
        let renderedTitle = NSMutableAttributedString(string: title)
        /// Full UTF-16 range to which the button's concrete font and color are applied.
        let titleRange = NSRange(location: 0, length: renderedTitle.length)
        renderedTitle.addAttribute(.font, value: titleFont, range: titleRange)
        renderedTitle.addAttribute(.foregroundColor, value: ink, range: titleRange)
        /// Measured title size used to center its baseline box inside the control.
        let size = renderedTitle.size()
        renderedTitle.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                      y: (bounds.height - size.height) / 2))
        if window?.firstResponder === self {
            ink.setStroke()
            /// Inset ring distinguishing the button that currently receives keyboard input.
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: radius, yRadius: radius)
            focus.lineWidth = 2
            focus.stroke()
        }
    }
}

/// Queue table that lets Return or keypad Enter play the selected row.
@MainActor private final class QueueTable: NSTableView {
    /// Main-actor activation callback receiving the selected zero-based queue index.
    var onKeyboardActivate: ((Int) -> Void)?
    /// Activates a selection on Enter and delegates other keyboard handling to AppKit.
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), selectedRow >= 0 {
            onKeyboardActivate?(selectedRow)
        } else { super.keyDown(with: event) }
    }
}

/// Renders a validated declarative layout using native controls bound to one session.
@MainActor final class SkinView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    /// Validated layout and palette used throughout this surface's lifetime.
    let theme: Theme
    /// Persistent queue and transport model observed by the surface's controls.
    let session: PlaybackSession
    /// Main-actor callback forwarding a supported button action to the controller.
    var onAction: ((String) -> Void)?
    /// Main-actor callback delivering local file URLs accepted by drag-and-drop.
    var onDrop: (([URL]) -> Void)?
    /// Binding-name/text-field pairs refreshed from the session.
    private var labels: [(String, NSTextField)] = []
    /// Binding-name/slider pairs tracking playback offset and output gain.
    private var sliders: [(String, NSSlider)] = []
    /// Original-title/button pairs used to switch Play to Pause without losing theme casing.
    private var playButtons: [(String, SkinButton)] = []
    /// Optional queue control; a layout can omit it or supply exactly one.
    private var queueTable: NSTableView?
    /// Queue hint shown only while the session has no tracks.
    private var emptyLabel: NSTextField?
    /// Queue identities from the last table reload, avoiding reloads on every timer tick.
    private var queueIDs: [UUID] = []
    /// Selection from the last table reload, used to detect transport selection changes.
    private var renderedSelection: Int?
    /// Uses top-left coordinates to match the JSON layout's frame convention.
    override var isFlipped: Bool { true }

    /// Builds native controls and drop handling for a previously validated theme.
    /// - Parameters:
    ///   - theme: Layout whose geometry and bindings must already have passed validation.
    ///   - session: Queue and transport model retained across skin replacements.
    init(theme: Theme, session: PlaybackSession) {
        self.theme = theme
        self.session = session
        super.init(frame: NSRect(x: 0, y: 0, width: theme.width, height: theme.height))
        registerForDraggedTypes([.fileURL])
        buildElements()
        refresh()
    }

    /// Rejects archive/storyboard construction because a validated layout and session are required.
    required init?(coder: NSCoder) { fatalError("Use init(theme:session:)") }

    /// Draws the background, track-label panel, and accent strip beneath native controls.
    /// - Parameter dirtyRect: AppKit invalidation region; this prototype redraws the full surface.
    override func draw(_ dirtyRect: NSRect) {
        NSColor(hex: theme.palette.background).setFill()
        bounds.fill()
        /// Track-bound label whose frame determines its decorative background panel.
        for element in theme.elements where element.binding == "track" {
            NSColor(hex: theme.palette.panel).setFill()
            NSBezierPath(roundedRect: rect(element).insetBy(dx: -6, dy: -5),
                         xRadius: theme.cornerRadius, yRadius: theme.cornerRadius).fill()
        }
        NSColor(hex: theme.palette.accent).withAlphaComponent(0.5).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 2).fill()
    }

    /// Converts a validated four-component theme frame into an AppKit rectangle in points.
    private func rect(_ element: Theme.Element) -> NSRect {
        NSRect(x: element.frame[0], y: element.frame[1], width: element.frame[2], height: element.frame[3])
    }

    /// Constructs native controls in layout order and registers dynamic session bindings.
    private func buildElements() {
        /// Validated layout entry used to choose and configure its native control.
        for element in theme.elements {
            switch element.kind {
            case .label:
                /// Single-line label displaying static text or a refreshed session value.
                let label = NSTextField(labelWithString: element.label)
                label.frame = rect(element)
                label.font = .monospacedSystemFont(ofSize: element.fontSize ?? 12,
                                                   weight: element.binding == "track" ? .medium : .regular)
                label.textColor = NSColor(hex: element.binding == "status" ? theme.palette.muted : theme.palette.text)
                label.lineBreakMode = .byTruncatingTail
                label.maximumNumberOfLines = 1
                /// Stable screen-reader names for the supported dynamic text bindings.
                let accessibleLabels = ["track": "Current track", "time": "Playback time", "status": "Player status"]
                label.setAccessibilityLabel(element.binding.flatMap { accessibleLabels[$0] } ?? element.label)
                addSubview(label)
                /// Optional session binding registered for subsequent text refreshes.
                if let binding = element.binding { labels.append((binding, label)) }
            case .button:
                /// Custom-drawn native button dispatching the element's validated action.
                let button = SkinButton(frame: rect(element))
                button.title = element.label
                button.actionName = element.action!
                button.fill = NSColor(hex: element.action == "playPause" ? theme.palette.accent : theme.palette.panel)
                button.ink = NSColor(hex: element.action == "playPause" ? theme.palette.background : theme.palette.text)
                button.radius = theme.cornerRadius
                button.isBordered = false
                button.setButtonType(.momentaryPushIn)
                button.target = self
                button.action = #selector(buttonPressed(_:))
                button.setAccessibilityLabel(accessibleAction(element.action!))
                addSubview(button)
                if element.action == "playPause" { playButtons.append((element.label, button)) }
            case .slider:
                /// Continuous native slider later refreshed with position or volume bounds.
                let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(sliderChanged(_:)))
                slider.frame = rect(element)
                slider.identifier = NSUserInterfaceItemIdentifier(element.binding!)
                slider.isContinuous = true
                slider.controlSize = .small
                slider.setAccessibilityLabel(element.label)
                addSubview(slider)
                sliders.append((element.binding!, slider))
            case .queue:
                buildQueue(element)
            }
        }
    }

    /// Returns a spoken command name for a supported transport/file-opening action.
    private func accessibleAction(_ action: String) -> String {
        switch action {
        case "open": return "Open audio files"
        case "previous": return "Previous track"
        case "next": return "Next track"
        case "stop": return "Stop playback"
        default: return "Play or pause"
        }
    }

    /// Builds the layout's queue, keyboard/double-click activation, and empty-state hint.
    private func buildQueue(_ element: Theme.Element) {
        /// Scroll container using the queue element's geometry and panel background.
        let scroll = NSScrollView(frame: rect(element))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(hex: theme.palette.panel)
        /// Native track table with Return-key activation support.
        let table = QueueTable(frame: NSRect(origin: .zero, size: scroll.bounds.size))
        /// Single track-title column sized to leave room for the scroll container.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        column.width = element.frame[2] - 20
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 28
        table.backgroundColor = NSColor(hex: theme.palette.panel)
        table.selectionHighlightStyle = .regular
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(queueActivated(_:))
        /// Row is the selected zero-based queue index activated with Return or keypad Enter.
        table.onKeyboardActivate = { [weak self] row in
            /// Surface retained only for this activation, avoiding a table callback retain cycle.
            guard let self else { return }
            do { try self.session.play(index: row) } catch { self.session.report(error) }
        }
        table.setAccessibilityLabel(element.label)
        scroll.documentView = table
        addSubview(scroll)
        queueTable = table

        /// Centered file-opening hint displayed over the empty queue region.
        let empty = NSTextField(wrappingLabelWithString: "Drop audio files here\nor use Open (⌘O)")
        empty.frame = rect(element).insetBy(dx: 18, dy: 28)
        empty.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        empty.textColor = NSColor(hex: theme.palette.muted)
        empty.alignment = .center
        addSubview(empty)
        emptyLabel = empty
    }

    /// Synchronizes text, sliders, transport labels, accessibility values, and queue selection.
    /// The table reloads only when queue identities or the selected track change.
    func refresh() {
        /// Session field name and corresponding label to update together.
        for (binding, label) in labels {
            switch binding {
            case "track": label.stringValue = session.currentTrack?.title ?? "No track selected"
            case "time": label.stringValue = "\(clock(session.position)) / \(clock(session.duration))"
            case "status": label.stringValue = session.status
            default: break
            }
            label.setAccessibilityValue(label.stringValue)
        }
        /// Session field name and corresponding continuous slider to update together.
        for (binding, slider) in sliders {
            if binding == "position" {
                slider.maxValue = max(1, session.duration)
                slider.doubleValue = session.position
                slider.isEnabled = session.currentTrack != nil && session.duration > 0
            } else { slider.doubleValue = Double(session.volume) }
        }
        /// Theme's original Play title and its button, used to preserve title casing.
        for (original, button) in playButtons {
            /// Whether the original title uses all capitals, controlling the Pause label's casing.
            let uppercase = original == original.uppercased()
            button.title = session.state == .playing ? (uppercase ? "PAUSE" : "Pause") : original
            button.setAccessibilityLabel(session.state == .playing ? "Pause playback" : "Play playback")
            button.needsDisplay = true
        }
        /// Current queue identities compared with the last rendered table contents.
        let ids = session.tracks.map(\.id)
        if ids != queueIDs || renderedSelection != session.selectedIndex {
            queueIDs = ids
            renderedSelection = session.selectedIndex
            queueTable?.reloadData()
            /// Loaded track index mirrored into the table selection after reloading.
            if let selection = session.selectedIndex {
                queueTable?.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false)
            }
        }
        emptyLabel?.isHidden = !session.tracks.isEmpty
    }

    /// Formats elapsed seconds as minutes and seconds, safely bounding non-finite/huge inputs.
    private func clock(_ seconds: Double) -> String {
        /// Nonnegative whole seconds capped before integer conversion to avoid overflow.
        let value = seconds.isFinite ? Int(min(max(0, seconds), 86_400_000)) : 0
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    /// Forwards a native button activation using the sender's validated theme action.
    @objc private func buttonPressed(_ sender: SkinButton) { onAction?(sender.actionName) }

    /// Seeks or adjusts gain according to the sender's session-binding identifier.
    @objc private func sliderChanged(_ sender: NSSlider) {
        if sender.identifier?.rawValue == "position" { session.seek(to: sender.doubleValue) }
        else { session.setVolume(Float(sender.doubleValue)) }
    }

    /// Plays the double-clicked row, falling back to selection, and reports loading failures.
    @objc private func queueActivated(_ sender: NSTableView) {
        /// Activated zero-based queue index, or a negative value when there is no selection.
        let row = sender.clickedRow >= 0 ? sender.clickedRow : sender.selectedRow
        guard row >= 0 else { return }
        do { try session.play(index: row) } catch { session.report(error) }
    }

    /// Supplies the current queue length to AppKit's table data source.
    func numberOfRows(in tableView: NSTableView) -> Int { session.tracks.count }

    /// Creates a numbered track-title cell with selection-aware palette coloring.
    /// - Parameters:
    ///   - tableView: Queue table requesting its visible row content.
    ///   - tableColumn: Column whose width determines the text field's available space.
    ///   - row: Valid zero-based index provided by AppKit's data-source callbacks.
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        /// Truncating track title with a one-based display number and accessible file title.
        let label = NSTextField(labelWithString: String(format: "%02d  ", row + 1) + session.tracks[row].title)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor(hex: row == session.selectedIndex ? theme.palette.accent : theme.palette.text)
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityLabel(session.tracks[row].title)
        /// Native row container retaining the track text field.
        let cell = NSTableCellView()
        cell.addSubview(label)
        label.frame = NSRect(x: 8, y: 4, width: max(20, tableColumn?.width ?? 200) - 16, height: 20)
        label.autoresizingMask = [.width]
        cell.textField = label
        return cell
    }

    /// Advertises a copy operation for file-URL drags registered by this surface.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    /// Extracts local file URLs, forwards accepted drops, and rejects empty/non-file payloads.
    /// - Returns: True when at least one file URL was delivered to the drop callback.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        /// Local file URLs read from the drag pasteboard, excluding remote URL payloads.
        guard let objects = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !objects.isEmpty else { return false }
        onDrop?(objects)
        return true
    }
}
