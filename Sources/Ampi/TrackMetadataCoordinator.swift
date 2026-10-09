// SPDX-License-Identifier: GPL-3.0-only
import AmpiCore
import Foundation

/// Prioritizes the loaded entry and first queued entries, with two workers and at most 64 cached results.
@MainActor final class TrackMetadataCoordinator {
    /// Session receives rendering-only results keyed by original identity rather than mutable row indices.
    private let session: PlaybackSession
    /// Sendable background reader returns empty tags on failure; injectable for deterministic cancellation/race checks.
    private let read: @Sendable (URL) async -> TrackMetadata
    /// Current bounded queue snapshot; selecting an entry beyond the first 64 moves it to the front of this set.
    private var targets: [Track] = []
    /// Attempted identities avoid retrying corrupt/untagged files on transport and timer refreshes.
    private var attempted = Set<UUID>()
    /// Active identities and cancellation tasks; no task is created for every entry in a large queue.
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Per-job tokens reject an older cancelled completion if the same identity is targeted again.
    private var tokens: [UUID: UUID] = [:]
    /// Closing the primary window prevents further background publication or scheduling.
    private var isClosed = false

    /// Attaches a reader without replacing the session's render/persistence observers or starting playback.
    init(session: PlaybackSession, read: @escaping @Sendable (URL) async -> TrackMetadata = TrackMetadataReader.read) {
        self.session = session; self.read = read
    }

    /// Reconciles live identities after queue/transport changes, preserving active jobs for surviving entries.
    func synchronize() {
        guard !isClosed else { return }
        targets = session.currentTrack.map { [$0] } ?? []
        /// Loaded identity is captured once; each filter input is a live ordered queue entry.
        let selected = session.currentTrack?.id
        targets.append(contentsOf: session.tracks.lazy.filter { $0.id != selected }
            .prefix(PlaybackSession.maximumMetadataEntries - targets.count))
        /// Current target identities bound cached results and pending work, including duplicate files as distinct entries.
        let identities = Set(targets.map(\.id))
        /// Removed/evicted job cancellation prevents its eventual value from populating another queue entry.
        for identity in Array(tasks.keys) where !identities.contains(identity) {
            tasks.removeValue(forKey: identity)?.cancel(); tokens.removeValue(forKey: identity)
        }
        attempted.formIntersection(identities)
        session.retainMetadata(for: identities)
        startPending()
    }

    /// Cancels active loads and stops this coordinator permanently when its primary player closes.
    func cancel() {
        isClosed = true
        /// Every pending outer task forwards cancellation to its detached native reader operation.
        for task in tasks.values { task.cancel() }
        tasks.removeAll(); tokens.removeAll(); targets.removeAll(); attempted.removeAll()
    }

    /// Starts at most two eligible jobs; result callbacks fill freed slots without reloading or playing audio.
    private func startPending() {
        /// Ordered target prioritizes selected metadata ahead of the first visible queue entries.
        for track in targets where !attempted.contains(track.id) {
            guard tasks.count < 2 else { break }
            attempted.insert(track.id)
            /// Unique job token distinguishes cancelled and replacement jobs for the same queue identity.
            let token = UUID()
            tokens[track.id] = token
            /// Captured sendable reader runs away from AppKit/main-actor controls.
            let reader = read
            tasks[track.id] = Task { [weak self] in
                /// Detached worker constructs native metadata objects locally rather than transferring them between actors.
                let worker = Task.detached(priority: .utility) { await reader(track.url) }
                /// Cancellation follows queue eviction and window closure through to native property loading.
                let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
                /// Only the latest live job can remove its slot and publish its bounded result.
                guard let self, !self.isClosed, self.tokens[track.id] == token else { return }
                self.tasks.removeValue(forKey: track.id); self.tokens.removeValue(forKey: track.id)
                if !Task.isCancelled { self.session.cacheMetadata(result, for: track) }
                self.startPending()
            }
        }
    }
}
