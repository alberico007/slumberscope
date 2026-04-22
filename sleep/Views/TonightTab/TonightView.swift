//
//  TonightView.swift
//  sleep
//
//

import os
import SwiftUI

// MARK: - TonightView (Track Tab)

struct TonightView: View {

    @Environment(SleepTrackingService.self) private var trackingService
    @Environment(SleepSettings.self) private var settings

    var body: some View {
        NavigationStack {
            Group {
                switch trackingService.phase {
                case .idle:
                    if trackingService.crashRecoveryService.hasPendingRecovery {
                        RecoveryView()
                    } else {
                        WindDownView()
                    }
                case .calibrating:
                    CalibrationView()
                case .tracking:
                    ActiveTrackingView()
                case .completing:
                    MorningReviewView()
                case .done:
                    DoneView()
                }
            }
            .navigationTitle("Track")
        }
        .onReceive(NotificationCenter.default.publisher(for: .startTrackingIntent)) { _ in
            AppLogger.ui.info("Received startTrackingIntent — phase: \(String(describing: trackingService.phase))")
            if trackingService.phase == .idle {
                trackingService.startTracking()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stopTrackingIntent)) { _ in
            AppLogger.ui.info("Received stopTrackingIntent — phase: \(String(describing: trackingService.phase))")
            if trackingService.phase == .tracking {
                trackingService.stopTracking()
            }
        }
    }
}

// MARK: - CalibrationView

struct CalibrationView: View {

    @Environment(SleepTrackingService.self) private var trackingService

    private var calibrationService: CalibrationService {
        trackingService.calibrationService
    }

    private var progress: Double {
        switch calibrationService.phase {
        case .calibrating(let p): p
        case .completed: 1.0
        default: 0.0
        }
    }

    private let timestampFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt
    }()

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sensor.fill")
                    .foregroundStyle(.cyan)
                    .font(.title2)
                Text("Calibrating Sensors")
                    .font(.headline)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.headline.monospaced())
                    .foregroundStyle(.cyan)
            }
            .padding(.horizontal)

            ProgressView(value: progress)
                .tint(.cyan)
                .padding(.horizontal)

            HStack(spacing: 12) {
                SensorPill(
                    label: "Motion",
                    value: String(format: "%.4f", trackingService.motionService.currentIntensity),
                    color: .green
                )
                SensorPill(
                    label: "Audio",
                    value: String(format: "%.4f", trackingService.audioService.currentAmplitude),
                    color: .yellow
                )
                SensorPill(
                    label: "FFT",
                    value: FormatHelpers.percentage(trackingService.audioService.snoringBandEnergy),
                    color: .purple
                )
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(calibrationService.logEntries) { entry in
                            LogEntryRow(entry: entry, formatter: timestampFormatter)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
                .onChange(of: calibrationService.logEntries.count) {
                    if let last = calibrationService.logEntries.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("LIVE")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.green)

                Spacer()

                Text("\(calibrationService.logEntries.count) entries")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Skip") {
                    calibrationService.skipCalibration()
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.orange)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.vertical)
    }
}

// MARK: - SensorPill

private struct SensorPill: View {

    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - LogEntryRow

private struct LogEntryRow: View {

    let entry: CalibrationLogEntry
    let formatter: DateFormatter

    private var categoryColor: Color {
        switch entry.category {
        case .system: .cyan
        case .motion: .green
        case .audio: .yellow
        case .fft: .purple
        case .result: .white
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(formatter.string(from: entry.timestamp))
                .foregroundStyle(.gray)
            Text("[\(entry.category.rawValue)]")
                .foregroundStyle(categoryColor)
            Text(entry.message)
                .foregroundStyle(.white)
        }
        .font(.system(size: 10.5, design: .monospaced))
        .textSelection(.enabled)
    }
}

// MARK: - RecoveryView

struct RecoveryView: View {

    @Environment(SleepTrackingService.self) private var trackingService

    private var recoveredState: RecoveryState? {
        trackingService.crashRecoveryService.recoveredState
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)

                Text("Session Interrupted")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("A previous sleep tracking session was interrupted. You can resume tracking or discard the session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let state = recoveredState {
                    GlassCard {
                        VStack(spacing: 12) {
                            StatRow(icon: "clock", label: "Started", value: FormatHelpers.timeOfDay(state.startTime))
                            StatRow(icon: "timer", label: "Elapsed", value: FormatHelpers.elapsedTime(state.elapsedTime))
                            StatRow(icon: "move.3d", label: "Movement Points", value: "\(state.movementPoints.count)")
                            StatRow(icon: "zzz", label: "Snoring Events", value: "\(state.snoringEvents.count)")
                        }
                    }
                }

                GlassButton(title: "Resume & Review", icon: "play.fill") {
                    trackingService.recoverSession()
                }

                Button(role: .destructive) {
                    trackingService.discardRecovery()
                } label: {
                    Label("Discard Session", systemImage: "trash")
                }
                .padding(.top, 8)

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - DoneView

struct DoneView: View {

    @Environment(SleepTrackingService.self) private var trackingService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Sleep Saved!")
                .font(.title)
                .fontWeight(.semibold)

            Text("Your sleep session has been recorded successfully.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            GlassButton(title: "Done", icon: "moon.zzz.fill") {
                trackingService.reset()
            }

            Spacer()
        }
        .padding(.horizontal)
    }
}

// MARK: - SensorStatusRow

struct SensorStatusRow: View {

    @Environment(SleepSettings.self) private var settings

    var body: some View {
        GlassCard {
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "move.3d")
                        .foregroundStyle(.green)
                    Text("Motion")
                        .font(.subheadline)
                    Spacer()
                    Text(settings.trackMotion ? "On" : "Off")
                        .font(.subheadline)
                        .foregroundStyle(settings.trackMotion ? .green : .secondary)
                }
                Divider()
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.yellow)
                    Text("Audio")
                        .font(.subheadline)
                    Spacer()
                    Text(settings.trackAudio ? "On" : "Off")
                        .font(.subheadline)
                        .foregroundStyle(settings.trackAudio ? .yellow : .secondary)
                }
                Divider()
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    Text("HealthKit")
                        .font(.subheadline)
                    Spacer()
                    Text(settings.syncHealthKit ? "On" : "Off")
                        .font(.subheadline)
                        .foregroundStyle(settings.syncHealthKit ? .red : .secondary)
                }
            }
        }
    }
}
