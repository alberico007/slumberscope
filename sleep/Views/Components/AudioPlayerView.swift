//
//  AudioPlayerView.swift
//  sleep
//
//  Displays a compact audio player control for sleep-related audio events (snoring, coughing, sleep talking, etc)
// It shows a play/pause button event type icon, timestamps, and an animated waveform visualization of the audio

import AVFoundation
import SwiftUI

// MARK: - AudioEventType


//Defines possible types of sleep events that can have audio
enum AudioEventType: String, CaseIterable, Identifiable {
    case snoring = "Snoring"
    case coughing = "Coughing"
    case sleepTalking = "Sleep Talking"
    case ambientNoise = "Ambient"
    case breathingIrregularity = "Breathing"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .snoring: "zzz"
        case .coughing: "waveform.badge.exclamationmark"
        case .sleepTalking: "text.bubble.fill"
        case .ambientNoise: "speaker.wave.2.fill"
        case .breathingIrregularity: "lungs.fill"
        case .other: "waveform"
        }
    }

    var color: Color {
        switch self {
        case .snoring: .purple
        case .coughing: .orange
        case .sleepTalking: .blue
        case .ambientNoise: .gray
        case .breathingIrregularity: .red
        case .other: .secondary
        }
    }

    /// Classify a snoring event by its characteristics
    static func classify(amplitude: Double, duration: TimeInterval) -> AudioEventType {
        if amplitude > 0.5 && duration > 3.0 {
            return .snoring
        } else if amplitude > 0.7 && duration < 1.5 {
            return .coughing
        } else if amplitude > 0.3 && duration > 5.0 {
            return .sleepTalking
        } else if amplitude < 0.2 {
            return .ambientNoise
        } else if duration > 10.0 {
            return .breathingIrregularity
        }
        return .snoring
    }
}

// MARK: - AudioPlayerView

struct AudioPlayerView: View {
    let event: SnoringEvent
    let eventType: AudioEventType

    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var playbackTimer: Timer?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var hasAudioFile = false

    private var amplitudes: [Float] {
        AudioWaveformView.simulatedAmplitudes(
            averageAmplitude: event.averageAmplitude,
            duration: event.duration
        )
    }

    /// When the cloud classifier has returned a verdict, prefer its label
    /// over the generic `AudioEventType.rawValue`. Keeps fallback behavior
    /// identical for events without a remote label.
    private var remoteLabel: String? {
        let label = event.classification
        guard !label.isEmpty,
              !event.remoteClassificationPending,
              label.lowercased() != "snoring" else {
            return nil
        }
        return label
    }

    var body: some View {
        HStack(spacing: 12) {
            // Play/Pause button
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(hasAudioFile ? eventType.color : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!hasAudioFile)

            VStack(alignment: .leading, spacing: 4) {
                // Type and time
                HStack {
                    Image(systemName: eventType.icon)
                        .font(.caption)
                        .foregroundStyle(eventType.color)
                    Text(remoteLabel ?? eventType.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                    if event.remoteClassificationPending {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Waiting on cloud classifier")
                    } else if event.remoteClassificationFailed {
                        Image(systemName: "exclamationmark.icloud")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Cloud classifier unavailable — showing local label")
                    }
                    Spacer()
                    if !hasAudioFile {
                        Text("No recording")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(FormatHelpers.timeOfDay(event.startTime))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(FormatHelpers.duration(event.duration))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Waveform
                AudioWaveformView(
                    amplitudes: amplitudes,
                    accentColor: eventType.color,
                    playbackProgress: playbackProgress
                )
                .frame(height: 28)
            }
        }
        .onAppear {
            loadAudioFile()
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func loadAudioFile() {
        guard let url = event.audioFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            hasAudioFile = false
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayer = player
            hasAudioFile = true
        } catch {
            hasAudioFile = false
        }
    }

    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        guard let player = audioPlayer else {
            // Fallback to simulated playback if no audio file
            startSimulatedPlayback()
            return
        }

        // Configure audio session for playback
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)

        player.currentTime = 0
        player.play()
        isPlaying = true
        playbackProgress = 0

        // Update progress based on real playback
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            Task { @MainActor in
                guard let player = audioPlayer, player.isPlaying else {
                    stopPlayback()
                    return
                }
                playbackProgress = player.duration > 0 ? player.currentTime / player.duration : 0
            }
        }
    }

    private func startSimulatedPlayback() {
        isPlaying = true
        playbackProgress = 0
        let stepDuration = event.duration / 50.0
        playbackTimer = Timer.scheduledTimer(withTimeInterval: max(0.02, stepDuration), repeats: true) { timer in
            Task { @MainActor in
                playbackProgress += 1.0 / 50.0
                if playbackProgress >= 1.0 {
                    stopPlayback()
                }
            }
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackProgress = 0
    }
}
