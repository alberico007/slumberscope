//
//  PrivacyControlsView.swift
//  sleep
//
//

import SwiftData
import SwiftUI

struct PrivacyControlsView: View {

    @Environment(\.modelContext) private var modelContext

    @Query private var sessions: [SleepSession]

    @State private var onDeviceOnly = true
    @State private var showingDeleteSleepData = false
    @State private var showingDeleteAudioRecordings = false
    @State private var showingDeleteCloudData = false

    var body: some View {
        Form {
            // MARK: Audio Processing
            Section {
                Text("Microphone audio is analyzed in real time on this device using on-device signal processing and Apple's SoundAnalysis framework. Only numeric results (amplitude, frequency energy, and classification labels) are ever written to storage. No audio recording is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Audio Processing")
            }

            // MARK: Cloud Sync
            Section {
                HStack {
                    Text("Account and sessions")
                        .font(.subheadline)
                    Spacer()
                    Text("Google Firebase")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Transport")
                        .font(.subheadline)
                    Spacer()
                    Text("HTTPS / TLS 1.2+")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Your sleep sessions, profile, and settings sync to Firebase so you can restore your history on a new device. Deleting your account removes both local and cloud copies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cloud Sync")
            }

            // MARK: AI Processing
            Section {
                Text("AI coaching tips and summaries run on-device using Apple Intelligence where available. Your sleep data is not sent to external model providers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI Processing")
            }

            // MARK: Data Export
            Section {
                Button {
                    // Export PDF
                } label: {
                    Label("Export PDF", systemImage: "doc.richtext")
                }

                Button {
                    // Export CSV
                } label: {
                    Label("Export CSV", systemImage: "tablecells")
                }

                Button {
                    // Export to Apple Health
                } label: {
                    Label("Export to Apple Health", systemImage: "heart.fill")
                }
            } header: {
                Text("Data Export")
            }

            // MARK: Data Management
            Section {
                Button(role: .destructive) {
                    showingDeleteSleepData = true
                } label: {
                    Label("Delete All Sleep Data", systemImage: "trash")
                }

                Button(role: .destructive) {
                    showingDeleteAudioRecordings = true
                } label: {
                    Label("Delete All Audio Recordings", systemImage: "waveform.slash")
                }

                Button(role: .destructive) {
                    showingDeleteCloudData = true
                } label: {
                    Label("Delete Cloud Data", systemImage: "icloud.slash")
                }
            } header: {
                Text("Data Management")
            } footer: {
                Text("\(sessions.count) sleep sessions recorded.")
            }

            // MARK: Privacy Info
            Section {
                HStack {
                    Text("Data collected")
                        .font(.subheadline)
                    Spacer()
                    Text("Sleep sessions, motion, audio events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Shared with third parties")
                        .font(.subheadline)
                    Spacer()
                    Text("None")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Cloud backup")
                        .font(.subheadline)
                    Spacer()
                    Text("Google Firebase")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("See the full Privacy Policy and Terms of Service in Settings > About.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy Info")
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete All Sleep Data?", isPresented: $showingDeleteSleepData) {
            Button("Delete", role: .destructive) {
                for session in sessions {
                    modelContext.delete(session)
                }
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(sessions.count) sleep sessions. This action cannot be undone.")
        }
        .alert("Delete All Audio Recordings?", isPresented: $showingDeleteAudioRecordings) {
            Button("Delete", role: .destructive) {
                // Delete audio recordings from disk
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all stored audio recordings. This action cannot be undone.")
        }
        .alert("Delete Cloud Data?", isPresented: $showingDeleteCloudData) {
            Button("Delete", role: .destructive) {
                // Delete iCloud data
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all sleep data stored in iCloud. Local data will not be affected.")
        }
    }
}
