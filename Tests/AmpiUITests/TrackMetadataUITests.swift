// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AVFoundation
import AmpiCore
import ImageIO
import XCTest
@testable import Ampi

/// Explicitly controlled noncooperative reader makes cancelled/out-of-order callback delivery deterministic.
private actor MetadataReadProbe {
    /// Request URLs expose worker ordering without tying identity to a mutable queue row.
    private(set) var requests: [URL] = []
    /// Pending continuations remain resumable after cancellation to simulate an older native completion.
    private var pending: [URL: [CheckedContinuation<TrackMetadata, Never>]] = [:]
    /// Current and peak active operations measure the two-worker scheduling limit.
    private(set) var active = 0
    /// Peak parallel reads, including requests that have not yet been explicitly completed.
    private(set) var peak = 0
    /// Suspends this URL until the test explicitly completes its first pending request.
    func read(_ url: URL) async -> TrackMetadata {
        requests.append(url); active += 1; peak = max(peak, active)
        return await withCheckedContinuation { continuation in
            pending[url, default: []].append(continuation)
        }
    }
    /// Completes the oldest request for this URL, allowing repeated paths to arrive across queue generations.
    func finish(_ url: URL, title: String) {
        /// Oldest native callback is deliberately delivered even if its outer coordinator task was cancelled.
        guard var values = pending[url], !values.isEmpty else { return }
        /// First continuation belongs to the original request for this URL.
        let continuation = values.removeFirst()
        pending[url] = values; active -= 1
        continuation.resume(returning: TrackMetadata(title: title))
    }
    /// Releases every pending test task so no suspended continuation survives teardown.
    func finishAll() {
        /// Each URL's retained continuations receive empty fallback values during cleanup.
        for values in pending.values {
            /// Each suspended reader is resumed once, independently from task cancellation.
            for continuation in values { continuation.resume(returning: TrackMetadata()) }
        }
        pending.removeAll(); active = 0
    }
}

/// No-output graph supports selected-entry tests while all UI controls remain actual AppKit objects.
@MainActor private final class MetadataUIBackend: AudioBackend {
    /// Simulated source length in seconds.
    var duration = 60.0
    /// Simulated playback offset is preserved while tags arrive.
    var position = 0.0
    /// Gain is never touched by the metadata layer.
    var volume: Float = 0.3
    /// Counts preparation to detect implicit activation from row refreshes.
    var loads = 0
    /// Simulates preparation and rewinds only on explicit queue activation.
    func load(_ url: URL) throws { loads += 1; position = 0 }
    /// Reports successful explicit playback without starting a native output device.
    func play() -> Bool { true }
    /// Pausing retains the simulated offset.
    func pause() {}
    /// Stopping rewinds the simulated clock.
    func stop() { position = 0 }
}

/// Checks real local tags/artwork, bounded image decoding, callback races, worker limits, and native/Classic refresh behavior.
final class TrackMetadataUITests: XCTestCase {
    /// Real native exporter/reader preserve original Unicode common tags and a bounded PNG thumbnail.
    @MainActor func testOriginalAACMetadataAndArtwork() async throws {
        /// Disposable original source is synthesized, tagged, decoded, and removed without third-party music/artwork.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ampi-metadata-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try await MetadataSmokeCheck.createFixture(at: url)
        /// Reader runs off the main actor, returning only Sendable values rather than native metadata objects.
        let metadata = await Task.detached { await TrackMetadataReader.read(url) }.value
        XCTAssertEqual(metadata.title, MetadataSmokeCheck.fixtureTitle)
        XCTAssertEqual(metadata.artist, MetadataSmokeCheck.fixtureArtist)
        XCTAssertEqual(metadata.album, MetadataSmokeCheck.fixtureAlbum)
        /// Actual PNG header verifies dimensions instead of trusting only a successful NSImage initialization.
        let data = try XCTUnwrap(metadata.artwork)
        XCTAssertLessThanOrEqual(data.count, TrackMetadata.maximumArtworkBytes)
        /// Thumbnail source reveals Image I/O's actual encoded width/height.
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        /// Decoded thumbnail is small enough for safe repeated native panel presentation.
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 256); XCTAssertEqual(image.height, 256)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Missing/non-file/corrupt assets produce empty fallback; they never open remote URLs or alter input bytes.
    func testUnreadableAndRemoteFallback() async throws {
        /// Disposable malformed local input exercises native parse failure rather than just absent-file preflight.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ampi-invalid-tags-\(UUID().uuidString).mp3")
        defer { try? FileManager.default.removeItem(at: url) }
        /// Original invalid bytes are compared after native inspection to prove read-only behavior.
        let original = Data("This is not audio or metadata".utf8)
        try original.write(to: url)
        /// Completed local parse result is captured before entering XCTest's synchronous assertion autoclosure.
        let corrupt = await TrackMetadataReader.read(url)
        /// Missing path is newly generated so it cannot coincide with a real user file.
        let missing = await TrackMetadataReader.read(URL(fileURLWithPath: "/missing-\(UUID().uuidString).m4a"))
        /// Non-file URL is rejected by preflight without any network access.
        let remote = await TrackMetadataReader.read(try XCTUnwrap(URL(string: "https://example.invalid/music.m4a")))
        XCTAssertEqual(corrupt, TrackMetadata()); XCTAssertEqual(missing, TrackMetadata()); XCTAssertEqual(remote, TrackMetadata())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    /// Oversized bytes/headers and damaged images are rejected before full-image decoding, while valid artwork downsamples.
    @MainActor func testArtworkBoundsAndMalformedFallback() throws {
        XCTAssertNil(TrackMetadataReader.thumbnail(Data("broken image".utf8)))
        XCTAssertNil(TrackMetadataReader.thumbnail(Data(repeating: 0, count: TrackMetadataReader.maximumSourceArtworkBytes + 1)))
        XCTAssertNil(TrackMetadataReader.thumbnail(try MetadataSmokeCheck.artwork(width: 4097, height: 1)))
        XCTAssertNotNil(TrackMetadataReader.thumbnail(try MetadataSmokeCheck.artwork(width: 600, height: 300)))
    }

    /// Clear/requeue of the same path cannot attach an older cancelled result to the new identity.
    @MainActor func testCancelledOldResultCannotPopulateRequeuedPath() async throws {
        /// Probe intentionally ignores cancellation until its native-style callback is explicitly delivered.
        let probe = MetadataReadProbe()
        /// Fresh queue receives an independently identified duplicate after clear.
        let session = PlaybackSession(backend: MetadataUIBackend())
        session.enqueue([URL(fileURLWithPath: "/same.wav")])
        /// Injectable reader takes a local URL; probe stores its request and returns a manually completed result.
        let coordinator = TrackMetadataCoordinator(session: session, read: { url in await probe.read(url) })
        defer { coordinator.cancel(); Task { await probe.finishAll() } }
        coordinator.synchronize(); try await waitForRequests(probe, count: 1)
        /// Old UUID must not survive the clear, even though its background URL is unchanged.
        let old = session.tracks[0]
        session.clearQueue(); session.enqueue([old.url]); coordinator.synchronize()
        try await waitForRequests(probe, count: 2)
        await probe.finish(old.url, title: "Old callback")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(session.metadata(for: session.tracks[0])); XCTAssertNotEqual(session.tracks[0].id, old.id)
        await probe.finish(old.url, title: "New callback")
        try await waitForTitle("New callback", in: session, index: 0)
        coordinator.cancel(); session.clearQueue()
    }

    /// Large queues start only two reads, then prioritize a loaded entry beyond the initial 64-cache target window.
    @MainActor func testBoundedWorkersPrioritizeSelectedEntry() async throws {
        /// Probe suspensions expose exact work scheduling rather than relying on native parse timing.
        let probe = MetadataReadProbe()
        /// One hundred distinct paths must not produce one hundred detached jobs or cached thumbnails.
        let session = PlaybackSession(backend: MetadataUIBackend())
        session.enqueue((0..<100).map { URL(fileURLWithPath: "/\($0).wav") })
        /// Injected input URL becomes a controllable suspended request.
        let coordinator = TrackMetadataCoordinator(session: session, read: { url in await probe.read(url) })
        defer { coordinator.cancel(); Task { await probe.finishAll() } }
        coordinator.synchronize(); try await waitForRequests(probe, count: 2)
        /// Initial request snapshot is copied out of the actor before synchronous assertions.
        let initial = await probe.requests
        XCTAssertEqual(initial.count, 2)
        try session.play(index: 90); session.seek(to: 17); session.pause(); coordinator.synchronize()
        await probe.finish(session.tracks[0].url, title: "First")
        try await waitForRequests(probe, count: 3)
        /// Ordered requests reveal that the newly selected entry takes the next freed worker slot.
        let requests = await probe.requests
        /// Peak concurrent operations must remain two while selected-entry priority changes.
        let peak = await probe.peak
        XCTAssertEqual(requests.last, session.tracks[90].url); XCTAssertEqual(peak, 2)
        await probe.finish(session.tracks[90].url, title: "Selected")
        try await waitForTitle("Selected", in: session, index: 90)
        XCTAssertEqual(session.position, 17); XCTAssertEqual(session.state, .paused)
        coordinator.cancel(); await probe.finishAll()
    }

    /// Native and Classic row refreshes retain browse selection, while Track Info follows loaded identity and clears stale art.
    @MainActor func testNativeClassicBrowsingAndTrackInfoFallback() throws {
        _ = NSApplication.shared
        /// Decoder preparation count proves metadata and browsing never activate a different entry.
        let backend = MetadataUIBackend()
        /// First loaded entry and second browsed entry intentionally differ.
        let session = PlaybackSession(backend: backend)
        session.enqueue([URL(fileURLWithPath: "/first.wav"), URL(fileURLWithPath: "/second.wav")])
        try session.resume(); session.seek(to: 18); session.pause()
        /// Native layout/table and shared read-only panel consume the same live session without a background test reader.
        let native = SkinView(theme: try ThemeCatalog.builtin("retro"), session: session)
        /// Independent metadata content makes its fallback/image state directly inspectable.
        let info = TrackInfoView(session: session)
        /// Original Classic package renders actual native queue borders and row controls.
        let package = try ClassicSkinPackage.load(XCTUnwrap(Bundle.module.url(forResource: "playable-classic", withExtension: "wsz", subdirectory: "Fixtures")))
        /// Actual Classic playlist can be refreshed manually without replacing a session observer.
        let classic = try ClassicPlaylistWindowController(package: package, session: session)
        defer { classic.close() }
        native.queueTable?.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        classic.content.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        /// Validated original artwork is downsampled before publication exactly like native reader output.
        let cover = try XCTUnwrap(TrackMetadataReader.thumbnail(MetadataSmokeCheck.artwork()))
        session.cacheMetadata(TrackMetadata(title: "Tagged first", artist: "Artist", album: "Album", artwork: cover), for: session.tracks[0])
        native.refresh(); classic.content.refresh(); info.refresh()
        XCTAssertEqual(native.queueTable?.selectedRow, 1); XCTAssertEqual(classic.content.table.selectedRow, 1)
        XCTAssertEqual(info.titleLabel.stringValue, "Tagged first"); XCTAssertEqual(info.artistLabel.stringValue, "Artist")
        XCTAssertNotNil(info.artworkView.image); XCTAssertTrue(info.artworkPlaceholder.isHidden)
        /// Actual native queue data source exposes the embedded title and artist/album tooltip.
        let cell = native.tableView(try XCTUnwrap(native.queueTable), viewFor: nil, row: 0) as? NSTableCellView
        XCTAssertTrue(cell?.textField?.stringValue.contains("Tagged first") == true)
        XCTAssertEqual(cell?.textField?.toolTip, "Tagged first\nArtist\nAlbum")
        XCTAssertEqual(session.position, 18); XCTAssertEqual(session.state, .paused); XCTAssertEqual(backend.loads, 1)
        try session.play(index: 1); info.refresh()
        XCTAssertEqual(info.titleLabel.stringValue, "second"); XCTAssertEqual(info.artistLabel.stringValue, "Artist unavailable")
        XCTAssertNil(info.artworkView.image); XCTAssertFalse(info.artworkPlaceholder.isHidden)
        session.clearQueue(); info.refresh(); XCTAssertEqual(info.titleLabel.stringValue, "No track selected")
    }

    /// Waits at most three seconds for main-actor jobs to enter the probe; sleeps allow background and UI continuations to run.
    @MainActor private func waitForRequests(_ probe: MetadataReadProbe, count: Int) async throws {
        /// Deadline prevents a broken scheduler from hanging the test process.
        let deadline = Date().addingTimeInterval(3)
        while await probe.requests.count < count, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        /// Completed request count is copied from the actor before XCTest evaluates its assertion.
        let actual = await probe.requests.count
        XCTAssertGreaterThanOrEqual(actual, count)
    }

    /// Waits for an expected identity-bound title without blocking reader publication on the main actor.
    @MainActor private func waitForTitle(_ title: String, in session: PlaybackSession, index: Int) async throws {
        /// Deadline converts a missing callback into an actionable assertion instead of an unbounded wait.
        let deadline = Date().addingTimeInterval(3)
        while session.displayTitle(for: session.tracks[index]) != title, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.displayTitle(for: session.tracks[index]), title)
    }
}
