// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import AmpiCore

/// No-output backend counts decoder mutation while metadata is published and queue entries move.
@MainActor private final class MetadataTestBackend: AudioBackend {
    /// Fixed source length in seconds makes offset preservation observable.
    var duration = 100.0
    /// Simulated clock changes only when transport requests it.
    var position = 0.0
    /// Saved gain remains independent of tags/artwork.
    var volume: Float = 0.4
    /// Preparation count detects unintended metadata-driven loads.
    var loads = 0
    /// Counts decoder preparation and resets the new source's simulated clock.
    func load(_ url: URL) throws { loads += 1; position = 0 }
    /// Simulates successful explicit playback without accessing a device.
    func play() -> Bool { true }
    /// Simulated pause retains the clock.
    func pause() {}
    /// Simulated stop rewinds the clock.
    func stop() { position = 0 }
}

/// Validates derived tag limits, identity safety, transport independence, and saved-state exclusion.
final class TrackMetadataTests: XCTestCase {
    /// Unicode is retained, controls become spaces, blank tags fall back, and unbounded fields/artwork are rejected or clipped.
    func testTextAndStorageLimits() {
        /// Raw input combines Unicode, newlines, NUL, and trailing whitespace to exercise UI sanitization.
        let metadata = TrackMetadata(title: "  ♫ موسیقی\ntrack\0  ", artist: "\t \n", album: String(repeating: "a", count: 1024),
            artwork: Data(repeating: 0, count: TrackMetadata.maximumArtworkBytes + 1))
        XCTAssertEqual(metadata.title, "♫ موسیقی track"); XCTAssertNil(metadata.artist)
        XCTAssertEqual(metadata.album?.count, 256); XCTAssertNil(metadata.artwork)
        XCTAssertNil(TrackMetadata().title)
    }

    /// Late results follow a moved duplicate UUID, never a row index; removed and requeued identities reject older tags.
    @MainActor func testIdentityAndTransportPreservation() throws {
        /// No-output backend proves publication cannot prepare another source or alter transport.
        let backend = MetadataTestBackend()
        /// Duplicate filenames still represent independently editable identities.
        let session = PlaybackSession(backend: backend)
        session.enqueue([URL(fileURLWithPath: "/same.wav"), URL(fileURLWithPath: "/same.wav")])
        try session.play(index: 1); session.seek(to: 42); session.pause()
        /// Original selected entry survives a move while its reader is pending.
        let track = session.tracks[1]
        session.moveTrack(from: 1, to: 0)
        /// Durable/render notification counts distinguish cached metadata from save-worthy changes.
        var durable = 0
        /// Rendering-only callbacks are counted independently from the durable observer.
        var derived = 0
        session.onChange = { durable += 1 }; session.onMetadataChange = { derived += 1 }
        session.cacheMetadata(TrackMetadata(title: "Embedded", artist: "Artist", album: "Album"), for: track)
        XCTAssertEqual(session.displayTitle(for: session.tracks[0]), "Embedded")
        XCTAssertEqual(session.displayTitle(for: session.tracks[1]), "same")
        XCTAssertEqual(session.trackDescription(for: track), "Embedded\nArtist\nAlbum")
        XCTAssertEqual(durable, 0); XCTAssertEqual(derived, 1)
        XCTAssertEqual(session.state, .paused); XCTAssertEqual(session.position, 42)
        XCTAssertEqual(session.volume, 0.4); XCTAssertEqual(backend.loads, 1)
        session.removeTrack(at: 0); session.enqueue([track.url])
        session.cacheMetadata(TrackMetadata(title: "Stale"), for: track)
        XCTAssertNil(session.metadata(for: track)); XCTAssertEqual(session.displayTitle(for: session.tracks[1]), "same")
        session.clearQueue(); session.cacheMetadata(TrackMetadata(title: "Stale"), for: track)
        XCTAssertNil(session.metadata(for: track))
    }

    /// Derived cache is bounded, excludes thumbnails/tags from JSON, and is rebuilt after restore.
    @MainActor func testCacheBoundsAndSavedStateExclusion() throws {
        /// Simulated backend keeps this persistence test independent of native file availability.
        let session = PlaybackSession(backend: MetadataTestBackend())
        session.enqueue((0..<70).map { URL(fileURLWithPath: "/\($0).wav") })
        /// Original live entry receives tags until the 64-result storage ceiling is reached.
        for track in session.tracks { session.cacheMetadata(TrackMetadata(title: "Private tag"), for: track) }
        XCTAssertEqual(session.tracks.filter { session.metadata(for: $0) != nil }.count, 64)
        /// Saved snapshot retains only queue file identities/settings/native geometry.
        let saved = session.savedState(skin: .native(try ThemeCatalog.builtin("retro")))
        /// Encoded JSON must contain neither derived title nor artwork cache storage.
        let json = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
        XCTAssertFalse(json.contains("Private tag")); XCTAssertFalse(json.contains("artwork"))
        session.retainMetadata(for: [session.tracks[0].id])
        XCTAssertEqual(session.tracks.filter { session.metadata(for: $0) != nil }.count, 1)
        _ = try session.restore(saved)
        XCTAssertEqual(session.tracks.filter { session.metadata(for: $0) != nil }.count, 0)
    }
}
