//
//  ProfileView.swift
//  sleep
//

import AuthenticationServices
import FirebaseAuth
import os
import SwiftData
import SwiftUI

struct ProfileView: View {
    @Environment(SleepSettings.self) private var settings
    @Environment(AuthenticationService.self) private var authService
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [SleepSession]
    @State private var showingDeleteConfirmation = false
    @State private var showingSignOutConfirmation = false
    @State private var isDeleting = false
    @State private var firebaseUser: FirebaseAuth.User? = Auth.auth().currentUser
    @State private var showingNamePrompt = false
    @State private var promptFirstName: String = ""
    @State private var promptLastName: String = ""

    private let genderOptions = ["Not specified", "Male", "Female", "Non-binary", "Prefer not to say"]

    private var profileInitials: String {
        let first = settings.userName.trimmingCharacters(in: .whitespaces).prefix(1)
        let last = settings.userLastName.trimmingCharacters(in: .whitespaces).prefix(1)
        return "\(first)\(last)"
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                HStack(spacing: 14) {
                    ProfilePhotoPicker(
                        photoData: $settings.userPhotoData,
                        size: 64,
                        initials: profileInitials
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        if !settings.userName.isEmpty {
                            Text(settings.userName)
                                .font(.title3)
                                .fontWeight(.semibold)
                        } else {
                            Text("Set up your profile")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }

                        if let user = firebaseUser {
                            let isApple = user.providerData.first?.providerID == "apple.com"
                            Label(isApple ? "Signed in with Apple" : "Signed in with Email",
                                  systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Your photo appears on PDF sleep reports so a clinician can identify you at a glance.")
            }

            Section {
                TextField("Name", text: $settings.userName)
                Stepper("Age: \(settings.userAge)", value: $settings.userAge, in: 13...120)
                Picker("Gender", selection: $settings.userGender) {
                    ForEach(genderOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
            } footer: {
                Text("Used for age-based sleep recommendations and benchmark comparisons.")
            }

            Section("Sleep Goal") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target: \(String(format: "%.1f", settings.sleepGoalHours)) hours")
                        .font(.subheadline)
                    Slider(value: $settings.sleepGoalHours, in: 5...12, step: 0.5)
                        .tint(.green)
                    Text("Recommended for your age: \(recommendedSleepLabel(forAge: settings.userAge))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Account") {
                if let user = firebaseUser {
                    HStack {
                        Text(user.providerData.first?.providerID == "apple.com" ? "Apple ID" : "Email")
                        Spacer()
                        Text(user.email ?? "Connected")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            let appleCred = authorization.credential as? ASAuthorizationAppleIDCredential
                            let appleGaveName = (appleCred?.fullName?.givenName?.isEmpty == false)
                                || (appleCred?.fullName?.familyName?.isEmpty == false)

                            authService.handleAuthorization(result: authorization)
                            if let given = authService.userGivenName, !given.isEmpty,
                               settings.userName.isEmpty {
                                settings.userName = given
                            }
                            if let family = authService.userFamilyName, !family.isEmpty,
                               settings.userLastName.isEmpty {
                                settings.userLastName = family
                            }
                            firebaseUser = Auth.auth().currentUser

                            if !appleGaveName {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(1.5))
                                    if settings.userName.trimmingCharacters(in: .whitespaces).isEmpty {
                                        promptFirstName = settings.userName
                                        promptLastName = settings.userLastName
                                        showingNamePrompt = true
                                    }
                                }
                            }
                        case .failure(let error):
                            print("Sign in failed: \(error)")
                        }
                    }
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Section {
                Button("Delete Account & All Data", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } footer: {
                Text("This will permanently delete your account and all sleep data. This action cannot be undone.")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            firebaseUser = Auth.auth().currentUser
        }
        .onDisappear {
            authService.syncSettings(settings)
        }
        .alert("Sign Out?", isPresented: $showingSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                LocalDataCleanup.wipeUserData(modelContext: modelContext, settings: settings)
                authService.signOut()
                firebaseUser = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing out will remove your sleep data from this device. It stays backed up in the cloud and will return when you sign back in.")
        }
        .alert("Delete Everything?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteEverything()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account, \(sessions.count) sleep sessions, and all settings. This cannot be undone.")
        }
        .sheet(isPresented: $showingNamePrompt) {
            NamePromptSheet(
                firstName: $promptFirstName,
                lastName: $promptLastName,
                onSave: { first, last in
                    settings.userName = first
                    settings.userLastName = last
                    authService.syncSettings(settings)
                    showingNamePrompt = false
                },
                onCancel: { showingNamePrompt = false }
            )
            .presentationDetents([.medium])
        }
    }

    private func deleteEverything() {
        AppLogger.auth.info("User requested account & data deletion")
        authService.deleteFirebaseAccount()
        LocalDataCleanup.wipeUserData(modelContext: modelContext, settings: settings)
        authService.signOut()
        firebaseUser = nil
        AppLogger.auth.info("All data deleted and settings reset")
    }
}

// MARK: - NamePromptSheet

private struct NamePromptSheet: View {
    @Binding var firstName: String
    @Binding var lastName: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    @FocusState private var firstFocused: Bool

    private var trimmedFirst: String {
        firstName.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First name", text: $firstName)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .focused($firstFocused)
                    TextField("Last name (optional)", text: $lastName)
                        .textContentType(.familyName)
                        .autocorrectionDisabled()
                } header: {
                    Text("What should we call you?")
                } footer: {
                    Text("Apple Sign-In only shares your name the very first time you use it with an app. If you're signing in again later we don't receive it, so we ask here instead.")
                }
            }
            .navigationTitle("Your Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(trimmedFirst, lastName.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(trimmedFirst.isEmpty)
                }
            }
            .onAppear { firstFocused = true }
        }
    }
}
