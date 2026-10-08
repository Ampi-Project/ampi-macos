// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import AmpiCore

/// Records DSP delivery independently of the real native engine to test session ownership and bounds.
@MainActor private final class EqualizerTestBackend: EqualizerAudioBackend {
    /// Fixed fake track duration in seconds.
    var duration: Double = 100
    /// Fake transport offset retained while the EQ changes.
    var position: Double = 0
    /// Independent output gain, unaffected by preamp edits.
    var volume: Float = 0.7
    /// Last curve delivered synchronously by the session.
    var settings = EqualizerSettings()
    /// Whether fake transport is advancing.
    var playing = false
    /// Accepts any local fixture URL without modifying DSP values.
    func load(_ url: URL) throws { position = 0 }
    /// Starts fake output for transport preservation assertions.
    func play() -> Bool { playing = true; return true }
    /// Pauses fake output without changing the position.
    func pause() { playing = false }
    /// Stops and rewinds fake output.
    func stop() { playing = false; position = 0 }
    /// Records the curve delivered to the backend.
    func applyEqualizer(_ settings: EqualizerSettings) { self.settings = settings }
}

/// Verifies bounded curves, bypass retention, observer delivery, and independence from transport.
final class EqualizerTests: XCTestCase {
    /// Non-finite inputs and invalid indices never corrupt the fixed ten-band state.
    func testGainBoundsAndInvalidInput() {
        /// Value under test starts flat and bypassed.
        var settings = EqualizerSettings()
        settings.setGain(50, at: 0); settings.setGain(-50, at: 9)
        settings.setPreamp(99)
        XCTAssertEqual(settings.gains[0], 12); XCTAssertEqual(settings.gains[9], -12)
        XCTAssertEqual(settings.preamp, 12)
        settings.setGain(.nan, at: 0); settings.setGain(.infinity, at: 4)
        settings.setGain(4, at: -1); settings.setGain(4, at: 10); settings.setPreamp(-.infinity)
        XCTAssertEqual(settings.gains.count, 10); XCTAssertEqual(settings.gains[4], 0)
        XCTAssertEqual(settings.gains[0], 12); XCTAssertEqual(settings.preamp, 12)
        settings.setPreamp(-99); XCTAssertEqual(settings.preamp, -12)
    }

    /// EQ mutations deliver synchronously while position, output volume, and selected track remain stable.
    func testSessionRetainsCurveAcrossTransportAndTracks() async throws {
        try await MainActor.run {
            /// Capable backend records all settings applied by the session.
            let backend = EqualizerTestBackend()
            /// Persistent playback model, independent of its UI.
            let session = PlaybackSession(backend: backend)
            session.enqueue([URL(fileURLWithPath: "/one.wav"), URL(fileURLWithPath: "/two.wav")])
            try session.play(index: 0); session.seek(to: 23)
            /// Number of synchronous model changes emitted during EQ edits.
            var notifications = 0
            session.onChange = { notifications += 1 }
            session.setEqualizerEnabled(true)
            session.setEqualizerGain(-8, at: 5); session.setEqualizerPreamp(-3)
            XCTAssertEqual(notifications, 3)
            XCTAssertEqual(backend.settings, session.equalizer)
            XCTAssertEqual(session.position, 23); XCTAssertEqual(session.volume, 0.7)
            XCTAssertTrue(backend.playing); XCTAssertEqual(session.selectedIndex, 0)
            session.setEqualizerEnabled(false)
            XCTAssertEqual(session.equalizer.gains[5], -8)
            session.pause(); session.stop(); try session.next()
            XCTAssertEqual(session.equalizer.preamp, -3)
            XCTAssertEqual(backend.settings.gains[5], -8)
            XCTAssertFalse(backend.settings.isEnabled)
            session.applyEqualizerPreset(.bass)
            XCTAssertEqual(session.equalizer.gains, EqualizerPreset.bass.gains)
            XCTAssertFalse(session.equalizer.isEnabled)
            session.applyEqualizerPreset(.flat)
            XCTAssertEqual(session.equalizer.preamp, 0)
            XCTAssertEqual(session.equalizer.gains, Array(repeating: 0, count: 10))
        }
    }
}
