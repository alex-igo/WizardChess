import AVFoundation
import UIKit

/// Sound effects and haptics. The sounds are synthesized in code, so there are no audio files to add.
@MainActor
enum Feedback {
    static var isEnabled = true

    /// Call once at launch so the first sound doesn't have to wait for the audio engine to start.
    static func prepare() {
        _ = SoundManager.shared
    }

    /// A piece lands on a square.
    static func landing() {
        guard isEnabled else { return }
        SoundManager.shared.play(.step)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// A piece is destroyed.
    static func capture(isKing: Bool) {
        guard isEnabled else { return }
        SoundManager.shared.play(.capture)
        UIImpactFeedbackGenerator(style: isKing ? .rigid : .heavy).impactOccurred()
    }

    /// A piece is crowned.
    static func crown() {
        guard isEnabled else { return }
        SoundManager.shared.play(.king)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The creepy 5-second build-up before the shark attacks, with a heartbeat you can feel.
    static func sharkTheme() {
        guard isEnabled else { return }
        if !SoundManager.shared.playSong(named: "sharkSong", skipping: 1.4) {
            SoundManager.shared.play(.sharkTheme)      // your song is missing: use the built-in one
        }
        Task { @MainActor in
            var elapsed = 0.0
            let generator = UIImpactFeedbackGenerator(style: .soft)
            while elapsed < 5.0 {
                generator.impactOccurred(intensity: min(1, 0.4 + elapsed / 6))
                let rate = 1.2 + 0.4 * elapsed        // beats per second: it speeds up
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / rate))
                elapsed += 1 / rate
            }
        }
    }

    /// Silences the attack song (a new game was started).
    static func stopSong() {
        SoundManager.shared.stopSong()
    }

    /// A short laser "pew" (sound only, so rapid fire doesn't buzz the phone).
    static func zap() {
        guard isEnabled else { return }
        SoundManager.shared.play(.zap)
    }

    /// The game has been won (or drawn off).
    static func gameOver() {
        guard isEnabled else { return }
        SoundManager.shared.play(.win)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    enum Sound {
        case step, capture, king, win, sharkTheme, zap
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]

    private let sampleRate = 44_100.0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    private init() {
        // .ambient respects the silent switch and mixes with the user's music.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        buffers[.step] = makeStepSound()
        buffers[.capture] = makeCaptureSound()
        buffers[.king] = makeKingSound()
        buffers[.win] = makeWinSound()
        buffers[.sharkTheme] = makeSharkThemeSound()
        buffers[.zap] = makeZapSound()

        try? engine.start()
    }

    private var songPlayer: AVAudioPlayer?

    /// Plays an audio file from the app (m4a). `skipping` jumps past leading silence.
    /// Returns false if the file isn't there, so the caller can use something else.
    func playSong(named name: String, skipping: TimeInterval) -> Bool {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a"),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            print("[Attack] \(name).m4a not found in the app")
            return false
        }
        player.currentTime = skipping
        player.volume = 1
        player.prepareToPlay()
        player.play()
        songPlayer = player
        return true
    }

    func stopSong() {
        songPlayer?.stop()
        songPlayer = nil
    }

    func play(_ sound: Sound) {
        guard let buffer = buffers[sound] else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }

        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // MARK: Synthesis

    private func makeBuffer(duration: Double, _ sample: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let value = sample(Double(i) / sampleRate)
            data[i] = Float(max(-1, min(1, value)))
        }
        return buffer
    }

    /// A short wooden "tock": a quickly falling low tone plus a tiny click.
    private func makeStepSound() -> AVAudioPCMBuffer {
        makeBuffer(duration: 0.14) { t in
            let thump = sin(2 * .pi * (140 * t - 250 * t * t)) * exp(-t * 35)
            let click = Double.random(in: -1...1) * exp(-t * 300) * 0.4
            return (thump + click) * 0.7
        }
    }

    /// Crash: filtered noise, a low thump, and a scatter of little clatters like shards landing.
    private func makeCaptureSound() -> AVAudioPCMBuffer {
        let clatters: [(start: Double, amp: Double)] = (0..<14).map { _ in
            (Double.random(in: 0.05...0.7), Double.random(in: 0.2...0.5))
        }
        var lowpassed = 0.0
        return makeBuffer(duration: 0.9) { t in
            let noise = Double.random(in: -1...1)
            lowpassed += 0.25 * (noise - lowpassed)
            let crash = lowpassed * exp(-t * 6) * 1.6
            let thump = sin(2 * .pi * (90 * t - 60 * t * t)) * exp(-t * 10) * 0.9
            var clatter = 0.0
            for c in clatters {
                let dt = t - c.start
                if dt > 0 && dt < 0.03 { clatter += noise * c.amp * exp(-dt * 120) }
            }
            return (crash + thump + clatter) * 0.8
        }
    }

    private func bell(_ frequency: Double, start: Double, at t: Double) -> Double {
        guard t >= start else { return 0 }
        let dt = t - start
        return (sin(2 * .pi * frequency * dt) + 0.4 * sin(2 * .pi * 2 * frequency * dt)) * exp(-dt * 7)
    }

    private func makeKingSound() -> AVAudioPCMBuffer {
        makeBuffer(duration: 0.6) { [self] t in
            (bell(660, start: 0, at: t) + bell(990, start: 0.1, at: t)) * 0.3
        }
    }

    /// Five seconds of dread, written from scratch (so there is nothing to license): a low drone whose notes
    /// sit a semitone and a tritone apart, a wobbling tone that creeps upward, a heartbeat that speeds up,
    /// and two shivering high notes. Everything swells towards the end.
    private func makeSharkThemeSound() -> AVAudioPCMBuffer {
        let length = 5.0
        let glideSpan = 3.0                                   // the creeping tone triples in pitch
        let glideScale = 220.0 * length / log(glideSpan)
        return makeBuffer(duration: length) { t in
            let swell = min(1, t / 4.0) * min(1, (length - t) / 0.25)
            let level = 0.25 + 0.75 * swell

            let twoPi = 2.0 * Double.pi

            // Low drone: A, B-flat (they beat against each other) and E-flat (the devil's interval).
            let a1: Double = sin(twoPi * 55.0 * t) * 0.5
            let b1: Double = sin(twoPi * 58.27 * t) * 0.3
            let e1: Double = sin(twoPi * 77.78 * t) * 0.25
            let drone: Double = a1 + b1 + e1

            // A tone that slides upward, with a nervous vibrato.
            let phase: Double = twoPi * glideScale * (pow(glideSpan, t / length) - 1.0)
            let vibrato: Double = 3.0 * sin(twoPi * 5.5 * t)
            let creep: Double = sin(phase + vibrato) * 0.16 * swell

            // Heartbeat: a "lub-dub" that speeds up from 1.2 to 3.2 beats per second.
            let rate: Double = 1.2 + 0.4 * t
            let cycle: Double = 1.2 * t + 0.2 * t * t
            let into: Double = (cycle - floor(cycle)) / rate               // seconds since this beat began
            let lub: Double = sin(twoPi * 48.0 * into) * exp(-into * 20.0)
            let dubDelay: Double = 0.24 / rate
            let dubTime: Double = max(0.0, into - dubDelay)
            let dub: Double = into > dubDelay ? sin(twoPi * 42.0 * dubTime) * exp(-dubTime * 24.0) * 0.7 : 0.0
            let heart: Double = (lub + dub) * (0.4 + 0.6 * swell)

            // Two high notes a semitone apart, shivering.
            let high1: Double = sin(twoPi * 1318.5 * t)
            let shiver: Double = 0.5 + 0.5 * sin(twoPi * 0.7 * t)
            let high2: Double = sin(twoPi * 1396.9 * t) * shiver
            let shimmer: Double = (high1 + high2) * 0.035 * swell

            let mix: Double = drone * 0.32 * level + creep + heart * 0.7 + shimmer
            return mix * 0.75
        }
    }

    /// A quick falling "pew": a tone sliding from high to low with a little grit.
    private func makeZapSound() -> AVAudioPCMBuffer {
        makeBuffer(duration: 0.11) { t in
            let sweep: Double = 2200.0 * t - 6000.0 * t * t
            let phase: Double = 2.0 * Double.pi * sweep
            return sin(phase) * exp(-t * 28) * 0.35
        }
    }

    private func makeWinSound() -> AVAudioPCMBuffer {
        makeBuffer(duration: 1.3) { [self] t in
            (bell(523, start: 0, at: t) + bell(659, start: 0.18, at: t)
             + bell(784, start: 0.36, at: t) + bell(1046, start: 0.54, at: t)) * 0.25
        }
    }
}
