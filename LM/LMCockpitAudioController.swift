import AVFAudio
import Foundation
import LMCore

/// Interior, structure-borne sound for the LM cockpit.
///
/// The Moon remains silent outside. This controller models only what the crew
/// can hear through the cabin: low DPS vibration, short RCS impulses, and
/// synthesized event tones. Historical mission recordings are not impersonated.
@MainActor
final class LMCockpitAudioController {
    enum CueTone {
        case phase
        case altitude
        case contact
        case success
        case warning
        case failure
    }

    private let engine = AVAudioEngine()
    private let enginePlayer = AVAudioPlayerNode()
    private let cuePlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

    private var started = false
    private var previousRCSCount = 0
    private var buffers = [CueTone: AVAudioPCMBuffer]()

    var isEnabled = true {
        didSet {
            enginePlayer.volume = isEnabled ? enginePlayer.volume : 0
            if !isEnabled {
                cuePlayer.stop()
            }
        }
    }

    init() {
        engine.attach(enginePlayer)
        engine.attach(cuePlayer)
        engine.connect(enginePlayer, to: engine.mainMixerNode, format: format)
        engine.connect(cuePlayer, to: engine.mainMixerNode, format: format)
    }

    func start() {
        guard !started else { return }
        do {
            let rumble = makeRumbleBuffer()
            enginePlayer.scheduleBuffer(rumble, at: nil, options: .loops)
            try engine.start()
            enginePlayer.volume = 0
            enginePlayer.play()
            started = true
        } catch {
            started = false
        }
    }

    func update(commands: LMVehicleSnapshot?) {
        start()
        guard started else { return }

        let engineOn = commands?.mainEngineOn == true && commands?.mainEngineOff != true
        let thrust = engineOn ? (commands?.dps.commandedThrustNewtons ?? 0) : 0
        let normalizedThrust = Float(min(max(thrust / 46_710, 0), 1))
        enginePlayer.volume = isEnabled && engineOn
            ? (0.04 + normalizedThrust * 0.24)
            : 0

        let rcsCount = commands?.rcsJets.count ?? 0
        if isEnabled, rcsCount > 0, previousRCSCount == 0 {
            play(frequency: 118, duration: 0.055, volume: 0.18)
        }
        previousRCSCount = rcsCount
    }

    func play(_ cue: LMCockpitCue) {
        guard isEnabled else { return }
        let tone: CueTone
        switch cue.kind {
        case .phase: tone = .phase
        case .altitude: tone = .altitude
        case .contact: tone = .contact
        case .success: tone = .success
        case .warning: tone = .warning
        case .failure: tone = .failure
        }
        let buffer = buffers[tone] ?? makeCueBuffer(tone)
        buffers[tone] = buffer
        cuePlayer.stop()
        cuePlayer.scheduleBuffer(buffer)
        cuePlayer.play()
    }

    func stop() {
        enginePlayer.stop()
        cuePlayer.stop()
        engine.stop()
        started = false
        previousRCSCount = 0
    }

    private func makeRumbleBuffer() -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        var randomState: UInt32 = 0xA11E_1969
        for index in 0..<Int(frames) {
            let time = Float(index) / Float(format.sampleRate)
            randomState = 1_664_525 &* randomState &+ 1_013_904_223
            let noise = Float(Int32(bitPattern: randomState)) / Float(Int32.max)
            let fundamental = sin(2 * .pi * 31 * time)
            let harmonic = sin(2 * .pi * 62 * time) * 0.35
            samples[index] = (fundamental + harmonic + noise * 0.22) * 0.19
        }
        return buffer
    }

    private func makeCueBuffer(_ tone: CueTone) -> AVAudioPCMBuffer {
        switch tone {
        case .phase:
            return toneSequence([(620, 0.08), (820, 0.10)], volume: 0.16)
        case .altitude:
            return toneSequence([(880, 0.07)], volume: 0.13)
        case .contact:
            return toneSequence([(1_050, 0.08), (1_050, 0.08)], volume: 0.2)
        case .success:
            return toneSequence([(520, 0.10), (660, 0.10), (820, 0.16)], volume: 0.18)
        case .warning:
            return toneSequence([(420, 0.14), (360, 0.14)], volume: 0.2)
        case .failure:
            return toneSequence([(240, 0.20), (180, 0.28)], volume: 0.24)
        }
    }

    private func toneSequence(
        _ notes: [(frequency: Float, duration: Double)],
        volume: Float
    ) -> AVAudioPCMBuffer {
        let gapSeconds = 0.035
        let totalSeconds = notes.reduce(0) { $0 + $1.duration + gapSeconds }
        let frames = AVAudioFrameCount(totalSeconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        var frameIndex = 0

        for note in notes {
            let noteFrames = Int(note.duration * format.sampleRate)
            for localIndex in 0..<noteFrames {
                let time = Float(localIndex) / Float(format.sampleRate)
                let envelope = min(Float(localIndex) / 240, Float(noteFrames - localIndex) / 360, 1)
                samples[frameIndex] = sin(2 * .pi * note.frequency * time) * volume * max(envelope, 0)
                frameIndex += 1
            }
            frameIndex += min(Int(gapSeconds * format.sampleRate), Int(frames) - frameIndex)
        }
        return buffer
    }

    private func play(frequency: Float, duration: Double, volume: Float) {
        let buffer = toneSequence([(frequency, duration)], volume: volume)
        cuePlayer.scheduleBuffer(buffer)
        if !cuePlayer.isPlaying {
            cuePlayer.play()
        }
    }
}
