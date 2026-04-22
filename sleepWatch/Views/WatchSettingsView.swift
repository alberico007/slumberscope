//
//  WatchSettingsView.swift
//  sleepWatch
//
//  Watch-side Settings tab. Shows the signed-in user at the top as a
//  NavigationLink into a detail view (age, recommended sleep hours).
//  Below that: About the Team (with photos of Simon and Aia mirroring
//  the iPhone), full Terms of Service, and full Privacy Policy.
//

import SwiftUI

struct WatchSettingsView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                NavigationLink {
                    UserInfoWatchView()
                } label: {
                    userCard
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AboutTeamWatchView()
                } label: {
                    settingsRow(icon: "person.3.fill", tint: .orange,
                                title: "About the Team")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TermsOfServiceWatchView()
                } label: {
                    settingsRow(icon: "doc.text.fill", tint: .indigo,
                                title: "Terms of Service")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    PrivacyPolicyWatchView()
                } label: {
                    settingsRow(icon: "lock.shield.fill", tint: .blue,
                                title: "Privacy Policy")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Settings")
    }

    private var userCard: some View {
        let initials = sessionManager.phoneUserName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
        let displayName = sessionManager.phoneUserName.isEmpty ? "Slumberscope" : sessionManager.phoneUserName

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.cyan.opacity(0.3), .blue.opacity(0.2)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                if initials.isEmpty {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.cyan)
                } else {
                    Text(initials)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(sessionManager.phoneSignedIn ? "Tap for profile" : "Not signed in")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func settingsRow(icon: String, tint: Color, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint, in: RoundedRectangle(cornerRadius: 6))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - User Info detail

struct UserInfoWatchView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager

    private var displayName: String {
        sessionManager.phoneUserName.isEmpty ? "Slumberscope" : sessionManager.phoneUserName
    }

    private var initials: String {
        sessionManager.phoneUserName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }

    private var recommendedSleep: String {
        recommendedSleepLabelWatch(forAge: sessionManager.phoneUserAge)
    }

    private var goalText: String {
        guard sessionManager.phoneSleepGoalHours > 0 else { return "Not set" }
        return String(format: "%.1f hours", sessionManager.phoneSleepGoalHours)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.cyan.opacity(0.3), .blue.opacity(0.2)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 60, height: 60)
                    if initials.isEmpty {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.cyan)
                    } else {
                        Text(initials)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                Text(displayName)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                infoRow(icon: "birthday.cake.fill", tint: .pink, title: "Age",
                        value: sessionManager.phoneUserAge > 0 ? "\(sessionManager.phoneUserAge)" : "Not set")
                infoRow(icon: "bed.double.fill", tint: .indigo, title: "Your Goal", value: goalText)
                infoRow(icon: "moon.stars.fill", tint: .cyan, title: "Recommended", value: recommendedSleep)

                Text("Edit your profile on iPhone.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Profile")
    }

    private func infoRow(icon: String, tint: Color, title: String, value: String) -> some View {
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

// MARK: - Recommended sleep helper (mirrors iPhone SleepSettings.swift)

func recommendedSleepLabelWatch(forAge age: Int) -> String {
    switch age {
    case 0:       return "Set age on iPhone"
    case 13...17: return "8-10 hours (teens)"
    case 18...25: return "7-9 hours (young adults)"
    case 26...64: return "7-9 hours (adults)"
    case 65...:   return "7-8 hours (older adults)"
    default:      return "7-9 hours"
    }
}

// MARK: - About team

struct AboutTeamWatchView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Slumberscope")
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                Text("Gannon University Senior Design, Spring 2026.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)

                memberRow(imageName: "Simon",
                          name: "Simon Alberico",
                          role: "Cyber Security",
                          gradient: [.cyan, .blue])
                memberRow(imageName: "Aia",
                          name: "Aia Ahmed",
                          role: "Computer Science",
                          gradient: [.purple, .pink])
                memberRow(imageName: nil,
                          name: "Ananjin Batdelger",
                          role: "Software Engineering",
                          gradient: [.green, .teal])

                Text("Full profiles and LinkedIn links are on your iPhone.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("About")
    }

    private func memberRow(imageName: String?, name: String, role: String, gradient: [Color]) -> some View {
        HStack(spacing: 10) {
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            } else {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                    Text(initials(for: name))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(role)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func initials(for name: String) -> String {
        name.split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}

// MARK: - Terms (full mirror of iPhone)

struct TermsOfServiceWatchView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header("Terms of Service", icon: "doc.text", subtitle: "Last updated: April 2026")

                section(1, "Acceptance of Terms",
                        "By downloading, installing, or using Slumberscope, you agree to these Terms of Service. If you do not agree, do not use the App.")

                section(2, "Description of Service",
                        "Slumberscope uses your iPhone microphone and motion sensors to monitor sleep, detect and classify snoring and other ambient sound events, and produce sleep quality insights. Optional features include Apple Watch heart rate, Apple Music, podcasts, HealthKit, WeatherKit, Live Activities, an AI morning summary, a Smart Alarm, and PDF and CSV export.")

                sectionBold(3, "Medical Disclaimer",
                            "IMPORTANT. Slumberscope is NOT a medical device and is NOT intended to diagnose, treat, cure, or prevent any condition. Data and scores are informational only. If you suspect a sleep disorder, consult a clinician. Snoring detection is not a substitute for a clinical sleep study.")

                sectionBullets(4, "User Responsibilities", [
                    "Use the App only for personal sleep tracking.",
                    "Place your device safely during tracking so it will not fall or overheat.",
                    "Keep the device charged during a tracking session.",
                    "Never rely on the Smart Alarm as your only alarm. Set a backup.",
                    "Keep your account password confidential."
                ])

                sectionBullets(5, "Account and Authentication", [
                    "Sign in with email and password or Sign in with Apple.",
                    "Passwords require 8+ characters with upper, lower, number, and symbol.",
                    "After 10 failed attempts, sign-in locks for 2 hours.",
                    "Some sensitive actions may require email verification."
                ])

                section(6, "Data and Privacy",
                        "Raw motion and audio are processed on your iPhone. Short audio clips of detected events are sent over HTTPS with HMAC-signed requests to our classifier, then discarded after a label is returned. Your account, profile photo, sessions, and settings sync to Google Firebase for backup.")

                sectionBullets(7, "HealthKit", [
                    "Sleep data written to Apple Health is governed by Apple's HealthKit terms.",
                    "You manage HealthKit permissions in iOS Settings.",
                    "We do not read HealthKit back into Firebase.",
                    "HealthKit can be disabled at any time."
                ])

                sectionBullets(8, "Apple Music", [
                    "An active Apple Music subscription is required to play catalog content.",
                    "Apple manages authorization and playback rights through MusicKit.",
                    "We do not store or transmit your listening history."
                ])

                sectionBullets(9, "Podcasts", [
                    "Podcast discovery uses the public Apple iTunes Podcast Search API.",
                    "Episodes stream directly from the publisher's feed.",
                    "Podcast content is owned by the respective publishers.",
                    "We do not guarantee episode availability."
                ])

                sectionBullets(10, "Cloud Snoring Classifier", [
                    "Roughly 2-second clips are sent only when an event is detected.",
                    "Requests are signed with a per-app HMAC key over HTTPS.",
                    "Clips are processed in memory and discarded immediately. No copy is retained.",
                    "The on-device environmental filter (fans, AC, dogs, speech) runs locally and is always on."
                ])

                sectionBullets(11, "Profile Photo and PDF Export", [
                    "Photos are optional and used to identify you on PDF sleep reports.",
                    "Photos are stored on your device, synced to Firebase, and embedded in any PDF you generate.",
                    "Exports are generated on your device and shared only through the iOS share sheet.",
                    "You can remove your photo at any time from Profile in Settings."
                ])

                sectionBullets(12, "Apple Watch", [
                    "If a paired Watch is reachable, Slumberscope reads heart rate during a session via HealthKit.",
                    "Samples cross devices through Apple's WatchConnectivity framework.",
                    "If your Watch is not reachable, the iPhone alone runs the session."
                ])

                section(13, "Intellectual Property",
                        "All content, features, source code, algorithms, graphics, audio, and UI are owned by the developer and protected by copyright and trademark law. Copying, modifying, distributing, or reverse-engineering any part of the App is prohibited without written permission.")

                sectionBullets(14, "Sensor Accuracy", [
                    "Results depend on device placement, sensor quality, and environment.",
                    "Snoring detection is probabilistic and may produce false positives or negatives, especially around fans, AC, pets, or speech.",
                    "Sleep stage estimation is approximate. It is derived from motion and audio, not clinical EEG.",
                    "Sleep scores are relative indicators, not clinical measurements."
                ])

                sectionBullets(15, "Limitation of Liability", [
                    "The App is provided AS IS and AS AVAILABLE without warranties.",
                    "We disclaim all implied warranties of merchantability, fitness, and non-infringement.",
                    "We are not liable for indirect, incidental, special, consequential, or punitive damages.",
                    "Our total aggregate liability will not exceed what you paid for the App, or fifty US dollars if free."
                ])

                sectionBullets(16, "Third-Party Services", [
                    "Google Firebase (Authentication, Firestore).",
                    "Apple services: Sign in with Apple, HealthKit, WeatherKit, MusicKit, SoundAnalysis.",
                    "Apple iTunes Podcast Search API and public podcast RSS feeds.",
                    "We do not control third-party services or their terms."
                ])

                section(17, "Modifications to Terms",
                        "We may modify these Terms. Material changes will be surfaced in the App and the Last Updated date will be revised. Continued use after changes means you accept the updated Terms.")

                section(18, "Termination",
                        "You may stop using the App at any time. You may delete your account and cloud data from Settings > Profile > Delete Account & All Data. We may terminate access for violations of these Terms.")

                section(19, "Governing Law",
                        "These Terms are governed by the laws of the United States and the state in which the developer resides. Disputes are resolved through binding arbitration where permitted by law.")

                sectionBullets(20, "Apple's Role", [
                    "Apple is not a party to these Terms.",
                    "Apple has no obligation to provide support for the App.",
                    "Apple is not responsible for any claims related to the App.",
                    "Apple is a third-party beneficiary with the right to enforce these Terms."
                ])

                section(21, "Contact",
                        "Email: alberico007@gannon.edu")
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Terms")
    }
}

// MARK: - Privacy (full mirror of iPhone)

struct PrivacyPolicyWatchView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header("Privacy Policy", icon: "lock.shield", subtitle: "Last updated: April 2026")

                section(1, "Introduction",
                        "Slumberscope is a sleep tracking app. This policy explains what we collect, how it is used, where it lives, and the choices you have. Read it together with our Terms of Service.")

                sectionBullets(2, "Data We Collect", [
                    "Motion data from your device's accelerometer.",
                    "Microphone amplitude and frequency energy for on-device snoring detection.",
                    "Sleep session timestamps, quality ratings, and optional notes.",
                    "Profile info from onboarding: first and last name, age, gender, sleep goal, optional photo.",
                    "Account info: email and Firebase-hashed password, or Apple user identifier and optional relay email.",
                    "App settings and preferences."
                ])

                sectionBullets(3, "How We Use Your Data", [
                    "Compute sleep scores, restfulness, and snoring metrics.",
                    "Generate insights, trends, and coaching tips.",
                    "Trigger Smart Alarm wake-ups during a light sleep phase.",
                    "Let you export history as PDF or CSV.",
                    "Restore your history on a new device."
                ])

                sectionBullets(4, "Where Your Data Lives", [
                    "On your device: SwiftData for sessions, UserDefaults for settings, Keychain for credentials.",
                    "Google Firebase (Authentication, Firestore) for cloud backup of sessions and profile, transmitted over HTTPS."
                ])

                sectionBullets(5, "What We Do Not Do", [
                    "No continuous audio recording, storage, or upload. Only numerical signals and short-lived classifier labels.",
                    "No third-party analytics or advertising SDKs.",
                    "No sale, rental, or sharing of personal info with data brokers, insurers, or employers.",
                    "No external ML training on your data."
                ])

                sectionBullets(6, "Third-Party Services", [
                    "Google Firebase Authentication and Firestore.",
                    "Apple Sign in with Apple, HealthKit, WeatherKit, MusicKit, SoundAnalysis.",
                    "Apple iTunes Podcast Search API (search term only, no account).",
                    "Podcast RSS feeds streamed directly from publishers."
                ])

                sectionBullets(7, "Apple HealthKit", [
                    "Sleep sessions may be written to Apple Health as sleep analysis samples.",
                    "Governed by Apple's HealthKit privacy terms.",
                    "We do not read HealthKit back into Firebase.",
                    "Revoke HealthKit access anytime in iOS Settings."
                ])

                sectionBullets(8, "Microphone", [
                    "Used only during an active tracking session.",
                    "Buffers are processed in real time via FFT and Apple's SoundAnalysis.",
                    "Only amplitude, band energy, and classification labels are stored.",
                    "No audio recording is ever sent off the device.",
                    "Audio tracking can be turned off in Settings."
                ])

                sectionBullets(9, "Apple Music", [
                    "MusicKit searches the Apple Music catalog and plays tracks you pick.",
                    "Apple manages your subscription and privacy.",
                    "We do not read listening history or upload what you played.",
                    "Disable in Settings anytime."
                ])

                sectionBullets(10, "Podcasts", [
                    "We query the public iTunes Podcast Search API with your term. No account.",
                    "Episodes stream directly from the publisher's RSS feed.",
                    "We do not report plays to any third party.",
                    "Disable in Settings anytime."
                ])

                sectionBullets(11, "Your Rights", [
                    "View and edit every session in the History tab.",
                    "Delete individual sessions or your entire account from Settings.",
                    "Export your history as PDF or CSV.",
                    "Revoke microphone, motion, location, HealthKit, or notification permissions in iOS Settings.",
                    "Sign out anytime. Signing out wipes local data while preserving cloud backup."
                ])

                sectionBullets(12, "GDPR (EEA)", [
                    "Processing is based on your consent during onboarding and per-feature enablement.",
                    "You have the right to access, correct, export, restrict, and erase your data.",
                    "You may withdraw consent at any time.",
                    "Data is stored on Google Firebase infrastructure, which may include servers outside the EEA under Standard Contractual Clauses."
                ])

                sectionBullets(13, "CCPA (California)", [
                    "We do not sell your personal information.",
                    "We do not share personal information for cross-context behavioral advertising.",
                    "You have the right to know, access, delete, and correct your data.",
                    "You will not be discriminated against for exercising your rights."
                ])

                sectionBullets(14, "Consumer Health Data", [
                    "Sleep, motion, and audio data may be considered consumer health data under some state laws.",
                    "Slumberscope is not a medical device and does not diagnose any condition.",
                    "We do not share consumer health data with insurers, employers, advertisers, or data brokers.",
                    "You can delete your health-related data at any time."
                ])

                section(15, "Children's Privacy",
                        "Slumberscope is not directed to children under 13. We do not knowingly collect data from children under 13. If you believe a child has provided data, contact us and we will delete it.")

                section(16, "Changes to This Policy",
                        "We may update this Privacy Policy. Material changes will be surfaced in the App and the Last Updated date will be revised. Continued use means you accept the updated policy.")

                section(17, "Contact",
                        "Email: alberico007@gannon.edu")
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Privacy")
    }
}

// MARK: - Shared section renderers

@ViewBuilder
private func header(_ title: String, icon: String, subtitle: String) -> some View {
    VStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 22))
            .foregroundStyle(.cyan)
        Text(title)
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
        Text(subtitle)
            .font(.system(size: 9, design: .rounded))
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 4)
}

private func section(_ number: Int, _ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("\(number). \(title)")
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
        Text(body)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func sectionBold(_ number: Int, _ title: String, _ body: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("\(number). \(title)")
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.red)
        Text(body)
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

private func sectionBullets(_ number: Int, _ title: String, _ bullets: [String]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("\(number). \(title)")
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
        ForEach(bullets, id: \.self) { bullet in
            HStack(alignment: .top, spacing: 4) {
                Text("\u{2022}")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(.cyan)
                Text(bullet)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}
