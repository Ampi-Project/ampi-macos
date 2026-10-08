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
public struct Track: Identifiable, Equatable, Sendable {
    /// Stable identity for this entry during the current session.
    public let id: UUID
    /// Local audio file represented by this entry.
    public let url: URL
    /// Filename without its extension, used until metadata titles are supported.
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
    /// Audio implementation retained across queue operations and skin replacements.
    private let backend: any AudioBackend
    /// Curve retained independently of windows, skins, and loaded tracks.
    public private(set) var equalizer = EqualizerSettings()
    /// Whether this backend can actually process the ten-band curve.
    public var supportsEqualizer: Bool { backend is any EqualizerAudioBackend }

    /// Creates an empty session using the supplied audio implementation.
    public init(backend: any AudioBackend) { self.backend = backend }
    /// Currently loaded queue entry, or nil when nothing has been selected.
    public var currentTrack: Track? { selectedIndex.map { tracks[$0] } }
    /// Loaded track length in seconds, with negative backend values treated as zero.
    public var duration: Double { max(0, backend.duration) }
    /// Current offset in seconds, with negative backend values treated as zero.
    public var position: Double { max(0, backend.position) }
    /// Current output gain; use `setVolume(_:)` to change it with bounds checking.
    public var volume: Float { backend.volume }
    /// Playing feedback derived from the live queue so appends cannot leave a stale track count.
    private var playingStatus: String { "Playing · \(tracks.count) track\(tracks.count == 1 ? "" : "s") in queue" }

    /// Appends file URLs in input order, ignoring non-file URLs, then notifies the observer.
    public func enqueue(_ urls: [URL]) {
        tracks.append(contentsOf: urls.filter(\.isFileURL).map(Track.init))
        if state == .playing { status = playingStatus }
        onChange?()
    }

    /// Loads and plays a queue entry, or resumes it when already selected.
    /// Invalid indices are ignored; failed replacement loads preserve the current track.
    /// - Parameter index: Zero-based queue index to play.
    /// - Throws: A backend loading error or `PlaybackError.couldNotStart`.
    public func play(index: Int) throws {
        guard tracks.indices.contains(index) else { return }
        if selectedIndex != index {
            // Prepare the replacement first. A corrupt track must not destroy the current player.
            try backend.load(tracks[index].url)
            selectedIndex = index
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

    /// Pauses active playback or plays the selected entry (the first entry if unselected).
    /// An empty queue is ignored; backend errors propagate to the caller.
    public func togglePlayback() throws {
        if state == .playing { pause() }
        else { try resume() }
    }

    /// Starts or resumes the selected entry, or the first entry of an unselected queue.
    /// Empty queues and already playing sessions are ignored; backend errors propagate.
    public func resume() throws {
        guard state != .playing else { return }
        /// Queue index to resume or start when playback is not active.
        if let index = selectedIndex ?? (tracks.isEmpty ? nil : 0) {
            try play(index: index)
        }
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

    /// Plays the following entry, or stops at the queue end; loading errors propagate.
    public func next() throws {
        guard !tracks.isEmpty else { return }
        /// Successor index; an unselected queue starts at its first entry.
        let index = (selectedIndex ?? -1) + 1
        if tracks.indices.contains(index) { try play(index: index) }
        else { stop() }
    }

    /// Restarts after three seconds, otherwise plays the previous entry without wrapping.
    /// Loading errors propagate to the caller.
    public func previous() throws {
        guard !tracks.isEmpty else { return }
        if position > 3 { seek(to: 0) }
        else { try play(index: max(0, (selectedIndex ?? 0) - 1)) }
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

    /// Advances on successful completion or stops and reports a decoding/loading failure.
    /// - Parameter successfully: Whether the backend reached the track end normally.
    public func finished(successfully: Bool) {
        if successfully {
            do { try next() } catch { state = .stopped; report(error) }
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
