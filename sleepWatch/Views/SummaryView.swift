//
//  SummaryView.swift
//  sleepWatch

import os
import SwiftUI

struct SummaryView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager

    let summaryData: SleepSummaryData

    private var durationFormatted: String {
        let total = Int(summaryData.duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// Grouped event counts (Snoring / Dogs / Cats / Voice / Other). Falls
    /// back to the phone-provided snoringCount if no event breakdown came
    /// through (older iPhone build).
    private var bucketedEvents: [(bucket: WatchEventBucket, count: Int)] {
        var counts: [WatchEventBucket: Int] = [:]
        for e in summaryData.events {
            counts[WatchEventBucket.classify(e.label), default: 0] += 1
        }
        if counts.isEmpty && summaryData.snoringCount > 0 {
            counts[.snoring] = summaryData.snoringCount
        }
        return WatchEventBucket.allCases.compactMap { b in
            guard let c = counts[b], c > 0 else { return nil }
            return (b, c)
        }
    }

    private var scoreColor: Color {
        switch summaryData.score {
        case 80...100: return .green
        case 60..<80:  return .cyan
        case 40..<60:  return .yellow
        default:       return .orange
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {

                // Header
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("Sleep Summary")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                // Score ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                        .frame(width: 56, height: 56)
                    Circle()
                        .trim(from: 0, to: CGFloat(summaryData.score) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))
                    Text("\(summaryData.score)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Duration + Quality
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(durationFormatted)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Duration")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text(summaryData.quality)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Quality")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // Sleep Stages Chart
                if !summaryData.stages.isEmpty {
                    VStack(spacing: 4) {
                        Text("Sleep Stages")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                        WatchStagesChart(stages: summaryData.stages)
                    }
                    .padding(.horizontal, 4)
                }

                // Heart Rate
                if summaryData.hrAvg > 0 {
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                            Text("\(Int(summaryData.hrAvg)) bpm")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("\(Int(summaryData.hrMin))-\(Int(summaryData.hrMax))")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // Classified sounds by category (Snoring / Dogs / Cats / Voice)
                if !bucketedEvents.isEmpty {
                    VStack(spacing: 3) {
                        HStack {
                            Text("Sounds")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        ForEach(bucketedEvents, id: \.bucket) { entry in
                            HStack(spacing: 6) {
                                Image(systemName: entry.bucket.icon)
                                    .font(.caption2)
                                    .foregroundStyle(entry.bucket.tint)
                                    .frame(width: 14)
                                Text(entry.bucket.displayName)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text("\(entry.count)")
                                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                                    .foregroundStyle(entry.bucket.tint)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Movement Chart
                if !summaryData.movement.isEmpty {
                    VStack(spacing: 4) {
                        Text("Movement")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                        WatchMovementChart(points: summaryData.movement)
                    }
                    .padding(.horizontal, 4)
                }

                // Done button
                Button {
                    WatchLogger.ui.info("User dismissed summary")
                    sessionManager.dismissSummary()
                } label: {
                    Text("Done")
                        .font(.system(.callout, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .padding(.top, 4)
            }
            .padding(.vertical, 6)
        }
    }
}
