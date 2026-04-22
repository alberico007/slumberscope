//
//  SettingsView.swift
//  sleep
//
//

import MusicKit
import SwiftData
import SwiftUI

struct SettingsView: View {

    @Environment(SleepSettings.self) private var settings
    @Environment(SleepTrackingService.self) private var trackingService
    @Environment(MediaPlaybackService.self) private var mediaService
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SleepSession.startTime, order: .reverse)
    private var sessions: [SleepSession]

    @Environment(AuthenticationService.self) private var authService
    @State private var showingPDFExport = false
    @State private var showingCSVExport = false
    @State private var showingSignOutConfirmation = false
    @State private var showingResetOnboardingConfirmation = false
    @State private var healthKitError: String?
    @State private var requestingAppleMusicAuth = false
    @State private var appleMusicDeniedAlert = false

    private let permissionService = PermissionService.shared

    private var notificationService: NotificationService {
        trackingService.notificationService
    }

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                // MARK: You
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack(spacing: 12) {
                            profileAvatar
                                .frame(width: 40, height: 40)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(settings.userName.isEmpty ? "Set Up Profile" : settings.userName)
                                    .font(.subheadline)
                                Text("Photo, name, age, sleep goal")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // MARK: Sleep
                Section {
                    NavigationLink {
                        SleepScheduleView()
                    } label: {
                        SettingRow(icon: "clock.fill", color: .cyan, title: "Sleep Schedule", subtitle: "Bedtime, wake time, sleep goal")
                    }
                } header: {
                    Text("Sleep")
                }

                // MARK: Sleep Audio
                Section {
                    Toggle("Apple Music", isOn: Binding(
                        get: { settings.appleMusicEnabled },
                        set: { newValue in
                            if newValue && !settings.appleMusicEnabled {
                                // Turning on — fire Apple's system auth prompt
                                // before flipping the toggle. Roll back if denied.
                                Task { await enableAppleMusicWithAuth() }
                            } else {
                                settings.appleMusicEnabled = newValue
                            }
                        }
                    ))
                    .disabled(requestingAppleMusicAuth)
                    Toggle("Podcasts", isOn: $settings.podcastsEnabled)
                } header: {
                    Text("Sleep Audio")
                } footer: {
                    Text("Apple Music and Podcasts add those categories to the Get Ready for Bed chooser. Slumberscope automatically filters out fans, AC, and other non-snore noise and uses its cloud classifier for the most accurate verdict.")
                }

                // MARK: Detection
                Section {
                    NavigationLink {
                        MicTestView()
                    } label: {
                        HStack {
                            Image(systemName: "mic.circle.fill")
                                .foregroundStyle(.blue)
                            Text("Mic Test")
                        }
                    }
                } header: {
                    Text("Detection")
                } footer: {
                    Text("Sensitivity tunes itself automatically based on your room's baseline noise. Mic Test records a clip, sends it to the classifier, and stores the labeled result on this device.")
                }

                // MARK: Notifications
                Section("Notifications") {
                    Toggle("Bedtime Reminder", isOn: $settings.bedtimeReminderEnabled)
                    if settings.bedtimeReminderEnabled {
                        DatePicker(
                            "Time",
                            selection: $settings.bedtimeReminderTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                    Toggle("Morning Summary", isOn: $settings.morningSummaryEnabled)
                }

                // MARK: Integrations
                Section("Integrations") {
                    NavigationLink {
                        IntegrationsView()
                    } label: {
                        SettingRow(icon: "link.circle.fill", color: .green, title: "Apple Health, Watch & Siri", subtitle: "Sync, pairing, voice shortcuts")
                    }
                }

                // MARK: Data
                Section {
                    Button {
                        showingPDFExport = true
                    } label: {
                        Label("Export PDF Report", systemImage: "doc.richtext")
                    }
                    Button {
                        showingCSVExport = true
                    } label: {
                        Label("Export CSV Data", systemImage: "tablecells")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Your sleep history stays on this device and your Firebase account. Exports are generated locally and shared only through the iOS share sheet.")
                }

                // MARK: Permissions (compact — read-only status)
                Section {
                    PermissionRow(title: "Microphone", icon: "mic.fill", granted: permissionService.microphoneGranted)
                    PermissionRow(title: "HealthKit", icon: "heart.fill", granted: permissionService.healthKitAuthorized)
                    PermissionRow(title: "Notifications", icon: "bell.fill", granted: permissionService.notificationsAuthorized)
                    if !permissionService.microphoneGranted
                        || !permissionService.healthKitAuthorized
                        || !permissionService.notificationsAuthorized {
                        Button("Request Missing Permissions") {
                            Task { await permissionService.requestAllPermissions() }
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("Permissions")
                }

                // MARK: About
                Section {
                    NavigationLink {
                        AboutTeamView()
                    } label: {
                        SettingRow(icon: "person.3.fill", color: .orange, title: "About the Team", subtitle: "The people behind Slumberscope")
                    }
                    NavigationLink {
                        LegalView()
                    } label: {
                        SettingRow(icon: "doc.text.fill", color: .indigo, title: "Legal", subtitle: "Version, Terms, Privacy Policy")
                    }
                } header: {
                    Text("About")
                }

                // MARK: Account actions (sign out / reset) — bottom of Settings
                Section {
                    Button(role: .destructive) {
                        showingSignOutConfirmation = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }

                    Button {
                        showingResetOnboardingConfirmation = true
                    } label: {
                        Label("Reset Onboarding", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Signing out wipes sleep data from this device. Cloud backup is preserved.")
                }
            }
            .navigationTitle("Settings")
            .alert("Sign Out?", isPresented: $showingSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    LocalDataCleanup.wipeUserData(modelContext: modelContext, settings: settings)
                    authService.signOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Signing out removes sleep data from this device. Your cloud backup is preserved and will return when you sign back in.")
            }
            .alert("Reset Onboarding?", isPresented: $showingResetOnboardingConfirmation) {
                Button("Reset", role: .destructive) {
                    settings.hasCompletedOnboarding = false
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You will see the welcome flow again. Your data and account are not affected.")
            }
            .sheet(isPresented: $showingPDFExport) {
                PDFExportView(sessions: sessions)
            }
            .sheet(isPresented: $showingCSVExport) {
                CSVExportView(sessions: sessions)
            }
            .alert("Apple Music Access Needed", isPresented: $appleMusicDeniedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) { }
            } message: {
                Text("Apple Music access was denied. You can allow it in iOS Settings → Slumberscope → Media & Apple Music.")
            }
            .onChange(of: settings.bedtimeReminderEnabled) { _, newValue in
                notificationService.scheduleBedtimeReminder(at: settings.bedtimeReminderTime, enabled: newValue)
            }
            .onChange(of: settings.bedtimeReminderTime) { _, newValue in
                if settings.bedtimeReminderEnabled {
                    notificationService.scheduleBedtimeReminder(at: newValue, enabled: true)
                }
            }
            .onChange(of: settings.syncHealthKit) { _, newValue in
                if newValue {
                    Task {
                        await permissionService.requestHealthKit()
                        if !permissionService.healthKitAuthorized {
                            healthKitError = "HealthKit authorization was not granted."
                            settings.syncHealthKit = false
                        } else {
                            healthKitError = nil
                        }
                    }
                } else {
                    healthKitError = nil
                }
            }
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let data = settings.userPhotoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
        } else {
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.cyan)
        }
    }

    @MainActor
    private func enableAppleMusicWithAuth() async {
        requestingAppleMusicAuth = true
        defer { requestingAppleMusicAuth = false }
        let status = await mediaService.requestAppleMusicAuthorization()
        switch status {
        case .authorized:
            settings.appleMusicEnabled = true
        case .denied, .restricted:
            settings.appleMusicEnabled = false
            appleMusicDeniedAlert = true
        case .notDetermined:
            // User dismissed without choosing — treat as decline.
            settings.appleMusicEnabled = false
        @unknown default:
            settings.appleMusicEnabled = false
        }
    }
}

// MARK: - SettingRow

private struct SettingRow: View {

    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {

    let title: String
    let icon: String
    let granted: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 24)
            Text(title)
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(granted ? .green : .red)
        }
    }
}
