// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Queue edits shared by native menus, Classic buttons, table context menus, and focused keyboard input.
enum QueueEditAction: String, CaseIterable {
    /// Removes the highlighted entry without deleting its local audio file.
    case remove
    /// Moves the highlighted entry one position toward the beginning.
    case moveUp
    /// Moves the highlighted entry one position toward the end.
    case moveDown
    /// Stops playback and removes every queue entry, retaining volume and EQ.
    case clear

    /// Visible menu label describing the edit and its scope.
    var title: String {
        switch self {
        case .remove: return "Remove Selected Track"
        case .moveUp: return "Move Selected Up"
        case .moveDown: return "Move Selected Down"
        case .clear: return "Clear Queue"
        }
    }
}

/// Native single-selection table with consistent browsing, activation, and queue-edit input across skins.
@MainActor final class EditableQueueTable: NSTableView, NSMenuItemValidation {
    /// Existing playback session, never replaced when entries are edited.
    let session: PlaybackSession
    /// Receives a valid highlighted index when Return/keypad Enter requests playback.
    var onPlay: ((Int) -> Void)?
    /// Right-clicked entry identity keeps a context command stable if playback advances while the menu is open.
    private var contextIdentity: UUID?

    /// Connects a shared model and supplies native contextual editing commands.
    init(session: PlaybackSession) {
        self.session = session
        super.init(frame: .zero)
        allowsMultipleSelection = false; allowsEmptySelection = true
        /// Context menu operates on the clicked row, independently of the currently loaded entry.
        let context = NSMenu(title: "Queue")
        /// Each item dispatches one typed queue action and uses dynamic bounds validation.
        for action in QueueEditAction.allCases {
            /// Native menu item carries its action string without exposing implementation details to users.
            let item = NSMenuItem(title: action.title, action: #selector(contextEdit(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = action.rawValue
            context.addItem(item)
        }
        menu = context
    }

    /// Rejects construction without a playback session.
    required init?(coder: NSCoder) { fatalError("Use init(session:)") }

    /// Reports edit availability from current bounds; moving at the first/last row is disabled.
    func canEdit(_ action: QueueEditAction) -> Bool {
        canEdit(action, at: selectedRow)
    }

    /// Checks a resolved row independently of highlight changes during context-menu tracking.
    private func canEdit(_ action: QueueEditAction, at row: Int) -> Bool {
        if action == .clear { return !session.tracks.isEmpty }
        guard session.tracks.indices.contains(row) else { return false }
        switch action {
        case .remove: return true
        case .moveUp: return row > 0
        case .moveDown: return row + 1 < session.tracks.count
        case .clear: return true
        }
    }

    /// Applies an available edit; removal highlights the following row (or the preceding row at the end).
    /// Model observers reload both presentations synchronously; this method also refreshes a standalone table.
    func performEdit(_ action: QueueEditAction) {
        guard canEdit(action) else { return }
        /// Original browse index determines the removal fallback and move destination.
        let row = selectedRow
        /// Browsed identity follows a moved entry even if its filename is duplicated elsewhere.
        let identity = session.tracks.indices.contains(row) ? session.tracks[row].id : nil
        switch action {
        case .remove: session.removeTrack(at: row)
        case .moveUp: session.moveTrack(from: row, to: row - 1)
        case .moveDown: session.moveTrack(from: row, to: row + 1)
        case .clear: session.clearQueue()
        }
        reloadData()
        /// Target browse row stays meaningful after removing or moving the selected entry.
        let selection = action == .remove ? (session.tracks.isEmpty ? nil : min(row, session.tracks.count - 1)) :
            identity.flatMap { id in session.tracks.firstIndex { $0.id == id } }
        /// Selection changes never start playback; only explicit activation does that.
        if let selection { selectRowIndexes(IndexSet(integer: selection), byExtendingSelection: false); scrollRowToVisible(selection) }
        else { deselectAll(nil) }
    }

    /// Handles Return, plain Delete/backspace, and Option-Up/Down only while this queue owns focus.
    override func keyDown(with event: NSEvent) {
        /// Command/control modifiers retain native handling; Option is reserved for row movement.
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if (event.keyCode == 36 || event.keyCode == 76), modifiers.isEmpty,
           session.tracks.indices.contains(selectedRow) { onPlay?(selectedRow) }
        else if (event.keyCode == 51 || event.keyCode == 117), modifiers.isEmpty { performEdit(.remove) }
        else if event.keyCode == 126, modifiers == [.option] { performEdit(.moveUp) }
        else if event.keyCode == 125, modifiers == [.option] { performEdit(.moveDown) }
        else { super.keyDown(with: event) }
    }

    /// Selects the right-clicked row before opening its menu; empty space exposes only Clear Queue.
    override func menu(for event: NSEvent) -> NSMenu? {
        /// Native pointer location converted to this table's content coordinates.
        let point = convert(event.locationInWindow, from: nil)
        /// Actual clicked row, or minus one below the queue.
        let row = row(at: point)
        contextIdentity = session.tracks.indices.contains(row) ? session.tracks[row].id : nil
        if session.tracks.indices.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else { deselectAll(nil) }
        return menu
    }

    /// Keeps context-menu availability synchronized with selection and queue bounds.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        /// Only recognized action payloads can mutate the model.
        guard let value = menuItem.representedObject as? String, let action = QueueEditAction(rawValue: value) else { return false }
        return canEdit(action, at: contextRow)
    }

    /// Current index of the right-clicked UUID; removal elsewhere disables its pending row commands.
    private var contextRow: Int {
        contextIdentity.flatMap { id in session.tracks.firstIndex { $0.id == id } } ?? -1
    }

    /// Dispatches a recognized contextual command using the same path as buttons and keyboard input.
    @objc private func contextEdit(_ sender: NSMenuItem) {
        /// Valid action strings originate in the fixed native menu built above.
        guard let value = sender.representedObject as? String, let action = QueueEditAction(rawValue: value) else { return }
        /// Resolve the clicked identity again because transport/queue callbacks may have changed the highlight.
        let row = contextRow
        guard canEdit(action, at: row) else { return }
        if action != .clear { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        performEdit(action)
    }
}
