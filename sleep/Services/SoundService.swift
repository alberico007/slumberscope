//
//  SoundService.swift
//  sleep
//
//

@preconcurrency import AVFoundation
import Foundation
import os
import SwiftData

// MARK: - SoundMixerSlot

struct SoundMixerSlot: Identifiable {
    let id: String
    var sound: SoundItem
    var volume: Float // 0.0 – 1.0
}

// MARK: - SoundService

@Observable
@MainActor
final class SoundService {

    // MARK: - Observable State

    var isPlaying = false
    var activeSlots: [SoundMixerSlot] = []
    var timerRemaining: TimeInterval = 0

    // MARK: - Private

    private var players: [String: AVAudioPlayer] = [:]
    private var countdownTimer: Timer?
    private let maxSlots = 4
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var speakingSoundID: String?
    private let speechDelegateProxy = SpeechSynthesizerDelegateProxy()

    init() {
        speechDelegateProxy.onFinish = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // TTS finished speaking — clean up the slot and any remaining
                // audio state so the mini-player doesn't show a ghost meditation.
                if let id = self.speakingSoundID {
                    AppLogger.sound.info("🔇 TTS finished naturally — clearing slot \(id)")
                    self.activeSlots.removeAll { $0.id == id }
                    self.speakingSoundID = nil
                }
                // If no other sounds are playing, flip the master state off.
                if self.players.isEmpty {
                    self.isPlaying = false
                    self.countdownTimer?.invalidate()
                    self.countdownTimer = nil
                    self.timerRemaining = 0
                }
            }
        }
        speechSynthesizer.delegate = speechDelegateProxy
    }

    // MARK: - Session Configuration

    /// Configures the audio session for sound playback.
    /// Uses `.playAndRecord` when audio tracking (snoring detection) is also active
    /// to avoid conflicting with AudioService's session category.
    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Check if AudioService already set .playAndRecord — use the same category
            // to avoid resetting the session and breaking snoring detection.
            if session.category == .playAndRecord {
                AppLogger.sound.info("Audio session already in .playAndRecord — keeping it (snoring detection active)")
                try session.setActive(true)
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                AppLogger.sound.info("Audio session configured for playback")
            }
        } catch {
            AppLogger.error("SoundService: Failed to configure audio session", error: error)
        }
    }

    // MARK: - Add Sound

    func addSound(_ sound: SoundItem, volume: Float = 0.7) {
        guard activeSlots.count < maxSlots else { return }
        guard !activeSlots.contains(where: { $0.sound.id == sound.id }) else { return }

        let slot = SoundMixerSlot(id: sound.id, sound: sound, volume: volume)
        activeSlots.append(slot)
        AppLogger.sound.info("🔊 Added sound: \(sound.name)")

        // TTS-backed sound (meditation or sleep story) — speak the script
        // instead of loading an audio file.
        if let script = SpeechContent.script(for: sound.id) {
            configureAudioSession()
            isPlaying = true
            speakingSoundID = sound.id
            let utterance = AVSpeechUtterance(string: script)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
            utterance.pitchMultiplier = 0.95
            utterance.volume = volume
            utterance.preUtteranceDelay = 0.3
            utterance.postUtteranceDelay = 0.3
            if let voice = AVSpeechSynthesisVoice(language: "en-US") {
                utterance.voice = voice
            }
            speechSynthesizer.speak(utterance)
            return
        }

        // Create and prepare a looping player
        if let url = Bundle.main.url(forResource: sound.fileName, withExtension: "m4a", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: sound.fileName, withExtension: "mp3", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: sound.fileName, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: sound.fileName, withExtension: "m4a")
            ?? Bundle.main.url(forResource: sound.fileName, withExtension: "mp3")
            ?? Bundle.main.url(forResource: sound.fileName, withExtension: "wav") {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1 // Loop forever
                player.volume = volume
                player.prepareToPlay()
                players[sound.id] = player
                if isPlaying { player.play() }
            } catch {
                AppLogger.sound.error("SoundService: failed to create player for \(sound.fileName): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Play Custom (AI-generated) Script
    //
    // Bypasses the SoundLibrary entirely — used for the "Tonight's Meditation"
    // feature where IntelligenceService produces a personalized script on the
    // fly. Creates a one-off SoundItem with a unique ID so the mixer shows it.
    func playCustomScript(title: String, script: String, volume: Float = 0.7, timerMinutes: Int = 0) {
        guard !script.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard activeSlots.count < maxSlots else { return }
        let id = "ai_script_\(UUID().uuidString.prefix(6))"
        let item = SoundItem(id: id, name: title, icon: "sparkles", category: .meditation, fileName: "", isPremium: false)
        activeSlots.append(SoundMixerSlot(id: id, sound: item, volume: volume))
        AppLogger.sound.info("✨ Playing AI meditation script (\(script.count) chars), timer: \(timerMinutes)m")

        configureAudioSession()
        isPlaying = true
        speakingSoundID = id
        let utterance = AVSpeechUtterance(string: script)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.82
        utterance.pitchMultiplier = 0.95
        utterance.volume = volume
        utterance.preUtteranceDelay = 0.4
        utterance.postUtteranceDelay = 0.5
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        speechSynthesizer.speak(utterance)

        if timerMinutes > 0 {
            timerRemaining = TimeInterval(timerMinutes * 60)
            countdownTimer?.invalidate()
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.timerRemaining -= 1
                    if self.timerRemaining <= 0 {
                        self.countdownTimer?.invalidate()
                        self.countdownTimer = nil
                        self.stop()
                    }
                }
            }
        }
    }

    // MARK: - Remove Sound

    func removeSound(id: String) {
        AppLogger.sound.info("🔊 Removed sound: \(id)")
        players[id]?.stop()
        players.removeValue(forKey: id)
        if speakingSoundID == id {
            speechSynthesizer.stopSpeaking(at: .immediate)
            speakingSoundID = nil
        }
        activeSlots.removeAll { $0.id == id }
        if activeSlots.isEmpty { stop() }
    }

    // MARK: - Update Volume

    func updateVolume(id: String, volume: Float) {
        if let idx = activeSlots.firstIndex(where: { $0.id == id }) {
            activeSlots[idx].volume = volume
        }
        players[id]?.volume = volume
    }

    // MARK: - Play / Pause / Stop

    func play(timerMinutes: Int = 0) {
        AppLogger.sound.info("🔊 Playing sound mix — timer: \(timerMinutes) minutes")
        configureAudioSession()
        isPlaying = true
        for player in players.values { player.play() }

        if timerMinutes > 0 {
            timerRemaining = TimeInterval(timerMinutes * 60)
            countdownTimer?.invalidate()
            countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.timerRemaining -= 1
                    if self.timerRemaining <= 0 {
                        self.countdownTimer?.invalidate()
                        self.countdownTimer = nil
                        self.fadeOutAndStop()
                    }
                }
            }
        }
    }

    func pause() {
        isPlaying = false
        for player in players.values { player.pause() }
        countdownTimer?.invalidate()
    }

    func stop() {
        isPlaying = false
        timerRemaining = 0
        countdownTimer?.invalidate()
        for player in players.values { player.stop() }
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speakingSoundID = nil
    }

    func stopAndClear() {
        stop()
        players.removeAll()
        activeSlots.removeAll()
    }

    // MARK: - Presets

    func saveCurrentAsPreset(name: String, modelContext: ModelContext) {
        let items = activeSlots.map { SoundPresetItem(id: $0.sound.id, volume: $0.volume) }
        let preset = SoundPreset(name: name, items: items)
        modelContext.insert(preset)
        try? modelContext.save()
    }

    func loadPreset(_ preset: SoundPreset) {
        stopAndClear()
        for item in preset.items {
            if let sound = SoundLibrary.all.first(where: { $0.id == item.id }) {
                addSound(sound, volume: item.volume)
            }
        }
    }

    // MARK: - Fade out

    private func fadeOutAndStop() {
        let fadeDuration: TimeInterval = 10
        let steps = 20
        let stepDuration = fadeDuration / Double(steps)

        final class FadeStep: @unchecked Sendable { var value = 0 }

        for player in players.values {
            let startVolume = player.volume
            let counter = FadeStep()

            Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
                counter.value += 1
                let fraction = Float(counter.value) / Float(steps)
                player.volume = startVolume * (1 - fraction)
                if counter.value >= steps {
                    timer.invalidate()
                    Task { @MainActor [weak self] in
                        self?.stop()
                    }
                }
            }
        }
    }
}

// MARK: - SpeechSynthesizerDelegateProxy
//
// AVSpeechSynthesizerDelegate must be NSObject-backed; SoundService is a
// pure Swift @Observable class, so we use a small NSObject proxy that
// forwards the finish + cancel events back via a closure.
private final class SpeechSynthesizerDelegateProxy: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?()
    }
}
