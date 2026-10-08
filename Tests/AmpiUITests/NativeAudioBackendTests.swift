// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import AVFAudio
import AmpiCore
import XCTest
@testable import Ampi

/// Verifies actual Apple decoder seek semantics without starting audible output.
final class NativeAudioBackendTests: XCTestCase {
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
