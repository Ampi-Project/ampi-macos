// SPDX-License-Identifier: GPL-3.0-only
import AVFAudio
import AmpiCore
import Foundation

/// Configures the same native ten-band audio unit used for device playback and offline verification.
@MainActor final class NativeEqualizerProcessor {
    /// Apple DSP node inserted before the output mixer and its volume control.
    let unit = AVAudioUnitEQ(numberOfBands: EqualizerSettings.frequencies.count)

    /// Sets one-octave parametric bands; centers at or above Nyquist are bypassed for low-rate files.
    /// - Parameters: settings contains bounded decibel values; sampleRate is decoded frames per second.
    init(settings: EqualizerSettings, sampleRate: Double) { apply(settings, sampleRate: sampleRate) }

    /// Changes DSP parameters in place; disabling bypasses both preamp and band processing.
    func apply(_ settings: EqualizerSettings, sampleRate: Double) {
        unit.bypass = !settings.isEnabled
        unit.globalGain = settings.preamp
        /// Each index connects a nominal frequency and bounded gain to its native filter.
        for (index, band) in unit.bands.enumerated() {
            /// Nominal center in hertz; an unrepresentable band remains stored but has no audio effect.
            let frequency = EqualizerSettings.frequencies[index]
            band.filterType = .parametric
            band.frequency = min(frequency, Float(sampleRate * 0.49))
            band.bandwidth = 1
            band.gain = settings.gains[index]
            band.bypass = Double(frequency) >= sampleRate / 2
        }
    }
}

/// Prepared per-track graph, built before the active graph is replaced on the main actor.
@MainActor private final class NativeAudioGraph {
    /// Streaming decoder, retained until its scheduled segments finish or are canceled.
    let file: AVAudioFile
    /// Native device engine; mixer performs conversion to the device's output format.
    let engine = AVAudioEngine()
    /// Source node whose player clock excludes paused intervals.
    let player = AVAudioPlayerNode()
    /// Equalizer between source and mixer; never owned by a skin window.
    let equalizer: NativeEqualizerProcessor

    /// Opens and probes the decoder, then prepares a graph without starting output.
    /// - Throws: File/decoder errors or a diagnostic for empty/unsupported PCM output.
    init(url: URL, settings: EqualizerSettings, volume: Float) throws {
        file = try AVAudioFile(forReading: url)
        /// Native floating-point decoded format used by the player and filters.
        let format = file.processingFormat
        /// Accepted mono/stereo PCM profile and an allocated probe buffer prevent unsupported native graph setup.
        guard file.length > 0, format.sampleRate >= 1_000, (1...2).contains(format.channelCount),
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              let probe = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024) else {
            throw PlaybackError.unsupportedDecodedFormat
        }
        try file.read(into: probe)
        guard probe.frameLength > 0 else { throw PlaybackError.couldNotStart }
        file.framePosition = 0
        equalizer = NativeEqualizerProcessor(settings: settings, sampleRate: format.sampleRate)
        engine.attach(player)
        engine.attach(equalizer.unit)
        engine.connect(player, to: equalizer.unit, format: format)
        engine.connect(equalizer.unit, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = volume
        engine.prepare()
    }
}

/// Streams local files through AVAudioEngine and ten-band DSP, independent of presentation.
@MainActor final class NativeAudioBackend: EqualizerAudioBackend {
    /// Prepared native graph, or nil before the first successful load.
    private var graph: NativeAudioGraph?
    /// Retained output gain, independent of the EQ preamp, initially seventy percent.
    private var outputVolume: Float = 0.7
    /// Most recent session curve, also applied to replacement tracks.
    private var settings = EqualizerSettings()
    /// Offset saved during pauses, stops, and seeks, measured in decoded file frames.
    private var offset: AVAudioFramePosition = 0
    /// File frame at player-clock zero for the currently scheduled segments.
    private var scheduledStart: AVAudioFramePosition = 0
    /// Whether segments remain scheduled, including while the source is paused.
    private var scheduled = false
    /// Whether output is advancing; paused and stopped positions use the saved offset.
    private var playing = false
    /// Monotonically changed token rejects completion from replaced or canceled schedules.
    private var generation: UInt64 = 0
    /// Main-actor end handler, invoked after the last segment is played through the device.
    var onFinish: ((Bool) -> Void)?

    /// Loaded decoded duration in seconds, or zero before loading.
    var duration: Double {
        /// Loaded decoder supplies length and sample rate without loading the full file into memory.
        guard let graph else { return 0 }
        return Double(graph.file.length) / graph.file.processingFormat.sampleRate
    }

    /// Current offset in seconds; seeks retain playing/paused state and clamp to the last sample.
    var position: Double {
        get {
            /// Available graph defines the file time base.
            guard let graph else { return 0 }
            /// Saved frame remains authoritative whenever the source is not advancing.
            var frame = offset
            /// Native source clock excludes pauses and starts at zero after unscheduling.
            if playing, let render = graph.player.lastRenderTime,
               let time = graph.player.playerTime(forNodeTime: render), time.isSampleTimeValid {
                frame = scheduledStart + max(0, time.sampleTime)
            }
            return Double(min(graph.file.length, max(0, frame))) / graph.file.processingFormat.sampleRate
        }
        set {
            /// Seeking requires a loaded file and finite seconds.
            guard let graph, newValue.isFinite else { return }
            /// Desired decoded frame, clamped before conversion to avoid overflow on huge input.
            let frame = AVAudioFramePosition(min(Double(graph.file.length - 1),
                max(0, newValue * graph.file.processingFormat.sampleRate)))
            /// Active output resumes after rescheduling; a paused seek stays paused.
            let resume = playing
            cancelSchedule()
            offset = frame
            if resume { _ = play() }
        }
    }

    /// Gain from zero through one, applied after equalization and retained between track loads.
    var volume: Float {
        get { outputVolume }
        set {
            guard newValue.isFinite else { return }
            outputVolume = min(1, max(0, newValue))
            graph?.engine.mainMixerNode.outputVolume = outputVolume
        }
    }

    /// Prepares a candidate decoder/graph before stopping the current stream; failure preserves it.
    func load(_ url: URL) throws {
        /// Candidate owns no active output until preparation succeeds.
        let replacement = try NativeAudioGraph(url: url, settings: settings, volume: outputVolume)
        cancelSchedule()
        graph?.engine.stop()
        graph = replacement
        offset = 0
    }

    /// Starts or resumes output, returning false if unloaded or the audio device cannot start.
    func play() -> Bool {
        /// Valid prepared graph is required; repeated play is an idempotent operation.
        guard let graph else { return false }
        if playing { return true }
        do {
            if !graph.engine.isRunning { try graph.engine.start() }
            if !scheduled { schedule(graph) }
            graph.player.play()
            playing = true
            return true
        } catch { graph.engine.pause(); return false }
    }

    /// Saves the player-clock position, pauses output, and keeps the schedule for a later resume.
    func pause() {
        /// Only advancing output needs to capture a new file offset.
        guard playing, let graph else { return }
        offset = AVAudioFramePosition((position * graph.file.processingFormat.sampleRate).rounded())
        graph.player.pause()
        graph.engine.pause()
        playing = false
    }

    /// Cancels completion events, stops output, and rewinds while retaining decoder and EQ values.
    func stop() { cancelSchedule(); offset = 0 }

    /// Updates live DSP and future tracks without rebuilding the graph or resetting its clock.
    func applyEqualizer(_ settings: EqualizerSettings) {
        self.settings = settings
        /// Loaded processor uses the decoded sample rate to bypass centers beyond Nyquist.
        if let graph { graph.equalizer.apply(settings, sampleRate: graph.file.processingFormat.sampleRate) }
    }

    /// Invalidates callbacks before unscheduling, because native stop may deliver old completions.
    private func cancelSchedule() {
        generation &+= 1
        playing = false
        scheduled = false
        graph?.player.stop()
        graph?.engine.pause()
    }

    /// Schedules the remaining file, splitting exceptionally long streams into UInt32 frame segments.
    /// Completion hops to the main actor before stopping nodes, avoiding callback-thread deadlocks.
    private func schedule(_ graph: NativeAudioGraph) {
        scheduledStart = min(graph.file.length - 1, max(0, offset))
        offset = scheduledStart
        scheduled = true
        /// Token identifies precisely this schedule, including seeks within the same file.
        let token = generation
        /// Next undecoded file frame to enqueue, initially the seek target.
        var start = scheduledStart
        /// Each chunk fits Apple's segment frame-count representation; only the last notifies the session.
        while start < graph.file.length {
            /// Size of this contiguous segment in decoded frames.
            let count = AVAudioFrameCount(min(graph.file.length - start, AVAudioFramePosition(UInt32.max)))
            /// Final segment owns the played-back completion, not the earlier decoding notification.
            let final = start + AVAudioFramePosition(count) == graph.file.length
            graph.player.scheduleSegment(graph.file, startingFrame: start, frameCount: count, at: nil,
                                         completionCallbackType: .dataPlayedBack) { [weak self] _ in
                if final {
                    Task { @MainActor [weak self] in
                        /// Current schedule alone may advance the session's queue.
                        guard let self, self.generation == token, self.scheduled else { return }
                        self.playing = false
                        self.scheduled = false
                        self.offset = self.graph?.file.length ?? 0
                        self.generation &+= 1
                        self.graph?.player.stop()
                        self.graph?.engine.pause()
                        self.onFinish?(true)
                    }
                }
            }
            start += AVAudioFramePosition(count)
        }
    }
}
