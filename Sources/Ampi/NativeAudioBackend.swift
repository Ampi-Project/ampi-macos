// SPDX-License-Identifier: GPL-3.0-only
import AVFAudio
import AmpiCore
import Foundation

/// Adapts AVAudioPlayer to the session, delivering completion callbacks on the main actor.
@MainActor final class NativeAudioBackend: NSObject, AudioBackend, AVAudioPlayerDelegate {
    /// Prepared native player for the current track, or nil before the first load.
    private var player: AVAudioPlayer?
    /// Gain retained between track loads, initially 70 percent.
    private var outputVolume: Float = 0.7
    /// Main-actor completion handler; true indicates normal completion, false a failure.
    var onFinish: ((Bool) -> Void)?

    /// Loaded track length in seconds, or zero when no native player exists.
    var duration: Double { player?.duration ?? 0 }
    /// Loaded track offset in seconds; writes seek through AVAudioPlayer.
    var position: Double {
        get { player?.currentTime ?? 0 }
        set { player?.currentTime = newValue }
    }
    /// Retained gain applied to the current player and subsequent replacements.
    /// The session clamps writes to the zero-through-one range.
    var volume: Float {
        get { outputVolume }
        set { outputVolume = newValue; player?.volume = newValue }
    }

    /// Prepares a replacement before stopping the current player, preserving it on failure.
    /// - Parameter url: Local audio file to decode.
    /// - Throws: A decoding/file error or `PlaybackError.couldNotStart`.
    func load(_ url: URL) throws {
        /// Candidate player whose preparation must succeed before replacing active output.
        let replacement = try AVAudioPlayer(contentsOf: url)
        guard replacement.prepareToPlay() else { throw PlaybackError.couldNotStart }
        replacement.volume = outputVolume
        replacement.delegate = self
        player?.stop()
        player = replacement
    }

    /// Starts or resumes native output; returns false when unloaded or output cannot start.
    func play() -> Bool { player?.play() ?? false }
    /// Pauses native output without rewinding the track.
    func pause() { player?.pause() }
    /// Stops native output and rewinds the track to zero seconds.
    func stop() { player?.stop(); player?.currentTime = 0 }

    /// Forwards completion to the main actor only if the finishing player is still current.
    /// - Parameters:
    ///   - player: Native player that emitted the completion callback.
    ///   - flag: Whether playback reached the end successfully.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        /// Sendable identity used to reject callbacks from a replaced native player.
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            /// Retained adapter and current player, present only while this callback is relevant.
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.onFinish?(flag)
        }
    }

    /// Reports decoding failure on the main actor, ignoring callbacks from replaced players.
    /// - Parameters:
    ///   - player: Native player that encountered the decoding failure.
    ///   - error: Optional system diagnostic; the session currently presents a general message.
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        /// Sendable identity used to verify that the failed player remains current.
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            /// Retained adapter and current player, checked before notifying the session.
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.onFinish?(false)
        }
    }
}
