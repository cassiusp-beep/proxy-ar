import AVFoundation

/// Generates a subtle ambient quadcopter drone rotor hum (~85 Hz fundamental with harmonics)
/// without requiring external audio asset files, adhering to the speculative critique aesthetic.
final class DroneAudioEngine {
    static let shared = DroneAudioEngine()

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var isPlaying = false
    private var phase: Float = 0
    private var harmonicPhase: Float = 0

    private init() {}

    func start() {
        guard !isPlaying else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PROXY] Audio session error: \(error)")
        }

        let engine = AVAudioEngine()
        let sampleRate: Float = 44100.0

        let src = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let fundamental: Float = 85.0 // ~5100 RPM quadcopter hum
            let bladePassing: Float = 170.0

            for frame in 0..<Int(frameCount) {
                self.phase += (2.0 * .pi * fundamental) / sampleRate
                if self.phase > 2.0 * .pi { self.phase -= 2.0 * .pi }

                self.harmonicPhase += (2.0 * .pi * bladePassing) / sampleRate
                if self.harmonicPhase > 2.0 * .pi { self.harmonicPhase -= 2.0 * .pi }

                // Modulate rotor wash (subtle background drone ambience)
                let val1 = sin(self.phase) * 0.08
                let val2 = sin(self.harmonicPhase) * 0.04
                let sample = (val1 + val2) * 0.5

                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        }

        self.sourceNode = src
        self.engine = engine

        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1)!
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.25

        do {
            try engine.start()
            isPlaying = true
            print("[PROXY] Drone ambient rotor audio started.")
        } catch {
            print("[PROXY] Failed to start drone audio engine: \(error)")
        }
    }

    func stop() {
        engine?.stop()
        isPlaying = false
    }
}
