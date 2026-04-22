//
//  InsightsView.swift
//  sleep
//
//

import SwiftData
import SwiftUI

// MARK: - InsightPeriod

enum InsightPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3 Months"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        }
    }
}

// MARK: - InsightsView

struct InsightsView: View {

    @Query(sort: \SleepSession.startTime, order: .reverse)
    private var allSessions: [SleepSession]

    @Environment(SleepSettings.self) private var settings

    @State private var selectedPeriod: InsightPeriod = .week

    private var filteredSessions: [SleepSession] {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -selectedPeriod.days,
            to: .now
        ) ?? .now
        return allSessions.filter { $0.startTime >= cutoff }
    }

    private var averageDuration: TimeInterval {
        guard !filteredSessions.isEmpty else { return 0 }
        return filteredSessions.map(\.durationSeconds).reduce(0, +) / Double(filteredSessions.count)
    }

    private var averageQuality: Double {
        guard !filteredSessions.isEmpty else { return 0 }
        return filteredSessions.map { Double($0.qualityRating) }.reduce(0, +) / Double(filteredSessions.count)
    }

    private var averageMovement: Double {
        guard !filteredSessions.isEmpty else { return 0 }
        return filteredSessions.map(\.averageMovement).reduce(0, +) / Double(filteredSessions.count)
    }

    private var averageSnoring: Double {
        guard !filteredSessions.isEmpty else { return 0 }
        return filteredSessions.map { Double($0.snoringCount) }.reduce(0, +) / Double(filteredSessions.count)
    }

    private var averageScore: Int {
        guard !filteredSessions.isEmpty else { return 0 }
        let total = filteredSessions.map { Double($0.sleepScore) }.reduce(0, +)
        return Int((total / Double(filteredSessions.count)).rounded())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Period picker
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(InsightPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if filteredSessions.isEmpty {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Track your sleep to see insights for this period.")
                        )
                    } else {
                        // Sleep Score card
                        if settings.showSleepScore {
                            GlassCard {
                                VStack(spacing: 8) {
                                    Text("Average Sleep Score")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("\(averageScore)")
                                        .font(.system(size: 48, weight: .bold, design: .rounded))
                                        .foregroundStyle(scoreColor)
                                    Text("out of 100")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }

                        // Averages
                        GlassCard {
                            VStack(spacing: 12) {
                                StatRow(
                                    icon: "clock",
                                    label: "Avg Duration",
                                    value: FormatHelpers.duration(averageDuration)
                                )
                                Divider()
                                StatRow(
                                    icon: "star.fill",
                                    label: "Avg Quality",
                                    value: String(format: "%.1f/5", averageQuality)
                                )
                                Divider()
                                StatRow(
                                    icon: "move.3d",
                                    label: "Avg Movement",
                                    value: String(format: "%.3f", averageMovement)
                                )
                                Divider()
                                StatRow(
                                    icon: "zzz",
                                    label: "Avg Snoring Events",
                                    value: String(format: "%.1f", averageSnoring)
                                )
                            }
                        }

                        // Duration trend
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Duration Trend")
                                    .font(.headline)
                                DurationTrendChart(sessions: filteredSessions)
                                    .frame(height: 200)
                            }
                        }

                        // Quality trend
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Quality Trend")
                                    .font(.headline)
                                QualityTrendChart(sessions: filteredSessions)
                                    .frame(height: 200)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Insights")
        }
    }

    private var scoreColor: Color {
        if averageScore >= 80 { return .green }
        if averageScore >= 60 { return .yellow }
        if averageScore >= 40 { return .orange }
        return .red
    }
}
