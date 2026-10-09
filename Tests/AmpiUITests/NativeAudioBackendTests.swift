// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AVFAudio
import AmpiCore
import XCTest
@testable import Ampi

/// Verifies actual Apple decoder seek semantics without starting audible output.
final class NativeAudioBackendTests: XCTestCase {
    /// Actual Repeat One schedules the full source again, then stops when Off is selected at the next completion.
    @MainActor func testMutedRepeatOneReplaysWholeDecoder() async throws {
        /// Original quarter-second source makes an erroneous last-sample-only loop distinguishable by elapsed time.
        let url = try Self.tone(seconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        /// Native output graph is muted throughout the completion loop.
        let backend = NativeAudioBackend()
        /// One queue identity must remain selected for both full-length completions.
        let session = PlaybackSession(backend: backend)
        defer { session.stop() }
        session.setVolume(0); session.enqueue([url]); session.setRepeatMode(.one)
        /// Callback timestamps measure the replay duration rather than initial device startup latency.
        var completions: [Date] = []
        backend.onFinish = { [weak session] success in
            completions.append(Date())
            if completions.count == 2 { session?.setRepeatMode(.off) }
            session?.finished(successfully: success)
        }
        try session.resume()
        /// Bounded main-actor suspension allows actual data-played-back callbacks to advance the model.
        let deadline = Date().addingTimeInterval(4)
        while completions.count < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(completions.count, 2)
        if completions.count == 2 { XCTAssertGreaterThan(completions[1].timeIntervalSince(completions[0]), 0.18) }
        XCTAssertEqual(session.state, .stopped); XCTAssertEqual(session.selectedIndex, 0)
        XCTAssertEqual(session.position, 0); XCTAssertEqual(session.volume, 0)
    }

    /// Native completion visits each duplicate identity once per shuffle cycle and safely stops when repeat is disabled.
    @MainActor func testMutedShuffleRepeatAllCompletesTwoCycles() async throws {
        /// Original stereo file exercises real rescheduling across duplicate queue identities.
        let url = try Self.tone(seconds: 0.2, channels: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        /// Real engine/EQ graph remains muted and retains the curve across every load.
        let backend = NativeAudioBackend()
        /// Three duplicate entries form two identity-based cycles.
        let session = PlaybackSession(backend: backend)
        defer { session.stop() }
        session.setVolume(0); session.enqueue([url, url, url])
        session.setShuffleEnabled(true); session.setRepeatMode(.all)
        session.setEqualizerEnabled(true); session.applyEqualizerPreset(.voice)
        /// Completed identity list exposes repeated/skipped entries independently from decoder URLs.
        var completed: [UUID] = []
        backend.onFinish = { [weak session] success in
            /// Record the completed selection before automatic advancement replaces it.
            if let identity = session?.currentTrack?.id { completed.append(identity) }
            if completed.count == 6 { session?.setRepeatMode(.off) }
            session?.finished(successfully: success)
        }
        try session.resume()
        /// Six short tracks plus device latency fit comfortably inside this bounded asynchronous wait.
        let deadline = Date().addingTimeInterval(5)
        while completed.count < 6, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(completed.count, 6)
        XCTAssertEqual(Set(completed.prefix(3)), Set(session.tracks.map(\.id)))
        XCTAssertEqual(Set(completed.suffix(3)), Set(session.tracks.map(\.id)))
        if completed.count == 6 { XCTAssertNotEqual(completed[2], completed[3]) }
        XCTAssertEqual(session.state, .stopped); XCTAssertEqual(session.volume, 0)
        XCTAssertTrue(session.equalizer.isEnabled); XCTAssertEqual(session.equalizer.gains, EqualizerPreset.voice.gains)
    }

    /// Real completion follows edited order, skipping a removed neighbor without restarting the loaded stream.
    @MainActor func testMutedCompletionFollowsReorderedQueue() async throws {
        /// Short original mono file supplies three independently identified entries.
        let url = try Self.tone(seconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        /// Actual device graph remains muted while queue identities change.
        let backend = NativeAudioBackend()
        /// Shared queue drives real completion after its order is edited.
        let session = PlaybackSession(backend: backend)
        defer { session.stop() }
        session.setVolume(0); session.enqueue([url, url, url])
        /// Original identities identify the expected loaded entry and its new successor.
        let identities = session.tracks.map(\.id)
        /// Completed identities are recorded before the session advances the queue.
        var completed: [UUID] = []
        backend.onFinish = { [weak session] success in
            /// Current entry remains loaded until the callback asks the model to advance.
            if let identity = session?.currentTrack?.id { completed.append(identity) }
            session?.finished(successfully: success)
        }
        try session.resume()
        session.moveTrack(from: 0, to: 1)
        session.removeTrack(at: 0)
        XCTAssertEqual(session.currentTrack?.id, identities[0]); XCTAssertEqual(session.selectedIndex, 0)
        /// Bounded wait includes device latency without blocking main-actor completion callbacks.
        let deadline = Date().addingTimeInterval(4)
        while completed.count < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(completed, [identities[0], identities[2]])
        XCTAssertEqual(session.state, .stopped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    /// Clearing and immediately loading a new queue must reject the old stream's cancellation callback.
    @MainActor func testMutedClearAndRequeueRejectsOldCompletion() async throws {
        /// Short original source makes spurious advancement observable within one second.
        let url = try Self.tone(seconds: 0.25)
        defer { try? FileManager.default.removeItem(at: url) }
        /// Actual backend owns cancellation generations during clear and reload.
        let backend = NativeAudioBackend()
        /// New queue must finish exactly once after old entries are cleared.
        let session = PlaybackSession(backend: backend)
        defer { session.stop() }
        session.setVolume(0); session.setEqualizerEnabled(true); session.applyEqualizerPreset(.bass)
        /// Played-back callbacks counted independently from the selected entry.
        var completions = 0
        backend.onFinish = { [weak session] success in completions += 1; session?.finished(successfully: success) }
        session.enqueue([url, url]); try session.resume()
        session.clearQueue(); session.enqueue([url]); try session.resume()
        /// Main actor stays available while the new entry reaches device output completion.
        let deadline = Date().addingTimeInterval(4)
        while completions < 1, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(completions, 1); XCTAssertEqual(session.state, .stopped)
        XCTAssertEqual(session.tracks.count, 1); XCTAssertEqual(session.selectedIndex, 0)
        XCTAssertEqual(session.equalizer.gains, EqualizerPreset.bass.gains)
        XCTAssertEqual(session.volume, 0)
    }
    /// Writes original floating-point tones for muted device checks; seconds sets duration, channels is one or two.
    @MainActor private static func tone(seconds: Double, channels: AVAudioChannelCount = 1) throws -> URL {
        /// Unique native CAF file, removed by the calling test.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        /// Mono or stereo 44.1-kHz source format used by the decoder and engine.
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: channels))
        /// Finite source buffer whose length matches the requested duration.
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(seconds * 44_100)))
        buffer.frameLength = buffer.frameCapacity
        /// Each native channel contains an independently synthesized frequency to exercise stereo routing.
        for channel in 0..<Int(channels) {
            /// Writable sample storage for this noninterleaved channel.
            let samples = try XCTUnwrap(buffer.floatChannelData)[channel]
            /// Each decoded frame is a quiet original sine sample, with a different tone in each channel.
            for index in 0..<Int(buffer.frameLength) {
                samples[index] = Float(0.05 * sin(2 * .pi * Double(440 + channel * 220) * Double(index) / 44_100))
            }
        }
        /// Native writer creates a decoder-compatible CAF stream.
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    /// Engine clock freezes on pause, seeking retains state, and canceled schedules cannot finish a new stream.
    @MainActor func testMutedClockPauseSeekStopAndCorruptReplacement() async throws {
        /// One-second source leaves enough time for pause and schedule cancellation before natural completion.
        let url = try Self.tone(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        /// Real device output stays muted for the entire integration check.
        let backend = NativeAudioBackend()
        defer { backend.stop() }
        backend.volume = 0
        /// Completion count detects spurious events from seeks and stops.
        var completions = 0
        backend.onFinish = { _ in completions += 1 }
        try backend.load(url); XCTAssertTrue(backend.play())
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThan(backend.position, 0.05)
        backend.pause()
        /// Frozen file time remains unchanged while the engine is suspended.
        let paused = backend.position
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(backend.position, paused, accuracy: 0.001)
        backend.position = 0.4
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(backend.position, 0.4, accuracy: 0.001)
        XCTAssertTrue(backend.play())
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(backend.position, 0.42)
        XCTAssertThrowsError(try backend.load(url.appendingPathExtension("missing")))
        XCTAssertEqual(backend.duration, 1, accuracy: 0.001)
        XCTAssertGreaterThan(backend.position, 0.42)
        backend.stop()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(backend.position, 0); XCTAssertEqual(completions, 0)
        XCTAssertTrue(backend.play()); backend.position = 0.98
        /// Bounded asynchronous wait includes native device latency while allowing main-actor callbacks.
        let deadline = Date().addingTimeInterval(3)
        while completions == 0, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(completions, 1)
    }

    /// Real played-back completions advance exactly once per queue entry and stop at the queue end.
    @MainActor func testMutedNativeCompletionAdvancesQueue() async throws {
        /// Short original stereo tone exercises two-channel routing and two natural completions.
        let url = try Self.tone(seconds: 0.25, channels: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        /// Actual graph exercises callback generations across track replacement.
        let backend = NativeAudioBackend()
        /// Session retains EQ settings while automatic advancement prepares a new graph.
        let session = PlaybackSession(backend: backend)
        defer { session.stop() }
        session.setVolume(0); session.setEqualizerEnabled(true); session.applyEqualizerPreset(.voice)
        /// Completed entries counted independently from the queue's selected index.
        var completions = 0
        backend.onFinish = { [weak session] success in
            completions += 1; session?.finished(successfully: success)
        }
        session.enqueue([url, url]); try session.resume()
        /// Bounded wait yields the main actor so native completion tasks can advance playback.
        let deadline = Date().addingTimeInterval(4)
        while completions < 2, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(completions, 2); XCTAssertEqual(session.selectedIndex, 1)
        XCTAssertEqual(session.state, .stopped); XCTAssertEqual(session.position, 0)
        XCTAssertEqual(session.equalizer.gains, EqualizerPreset.voice.gains)
    }
    /// Encodes a fixed little-endian integer for the original PCM WAV header.
    private func integer(_ value: UInt32) -> Data {
        /// Native word converted to the byte order required by RIFF/WAVE.
        var littleEndian = value.littleEndian
        /// Closure bytes are the converted word's temporary buffer, copied into owned data.
        return withUnsafeBytes(of: &littleEndian) { bytes in Data(bytes) }
    }

    /// Exact-end seek must stay near the end rather than silently wrapping to the start.
    func testNativeSeekClampsToLastSample() async throws {
        /// Unique temporary one-second, mono 8-kHz, 16-bit silent PCM fixture.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        /// Original RIFF header followed by zero samples; no copyrighted audio is used.
        var data = Data("RIFF".utf8)
        data.append(integer(36 + 16_000)); data.append(Data("WAVEfmt ".utf8))
        data.append(integer(16)); data.append(contentsOf: [1, 0, 1, 0])
        data.append(integer(8_000)); data.append(integer(16_000))
        data.append(contentsOf: [2, 0, 16, 0]); data.append(Data("data".utf8))
        data.append(integer(16_000)); data.append(Data(repeating: 0, count: 16_000))
        try data.write(to: url)
        try await MainActor.run {
            /// Real native decoder, prepared but never played by this test.
            let backend = NativeAudioBackend()
            try backend.load(url)
            XCTAssertEqual(backend.duration, 1, accuracy: 0.001)
            backend.position = backend.duration
            XCTAssertGreaterThan(backend.position, 0.99)
            XCTAssertLessThan(backend.position, backend.duration)
            backend.position = 99
            XCTAssertGreaterThan(backend.position, 0.99)
            backend.position = .nan
            XCTAssertGreaterThan(backend.position, 0.99)
            backend.position = -10
            XCTAssertEqual(backend.position, 0)
        }
    }
}
