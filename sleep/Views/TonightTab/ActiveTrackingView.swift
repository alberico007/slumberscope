//
//  ActiveTrackingView.swift
//  sleep
//
//

import os
import SwiftUI

struct ActiveTrackingView: View {

    @Environment(SleepTrackingService.self) private var trackingService
    @Environment(SoundService.self) private var soundService
    @Environment(SleepSettings.self) private var settings
    @Environment(MediaPlaybackService.self) private var mediaService
    @State private var showingSoundPicker = false
    @State private var showingFactorLog = false
    @State private var soundTimerMinutes: Int = 30

    private var batteryService: BatteryService {
        trackingService.batteryService
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Elapsed time
                    Text(FormatHelpers.elapsedTime(trackingService.elapsedTime))
                        .font(.system(size: 56, weight: .thin, design: .monospaced))
                        .foregroundStyle(.cyan)

                    Text("Tracking Sleep")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    // Battery warning
                    if batteryService.warningLevel != .normal {
                        BatteryWarningBanner(warningLevel: batteryService.warningLevel)
                    }

                    // Now playing (Apple Music / Podcast from GetReadyForBed)
                    if let np = mediaService.nowPlaying, np.source != .sound {
                        NowPlayingBar(
                            info: np,
                            timerRemaining: mediaService.timerRemaining,
                            onStop: { mediaService.stop() }
                        )
                    }

                    // Sleep sounds player
                    SleepSoundBar(
                        soundService: soundService,
                        timerMinutes: $soundTimerMinutes,
                        showingSoundPicker: $showingSoundPicker
                    )

                    // Motion / HR card. When the session was started from
                    // the Watch, iPhone's accelerometer isn't driving the
                    // session so we mirror Watch HR here instead of showing
                    // a useless iPhone motion meter.
                    if trackingService.isWatchInitiated || trackingService.isUsingWatchMotion {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "heart.fill")
                                        .foregroundStyle(.pink)
                                    Text("Heart Rate (Watch)")
                                        .font(.subheadline)
                                    Spacer()
                                    if let bpm = trackingService.watchService?.liveHeartRate {
                                        Text("\(Int(bpm.rounded())) bpm")
                                            .font(.subheadline.monospaced())
                                            .foregroundStyle(.primary)
                                    } else {
                                        Text("—")
                                            .font(.subheadline.monospaced())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if let bpm = trackingService.watchService?.liveHeartRate {
                                    let normalized = min(max((bpm - 40) / 80, 0), 1)
                                    ProgressView(value: normalized)
                                        .tint(.pink)
                                } else {
                                    Text("Waiting for samples from your Apple Watch…")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "move.3d")
                                        .foregroundStyle(.green)
                                    Text("Motion Level")
                                        .font(.subheadline)
                                    Spacer()
                                    Text(String(format: "%.3f", trackingService.motionService.currentIntensity))
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: min(trackingService.motionService.currentIntensity, 1.0))
                                    .tint(.green)
                            }
                        }
                    }

                    // Audio level
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "waveform")
                                    .foregroundStyle(.yellow)
                                Text("Audio Level")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.3f", trackingService.audioService.currentAmplitude))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: min(trackingService.audioService.currentAmplitude, 1.0))
                                .tint(.yellow)
                        }
                    }

                    // Live events breakdown — grouped by classification bucket
                    // (Snoring, Dogs, Cats, Voice, Other) so users see exactly
                    // what the mic is picking up during the session.
                    GlassCard {
                        let groups = trackingService.audioService.snoringEvents
                            .groupedByClassification()
                        let total = trackingService.audioService.snoringEvents.count
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Audio Events", systemImage: "waveform")
                                    .font(.subheadline)
                                Spacer()
                                Text("\(total)")
                                    .font(.title2).fontWeight(.semibold)
                                    .foregroundStyle(.purple)
                            }
                            if total == 0 {
                                Text("Listening for snoring, barks, voice, and other noises.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 12) {
                                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                                        HStack(spacing: 4) {
                                            Image(systemName: group.bucket.icon)
                                                .font(.caption)
                                                .foregroundStyle(group.bucket.tint)
                                            Text("\(group.events.count)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.primary)
                                            Text(group.bucket.displayName)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }

                    // Data source indicator
                    if trackingService.isUsingWatchMotion {
                        HStack(spacing: 6) {
                            Image(systemName: "applewatch")
                                .foregroundStyle(.cyan)
                            Text("Watch is tracking motion & heart rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Log factor — lets the user jot down caffeine, migraine,
                    // stress, etc. while already in bed and tracking.
                    Button {
                        showingFactorLog = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "cup.and.saucer.fill")
                                .foregroundStyle(.brown)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Log a factor")
                                    .font(.subheadline).fontWeight(.semibold)
                                Text("Caffeine, migraine, alcohol, stress, etc.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.brown)
                        }
                        .padding(14)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    // Stop button
                    GlassButton(title: "Wake Up", icon: "stop.fill") {
                        AppLogger.ui.info("User tapped Wake Up — stopping tracking")
                        soundService.stopAndClear()
                        trackingService.stopTracking()
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
            .sheet(isPresented: $showingSoundPicker) {
                NavigationStack {
                    SoundMixerView()
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingFactorLog) {
                NavigationStack {
                    FactorLoggingView()
                }
            }

        }
    }
}

// MARK: - Battery Warning Banner

private struct BatteryWarningBanner: View {

    let warningLevel: BatteryWarningLevel

    private var bannerColor: Color {
        switch warningLevel {
        case .normal: .clear
        case .low: .orange
        case .critical: .red
        }
    }

    private var message: String {
        switch warningLevel {
        case .normal: ""
        case .low: "Low battery. Plug in to ensure uninterrupted tracking."
        case .critical: "Critical battery! Tracking may stop soon."
        }
    }

    var body: some View {
        HStack {
            Image(systemName: "battery.25percent")
                .foregroundStyle(bannerColor)
            Text(message)
                .font(.caption)
                .foregroundStyle(bannerColor)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(bannerColor.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Sleep Sound Bar

private struct SleepSoundBar: View {

    let soundService: SoundService
    @Binding var timerMinutes: Int
    @Binding var showingSoundPicker: Bool

    private let timerOptions = [15, 30, 45, 60, 0] // 0 = all night

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.cyan)
                    Text("Sleep Sounds")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        showingSoundPicker = true
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.cyan)
                    }
                }

                if soundService.activeSlots.isEmpty {
                    Text("Tap + to add a sleep sound")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    // Active sounds
                    ForEach(soundService.activeSlots) { slot in
                        HStack {
                            Image(systemName: slot.sound.icon)
                                .foregroundStyle(.cyan)
                                .frame(width: 24)
                            Text(slot.sound.name)
                                .font(.caption)
                            Spacer()
                            Button {
                                soundService.removeSound(id: slot.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Timer picker
                    HStack {
                        Text("Timer:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(timerOptions, id: \.self) { mins in
                            Button {
                                timerMinutes = mins
                            } label: {
                                Text(mins == 0 ? "All Night" : "\(mins)m")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(timerMinutes == mins ? Color.cyan : Color.clear)
                                    .background(.ultraThinMaterial)
                                    .foregroundStyle(timerMinutes == mins ? .white : .secondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }

                    // Play/Stop
                    HStack(spacing: 16) {
                        if soundService.isPlaying {
                            Button {
                                soundService.stop()
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            if soundService.timerRemaining > 0 {
                                Text(FormatHelpers.elapsedTime(soundService.timerRemaining))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Button {
                                soundService.play(timerMinutes: timerMinutes)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(.cyan)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - NowPlayingBar (Apple Music / Podcast from GetReadyForBed)

private struct NowPlayingBar: View {

    let info: NowPlayingInfo
    let timerRemaining: TimeInterval
    let onStop: () -> Void

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                ZStack {
                    if let url = info.artworkURL {
                        AsyncImage(url: url) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            sourcePlaceholder
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        sourcePlaceholder
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: sourceIcon)
                            .font(.caption2)
                            .foregroundStyle(sourceColor)
                        Text(sourceLabel)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(sourceColor)
                    }
                    Text(info.title)
                        .font(.subheadline).fontWeight(.semibold)
                        .lineLimit(1)
                    Text(info.subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if timerRemaining > 0 {
                        Text(formatTimer(timerRemaining))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Button(action: onStop) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.cyan)
                    }
                }
            }
        }
    }

    private var sourceIcon: String {
        switch info.source {
        case .appleMusic: return "music.note"
        case .podcast: return "waveform.badge.mic"
        case .sound: return "speaker.wave.2.fill"
        }
    }

    private var sourceColor: Color {
        switch info.source {
        case .appleMusic: return .red
        case .podcast: return .purple
        case .sound: return .cyan
        }
    }

    private var sourceLabel: String {
        switch info.source {
        case .appleMusic: return "APPLE MUSIC"
        case .podcast: return "PODCAST"
        case .sound: return "SLEEP SOUND"
        }
    }

    private var sourcePlaceholder: some View {
        LinearGradient(
            colors: [sourceColor.opacity(0.7), sourceColor.opacity(0.3)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: sourceIcon)
                .foregroundStyle(.white)
                .font(.title3)
        }
    }

    private func formatTimer(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
