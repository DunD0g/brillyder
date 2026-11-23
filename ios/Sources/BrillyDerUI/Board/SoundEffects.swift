import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

public enum ChessSoundCue: Sendable {
    case move
    case capture
    case brilliant
    case blunder
    case sonar
}

/// Lightweight zero-asset procedural sound engine using AVAudioEngine (obeys iOS silent switch via .ambient).
@MainActor
public final class BrillySoundEngine {
    public static let shared = BrillySoundEngine()

    #if canImport(AVFoundation)
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false
    private let sampleRate: Double = 44_100
    #endif

    private init() {
        #if canImport(AVFoundation)
        engine.attach(player)
        if let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
        #endif
    }

    public func play(_ cue: ChessSoundCue) {
        #if canImport(AVFoundation)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return }
        if !started {
            try? engine.start()
            started = engine.isRunning
        }
        guard engine.isRunning else { return }

        let buffer: AVAudioPCMBuffer?
        switch cue {
        case .move:
            buffer = synthesizeTone(freqs: [240], duration: 0.055, gain: 0.22, decay: 38, format: format)
        case .capture:
            buffer = synthesizeTone(freqs: [310, 175], duration: 0.085, gain: 0.28, decay: 26, format: format)
        case .brilliant:
            buffer = synthesizeTone(freqs: [587.33, 880.0, 1174.66], duration: 0.36, gain: 0.20, decay: 7.5, format: format)
        case .blunder:
            buffer = synthesizeTone(freqs: [130.81, 98.0], duration: 0.28, gain: 0.26, decay: 9.0, format: format)
        case .sonar:
            buffer = synthesizeTone(freqs: [740.0], duration: 0.16, gain: 0.16, decay: 16, format: format)
        }

        if let buffer {
            if !player.isPlaying { player.play() }
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
        #endif
    }

    #if canImport(AVFoundation)
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
