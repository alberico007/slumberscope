//
//  SleepLiveActivityView.swift
//  sleep
//
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Sleep Tracking Live Activity

struct SleepTrackingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepTrackingAttributes.self) { context in
            // Lock Screen presentation
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(.cyan)
                        Text("Sleep Tracking")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Text(formatElapsed(context.state.elapsedSeconds))
                        .font(.system(.title2, design: .monospaced, weight: .medium))
                        .foregroundStyle(.cyan)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "zzz")
                            .font(.caption)
                        Text("\(context.state.snoringCount)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.purple)

                    Text(context.state.currentPhase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.7))

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.zzz.fill")
                            .foregroundStyle(.cyan)
                        Text("Sleep")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "zzz")
                            .font(.caption)
                        Text("\(context.state.snoringCount)")
                            .font(.caption)
                    }
                    .foregroundStyle(.purple)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(formatElapsed(context.state.elapsedSeconds))
                        .font(.system(.title, design: .monospaced, weight: .medium))
                        .foregroundStyle(.cyan)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.currentPhase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.cyan)
                    .font(.caption)
            } compactTrailing: {
                Text(formatElapsedShort(context.state.elapsedSeconds))
                    .font(.caption)
                    .foregroundStyle(.cyan)
            } minimal: {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(.cyan)
                    .font(.caption2)
            }
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%d:%02d:%02d", h, m, s)
    }

    private func formatElapsedShort(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}
