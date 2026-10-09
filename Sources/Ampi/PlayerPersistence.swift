// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AmpiCore

/// Off-thread restore preparation retains only readable regular audio files and rechecks Classic input.
private struct PreparedRestoration: Sendable {
    /// Pruned durable values whose selected identity remains valid or becomes nil.
    let saved: SavedSession
    /// Parsed Classic assets, still subject to main/playlist/EQ rendering checks on the main actor.
    let classic: ClassicSkinPackage?
    /// Nonfatal unavailable-file/skin notices presented after all successful state has restored.
    let notices: [String]

    /// Performs local filesystem work off the main actor; URL/queue rules were validated by the store.
    static func prepare(_ saved: SavedSession) -> PreparedRestoration {
        /// Filter by actual file type and readability while preserving duplicate identities and visible order.
        let available = saved.tracks.filter { track in
            FileManager.default.isReadableFile(atPath: track.url.path) &&
                (try? track.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
        /// Missing/offline/unreadable entries are skipped; their source files are never modified.
        let missing = saved.tracks.count - available.count
        /// Combined messages explain partial recovery without opening a series of startup alerts.
        var notices: [String] = []
        if missing > 0 { notices.append("\(missing) saved queue \(missing == 1 ? "entry was" : "entries were") unavailable and skipped.") }
        /// Optional Classic import is bounded by the same ZIP/folder parser used for interactive import.
        var classic: ClassicSkinPackage?
        /// Saved source is local and optional; an in-memory source cannot be reconstructed after restart.
        if case .classic(let url) = saved.skin {
            if let url { classic = try? ClassicSkinPackage.load(url) }
            if classic == nil { notices.append("The saved Classic skin was unavailable. The default layout was restored.") }
        }
        return PreparedRestoration(saved: saved.retainingTracks(available), classic: classic, notices: notices)
    }
}

/// Coordinates stopped startup recovery, debounced actor-serialized saves, and a final awaited quit save.
@MainActor final class PlayerPersistence {
    /// Player retained by the host; its weak observer avoids a controller/persistence reference cycle.
    private let controller: PlayerWindowController
    /// Serial background file store; tests supply isolated temporary paths.
    let store: SessionStateStore
    /// Pending 400-ms save delay, canceled/coalesced as edits and continuous sliders emit changes.
    private var pendingSave: Task<Void, Never>?
    /// Prevents delayed observer writes after a final termination snapshot has been requested.
    private var isStopping = false
    /// Prevents reporting a save failure from recursively scheduling that same failure.
    private var reportingFailure = false

    /// Retains a player and storage actor; startup restore precedes attaching the save observer.
    init(controller: PlayerWindowController, store: SessionStateStore) {
        self.controller = controller; self.store = store
    }

    /// Restores valid state without output, falling back independently for missing audio or invalid skin artwork.
    /// Returns combined recovery notices; first launch returns none. No startup diagnostic is written to disk here.
    func restore() async -> [String] {
        do {
            /// Nil means there has never been a saved session at this storage location.
            guard let saved = try await store.load() else { return [] }
            /// File probes/decompression must not block native controls or the main run loop.
            let prepared = await Task.detached(priority: .userInitiated) { PreparedRestoration.prepare(saved) }.value
            /// Valid queue/settings still restore if the selected decoder or presentation needs a fallback.
            var notices = prepared.notices
            /// Decoder failure clears selection while leaving the remaining restored queue/settings available.
            if let diagnostic = try controller.session.restore(prepared.saved) { notices.append(diagnostic) }
            do {
                /// Associated layout/source determines whether to validate native geometry or all Classic panels.
                switch saved.skin {
                case .native(let theme): try controller.apply(theme)
                case .classic:
                    /// Structural parsing succeeded, but renderer-specific sprite checks can still reject activation.
                    if let classic = prepared.classic { try controller.applyClassic(classic) }
                }
            } catch { notices.append("The saved skin could not be used. The default layout was restored.") }
            return notices
        } catch { return ["The saved session could not be read. Default layout and settings are in use."] }
    }

    /// Attaches the weak durable-change observer after restore and begins saving subsequent changes.
    func startSaving() {
        controller.onPersistentChange = { [weak self] in self?.scheduleSave() }
    }

    /// Coalesces rapid controls/edits; actor byte comparison avoids writes for unchanged durable values.
    private func scheduleSave() {
        guard !isStopping, !reportingFailure else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                /// Available owner captures the latest state only after the input burst settles.
                guard let self else { return }
                try await self.store.save(self.controller.session.savedState(skin: self.controller.savedSkin))
            } catch is CancellationError {
                // A newer edit or final quit snapshot supersedes this delayed save.
            } catch {
                /// A live owner reports failure once without causing a new save from its own status notification.
                guard let self, !self.isStopping else { return }
                self.reportingFailure = true
                self.controller.session.report(ThemeError.invalid("Session changes could not be saved. Check storage access before quitting."))
                self.reportingFailure = false
            }
        }
    }

    /// Cancels delayed input work and awaits the final snapshot after all older actor writes; errors propagate to Quit UI.
    func flush() async throws {
        isStopping = true; pendingSave?.cancel(); pendingSave = nil
        try await store.save(controller.session.savedState(skin: controller.savedSkin), force: true)
    }

    /// Resumes debounced observation when a failed Quit is canceled, retaining the current in-memory session.
    func resumeSaving() { isStopping = false; scheduleSave() }
}
