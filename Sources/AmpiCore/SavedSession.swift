// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin

/// Durable presentation choice; native layouts are embedded, Classic sources are reopened and revalidated.
public enum SavedSkin: Codable, Sendable {
    /// Validated experimental native layout, retained even when its original JSON file moves.
    case native(Theme)
    /// Original Classic archive/folder; nil denotes an in-memory package that cannot be restored.
    case classic(URL?)

    /// Checks source locality and validates embedded geometry when preparing a new save.
    public func validateForSaving() throws {
        /// Associated layout or source identifies the selected presentation without executing external code.
        switch self {
        case .native(let theme): try theme.validate()
        case .classic(let url):
            /// An absent source is saved explicitly so restart can report its native fallback.
            if let url { try SavedSession.validateLocalURL(url) }
        }
    }
}

/// Version-one durable state; omits transport activity, elapsed time, window positions, and random history.
public struct SavedSession: Codable, Sendable {
    /// Schema version, checked before any data reaches a playback session.
    public let schemaVersion: Int
    /// Ordered entries with stable UUIDs, including independent entries for repeated file URLs.
    public let tracks: [Track]
    /// Loaded identity to prepare at zero on restart, or nil for an unselected queue.
    public let selectedTrackID: UUID?
    /// Main output gain, bounded to zero through one.
    public let volume: Float
    /// Whether resumed navigation begins a fresh shuffle traversal.
    public let shuffle: Bool
    /// Completion policy restored without starting playback.
    public let repeatMode: PlaybackSession.RepeatMode
    /// Ten-band curve, preamp in decibels, and bypass state.
    public let equalizer: EqualizerSettings
    /// Presentation to validate independently so a bad skin need not discard valid queue/settings.
    public let skin: SavedSkin
    /// Maximum durable entries; encoded state must also fit the store's byte limit.
    public static let maximumTracks = 10_000

    /// Records durable values without touching audio; validation is required before storage or restoration.
    /// Parameters retain queue order/IDs, selected identity, gain, modes, curve, presentation, and format version.
    public init(tracks: [Track], selectedTrackID: UUID?, volume: Float, shuffle: Bool,
                repeatMode: PlaybackSession.RepeatMode, equalizer: EqualizerSettings, skin: SavedSkin,
                schemaVersion: Int = 1) {
        self.schemaVersion = schemaVersion; self.tracks = tracks; self.selectedTrackID = selectedTrackID
        self.volume = volume; self.shuffle = shuffle; self.repeatMode = repeatMode
        self.equalizer = equalizer; self.skin = skin
    }

    /// Rejects unknown versions, oversized/ambiguous queues, invalid audio values, and remote source URLs.
    /// Embedded native geometry is checked separately during restore, allowing a default-skin fallback.
    public func validate() throws {
        guard schemaVersion == 1 else { throw ThemeError.invalid("The saved session uses an unsupported version.") }
        guard tracks.count <= Self.maximumTracks, Set(tracks.map(\.id)).count == tracks.count,
              selectedTrackID == nil || tracks.contains(where: { $0.id == selectedTrackID }) else {
            throw ThemeError.invalid("The saved queue has invalid or too many entries.")
        }
        /// Every queue URL must identify a local absolute path, never a network or relative resource.
        for track in tracks { try Self.validateLocalURL(track.url) }
        guard volume.isFinite, (0...1).contains(volume), equalizer.preamp.isFinite,
              (-12...12).contains(equalizer.preamp), equalizer.gains.count == EqualizerSettings.frequencies.count,
              equalizer.gains.allSatisfy({ $0.isFinite && (-12...12).contains($0) }) else {
            throw ThemeError.invalid("The saved audio settings are outside supported bounds.")
        }
        /// A Classic source is checked for locality here; actual archive/bitmap validation happens off the UI thread.
        if case .classic(let url) = skin, let url { try Self.validateLocalURL(url) }
    }

    /// Returns a snapshot using the supplied surviving entries in their supplied order, retaining settings.
    /// A removed selected identity becomes nil so another decoder cannot be mistaken for that file.
    public func retainingTracks(_ available: [Track]) -> SavedSession {
        SavedSession(tracks: available,
            selectedTrackID: available.contains(where: { $0.id == selectedTrackID }) ? selectedTrackID : nil,
            volume: volume, shuffle: shuffle, repeatMode: repeatMode, equalizer: equalizer, skin: skin,
            schemaVersion: schemaVersion)
    }

    /// Requires a local absolute file URL with a bounded path; this does not grant filesystem permission.
    public static func validateLocalURL(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), url.path.utf8.count <= 4_096,
              url.host == nil || url.host == "" || url.host == "localhost" else {
            throw ThemeError.invalid("Saved files must use local absolute paths.")
        }
    }
}

/// Serial off-main-actor JSON storage with bounded reads and atomic replacement of a complete valid snapshot.
public actor SessionStateStore {
    /// Immutable state-file URL supplied by the native host or tests, safely readable outside the storage actor.
    public nonisolated let url: URL
    /// Maximum on-disk JSON payload; checked during both bounded reading and encoding.
    public static let maximumBytes = 2 * 1024 * 1024
    /// Last successfully written bytes, avoiding disk writes for transport-only changes.
    private var lastWritten: Data?

    /// Uses a local state file; methods throw on invalid URLs or filesystem/format failures.
    public init(url: URL) { self.url = url }

    /// Locates the native app's private support directory without creating or modifying it.
    public static func defaultURL() throws -> URL {
        /// User application-support location is supplied by Foundation rather than a hard-coded home path.
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: false)
        return directory.appendingPathComponent("org.ampi-project.macos", isDirectory: true)
            .appendingPathComponent("session-v1.json")
    }

    /// Returns nil on first launch; rejects nonregular/symlink files, unknown versions, and invalid durable data.
    /// A limit-plus-one read prevents a file that grows during loading from causing an unbounded allocation.
    public func load() throws -> SavedSession? {
        try SavedSession.validateLocalURL(url)
        /// Nonfollowing, nonblocking open prevents cached URL metadata or a file-type race from admitting a link/FIFO.
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            /// Filesystem representation is supplied by Foundation for this already validated absolute URL.
            guard let path else { return Int32(-1) }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw ThemeError.invalid("The saved session could not be opened as a regular local file.")
        }
        /// Open descriptor is owned by a handle and closed after validation/read, including all failure paths.
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        /// Actual opened file metadata bypasses URL resource caching and validates before allocating payload memory.
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG,
              information.st_size >= 0, information.st_size <= Self.maximumBytes else {
            throw ThemeError.invalid("The saved session is not a supported state file.")
        }
        /// At most two MiB plus a sentinel byte enter memory.
        let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard data.count <= Self.maximumBytes else { throw ThemeError.invalid("The saved session exceeds 2 MiB.") }
        /// Decoded durable values must pass audio/queue rules before the caller sees them.
        let saved = try JSONDecoder().decode(SavedSession.self, from: data)
        try saved.validate()
        return saved
    }

    /// Serializes valid state and atomically replaces the previous file; failures leave the previous snapshot intact.
    /// Identical snapshots avoid writes while the file exists; force always replaces it for final Quit/recovery.
    /// No audio/skin assets are copied or deleted. A forced save also repairs externally changed state bytes.
    public func save(_ saved: SavedSession, force: Bool = false) throws {
        try SavedSession.validateLocalURL(url); try saved.validate(); try saved.skin.validateForSaving()
        /// Stable key order enables inexpensive byte equality for unchanged durable values.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        /// Whole validated replacement is encoded before touching the existing state file.
        let data = try encoder.encode(saved)
        guard data.count <= Self.maximumBytes else { throw ThemeError.invalid("The queue is too large to save within 2 MiB.") }
        guard force || data != lastWritten || !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic])
        lastWritten = data
    }
}
