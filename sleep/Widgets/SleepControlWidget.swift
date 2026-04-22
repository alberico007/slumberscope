//
//  SleepControlWidget.swift
//  sleep
//
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Control Widget Intent

struct ControlToggleSleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Sleep Tracking"
    static let description: IntentDescription = "Start or stop sleep tracking from Control Center."
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let isTracking = UserDefaults.standard.bool(forKey: "isCurrentlyTracking")
        await MainActor.run {
            if isTracking {
                NotificationCenter.default.post(name: Notification.Name("com.slumberscope.stopTrackingIntent"), object: nil)
                UserDefaults.standard.set(false, forKey: "isCurrentlyTracking")
            } else {
                NotificationCenter.default.post(name: Notification.Name("com.slumberscope.startTrackingIntent"), object: nil)
                UserDefaults.standard.set(true, forKey: "isCurrentlyTracking")
            }
        }
        return .result()
    }
}

// MARK: - Sleep Control Widget

struct SleepControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.smarterpillow.sleep.control"
        ) {
            ControlWidgetButton(action: ControlToggleSleepIntent()) {
                Label("Sleep", systemImage: "moon.zzz.fill")
            }
        }
        .displayName("Sleep Tracking")
        .description("Start or stop sleep tracking.")
    }
}

// MARK: - Quick Start Widget

struct QuickStartSleepIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Start Sleep"
    static let description: IntentDescription = "Quickly start a sleep tracking session."
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("com.slumberscope.startTrackingIntent"), object: nil)
            UserDefaults.standard.set(true, forKey: "isCurrentlyTracking")
        }
        return .result()
    }
}

struct SleepQuickStartWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.smarterpillow.sleep.quickstart"
        ) {
            ControlWidgetButton(action: QuickStartSleepIntent()) {
                Label("Sleep", systemImage: "moon.zzz.fill")
            }
        }
        .displayName("Quick Start Sleep")
        .description("One-tap start sleep tracking.")
    }
}
