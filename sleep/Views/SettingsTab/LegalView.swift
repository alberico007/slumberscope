//
//  LegalView.swift
//  sleep
//
//  Settings > About > Legal. Single screen that lists app version,
//  Terms of Service, and Privacy Policy. Pushed onto the Settings
//  navigation stack rather than presented as a sheet so the back chevron
//  fits the rest of the Settings hierarchy.
//

import SwiftUI

struct LegalView: View {

    @State private var showingTerms = false
    @State private var showingPrivacy = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        Form {
            Section("App") {
                HStack {
                    Image(systemName: "moon.zzz.fill")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Slumberscope")
                            .font(.subheadline.weight(.semibold))
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Documents") {
                Button {
                    showingTerms = true
                } label: {
                    legalRow(icon: "doc.text.fill",
                             color: .indigo,
                             title: "Terms of Service",
                             subtitle: "Usage terms and disclaimers")
                }
                .tint(.primary)

                Button {
                    showingPrivacy = true
                } label: {
                    legalRow(icon: "lock.shield.fill",
                             color: .blue,
                             title: "Privacy Policy",
                             subtitle: "What we collect and how it's used")
                }
                .tint(.primary)
            }

            Section("Your Data") {
                NavigationLink {
                    PrivacyControlsView()
                } label: {
                    legalRow(icon: "externaldrive.fill",
                             color: .teal,
                             title: "Privacy & Data Controls",
                             subtitle: "Storage, sync, and data management")
                }
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingTerms) {
            TermsOfServiceView()
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyPolicyView()
        }
    }

    private func legalRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
