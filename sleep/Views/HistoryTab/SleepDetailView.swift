//
//  SleepDetailView.swift
//  sleep
//
//

import SwiftUI

struct SleepDetailView: View {

    let session: SleepSession

    @Environment(SleepSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // Stats
                GlassCard {
                    VStack(spacing: 12) {
                        StatRow(
                            icon: "clock",
                            label: "Duration",
                            value: FormatHelpers.duration(session.durationSeconds)
                        )
                        Divider()
                        StatRow(
                            icon: "star.fill",
                            label: "Quality",
                            value: session.quality.label
                        )
                        Divider()
                        if settings.showSleepScore {
                            StatRow(
                                icon: "gauge.with.dots.needle.33percent",
                                label: "Sleep Score",
                                value: "\(session.sleepScore)/100"
                            )
                            Divider()
                        }
                        StatRow(
                            icon: "move.3d",
                            label: "Avg Movement",
                            value: String(format: "%.3f", session.averageMovement)
                        )
                        Divider()
                        StatRow(
                            icon: "zzz",
                            label: "Snoring Events",
                            value: "\(session.snoringCount)"
                        )
                    }
                }

                // Sleep Stages Chart
                if !session.sleepStages.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sleep Stages")
                                .font(.headline)
                            SleepStagesChart(stages: session.sleepStages)
                                .frame(height: 200)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Stage Breakdown")
                                .font(.headline)
                            SleepStageBreakdownChart(stages: session.sleepStages)
                                .frame(height: 200)
                        }
                    }
                }

                // Movement Timeline
                if !session.movementPoints.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Movement Timeline")
                                .font(.headline)
                            MovementTimelineChart(dataPoints: session.movementPoints)
                                .frame(height: 200)
                        }
                    }
                }

                // Audio Events — grouped by classification bucket so dogs,
                // meows, voices, and "other" noises each get their own
                // section alongside snoring. Each event has a tap-to-play
                // control for reviewing the captured clip.
                if !session.snoringEvents.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Audio Events", systemImage: "waveform")
                                    .font(.headline)
                                Spacer()
                                Text("\(session.snoringEvents.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(Array(session.snoringEvents.groupedByClassification().enumerated()),
                                    id: \.offset) { _, group in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: group.bucket.icon)
                                            .font(.subheadline)
                                            .foregroundStyle(group.bucket.tint)
                                        Text(group.bucket.displayName)
                                            .font(.subheadline).fontWeight(.semibold)
                                        Text("\(group.events.count)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.top, 2)

                                    ForEach(group.events) { event in
                                        let eventType = AudioEventType.classify(
                                            amplitude: event.averageAmplitude,
                                            duration: event.duration
                                        )
                                        HStack(alignment: .center, spacing: 8) {
                                            AudioPlayerView(event: event, eventType: eventType)
                                            if !event.classification.isEmpty,
                                               event.classification.lowercased() != "snoring" {
                                                Text(event.classification.replacingOccurrences(of: "_", with: " "))
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(group.bucket.tint.opacity(0.15))
                                                    .foregroundStyle(group.bucket.tint)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                        }
                    }
                }

                // Notes
                if !session.notes.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.headline)
                            Text(session.notes)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(FormatHelpers.shortDate(session.startTime))
        .navigationBarTitleDisplayMode(.inline)
    }
}
