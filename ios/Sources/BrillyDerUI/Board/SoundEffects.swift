import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

public enum ChessSoundCue: Hashable, CaseIterable, Sendable {
    case move
    case capture
    case brilliant
    case blunder
    case sonar
}

/// Lightweight zero-asset procedural sound engine using AVAudioEngine (obeys iOS silent switch via .ambient).
/// Fully lazy-initialized (never starts audio hardware on app launch), pre-caches all 5 PCM buffers,
/// guards against sampleRate == 0 hardware transitions, and recovers safely from interruptions/route changes.
@MainActor
public final class BrillySoundEngine {
    public static let shared = BrillySoundEngine()

    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private var format: AVAudioFormat?
    private var buffers: [ChessSoundCue: AVAudioPCMBuffer] = [:]
    private var isConnected = false
    private var hasPrewarmed = false
    private var observers: [NSObjectProtocol] = []
    #endif

    private init() {
        #if canImport(AVFoundation)
        self.format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        registerLifecycleObservers()
        #endif
    }

    public func play(_ cue: ChessSoundCue) {
        #if canImport(AVFoundation)
        guard let format else { return }
        if !hasPrewarmed {
            prewarmBuffers(format: format)
            hasPrewarmed = true
        }
        guard let buffer = buffers[cue] else { return }

        // Guard against iOS audio hardware transition where outputNode reports 0 Hz (prevents NSException!)
        let hwFormat = engine.outputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 else { return }

        if !isConnected {
            setupGraph(format: format)
        }
        guard isConnected else { return }

        if !engine.isRunning {
            engine.prepare()
            do {
                try engine.start()
            } catch {
                isConnected = false
                return
            }
        }
        guard engine.isRunning else { return }

        if !player.isPlaying {
            player.play()
        }
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        #endif
    }

    public func pause() {
        #if canImport(AVFoundation)
        guard isConnected else { return }
        if player.isPlaying {
            player.stop()
        }
        if engine.isRunning {
            engine.pause()
        }
        #endif
    }

    /// Marks audio graph ready for lazy restart on the next sound cue (never starts hardware eagerly at launch).
    public func resumeIfNeeded() {
        // Intentionally lazy: audio engine restarts cleanly on the next play(_:) call once hardware is active.
    }

    #if canImport(AVFoundation)
    private func setupGraph(format: AVAudioFormat) {
        if !engine.attachedNodes.contains(player) {
            engine.attach(player)
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isConnected = true
    }

    private func invalidateGraph() {
        if isConnected {
            player.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        isConnected = false
    }

    private func registerLifecycleObservers() {
        let nc = NotificationCenter.default
        let configObs = nc.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Never mutate/reconnect inside the config notification; rebuild lazily on next play().
                self?.isConnected = false
            }
        }
        observers.append(configObs)

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let interruptObs = nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            let typeVal = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in
                if typeVal == AVAudioSession.InterruptionType.began.rawValue {
                    self?.pause()
                } else if typeVal == AVAudioSession.InterruptionType.ended.rawValue {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self?.isConnected = false
                }
            }
        }
        observers.append(interruptObs)

        let resetObs = nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
                self?.invalidateGraph()
            }
        }
        observers.append(resetObs)
        #endif
    }

    private func prewarmBuffers(format: AVAudioFormat) {
        let specs: [(ChessSoundCue, [Double], Double, Float, Double)] = [
            (.move, [240], 0.055, 0.22, 38),
            (.capture, [310, 175], 0.085, 0.28, 26),
            (.brilliant, [587.33, 880.0, 1174.66], 0.36, 0.20, 7.5),
            (.blunder, [130.81, 98.0], 0.28, 0.26, 9.0),
            (.sonar, [740.0], 0.16, 0.16, 16),
        ]
        for (cue, freqs, duration, gain, decay) in specs {
            if let buf = synthesizeTone(freqs: freqs, duration: duration, gain: gain, decay: decay, format: format) {
                buffers[cue] = buf
            }
        }
    }

    private func synthesizeTone(
        freqs: [Double],
        duration: Double,
        gain: Float,
        decay: Double,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        let scale = gain / Float(max(1, freqs.count))

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let env = Float(exp(-decay * t)) * Float(min(1.0, t / 0.004))
            var sum: Double = 0
            for f in freqs {
                sum += sin(2.0 * .pi * f * t)
            }
            channel[i] = Float(sum) * scale * env
        }
        return buffer
    }
    #endif
}
