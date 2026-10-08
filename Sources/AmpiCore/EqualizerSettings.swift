// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Session-owned ten-band equalizer values; gains use decibels and default to bypassed, flat output.
public struct EqualizerSettings: Equatable, Sendable {
    /// Classic nominal center frequencies in hertz, ordered from bass to treble.
    public static let frequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    /// Whether the preamp and all filters process audio; disabling preserves their values.
    public private(set) var isEnabled = false
    /// Overall EQ gain in decibels, bounded to minus twelve through plus twelve.
    public private(set) var preamp: Float = 0
    /// Ten filter gains in decibels, bounded to minus twelve through plus twelve.
    public private(set) var gains: [Float] = Array(repeating: 0, count: frequencies.count)

    /// Creates a flat, bypassed equalizer without affecting playback volume.
    public init() {}

    /// Changes bypass state without clearing the stored curve.
    public mutating func setEnabled(_ enabled: Bool) { isEnabled = enabled }

    /// Stores a finite preamp value, clamping it to the supported decibel range.
    public mutating func setPreamp(_ decibels: Float) {
        guard decibels.isFinite else { return }
        preamp = min(12, max(-12, decibels))
    }

    /// Updates one valid band, ignoring invalid indices and non-finite decibel input.
    public mutating func setGain(_ decibels: Float, at index: Int) {
        guard gains.indices.contains(index), decibels.isFinite else { return }
        gains[index] = min(12, max(-12, decibels))
    }

    /// Applies an original Ampi curve while retaining enabled/bypassed state.
    public mutating func apply(_ preset: EqualizerPreset) {
        preamp = preset.preamp
        gains = preset.gains
    }
}

/// Original starter curves; these are not imported Winamp preset files.
public enum EqualizerPreset: String, CaseIterable, Sendable {
    /// Unity preamp and zero gain on every band.
    case flat = "Flat"
    /// Gentle low-frequency lift with preamp headroom.
    case bass = "Bass"
    /// Reduces low bass and lifts the middle speech range.
    case voice = "Voice"

    /// Preamp attenuation in decibels associated with this curve.
    public var preamp: Float { self == .flat ? 0 : -4 }
    /// Ten original per-band gains in the same order as the nominal frequencies.
    public var gains: [Float] {
        switch self {
        case .flat: return Array(repeating: 0, count: 10)
        case .bass: return [4, 4, 3, 1, 0, 0, 0, 0, 0, 0]
        case .voice: return [-4, -3, -2, 0, 2, 3, 3, 1, 0, -1]
        }
    }
}

/// Optional backend capability; a session never advertises functional EQ for an incapable backend.
@MainActor public protocol EqualizerAudioBackend: AudioBackend {
    /// Applies bounded session settings without seeking or restarting output.
    func applyEqualizer(_ settings: EqualizerSettings)
}
