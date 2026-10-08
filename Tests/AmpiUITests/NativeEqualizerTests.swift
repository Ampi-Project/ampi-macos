// SPDX-License-Identifier: GPL-3.0-only
import AVFAudio
import AmpiCore
import XCTest
@testable import Ampi

/// Measures real native DSP output instead of only asserting stored node parameters.
final class NativeEqualizerTests: XCTestCase {
    /// Offline mono tone RMS after the native processor, discarding the first quarter for filter settling.
    /// - Parameters: settings contains the curve; frequency is the source tone in hertz.
    @MainActor private static func rms(_ settings: EqualizerSettings, frequency: Double = 1_000) throws -> Double {
        /// Fixed sample rate supports all nominal EQ centers.
        let rate = 48_000.0
        /// Half-second original tone, kept well below clipping even at maximum supported gain.
        let frames: AVAudioFrameCount = 24_000
        /// Noninterleaved floating-point signal format also used in actual playback graphs.
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        /// Original signal buffer supplied to the player node.
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        input.frameLength = frames
        /// Writable mono samples owned by the input buffer.
        let samples = try XCTUnwrap(input.floatChannelData)[0]
        /// Each sample represents the same phase-continuous, original sine tone.
        for index in 0..<Int(frames) { samples[index] = Float(0.05 * sin(2 * .pi * frequency * Double(index) / rate)) }
        /// Offline engine and source use the production DSP class without a hardware output stream.
        let engine = AVAudioEngine()
        /// Native source node scheduled once for this measurement.
        let player = AVAudioPlayerNode()
        /// Exact processor construction and parameter application used by NativeAudioBackend.
        let processor = NativeEqualizerProcessor(settings: settings, sampleRate: rate)
        engine.attach(player); engine.attach(processor.unit)
        engine.connect(player, to: processor.unit, format: format)
        engine.connect(processor.unit, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
        player.scheduleBuffer(input)
        try engine.start(); player.play()
        defer { player.stop(); engine.stop() }
        /// Reusable output buffer limits memory and matches the native renderer's maximum block size.
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024))
        /// Number of frames successfully rendered so far.
        var rendered = 0
        /// Sum of squared settled output samples for RMS measurement.
        var sum = 0.0
        /// Count of settled samples contributing to the RMS.
        var count = 0
        /// Retry budget prevents a stalled engine from hanging the suite.
        var attempts = 0
        /// Each block is rendered through the audio unit's actual filtering code.
        while rendered < Int(frames), attempts < 100 {
            attempts += 1
            /// Requested block fits both the output buffer and remaining tone duration.
            let requested = AVAudioFrameCount(min(1_024, Int(frames) - rendered))
            /// Native offline status reports whether audio samples are available.
            let result = try engine.renderOffline(requested, to: output)
            guard result == .success else { continue }
            /// Real filtered mono output samples; count is restricted to the returned frame length.
            let values = try XCTUnwrap(output.floatChannelData)[0]
            /// Settled samples omit the tone's startup and the filter's transient response.
            for index in 0..<Int(output.frameLength) where rendered + index >= Int(frames) / 4 {
                XCTAssertTrue(values[index].isFinite)
                sum += Double(values[index]) * Double(values[index]); count += 1
            }
            rendered += Int(output.frameLength)
        }
        XCTAssertEqual(rendered, Int(frames)); XCTAssertGreaterThan(count, 0)
        return sqrt(sum / Double(max(1, count)))
    }

    /// A minus-twelve-decibel center cut attenuates a 1-kHz tone by approximately four times.
    func testNativeBandCutAndBypassAreAudibleInRenderedSamples() async throws {
        try await MainActor.run {
            /// Baseline curve with the effect enabled and all gains at unity.
            var settings = EqualizerSettings()
            settings.setEnabled(true)
            /// Real flat response for the original mono tone.
            let flat = try Self.rms(settings)
            settings.setGain(-12, at: 5)
            /// Measured center-band attenuation, independent of output volume.
            let cut = try Self.rms(settings)
            XCTAssertGreaterThan(flat, 0.03)
            XCTAssertEqual(cut / flat, pow(10, -12.0 / 20), accuracy: 0.04)
            settings.setPreamp(-6); settings.setEnabled(false)
            /// Whole-unit bypass must also bypass preamp while retaining the stored curve.
            let bypassed = try Self.rms(settings)
            XCTAssertEqual(bypassed / flat, 1, accuracy: 0.01)
        }
    }

    /// Preamp attenuation has the expected decibel ratio and a band cut remains frequency-selective.
    func testPreampAndFrequencySelectivity() async throws {
        try await MainActor.run {
            /// Unity baseline used for both gain and selectivity measurements.
            var settings = EqualizerSettings()
            settings.setEnabled(true)
            /// Reference tone level before any attenuation.
            let flat = try Self.rms(settings)
            settings.setPreamp(-6)
            /// Half-amplitude response expected from minus six decibels.
            let quieter = try Self.rms(settings)
            XCTAssertEqual(quieter / flat, pow(10, -6.0 / 20), accuracy: 0.01)
            settings.setPreamp(0); settings.setGain(-12, at: 0)
            /// Cutting 31 Hz must leave a distant 1-kHz tone essentially unchanged.
            let distantCut = try Self.rms(settings)
            XCTAssertEqual(distantCut / flat, 1, accuracy: 0.02)
        }
    }
}
