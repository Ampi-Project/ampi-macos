// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Supplies imported row selection colors while leaving table accessibility and navigation native.
@MainActor private final class ClassicPlaylistRow: NSTableRowView {
    /// Imported or original fallback background of a selected queue row.
    let selectedColor: NSColor
    /// Constructs one native row using the validated palette.
    init(selectedColor: NSColor) { self.selectedColor = selectedColor; super.init(frame: .zero) }
    /// Rejects construction without the validated row palette.
    required init?(coder: NSCoder) { fatalError("Use init(selectedColor:)") }
    /// Paints the browse selection; the loaded-track indicator is supplied independently by its text cell.
    override func drawSelection(in dirtyRect: NSRect) { selectedColor.setFill(); bounds.fill() }
}

/// Fixed-size Classic playlist with skin borders and a native, Unicode-capable queue and toolbar.
@MainActor final class ClassicPlaylistView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    /// Shared queue and playback state; the view never replaces the session observer.
    let session: PlaybackSession
    /// Checked border artwork, palette, and compatibility report.
    let style: ClassicPlaylistStyle
    /// Receives common transport commands from toolbar buttons.
    var onAction: ((String) -> Void)?
    /// Receives a queue index for double-click, Return, or Play Selected.
    var onPlay: ((Int) -> Void)?
    /// Receives local dropped files for the common skin/audio importer.
    var onDrop: (([URL]) -> Void)?
    /// Native queue used by visible interaction and regression checks.
    let table: EditableQueueTable
    /// Native scroll container; the scrollbar is explicitly not a legacy sprite implementation.
    private let scroll = NSScrollView()
    /// Toolbar buttons keyed by common command, including Play Selected.
    private(set) var buttons: [String: SkinButton] = [:]
    /// Empty-state text displayed only when the queue has no entries.
    private let empty = NSTextField(labelWithString: "Open or drop audio files to build your playlist.")
    /// Counts queue entries without pretending their durations have already been decoded.
    private let countLabel = NSTextField(labelWithString: "0 tracks")
    /// Last rendered queue identities, preventing table reloads on timer ticks.
    private var renderedIDs: [UUID] = []
    /// Last loaded track identity, independent of the user's browsed row.
    private var renderedTrack: UUID?
    /// Derived tag revision updates row labels while preserving the user's browsed identity.
    private var renderedMetadata: UInt = 0
    /// Skin destinations use top-left Classic coordinates.
    override var isFlipped: Bool { true }

    /// Configures fixed 2× geometry, native queue behavior, labelled transport, and file drops.
    init(session: PlaybackSession, style: ClassicPlaylistStyle) {
        self.session = session; self.style = style
        table = EditableQueueTable(session: session)
        super.init(frame: NSRect(x: 0, y: 0, width: 550, height: 464))
        registerForDraggedTypes([.fileURL])
        scroll.frame = NSRect(x: 24, y: 40, width: 486, height: 348)
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .legacy
        scroll.drawsBackground = true; scroll.backgroundColor = style.background
        // Native scrollbar appearance follows the imported background instead of inserting a bright track into dark artwork.
        scroll.appearance = NSAppearance(named: style.background.redComponent + style.background.greenComponent +
            style.background.blueComponent < 1.5 ? .darkAqua : .aqua)
        /// Single native column filling the visible queue; filenames are truncated visually, accessible in full.
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("classic.track"))
        column.width = scroll.contentSize.width
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.rowHeight = 24; table.intercellSpacing = .zero
        table.backgroundColor = style.background
        table.allowsMultipleSelection = false; table.allowsEmptySelection = true
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(doubleClick(_:))
        table.setAccessibilityLabel("Classic playback queue")
        /// Keyboard index is forwarded through the same activation path as a double-click.
        table.onPlay = { [weak self] index in self?.onPlay?(index) }
        scroll.documentView = table
        addSubview(scroll)
        empty.frame = NSRect(x: 40, y: 90, width: 454, height: 40)
        empty.font = .systemFont(ofSize: 12); empty.textColor = style.normal
        empty.maximumNumberOfLines = 2
        addSubview(empty)
        countLabel.frame = NSRect(x: 28, y: 394, width: 214, height: 18)
        countLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = style.normal
        countLabel.setAccessibilityLabel("Playlist track count")
        addSubview(countLabel)
        /// Toolbar command, visible label, and width in logical points.
        let commands: [(String, String, CGFloat)] = [("open", "Add…", 52), ("selected", "Play Selected", 106),
            ("previous", "Prev", 54), ("play", "Play", 52), ("pause", "Pause", 56), ("stop", "Stop", 52), ("next", "Next", 54)]
        /// Horizontal cursor keeping all native toolbar hit regions inside the bottom frame.
        var x: CGFloat = 28
        /// Every command uses a native button, independent of unimplemented historical toolbar sprites.
        for (command, label, width) in commands {
            /// Palette-matched original control using the retained-font renderer.
            let button = SkinButton(frame: NSRect(x: x, y: 419, width: width, height: 28))
            button.title = label; button.actionName = command
            button.fill = style.background; button.ink = style.normal
            button.target = self; button.action = #selector(activate(_:))
            button.setAccessibilityLabel(command == "selected" ? "Play selected playlist track" : label)
            addSubview(button); buttons[command] = button
            x += width + 4
        }
        /// Compact native editing row keeps the fixed historical panel dimensions unchanged.
        let edits: [(QueueEditAction, String, CGFloat)] = [(.remove, "Remove", 70), (.moveUp, "Up", 54),
            (.moveDown, "Down", 58), (.clear, "Clear", 62)]
        x = 250
        /// Each edit uses the same table method as its context menu and keyboard handler.
        for (edit, label, width) in edits {
            /// Palette-matched editing control with a full spoken action name.
            let button = SkinButton(frame: NSRect(x: x, y: 390, width: width, height: 24))
            button.title = label; button.actionName = edit.rawValue
            button.fill = style.background; button.ink = style.normal
            button.target = self; button.action = #selector(activate(_:))
            button.setAccessibilityLabel(edit.title); button.toolTip = edit.title
            addSubview(button); buttons[edit.rawValue] = button
            x += width + 4
        }
        refresh()
    }

    /// Rejects construction without a playback session and checked border/palette profile.
    required init?(coder: NSCoder) { fatalError("Use init(session:style:)") }

    /// Converts Classic source-pixel geometry into fixed 2× logical points.
    private func scaled(_ rect: NSRect) -> NSRect {
        NSRect(x: rect.minX * 2, y: rect.minY * 2, width: rect.width * 2, height: rect.height * 2)
    }

    /// Repeats an original sprite without stretching individual pixels; clips the final partial tile.
    private func tile(_ image: NSImage, in rect: NSRect, vertically: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        rect.clip()
        /// Cursor along the chosen tiling axis, measured in logical points.
        var cursor = vertically ? rect.minY : rect.minX
        /// Positive source dimension checked by the importer and crop validation.
        let increment = (vertically ? image.size.height : image.size.width) * 2
        while cursor < (vertically ? rect.maxY : rect.maxX) {
            drawClassicSprite(image, in: NSRect(x: vertically ? rect.minX : cursor,
                y: vertically ? cursor : rect.minY, width: image.size.width * 2, height: image.size.height * 2))
            cursor += increment
        }
    }

    /// Composes active/inactive borders while keeping the queue and toolbar genuinely interactive.
    override func draw(_ dirtyRect: NSRect) {
        style.background.setFill(); bounds.fill()
        if !style.borders.isEmpty {
            /// Native focus chooses the corresponding imported title-strip state.
            let title = style.titles[window?.isKeyWindow == true ? 0 : 1]
            tile(title[1], in: scaled(NSRect(x: 25, y: 0, width: 225, height: 20)), vertically: false)
            drawClassicSprite(title[0], in: scaled(NSRect(x: 0, y: 0, width: 25, height: 20)))
            drawClassicSprite(title[2], in: scaled(NSRect(x: 88, y: 0, width: 100, height: 20)))
            drawClassicSprite(title[3], in: scaled(NSRect(x: 250, y: 0, width: 25, height: 20)))
            tile(style.borders[0], in: scaled(NSRect(x: 0, y: 20, width: 12, height: 174)), vertically: true)
            tile(style.borders[1], in: scaled(NSRect(x: 255, y: 20, width: 20, height: 174)), vertically: true)
            drawClassicSprite(style.borders[2], in: scaled(NSRect(x: 0, y: 194, width: 125, height: 38)))
            drawClassicSprite(style.borders[3], in: scaled(NSRect(x: 125, y: 194, width: 150, height: 38)))
        } else {
            style.current.withAlphaComponent(0.35).setStroke()
            NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).stroke()
        }
        // Original native toolbar obscures unsupported legacy menu graphics rather than exposing dead buttons.
        style.background.setFill()
        NSRect(x: 24, y: 390, width: 502, height: 60).fill()
    }

    /// Refreshes rows on identity/current-track/tag changes, preserving browsing on asynchronous tag arrival.
    func refresh() {
        /// Stable identities preserve browse selection across appends, removals, and reordering, including duplicate URLs.
        let ids = session.tracks.map(\.id)
        /// Loaded-track changes update its marker and reveal the new current row.
        let changedTrack = renderedTrack != session.currentTrack?.id
        if ids != renderedIDs || changedTrack || renderedMetadata != session.metadataRevision {
            /// Browsed queue identity retained when editing without changing the loaded track.
            let browsed = renderedIDs.indices.contains(table.selectedRow) ? renderedIDs[table.selectedRow] : nil
            table.reloadData()
            /// Desired row follows transport changes; otherwise it preserves the user's browse selection.
            let selection = changedTrack ? session.selectedIndex : browsed.flatMap { ids.firstIndex(of: $0) }
            /// Valid selection applied after reloading; otherwise the empty queue remains unselected.
            if let selection { table.selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false) }
            else { table.deselectAll(nil) }
            /// Transport-selected row is scrolled into view, but timer ticks and append operations do not jump.
            if changedTrack, let index = session.selectedIndex { table.scrollRowToVisible(index) }
            renderedIDs = ids; renderedTrack = session.currentTrack?.id
            renderedMetadata = session.metadataRevision
        }
        empty.isHidden = !session.tracks.isEmpty
        countLabel.stringValue = "\(session.tracks.count) track\(session.tracks.count == 1 ? "" : "s") · \(session.state.rawValue.capitalized)"
        buttons["selected"]?.isEnabled = session.tracks.indices.contains(table.selectedRow)
        updateEditButtons()
        needsDisplay = true
    }

    /// Returns the current editable queue length to the native table.
    func numberOfRows(in tableView: NSTableView) -> Int { session.tracks.count }

    /// Creates a Unicode-capable row title with a loaded-track marker separate from the browse highlight.
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard session.tracks.indices.contains(row) else { return nil }
        /// Queue entry whose identity, filename, and playback status determine the visible row.
        let track = session.tracks[row]
        /// Loaded track receives a visible triangle; browsing another row does not change playback.
        let loaded = track.id == session.currentTrack?.id
        /// Original native text field; no limited bitmap font is used for Unicode filenames.
        let label = NSTextField(labelWithString: "\(loaded ? "▶" : " ") \(row + 1). \(session.displayTitle(for: track))")
        label.font = .monospacedSystemFont(ofSize: 12, weight: loaded ? .semibold : .regular)
        label.textColor = loaded ? style.current : style.normal
        label.lineBreakMode = .byTruncatingTail
        label.cell?.baseWritingDirection = .leftToRight
        label.setAccessibilityLabel("\(row + 1). \(session.displayTitle(for: track))\(loaded ? ", current track" : "")")
        label.toolTip = session.trackDescription(for: track)
        label.frame = NSRect(x: 5, y: 3, width: max(20, tableColumn?.width ?? 400) - 10, height: 18)
        label.autoresizingMask = [.width]
        /// Native row container retains the field while AppKit handles scrolling and selection.
        let cell = NSTableCellView()
        cell.addSubview(label); cell.textField = label
        return cell
    }

    /// Supplies the imported browse-selection fill to each native table row.
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ClassicPlaylistRow(selectedColor: style.selected)
    }

    /// Updates Play Selected availability when the user browses without starting playback.
    func tableViewSelectionDidChange(_ notification: Notification) {
        buttons["selected"]?.isEnabled = session.tracks.indices.contains(table.selectedRow)
        updateEditButtons()
    }

    /// Keeps editing buttons disabled for missing rows, empty queues, and movement beyond the queue ends.
    private func updateEditButtons() {
        /// Every typed action shares the table's dynamic selection and bounds checks.
        for edit in QueueEditAction.allCases { buttons[edit.rawValue]?.isEnabled = table.canEdit(edit) }
    }

    /// Double-click activates only a real clicked row; double-clicking empty space does nothing.
    @objc private func doubleClick(_ sender: NSTableView) {
        guard session.tracks.indices.contains(sender.clickedRow) else { return }
        onPlay?(sender.clickedRow)
    }

    /// Forwards native transport commands or plays the currently highlighted queue entry.
    @objc private func activate(_ sender: SkinButton) {
        if sender.actionName == "selected" {
            guard session.tracks.indices.contains(table.selectedRow) else { return }
            onPlay?(table.selectedRow)
            return
        }
        /// Recognized edit is dispatched locally; transport/file actions still use the shared controller.
        if let edit = QueueEditAction(rawValue: sender.actionName) { table.performEdit(edit) }
        else { onAction?(sender.actionName) }
    }

    /// Advertises local file drops anywhere over the playlist's native content.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    /// Forwards local file URLs to the common importer without trying to decode them as music here.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        /// Local file URLs read through the same pasteboard profile as the main player.
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls); return true
    }
}

/// Retains a detachable Classic playlist without owning another playback session, observer, or timer.
@MainActor final class ClassicPlaylistWindowController: NSWindowController, NSWindowDelegate {
    /// Shared-session queue surface and native input controls.
    let content: ClassicPlaylistView
    /// Receives false when its close button hides the playlist; playback is unaffected.
    var onVisibilityChange: ((Bool) -> Void)?

    /// Validates borders/colors before constructing a fixed-size native playlist window.
    /// - Throws: Optional-present sprite validation errors, preserving the previously active skin.
    init(package: ClassicSkinPackage, session: PlaybackSession) throws {
        content = ClassicPlaylistView(session: session, style: try ClassicPlaylistStyle(package: package))
        /// Native title bar provides supported move/close/minimize behavior independently of legacy artwork.
        let window = NSWindow(contentRect: content.bounds, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Ampi Playlist — \(package.name)"
        window.contentView = content; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.initialFirstResponder = content.table
    }

    /// Rejects construction without a validated package and shared session.
    required init?(coder: NSCoder) { fatalError("Use init(package:session:)") }

    /// Announces closing only; selection, output, queue, and window controller remain reusable.
    func windowWillClose(_ notification: Notification) { onVisibilityChange?(false) }

    /// Refreshes the title's active/inactive bitmap state on native focus changes.
    func windowDidBecomeKey(_ notification: Notification) { content.needsDisplay = true }

    /// Refreshes the title strip after the main player or another application becomes key.
    func windowDidResignKey(_ notification: Notification) { content.needsDisplay = true }

    /// Exports the actual playlist renderer to a PNG for visual checks.
    /// - Throws: Bitmap creation, encoding, or file-write errors.
    func exportPreview(to url: URL) throws {
        content.layoutSubtreeIfNeeded()
        /// Native bitmap context covering the composed border, queue, and transport controls.
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { throw ThemeError.invalid("Cannot render the playlist preview.") }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        /// Portable PNG encoding of the same content shown to the user.
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw ThemeError.invalid("Cannot encode the playlist preview.") }
        try png.write(to: url)
    }
}
