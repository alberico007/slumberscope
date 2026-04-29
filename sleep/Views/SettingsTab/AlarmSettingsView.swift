//
//  AlarmSettingsView.swift
//  sleep
//
//  Created by Michael Berinshteyn on 3/17/26.
//

import SwiftUI

struct AlarmSettingsView: View {
    @Environment(SleepSettings.self) private var settings

    var body: some View {
        
        @Bindable var settings = settings
        
        Form {
            Section("Smart Alarm") {
                Toggle("Enable Smart Alarm", isOn: $settings.smartAlarmEnabled)

                if settings.smartAlarmEnabled {
                    DatePicker("Wake Time", selection: $settings.smartAlarmTime, displayedComponents: .hourAndMinute)

                    Picker("Detection Window", selection: $settings.smartAlarmWindowMinutes) {
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                    }

                    Text("Alarm will trigger during your lightest sleep within this window before your wake time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Gradual Wake") {
                Toggle("Enable Gradual Wake", isOn: $settings.gradualWakeEnabled)

                if settings.gradualWakeEnabled {
                    Picker("Ramp Duration", selection: $settings.gradualWakeMinutes) {
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }

                    Text("Alarm volume gradually increases over this duration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Alarm Sound") {
                ForEach(AlarmSound.allCases) { sound in
                    HStack {
                        Image(systemName: sound.icon)
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                        Text(sound.rawValue)
                            .font(.subheadline)
                        Spacer()
                        if sound == .gentle {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Section("Auto-Stop") {
                Toggle("Auto-Stop Tracking on Wake", isOn: $settings.autoStopTracking)
                
                Text("Automatically ends sleep tracking when significant movement is detected after your wake window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Alarm Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
