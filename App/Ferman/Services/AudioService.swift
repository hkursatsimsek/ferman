import AVFoundation
import SwiftUI
import os

/// Plays the game's sounds. Models and the battle scene take this as a dependency so tests, previews
/// and silent surfaces (the debrief's photograph, home's frozen table) make no sound; views that make a
/// sound of their own (the dial) read it from the environment.
@MainActor
protocol AudioPlaying: Sendable {
    /// `pan` is -1 (left) … 1 (right), where on the table the sound happened; `volume` is 0…1.
    func play(_ effect: SoundEffect, pan: Float, volume: Float)
    /// The war room's ambience, looped under everything while the app is in front.
    func setAmbience(_ playing: Bool)
    /// Re-reads `GameSettings.soundEnabled` — Ayarlar calls it when the switch changes.
    func soundSettingDidChange()
}

extension AudioPlaying {
    func play(_ effect: SoundEffect) {
        play(effect, pan: 0, volume: 1)
    }
}

/// Used everywhere a model takes an `AudioPlaying` dependency but no real session should exist —
/// tests, previews, and fixtures that don't drive a real screen.
struct SilentAudioPlaying: AudioPlaying {
    func play(_ effect: SoundEffect, pan: Float, volume: Float) {}
    func setAmbience(_ playing: Bool) {}
    func soundSettingDidChange() {}
}

extension EnvironmentValues {
    /// Silent unless the app injects `AudioService.shared` — previews and tests stay quiet.
    @Entry var audio: any AudioPlaying = SilentAudioPlaying()
}

/// One engine, a small pool of voices, every sound decoded up front (they're short) — a battle at 4×
/// can fire a dozen cues in a frame, and a voice is only ever stolen from the oldest sound playing.
///
/// `.ambient` session: mixes with whatever else is playing and respects the silent switch, like any
/// incidental game sound. Sounds come from `Tools/sounds/synthesize.py` (`Sounds/SOURCES.md`).
@MainActor
final class AudioService: AudioPlaying {
    static let shared = AudioService()

    /// Voices for one-shot sounds. Past this many at once the oldest is cut — which, with sounds this
    /// short, is one already fading out.
    static let voiceCount = 10
    static let ambienceFileName = "ambience"
    /// The room sits well under everything else.
    static let ambienceVolume: Float = 0.32

    private static let logger = Logger(subsystem: "com.hksimsek.FERMAN", category: "Audio")

    private let engine = AVAudioEngine()
    private let voices: [AVAudioPlayerNode]
    private let ambiencePlayer = AVAudioPlayerNode()
    private var buffers: [SoundEffect: [AVAudioPCMBuffer]] = [:]
    private var ambienceBuffer: AVAudioPCMBuffer?
    private var nextVoice = 0
    private var nextVariant: [SoundEffect: Int] = [:]
    private var wantsAmbience = false
    private var observers: [Task<Void, Never>] = []

    private init() {
        voices = (0..<Self.voiceCount).map { _ in AVAudioPlayerNode() }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.logger.error("Could not activate the ambient audio session: \(error, privacy: .public)")
        }

        for effect in SoundEffect.allCases {
            let variants = effect.fileNames.compactMap(Self.loadBuffer(named:))
            if variants.count != effect.variantCount {
                Self.logger.error("Missing sound files for \(effect.rawValue, privacy: .public)")
            }
            buffers[effect] = variants
        }
        ambienceBuffer = Self.loadBuffer(named: Self.ambienceFileName)

        // Every one-shot shares one format (the synthesiser writes 44.1 kHz mono), so any voice can play
        // any sound; the ambience has its own rate and the mixer converts it.
        let format = buffers.values.lazy.compactMap(\.first).first?.format
        do {
            for voice in voices {
                engine.attach(voice)
                try engine.connectNode(voice, to: engine.mainMixerNode, format: format)
            }
            engine.attach(ambiencePlayer)
            try engine.connectNode(ambiencePlayer, to: engine.mainMixerNode, format: ambienceBuffer?.format)
            engine.prepare()
        } catch {
            Self.logger.error("Could not build the audio graph: \(error, privacy: .public)")
        }
        observeInterruptions()
    }

    func play(_ effect: SoundEffect, pan: Float, volume: Float) {
        guard GameSettings.soundEnabled, let variants = buffers[effect], !variants.isEmpty, ensureRunning() else {
            return
        }
        let variant = nextVariant[effect, default: 0] % variants.count
        nextVariant[effect] = variant + 1
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count

        voice.pan = max(-1, min(1, pan))
        voice.volume = max(0, min(1, volume))
        // `.interrupts` replaces whatever the voice was still playing instead of queueing behind it.
        voice.scheduleBuffer(
            variants[variant], atTime: nil, options: .interrupts, completionCallbackType: .dataConsumed,
            completionHandler: nil)
        startPlaying(voice)
    }

    func setAmbience(_ playing: Bool) {
        wantsAmbience = playing
        updateAmbience()
    }

    func soundSettingDidChange() {
        if !GameSettings.soundEnabled {
            voices.forEach { $0.stop() }
        }
        updateAmbience()
    }

    // MARK: - Engine

    private func updateAmbience() {
        guard wantsAmbience, GameSettings.soundEnabled, let ambienceBuffer else {
            ambiencePlayer.stop()
            return
        }
        guard ensureRunning(), !ambiencePlayer.isPlaying else { return }
        ambiencePlayer.volume = Self.ambienceVolume
        ambiencePlayer.scheduleBuffer(
            ambienceBuffer, atTime: nil, options: .loops, completionCallbackType: .dataConsumed,
            completionHandler: nil)
        startPlaying(ambiencePlayer)
    }

    private func startPlaying(_ player: AVAudioPlayerNode) {
        guard !player.isPlaying else { return }
        do {
            try player.playAudio()
        } catch {
            Self.logger.error("Could not start a voice: \(error, privacy: .public)")
        }
    }

    /// The engine stops on its own after an interruption or a route change; the next sound restarts it.
    private func ensureRunning() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            return true
        } catch {
            Self.logger.error("Could not start the audio engine: \(error, privacy: .public)")
            return false
        }
    }

    /// A call, Siri or a headphone change stops the engine (and the ambience with it). One-shots restart
    /// it by themselves; the loop needs picking back up.
    private func observeInterruptions() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.AVAudioEngineConfigurationChange, AVAudioSession.interruptionNotification]
        for name in names {
            observers.append(
                Task { [weak self] in
                    for await _ in center.notifications(named: name) {
                        guard let self else { return }
                        self.ambiencePlayer.stop()
                        self.updateAmbience()
                    }
                })
        }
    }

    private static func loadBuffer(named name: String) -> AVAudioPCMBuffer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
            else { return nil }
            try file.read(into: buffer)
            return buffer
        } catch {
            logger.error("Could not load \(name, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}
