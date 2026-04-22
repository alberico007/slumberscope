//
//  SleepCharts.swift
//  sleep
//
//

import Charts
import SwiftUI

// MARK: - SleepStagesChart

struct SleepStagesChart: View {

    let stages: [SleepStageEntry]

    private var stageValue: (SleepStageType) -> Int {
        return { stage in
            switch stage {
            case .awake: 4
            case .rem: 3
            case .light: 2
            case .deep: 1
            }
        }
    }

    var body: some View {
        Chart(stages) { entry in
            RectangleMark(
                xStart: .value("Start", entry.startTime),
                xEnd: .value("End", entry.endTime),
                yStart: .value("Stage", stageValue(entry.stage) - 1),
                yEnd: .value("Stage Top", stageValue(entry.stage))
            )
            .foregroundStyle(entry.stage.color)
        }
        .chartYAxis {
            AxisMarks(values: [0.5, 1.5, 2.5, 3.5]) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        switch Int(v) {
                        case 0: Text("Deep")
                        case 1: Text("Light")
                        case 2: Text("REM")
                        case 3: Text("Awake")
                        default: Text("")
                        }
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel(format: .dateTime.hour().minute())
                AxisGridLine()
            }
        }
    }
}

// MARK: - MovementTimelineChart

struct MovementTimelineChart: View {

    let dataPoints: [MovementDataPoint]

    var body: some View {
        Chart(dataPoints) { point in
            AreaMark(
                x: .value("Time", point.timestamp),
                y: .value("Intensity", point.intensity)
            )
            .foregroundStyle(
                .linearGradient(
                    colors: [.cyan.opacity(0.4), .cyan.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Time", point.timestamp),
                y: .value("Intensity", point.intensity)
            )
            .foregroundStyle(.cyan)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel(format: .dateTime.hour().minute())
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }
}

// MARK: - DurationTrendChart

struct DurationTrendChart: View {

    let sessions: [SleepSession]

    /// Adaptive Y-axis range + stride based on the longest session in view.
    /// Short sessions (a nap or test) get fine-grained 15-minute ticks so the
    /// bar isn't a tiny sliver against an 8-hour scale. Normal-length sleeps
    /// get whole-hour ticks like before.
    private var yConfig: (maxHours: Double, stride: Double) {
        let maxHours = sessions.map { $0.durationSeconds / 3600.0 }.max() ?? 0
        if maxHours <= 0 {
            return (maxHours: 1.0, stride: 0.25)          // no data → show 0–1h axis with 15m ticks
        } else if maxHours < 2 {
            let top = max(0.5, ceil(maxHours / 0.25) * 0.25) // round up to next 15 min
            return (maxHours: top, stride: 0.25)          // 15-minute ticks
        } else if maxHours < 4 {
            let top = ceil(maxHours / 0.5) * 0.5          // round up to next 30 min
            return (maxHours: top, stride: 0.5)           // 30-minute ticks
        } else if maxHours < 8 {
            return (maxHours: max(8.0, ceil(maxHours)), stride: 1) // 1-hour ticks
        } else {
            return (maxHours: ceil(maxHours), stride: 2)  // 2-hour ticks for long ranges
        }
    }

    var body: some View {
        let cfg = yConfig
        Chart(sessions) { session in
            BarMark(
                x: .value("Date", session.startTime, unit: .day),
                y: .value("Hours", session.durationSeconds / 3600.0)
            )
            .foregroundStyle(.indigo.gradient)
            .cornerRadius(4)
        }
        .chartYScale(domain: 0...cfg.maxHours)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: cfg.stride)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(hourLabel(for: v))
                    }
                }
                AxisGridLine()
            }
        }
    }

    /// Compact axis label that adapts to the value:
    ///   0      → "0"
    ///   0.25   → "15m"
    ///   1.5    → "1h 30m"
    ///   2      → "2h"
    private func hourLabel(for hours: Double) -> String {
        guard hours > 0 else { return "0" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        switch (h, m) {
        case (0, let m): return "\(m)m"
        case (let h, 0): return "\(h)h"
        case (let h, let m): return "\(h)h \(m)m"
        }
    }
}

// MARK: - QualityTrendChart

struct QualityTrendChart: View {

    let sessions: [SleepSession]

    var body: some View {
        Chart(sessions) { session in
            LineMark(
                x: .value("Date", session.startTime, unit: .day),
                y: .value("Quality", session.qualityRating)
            )
            .foregroundStyle(.yellow)
            .lineStyle(StrokeStyle(lineWidth: 2))

            PointMark(
                x: .value("Date", session.startTime, unit: .day),
                y: .value("Quality", session.qualityRating)
            )
            .foregroundStyle(.yellow)
            .symbolSize(40)
        }
        .chartYScale(domain: 1...5)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 7)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                    }
                }
                AxisGridLine()
            }
        }
    }
}

// MARK: - SleepStageBreakdownChart

struct SleepStageBreakdownChart: View {

    let stages: [SleepStageEntry]

    private var stagePercentages: [(type: SleepStageType, percentage: Double)] {
        let totalDuration = stages.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        guard totalDuration > 0 else { return [] }

        return SleepStageType.allCases.compactMap { stageType in
            let stageDuration = stages
                .filter { $0.stage == stageType }
                .reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
            let percentage = stageDuration / totalDuration
            guard percentage > 0 else { return nil }
            return (type: stageType, percentage: percentage)
        }
    }

    var body: some View {
        Chart(stagePercentages, id: \.type) { item in
            SectorMark(
                angle: .value("Duration", item.percentage),
                innerRadius: .ratio(0.5),
                angularInset: 2
            )
            .foregroundStyle(by: .value("Stage", item.type.label))
            .annotation(position: .overlay) {
                Text(FormatHelpers.percentage(item.percentage))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
        }
        .chartLegend(position: .bottom, spacing: 16)
        .chartForegroundStyleScale(
            domain: SleepStageType.allCases.map(\.label),
            range: SleepStageType.allCases.map(\.color)
        )
    }
}
