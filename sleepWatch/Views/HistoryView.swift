//
//  HistoryView.swift
//  sleepWatch
//
//  History tab. Shows a 7-day date strip at the top. Tapping a day filters
//  the list below. Tapping a session pushes a detail view with duration,
//  HR range, snoring count, and score.
//

import Charts
import SwiftUI

struct HistoryView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    private var last7Days: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).map { cal.date(byAdding: .day, value: -$0, to: today) ?? today }.reversed()
    }

    private var sessionsForSelectedDay: [WatchSleepHistoryEntry] {
        let cal = Calendar.current
        return sessionManager.sleepHistory
            .filter { cal.isDate($0.startTime, inSameDayAs: selectedDay) }
            .sorted { $0.startTime > $1.startTime }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                dayStrip
                if sessionsForSelectedDay.isEmpty {
                    emptyState
                } else {
                    ForEach(sessionsForSelectedDay) { entry in
                        NavigationLink {
                            HistoryDetailView(entry: entry)
                        } label: {
                            HistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("History")
    }

    private var dayStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(last7Days, id: \.self) { day in
                        DayPill(day: day, isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDay))
                            .id(day)
                            .onTapGesture { selectedDay = day }
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                withAnimation { proxy.scrollTo(selectedDay, anchor: .center) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("No sessions")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Tracked sessions from this day will appear here.")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DayPill

private struct DayPill: View {
    let day: Date
    let isSelected: Bool

    private var weekday: String {
        day.formatted(.dateTime.weekday(.abbreviated))
    }

    private var dayNumber: String {
        day.formatted(.dateTime.day())
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(weekday.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .secondary)
            Text(dayNumber)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.85))
        }
        .frame(width: 32, height: 40)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.indigo : Color.white.opacity(0.08))
        )
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let entry: WatchSleepHistoryEntry

    private var timeRange: String {
        let f = DateFormatter()
        f.timeStyle = .short
        return "\(f.string(from: entry.startTime)) – \(f.string(from: entry.endTime))"
    }

    private var durationLabel: String { WatchFormatHelpers.duration(entry.duration) }

    private var scoreColor: Color {
        switch entry.score {
        case 80...100: return .green
        case 60..<80: return .cyan
        case 40..<60: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 3)
                    .frame(width: 30, height: 30)
                Circle()
                    .trim(from: 0, to: CGFloat(entry.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))
                Text("\(entry.score)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(durationLabel)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Text(timeRange)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - HistoryDetailView

private struct HistoryDetailView: View {
    let entry: WatchSleepHistoryEntry

    private var durationLabel: String { WatchFormatHelpers.duration(entry.duration) }

    private var bucketedEvents: [(bucket: WatchEventBucket, count: Int)] {
        var counts: [WatchEventBucket: Int] = [:]
        for e in entry.events {
            counts[WatchEventBucket.classify(e.label), default: 0] += 1
        }
        if counts.isEmpty && entry.snoringCount > 0 {
            counts[.snoring] = entry.snoringCount
        }
        return WatchEventBucket.allCases.compactMap { b in
            guard let c = counts[b], c > 0 else { return nil }
            return (b, c)
        }
    }

    private var scoreColor: Color {
        switch entry.score {
        case 80...100: return .green
        case 60..<80: return .cyan
        case 40..<60: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 6)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: CGFloat(entry.score) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(entry.score)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text(entry.qualityLabel)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                statRow(icon: "bed.double.fill", tint: .indigo,
                        title: "Duration", value: durationLabel)
                statRow(icon: "clock.fill", tint: .cyan,
                        title: "Start", value: entry.startTime.formatted(date: .abbreviated, time: .shortened))

                heartRateCard

                if !bucketedEvents.isEmpty {
                    soundsBucketCard
                }

                if !entry.events.isEmpty {
                    eventTimelineCard
                }

                Text("Full session details, audio clips, and trends are on your iPhone.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(entry.startTime.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.pink)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Heart rate")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    if entry.hrAvg > 0 {
                        HStack(spacing: 6) {
                            Text("\(Int(entry.hrAvg.rounded())) bpm")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                            if entry.hrMin > 0 && entry.hrMax > 0 {
                                Text("\(Int(entry.hrMin.rounded()))–\(Int(entry.hrMax.rounded()))")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("No watch data")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if entry.hrSamples.count >= 2 {
                HeartRateTrendChart(samples: entry.hrSamples)
                    .frame(height: 44)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var soundsBucketCard: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Chronological list showing each detected sound, how long it lasted,
    /// and when it happened. Mirrors the per-event breakdown the iPhone
    /// shows in its session detail view.
    private var eventTimelineCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Timeline")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
            ForEach(entry.events.sorted(by: { $0.timestamp < $1.timestamp }), id: \.timestamp) { e in
                let bucket = WatchEventBucket.classify(e.label)
                HStack(spacing: 6) {
                    Image(systemName: bucket.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(bucket.tint)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.label.capitalized)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(e.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(WatchFormatHelpers.duration(e.duration))
                        .font(.system(size: 9, design: .rounded).monospacedDigit())
                        .foregroundStyle(bucket.tint)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func statRow(icon: String, tint: Color, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - HeartRateTrendChart

private struct HeartRateTrendChart: View {
    let samples: [Double]

    private var pairs: [(index: Int, bpm: Double)] {
        samples.enumerated().map { (index: $0.offset, bpm: $0.element) }
    }

    private var minValue: Double {
        max(30, (samples.min() ?? 60) - 3)
    }

    private var maxValue: Double {
        (samples.max() ?? 100) + 3
    }

    var body: some View {
        Chart(pairs, id: \.index) { point in
            LineMark(
                x: .value("i", point.index),
                y: .value("bpm", point.bpm)
            )
            .foregroundStyle(
                LinearGradient(colors: [.pink, .red],
                               startPoint: .leading, endPoint: .trailing)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))

            AreaMark(
                x: .value("i", point.index),
                yStart: .value("base", minValue),
                yEnd: .value("bpm", point.bpm)
            )
            .foregroundStyle(
                LinearGradient(colors: [.pink.opacity(0.28), .pink.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom)
            )
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: minValue...maxValue)
    }
}
