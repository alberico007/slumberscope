//
//  IntegrationsView.swift
//  sleep
//

import SwiftUI

struct IntegrationsView: View {

    @Environment(SleepSettings.self) private var settings
    @Environment(SleepTrackingService.self) private var trackingService
    @Environment(WatchConnectivityService.self) private var watchService

    private let permissionService = PermissionService.shared

    var body: some View {
        @Bindable var settings = settings

        Form {
            // MARK: Apple Health
            Section {
                Toggle("Sync Sleep to Health", isOn: $settings.syncHealthKit)
                HStack {
                    Text("Heart Rate (Read)")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: permissionService.healthKitAuthorized ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(permissionService.healthKitAuthorized ? .green : .secondary)
                }
            } header: {
                Label("Apple Health", systemImage: "heart.fill")
            } footer: {
                Text("Sleep data, heart rate, HRV, and respiratory rate sync with Apple Health.")
            }

            Section {
                HStack {
                    Text("Watch Connected")
                    Spacer()
                    Image(systemName: watchService.isWatchAppInstalled
                          ? "applewatch.radiowaves.left.and.right"
                          : "applewatch.slash")
                        .foregroundStyle(watchService.isWatchAppInstalled ? .green : .secondary)
                    Text(watchService.isWatchAppInstalled ? "Yes" : "No")
                        .foregroundStyle(.secondary)
                }

                if watchService.isWatchAppInstalled {
                    HStack {
                        Text("Live Session Ready")
                        Spacer()
                        Text(watchService.isWatchReachable ? "Yes" : "Open watch app to wake")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                if let hr = watchService.liveHeartRate {
                    HStack {
                        Text("Last Heart Rate")
                        Spacer()
                        Text("\(Int(hr)) bpm")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Label("Apple Watch", systemImage: "applewatch")
            } footer: {
                Text("Apple Watch provides heart rate, HRV, respiratory rate, and haptic alarm during sleep.")
            }

            Section {
                NavigationLink {
                    SiriManagementView()
                } label: {
                    HStack {
                        Image(systemName: "mic.circle.fill")
                            .foregroundStyle(.purple)
                        VStack(alignment: .leading) {
                            Text("Siri & Shortcuts")
                                .font(.subheadline)
                            Text("5 voice commands configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Label("Voice & Automation", systemImage: "wand.and.stars")
            }

            Section {
                HStack {
                    Text("Sleep Focus")
                    Spacer()
                    Text(settings.enableSleepFocus ? "Auto-enable on tracking" : "Disabled")
                        .foregroundStyle(.secondary)
                }
                Toggle("Enable Sleep Focus when tracking", isOn: $settings.enableSleepFocus)
            } header: {
                Label("Sleep Focus", systemImage: "moon.fill")
            } footer: {
                Text("Automatically enables Sleep Focus when you start a tracking session.")
            }

            Section {
                Toggle("iCloud Backup", isOn: $settings.audioStorageCloud)
                if settings.audioStorageCloud {
                    HStack {
                        Text("Status")
                        Spacer()
                        Image(systemName: "checkmark.icloud.fill")
                            .foregroundStyle(.blue)
                        Text("Enabled")
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Sleep data and recordings will be backed up to iCloud.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("iCloud", systemImage: "icloud.fill")
            }

            Section {
                HStack {
                    Text("Lock Screen & Dynamic Island")
                    Spacer()
                    Image(systemName: "platter.filled.bottom.and.arrow.down.iphone")
                        .foregroundStyle(.cyan)
                }
                Text("Shows real-time sleep tracking status on your Lock Screen and in the Dynamic Island.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Live Activities", systemImage: "platter.filled.bottom.and.arrow.down.iphone")
            }
        }
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - SiriManagementView

private struct SiriManagementView: View {
    private let shortcuts: [(phrase: String, intent: String, icon: String)] = [
        ("\"Start sleep tracking\"", "StartSleepTrackingIntent", "moon.zzz.fill"),
        ("\"Stop sleep tracking\"", "StopSleepTrackingIntent", "stop.fill"),
        ("\"What was my sleep score?\"", "GetLastSleepScoreIntent", "gauge.with.dots.needle.33percent"),
        ("\"Start tracking with rain sounds\"", "StartTrackingWithSoundsIntent", "cloud.rain.fill"),
        ("\"How have I been sleeping?\"", "GetSleepSummaryIntent", "chart.line.uptrend.xyaxis")
    ]

    var body: some View {
        Form {
            Section {
                Text("Say these phrases to Siri to control Slumberscope:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Available Commands") {
                ForEach(shortcuts, id: \.intent) { shortcut in
                    HStack(spacing: 12) {
                        Image(systemName: shortcut.icon)
                            .foregroundStyle(.purple)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shortcut.phrase)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(shortcut.intent)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section {
                Link(destination: URL(string: "shortcuts://")!) {
                    Label("Open Shortcuts App", systemImage: "arrow.up.forward.app.fill")
                }
                Text("Create custom automations using the Shortcuts app, like \"Dim lights and start tracking.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI Actions")
            }
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
