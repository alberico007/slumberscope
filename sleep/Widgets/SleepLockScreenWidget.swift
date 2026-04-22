//
//  SleepLockScreenWidget.swift
//  sleep
//
//

import SwiftUI
import WidgetKit

// MARK: - Sleep Score Timeline Provider

struct SleepScoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepScoreEntry {
        SleepScoreEntry(date: .now, score: 85, duration: "7h 30m", isTracking: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepScoreEntry) -> Void) {
        let entry = SleepScoreEntry(
            date: .now,
            score: UserDefaults.standard.integer(forKey: "lastSleepScore"),
            duration: UserDefaults.standard.string(forKey: "lastSleepDuration") ?? "--",
            isTracking: UserDefaults.standard.bool(forKey: "isCurrentlyTracking")
        )
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepScoreEntry>) -> Void) {
        let entry = SleepScoreEntry(
            date: .now,
            score: UserDefaults.standard.integer(forKey: "lastSleepScore"),
            duration: UserDefaults.standard.string(forKey: "lastSleepDuration") ?? "--",
            isTracking: UserDefaults.standard.bool(forKey: "isCurrentlyTracking")
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Entry

struct SleepScoreEntry: TimelineEntry {
    let date: Date
    let score: Int
    let duration: String
    let isTracking: Bool
}

// MARK: - Lock Screen Widget View

struct SleepScoreLockScreenView: View {
    var entry: SleepScoreEntry
    @Environment(\.widgetFamily) var family

    var scoreColor: Color {
        if entry.score >= 80 { return .green }
        if entry.score >= 60 { return .yellow }
        if entry.score >= 40 { return .orange }
        return .red
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                    Text("\(entry.score)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                }
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .font(.caption)
                    Text("Slumberscope")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                if entry.isTracking {
                    Text("Tracking...")
                        .font(.headline)
                    Text("Sleep in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if entry.score > 0 {
                    Text("Score: \(entry.score)/100")
                        .font(.headline)
                    Text("Duration: \(entry.duration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No data yet")
                        .font(.headline)
                    Text("Start tracking tonight")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .accessoryInline:
            if entry.isTracking {
                Label("Tracking Sleep...", systemImage: "moon.zzz.fill")
            } else if entry.score > 0 {
                Label("Sleep Score: \(entry.score)", systemImage: "moon.zzz.fill")
            } else {
                Label("Slumberscope", systemImage: "moon.zzz.fill")
            }

        case .systemSmall:
            VStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title2)
                    .foregroundStyle(.cyan)
                if entry.isTracking {
                    Text("Tracking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView()
                } else {
                    Text("\(entry.score)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    Text(entry.duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .containerBackground(.fill.tertiary, for: .widget)

        default:
            VStack {
                Text("Slumberscope")
                    .font(.caption)
                Text("\(entry.score)")
                    .font(.title)
                    .fontWeight(.bold)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }
}

// MARK: - Widget Definition

struct SleepScoreWidget: Widget {
    let kind = "com.smarterpillow.sleep.scoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SleepScoreProvider()) { entry in
            SleepScoreLockScreenView(entry: entry)
        }
        .configurationDisplayName("Sleep Score")
        .description("Shows your last night's sleep score.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .systemSmall
        ])
    }
}
