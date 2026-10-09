// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Main-thread audio operations used by the queue without depending on a native UI.
@MainActor public protocol AudioBackend: AnyObject {
    /// Length of the loaded track in seconds; zero when no track is loaded.
    var duration: Double { get }
    /// Playback offset in seconds; writes seek within the loaded track.
    var position: Double { get set }
    /// Output gain from zero (muted) to one (full volume).
    var volume: Float { get set }
    /// Prepares a local audio file, preserving the current player if preparation fails.
    /// - Parameter url: File URL of the replacement track.
    /// - Throws: A file-reading, decoding, or audio-preparation error.
    func load(_ url: URL) throws
    /// Starts or resumes the loaded track and returns whether output started.
    func play() -> Bool
    /// Suspends playback while retaining the current offset.
    func pause()
    /// Stops output and resets the loaded track's offset to zero.
    func stop()
}

/// One queue entry, with an identity distinct from other entries for the same file.
public struct Track: Identifiable, Equatable, Codable, Sendable {
    /// Stable identity for this entry, retained in saved queues across restart.
    public let id: UUID
    /// Local audio file represented by this entry.
    public let url: URL
    /// Filename without its extension; the session uses this when embedded metadata has no title.
    public var title: String { url.deletingPathExtension().lastPathComponent }
    /// Creates a queue entry with a fresh identity for the supplied file URL.
    public init(url: URL) { self.id = UUID(); self.url = url }
}

/// Owns queue and transport state independently of the active skin on the main actor.
@MainActor public final class PlaybackSession {
    /// Transport state reported to controls and accessibility clients.
    public enum State: String {
        /// Output is stopped; the selected entry may remain available for replay.
        case stopped
        /// The backend successfully started audio output.
        case playing
        /// Playback is suspended or a start attempt failed.
        case paused
    }
    /// Automatic completion policy; manual Next always ignores Repeat One.
    public enum RepeatMode: String, CaseIterable, Codable, Sendable {
        /// Stops after the last sequential entry or all entries in a shuffle cycle.
        case off
        /// Starts another queue cycle after reaching its end.
        case all
        /// Rewinds and replays the current entry on successful completion.
        case one
    }
    /// Whether navigation draws unvisited identities instead of following visible queue order.
    public private(set) var isShuffleEnabled = false
    /// Completion policy retained across queue edits and skin replacements.
    public private(set) var repeatMode: RepeatMode = .off
    /// Identities visited in the current shuffle cycle; duplicate URLs remain distinct entries.
    private var shuffleVisited = Set<UUID>()
    /// At most 200 played identities supporting backward and forward shuffle navigation.
    private var shuffleHistory: [UUID] = []
    /// Current position in shuffle history, or nil before playback in this traversal.
    private var historyIndex: Int?
    /// Chooses an index in a nonempty candidate list; production uses uniform randomness.
    private let chooseShuffleIndex: (Int) -> Int
    /// Ordered queue entries, including repeated additions of the same file.
    public private(set) var tracks: [Track] = []
    /// Index of the loaded entry, or nil before any track loads successfully.
    public private(set) var selectedIndex: Int?
    /// Current transport state, updated only after backend operations.
    public private(set) var state: State = .stopped
    /// User-facing playback feedback or the latest reported error.
    public private(set) var status = "Open music to start listening."
    /// Optional main-actor observer invoked synchronously after session changes.
    public var onChange: (() -> Void)?
    /// Rendering-only observer; derived metadata never triggers durable settings writes.
    public var onMetadataChange: (() -> Void)?
    /// At most 64 derived tag/thumbnail results indexed by queue identity, independent of saved state.
    private var trackMetadata: [UUID: TrackMetadata] = [:]
    /// Wrapping revision lets queues refresh tag text without changing browsing or playback selection.
    public private(set) var metadataRevision: UInt = 0
    /// Maximum cached queue entries, including the currently loaded entry when present.
    public static let maximumMetadataEntries = 64
    /// Audio implementation retained across queue operations and skin replacements.
    private let backend: any AudioBackend
    /// Curve retained independently of windows, skins, and loaded tracks.
    public private(set) var equalizer = EqualizerSettings()
    /// Whether this backend can actually process the ten-band curve.
    public var supportsEqualizer: Bool { backend is any EqualizerAudioBackend }

    /// Creates an empty session using the supplied audio implementation.
    public convenience init(backend: any AudioBackend) {
        /// The chooser's count is the positive number of eligible shuffle entries.
        self.init(backend: backend, chooseShuffleIndex: { count in Int.random(in: 0..<count) })
    }
    /// Injects a bounded candidate-index chooser for deterministic module tests; count is always positive.
    internal init(backend: any AudioBackend, chooseShuffleIndex: @escaping (Int) -> Int) {
        self.backend = backend; self.chooseShuffleIndex = chooseShuffleIndex
    }
    /// Currently loaded queue entry, or nil when nothing has been selected.
    public var currentTrack: Track? { selectedIndex.map { tracks[$0] } }
    /// Loaded track length in seconds; zero without a queue selection, even if the backend retains a decoder.
    public var duration: Double { selectedIndex == nil ? 0 : max(0, backend.duration) }
    /// Current offset in seconds; zero without a selection and negative backend values treated as zero.
    public var position: Double { selectedIndex == nil ? 0 : max(0, backend.position) }
    /// Current output gain; use `setVolume(_:)` to change it with bounds checking.
    public var volume: Float { backend.volume }
    /// Playing feedback derived from the live queue so appends cannot leave a stale track count.
    private var playingStatus: String { "Playing · \(tracks.count) track\(tracks.count == 1 ? "" : "s") in queue" }

    /// Returns cached tags for a live identity, or nil while reading or after eviction/removal.
    public func metadata(for track: Track) -> TrackMetadata? { trackMetadata[track.id] }

    /// Returns an embedded title when available, retaining the filename for untagged or unreadable files.
    public func displayTitle(for track: Track) -> String { metadata(for: track)?.title ?? track.title }

    /// Returns title, artist, and album on separate tooltip lines, omitting absent tags.
    public func trackDescription(for track: Track) -> String {
        [displayTitle(for: track), metadata(for: track)?.artist, metadata(for: track)?.album].compactMap { $0 }.joined(separator: "\n")
    }

    /// Publishes a background result only if its original identity and URL still exist; never touches the backend.
    public func cacheMetadata(_ metadata: TrackMetadata, for track: Track) {
        guard tracks.contains(track), trackMetadata[track.id] != metadata,
              trackMetadata[track.id] != nil || trackMetadata.count < Self.maximumMetadataEntries else { return }
        trackMetadata[track.id] = metadata; metadataRevision &+= 1; onMetadataChange?()
    }

    /// Evicts results outside the reader's bounded live target set; rendering updates do not save state.
    public func retainMetadata(for identities: Set<UUID>) {
        /// Reduced cache contains only live identities chosen by the native reader coordinator.
        let retained = trackMetadata.filter { identities.contains($0.key) }
        guard retained.count != trackMetadata.count else { return }
        trackMetadata = retained; metadataRevision &+= 1; onMetadataChange?()
    }

    /// Captures durable settings and identities; transport state, offset, and shuffle history are intentionally omitted.
    public func savedState(skin: SavedSkin) -> SavedSession {
        SavedSession(tracks: tracks, selectedTrackID: currentTrack?.id, volume: volume,
                     shuffle: isShuffleEnabled, repeatMode: repeatMode, equalizer: equalizer, skin: skin)
    }

    /// Replaces the session with validated durable state without playing; the selected decoder is prepared at zero.
    /// - Returns: A diagnostic if the selected file could not be prepared; queue/settings still restore safely.
    /// - Throws: Invalid snapshot data before modifying the current session. File availability is filtered by the caller.
    public func restore(_ saved: SavedSession) throws -> String? {
        try saved.validate()
        backend.stop(); selectedIndex = nil; state = .stopped
        tracks = saved.tracks; trackMetadata.removeAll(); metadataRevision &+= 1; backend.volume = saved.volume
        equalizer = saved.equalizer
        (backend as? any EqualizerAudioBackend)?.applyEqualizer(equalizer)
        isShuffleEnabled = saved.shuffle; repeatMode = saved.repeatMode
        shuffleVisited.removeAll(); shuffleHistory.removeAll(); historyIndex = nil
        /// Optional selected-file diagnostic lets the native launcher combine recovery notices into one status.
        var diagnostic: String?
        /// Restored identity resolves the exact duplicate, after the native caller has pruned missing files.
        if let index = tracks.firstIndex(where: { $0.id == saved.selectedTrackID }) {
            do { try backend.load(tracks[index].url); backend.stop(); selectedIndex = index }
            catch { diagnostic = "The saved selected track could not be opened. Select another track to play." }
        }
        /// Selected entry begins a fresh shuffle traversal; prior random visits are never persisted.
        if isShuffleEnabled, let identity = currentTrack?.id {
            shuffleVisited.insert(identity); shuffleHistory = [identity]; historyIndex = 0
        }
        status = diagnostic ?? (tracks.isEmpty ? "Open music to start listening." : "Restored \(tracks.count) queue \(tracks.count == 1 ? "entry" : "entries"). Press Play to listen.")
        onChange?()
        return diagnostic
    }

    /// Appends file URLs in input order, ignoring non-file URLs, then notifies the observer.
    public func enqueue(_ urls: [URL]) {
        tracks.append(contentsOf: urls.filter(\.isFileURL).map(Track.init))
        if state == .playing { status = playingStatus }
        onChange?()
    }

    /// Removes a valid zero-based entry without deleting its file; invalid indices are ignored.
    /// Removing the loaded entry stops output and clears its selection without starting another track.
    /// Removing any other entry preserves loaded identity, offset, transport, output gain, and EQ.
    public func removeTrack(at index: Int) {
        guard tracks.indices.contains(index) else { return }
        /// Loaded entry identity is stable even when earlier entries are removed.
        let loaded = currentTrack?.id
        /// Removing the loaded entry cancels output and its scheduled completion before mutating the queue.
        let removedCurrent = tracks[index].id == loaded
        /// Removed identity must disappear from the shuffle cycle and navigation history too.
        let removedIdentity = tracks[index].id
        if removedCurrent { backend.stop(); state = .stopped }
        tracks.remove(at: index)
        if trackMetadata.removeValue(forKey: removedIdentity) != nil { metadataRevision &+= 1 }
        shuffleVisited.remove(removedIdentity)
        /// Earlier surviving visits determine the new cursor after history entries are filtered.
        let survivingPrefix = historyIndex.map { shuffleHistory.prefix($0 + 1).filter { $0 != removedIdentity }.count } ?? 0
        shuffleHistory.removeAll { $0 == removedIdentity }
        historyIndex = survivingPrefix > 0 ? survivingPrefix - 1 : nil
        if removedCurrent { shuffleHistory.removeAll(); historyIndex = nil }
        /// Optional identity is matched against remaining entries, preserving the exact loaded duplicate's index.
        selectedIndex = loaded.flatMap { identity in tracks.firstIndex { $0.id == identity } }
        if tracks.isEmpty { status = "Queue is empty. Open music to start listening." }
        else if removedCurrent { status = "Removed current track. Select a track to play." }
        else if state == .playing { status = playingStatus }
        onChange?()
    }

    /// Moves one entry to a final zero-based index; invalid indices and unchanged positions are ignored.
    /// Loaded identity and backend are retained; sequential navigation follows new order, shuffle retains visits.
    public func moveTrack(from source: Int, to destination: Int) {
        guard tracks.indices.contains(source), tracks.indices.contains(destination), source != destination else { return }
        /// Loaded identity is resolved after insertion rather than treating its old index as authoritative.
        let loaded = currentTrack?.id
        /// Existing entry moves with its original UUID, including repeated URLs.
        let entry = tracks.remove(at: source)
        tracks.insert(entry, at: destination)
        /// Optional identity is matched against reordered entries rather than their repeated file URLs.
        selectedIndex = loaded.flatMap { identity in tracks.firstIndex { $0.id == identity } }
        if state == .playing { status = playingStatus }
        onChange?()
    }

    /// Stops output and empties the queue without deleting audio files or resetting output gain/EQ.
    /// An already empty queue is ignored; a later explicit Play/Open starts from a newly loaded entry.
    public func clearQueue() {
        guard !tracks.isEmpty else { return }
        backend.stop()
        tracks.removeAll()
        trackMetadata.removeAll(); metadataRevision &+= 1
        shuffleVisited.removeAll(); shuffleHistory.removeAll(); historyIndex = nil
        selectedIndex = nil; state = .stopped
        status = "Queue is empty. Open music to start listening."
        onChange?()
    }

    /// Loads and plays a queue entry, or resumes it when already selected.
    /// Invalid indices are ignored; failed replacement loads preserve the current track.
    /// - Parameter index: Zero-based queue index to play.
    /// - Throws: A backend loading error or `PlaybackError.couldNotStart`.
    public func play(index: Int) throws {
        try start(index: index, historyPosition: nil, newCycle: false)
    }

    /// Prepares a destination before consuming its shuffle visit, optionally retracing history or starting a cycle.
    /// Loading errors preserve traversal and current output; a failed start retains the newly prepared selection.
    private func start(index: Int, historyPosition: Int?, newCycle: Bool) throws {
        guard tracks.indices.contains(index) else { return }
        if selectedIndex != index {
            /// Prepare before replacing selection or traversal, preserving the player on a corrupt file.
            try backend.load(tracks[index].url)
            selectedIndex = index
        }
        else if newCycle || (duration > 0 && position >= duration) { backend.position = 0 }
        if isShuffleEnabled {
            if newCycle { shuffleVisited.removeAll() }
            shuffleVisited.insert(tracks[index].id)
            /// Retracing history changes its cursor without discarding the already played forward path.
            if let historyPosition { historyIndex = historyPosition }
            else if historyIndex.map({ shuffleHistory[$0] }) != tracks[index].id {
                /// A directly selected entry replaces any unused forward path after Previous.
                if let historyIndex { shuffleHistory = Array(shuffleHistory.prefix(historyIndex + 1)) }
                shuffleHistory.append(tracks[index].id)
                if shuffleHistory.count > 200 { shuffleHistory.removeFirst(shuffleHistory.count - 200) }
                historyIndex = shuffleHistory.count - 1
            }
        }
        guard backend.play() else {
            state = .paused
            status = "The audio output could not start. Try playing again."
            onChange?()
            throw PlaybackError.couldNotStart
        }
        state = .playing
        status = playingStatus
        onChange?()
    }

    /// Pauses active playback or resumes the loaded entry; an unselected queue follows the current shuffle policy.
    /// An empty queue is ignored; backend errors propagate to the caller.
    public func togglePlayback() throws {
        if state == .playing { pause() }
        else { try resume() }
    }

    /// Resumes the selected entry; an unselected queue starts at a random entry in shuffle or the first otherwise.
    /// Empty queues and already playing sessions are ignored; backend errors propagate.
    public func resume() throws {
        guard state != .playing else { return }
        /// Queue index to resume or start when playback is not active.
        if let selectedIndex { try play(index: selectedIndex) }
        else { try next() }
    }

    /// Pauses active output while retaining offset; paused or stopped sessions are ignored.
    public func pause() {
        guard state == .playing else { return }
        backend.pause(); state = .paused; status = "Paused"; onChange?()
    }

    /// Stops and rewinds the loaded track while retaining its queue selection.
    public func stop() {
        backend.stop(); state = .stopped; status = "Stopped"; onChange?()
    }

    /// Plays the sequential successor or next shuffle visit; Repeat All opens another cycle.
    /// Manual Next overrides Repeat One; an exhausted cycle with Off/One stops and rewinds.
    public func next() throws {
        guard !tracks.isEmpty else { return }
        if isShuffleEnabled {
            /// A previous backward navigation leaves a known forward visit to retrace first.
            if let historyIndex, shuffleHistory.indices.contains(historyIndex + 1),
               let index = tracks.firstIndex(where: { $0.id == shuffleHistory[historyIndex + 1] }) {
                try start(index: index, historyPosition: historyIndex + 1, newCycle: false)
                return
            }
            /// Candidate rows preserve visible ordering; selection alone is randomized, not the queue itself.
            var candidates = tracks.indices.filter { !shuffleVisited.contains(tracks[$0].id) }
            /// Empty visits with no loaded selection can restart a previously exhausted/edited queue explicitly.
            let newCycle = candidates.isEmpty
            if newCycle {
                guard repeatMode == .all || selectedIndex == nil else { stop(); return }
                candidates = Array(tracks.indices)
                if candidates.count > 1 { candidates.removeAll { $0 == selectedIndex } }
            }
            try start(index: candidates[chooseShuffleIndex(candidates.count)], historyPosition: nil, newCycle: newCycle)
            return
        }
        /// Successor index; an unselected queue starts at its first entry.
        let index = (selectedIndex ?? -1) + 1
        if tracks.indices.contains(index) { try play(index: index) }
        else if repeatMode == .all {
            if tracks.count == 1 { backend.position = 0 }
            try play(index: 0)
        }
        else { stop() }
    }

    /// Restarts after three seconds, otherwise retraces shuffle history or moves backward in visible queue order.
    /// Previous does not wrap; without earlier shuffle history it rewinds the loaded entry.
    /// Loading errors propagate to the caller.
    public func previous() throws {
        guard !tracks.isEmpty else { return }
        if position > 3 { seek(to: 0) }
        else if isShuffleEnabled {
            /// Replay the preceding surviving history entry; without history simply rewind the current selection.
            if let historyIndex, historyIndex > 0,
               let index = tracks.firstIndex(where: { $0.id == shuffleHistory[historyIndex - 1] }) {
                try start(index: index, historyPosition: historyIndex - 1, newCycle: false)
            } else if let selectedIndex {
                backend.position = 0; try play(index: selectedIndex)
            } else { try resume() }
        }
        else { try play(index: max(0, (selectedIndex ?? 0) - 1)) }
    }

    /// Changes shuffle without seeking, loading, or reordering; each toggle starts a new traversal from the loaded entry.
    public func setShuffleEnabled(_ enabled: Bool) {
        guard enabled != isShuffleEnabled else { return }
        isShuffleEnabled = enabled
        shuffleVisited.removeAll(); shuffleHistory.removeAll(); historyIndex = nil
        /// The loaded identity counts as the first visit even when paused or stopped.
        if enabled, let identity = currentTrack?.id {
            shuffleVisited.insert(identity); shuffleHistory = [identity]; historyIndex = 0
        }
        onChange?()
    }

    /// Sets automatic completion policy without disturbing output, offset, queue, or shuffle history.
    public func setRepeatMode(_ mode: RepeatMode) { repeatMode = mode; onChange?() }

    /// Cycles Off → All → One → Off, matching the single Classic/native theme button.
    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: setRepeatMode(.all)
        case .all: setRepeatMode(.one)
        case .one: setRepeatMode(.off)
        }
    }

    /// Seeks within the loaded track, ignoring non-finite values and an empty selection.
    /// - Parameter value: Desired offset in seconds, clamped to zero through duration.
    public func seek(to value: Double) {
        guard value.isFinite, selectedIndex != nil else { return }
        backend.position = min(duration, max(0, value))
        onChange?()
    }

    /// Updates gain and notifies the observer, ignoring non-finite input.
    /// - Parameter value: Gain clamped to zero (muted) through one (full volume).
    public func setVolume(_ value: Float) {
        guard value.isFinite else { return }
        backend.volume = min(1, max(0, value))
        onChange?()
    }

    /// Enables or bypasses supported DSP without clearing the curve or changing transport.
    public func setEqualizerEnabled(_ enabled: Bool) {
        guard supportsEqualizer else { return }
        equalizer.setEnabled(enabled)
        updateEqualizer()
    }

    /// Adjusts preamp in decibels; finite input is clamped to minus twelve through plus twelve.
    public func setEqualizerPreamp(_ decibels: Float) {
        guard supportsEqualizer, decibels.isFinite else { return }
        equalizer.setPreamp(decibels)
        updateEqualizer()
    }

    /// Adjusts a valid zero-based band in decibels without seeking or changing volume.
    public func setEqualizerGain(_ decibels: Float, at index: Int) {
        guard supportsEqualizer, equalizer.gains.indices.contains(index), decibels.isFinite else { return }
        equalizer.setGain(decibels, at: index)
        updateEqualizer()
    }

    /// Applies an original preset, preserving bypass state and transport position.
    public func applyEqualizerPreset(_ preset: EqualizerPreset) {
        guard supportsEqualizer else { return }
        equalizer.apply(preset)
        updateEqualizer()
    }

    /// Delivers the current curve synchronously to a capable backend and refreshes observers.
    private func updateEqualizer() {
        (backend as? any EqualizerAudioBackend)?.applyEqualizer(equalizer)
        onChange?()
    }

    /// Displays an error's localized description without changing transport state.
    public func report(_ error: Error) {
        status = error.localizedDescription; onChange?()
    }

    /// Repeats or advances according to policy on successful completion, otherwise stops/reports a failure.
    /// Ignores completion without an active playing selection, including paused/stopped stale callbacks.
    /// - Parameter successfully: Whether the backend reached the track end normally.
    public func finished(successfully: Bool) {
        guard selectedIndex != nil, state == .playing else { return }
        if successfully {
            do {
                /// Repeat One must rewind a completed decoder before playing the same selected identity.
                if repeatMode == .one, let selectedIndex {
                    backend.position = 0; try play(index: selectedIndex)
                } else { try next() }
            } catch { backend.stop(); state = .stopped; report(error) }
        } else {
            state = .stopped; status = "Playback ended because the audio could not be decoded."; onChange?()
        }
    }
}

/// Transport failures that can be presented directly to the user.
public enum PlaybackError: LocalizedError {
    /// The backend could not start output for the selected track.
    case couldNotStart
    /// The decoder produced empty audio or a format outside the current native processing profile.
    case unsupportedDecodedFormat
    /// Human-readable explanation used by session feedback and alerts.
    public var errorDescription: String? {
        switch self {
        case .couldNotStart: return "The audio output could not start."
        case .unsupportedDecodedFormat: return "The audio file has no supported decoded samples. The current player processes mono or stereo floating-point audio."
        }
    }
}
