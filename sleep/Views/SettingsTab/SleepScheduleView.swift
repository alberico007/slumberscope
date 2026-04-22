//
//  SleepScheduleView.swift
//  sleep
//
//

import SwiftUI

struct SleepScheduleView: View {

    @Environment(SleepSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Sleep Goal") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target: \(String(format: "%.1f", settings.sleepGoalHours)) hours")
                        .font(.subheadline)
                    Slider(value: $settings.sleepGoalHours, in: 5...12, step: 0.5)
                        .tint(.cyan)
                }
                Text("Adults typically need 7-9 hours per night.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Weekday Schedule") {
                DatePicker("Bedtime", selection: $settings.scheduledBedtime, displayedComponents: .hourAndMinute)
                DatePicker("Wake Time", selection: $settings.scheduledWakeTime, displayedComponents: .hourAndMinute)
            }

            Section("Weekend Schedule") {
                Toggle("Separate Weekend Schedule", isOn: $settings.useWeekendSchedule)
                if settings.useWeekendSchedule {
                    DatePicker("Bedtime", selection: $settings.weekendBedtime, displayedComponents: .hourAndMinute)
                    DatePicker("Wake Time", selection: $settings.weekendWakeTime, displayedComponents: .hourAndMinute)
                }
            }

            Section("Wind Down") {
                Picker("Reminder Before Bed", selection: $settings.windDownReminderMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }

                Toggle("Auto-Enable Sleep Focus", isOn: $settings.enableSleepFocus)
            }
        }
        .navigationTitle("Sleep Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }
}
