//
//  OnboardingView.swift
//  sleep
//

import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import MusicKit
import os
@preconcurrency import SwiftUI

// MARK: - OnboardingView

struct OnboardingView: View {

    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var isNewUser = false
    @State private var needsEmailVerification = false
    @State private var isTransitioning = false
    private let totalPages = 7

    private let permissionService = PermissionService.shared

    var body: some View {
        ZStack(alignment: .top) {
            if currentPage > 0 {
                ProgressBar(current: currentPage, total: totalPages)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    .zIndex(1)
            }

            Group {
                switch currentPage {
                case 0:
                    SplashPage { advance() }
                case 1:
                    SignInPage { newUser, needsVerify in
                        isNewUser = newUser
                        needsEmailVerification = needsVerify
                        advance()
                    }
                case 2:
                    // Only rendered when needsEmailVerification is true —
                    // advance() now skips past this page when it's false.
                    VerifyEmailPage { advance() }
                case 3:
                    // Only rendered when isNewUser is true — same skip logic.
                    AccountSetupPage { advance() }
                case 4:
                    PermissionsPage(permissionService: permissionService) { advance() }
                case 5:
                    MediaSetupPage { advance() }
                case 6:
                    // Final step — the animated feature showcase now closes
                    // out onboarding. The interactive tutorial it used to
                    // precede has been dissolved into the animation itself
                    // (sensor callouts, morning review, AI coach moment).
                    FeatureShowcasePage { onComplete() }
                default:
                    EmptyView()
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.35), value: currentPage)
        }
        .interactiveDismissDisabled()
    }

    private func advance() {
        // Spam-tap guard: a page's "Continue" button stays alive until the
        // transition animation completes (~0.35s). Without this, a double-tap
        // fires advance() twice and currentPage jumps two pages.
        guard !isTransitioning else { return }
        isTransitioning = true

        // Compute the next page that should actually render, skipping any
        // that don't apply to this user (e.g. VerifyEmail for Apple sign-in,
        // AccountSetup for returning users). We must do this here rather
        // than relying on `Color.clear.onAppear { advance() }` because the
        // spam-tap guard would block that auto-advance.
        var next = currentPage + 1
        while shouldSkip(page: next) && next < totalPages {
            next += 1
        }
        let target = next
        withAnimation { currentPage = target }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isTransitioning = false
        }
    }

    private func shouldSkip(page: Int) -> Bool {
        switch page {
        case 2: return !needsEmailVerification  // VerifyEmailPage
        // AccountSetupPage used to be skipped for returning Firebase users,
        // which meant age was never collected on re-signs or when the first
        // sign-in didn't capture it. Always show it — existing values are
        // restored from Firestore into SleepSettings, so returning users
        // just confirm & tap Continue.
        default: return false
        }
    }
}

// MARK: - ProgressBar

private struct ProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.cyan : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - SplashPage

private struct SplashPage: View {

    let onContinue: () -> Void

    @State private var iconScale: CGFloat = 0.3
    @State private var iconOpacity: Double = 0
    @State private var glowRadius: CGFloat = 0
    @State private var titleOffset: CGFloat = 30
    @State private var titleOpacity: Double = 0
    @State private var subtitleOffset: CGFloat = 20
    @State private var subtitleOpacity: Double = 0
    @State private var teamHeaderOpacity: Double = 0
    @State private var visibleMembers: Int = 0
    @State private var universityOpacity: Double = 0
    @State private var buttonOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    private let team: [(name: String, role: String, initials: String, colors: [Color], imageName: String?, linkedIn: URL?)] = [
        (
            name: "Simon Alberico",
            role: "Cyber Security",
            initials: "SA",
            colors: [Color.cyan, Color.blue],
            imageName: "Simon",
            linkedIn: URL(string: "https://www.linkedin.com/in/simon-alberico-0b2769329/")
        ),
        (
            name: "Aia Ahmed",
            role: "Software Engineering",
            initials: "AA",
            colors: [Color.purple, Color.pink],
            imageName: "Aia",
            linkedIn: URL(string: "https://www.linkedin.com/in/aia-ahmed/")
        ),
        (
            name: "Ananjin Batdelger",
            role: "Computer Science",
            initials: "AB",
            colors: [Color.green, Color.teal],
            imageName: "Ana",
            linkedIn: URL(string: "https://www.linkedin.com/in/anabatdelger/")
        )
    ]
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .stroke(.cyan.opacity(0.2), lineWidth: 2)
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseScale)
                        .opacity(2 - pulseScale)

                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .shadow(color: .cyan.opacity(0.6), radius: glowRadius)
                        .scaleEffect(iconScale)
                        .opacity(iconOpacity)
                }

                Text("Welcome to Slumberscope")
                    .font(.largeTitle).fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .offset(y: titleOffset).opacity(titleOpacity)

                Text("Track your sleep patterns, detect snoring, and wake up refreshed with intelligent insights.")
                    .font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .offset(y: subtitleOffset).opacity(subtitleOpacity)

                VStack(spacing: 12) {
                    Text("Meet the Team")
                        .font(.title3).fontWeight(.semibold)
                        .opacity(teamHeaderOpacity)

                    ForEach(Array(team.enumerated()), id: \.offset) { index, member in
                        Button {
                            if let url = member.linkedIn { openURL(url) }
                        } label: {
                            HStack(spacing: 14) {
                                Group {
                                    if let imageName = member.imageName {
                                        Image(imageName)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                                    } else {
                                        ZStack {
                                            Circle()
                                                .fill(LinearGradient(colors: member.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .frame(width: 44, height: 44)
                                            Text(member.initials)
                                                .font(.subheadline).fontWeight(.bold).foregroundStyle(.white)
                                        }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name).font(.subheadline).fontWeight(.semibold)
                                    Text(member.role).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if member.linkedIn != nil {
                                    Text("in")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Color(red: 0.04, green: 0.40, blue: 0.71))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(member.linkedIn == nil)
                        .opacity(visibleMembers > index ? 1 : 0)
                        .animation(.easeIn(duration: 0.25).delay(Double(index) * 0.08), value: visibleMembers)
                    }
                }
                .padding(.horizontal, 32)

                VStack(spacing: 4) {
                    Text("Gannon University").font(.headline).fontWeight(.semibold)
                    Text("Senior Design \u{2022} Spring 2026").font(.subheadline).foregroundStyle(.secondary)
                }
                .opacity(universityOpacity).padding(.top, 8)

                PrimaryButton(title: "Get Started") { onContinue() }
                    .padding(.horizontal, 32)
                    .opacity(buttonOpacity)
                    .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(0.1)) {
                iconScale = 1.0; iconOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.8).delay(0.4)) { glowRadius = 20 }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) { titleOffset = 0; titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.7)) { subtitleOffset = 0; subtitleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(1.2)) { teamHeaderOpacity = 1 }
            withAnimation(.easeOut(duration: 0.1).delay(1.4)) { visibleMembers = team.count }
            withAnimation(.easeOut(duration: 0.5).delay(2.2)) { universityOpacity = 1 }
            withAnimation(.easeIn(duration: 0.4).delay(2.6)) { buttonOpacity = 1 }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false).delay(0.8)) {
                pulseScale = 1.8
            }
        }
    }
}

// MARK: - AccountSetupPage

private struct AccountSetupPage: View {

    let onContinue: () -> Void

    @Environment(SleepSettings.self) private var settings
    @Environment(AuthenticationService.self) private var authService
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var age: Int = 22
    @State private var goalHours: Double = 8.0
    @State private var photoData: Data?
    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case first, last }

    private var initials: String {
        let first = firstName.trimmingCharacters(in: .whitespaces).prefix(1)
        let last = lastName.trimmingCharacters(in: .whitespaces).prefix(1)
        return "\(first)\(last)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                ProfilePhotoPicker(photoData: $photoData, size: 120, initials: initials)
                    .opacity(titleOpacity)

                Text("Add a photo so your doctor can recognize you on exported sleep reports")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(titleOpacity)

                Text("Create Your Profile")
                    .font(.title).fontWeight(.bold).opacity(titleOpacity)

                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("First Name").font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                        TextField("First name", text: $firstName)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .first)
                            .padding(12).background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .submitLabel(.next)
                            .onSubmit { focusedField = .last }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Name").font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                        TextField("Last name", text: $lastName)
                            .textContentType(.familyName)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .last)
                            .padding(12).background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    }
                }
                .padding(.horizontal, 32)
                .opacity(contentOpacity)

                VStack(spacing: 10) {
                    Text("Age").font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                    Text("\(age)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                        .contentTransition(.numericText(value: Double(age)))
                        .animation(.snappy, value: age)
                    Slider(
                        value: Binding(
                            get: { Double(age) },
                            set: { newValue in
                                let rounded = Int(newValue.rounded())
                                if rounded != age {
                                    age = rounded
                                    updateGoalForAge()
                                }
                            }
                        ),
                        in: 13...100,
                        step: 1
                    )
                    .tint(.cyan)
                    .padding(.horizontal, 40)
                }
                .padding(.horizontal, 32)
                .opacity(contentOpacity)

                // Live sleep-hours feedback — reads the age stepper and
                // shows the CDC/NSF-derived recommendation with a one-line
                // rationale. Updates as the user taps +/−.
                sleepFeedbackCard
                    .padding(.horizontal, 32)
                    .opacity(contentOpacity)

                VStack(spacing: 8) {
                    Text("Your Sleep Goal").font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", goalHours)) hours")
                        .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.green)
                    Slider(value: $goalHours, in: 5...12, step: 0.5).tint(.green).padding(.horizontal, 40)
                    Text("Adjust if you'd like a different target").font(.caption).foregroundStyle(.tertiary)
                }
                .opacity(contentOpacity)

                PrimaryButton(title: "Continue") {
                    saveProfile()
                    onContinue()
                }
                .padding(.horizontal, 32)
                .opacity(contentOpacity)
                .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)

                if firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Please enter your first and last name to continue")
                        .font(.caption).foregroundStyle(.red.opacity(0.8)).padding(.horizontal, 32)
                }

                Spacer(minLength: 40)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            firstName = settings.userName
            lastName = settings.userLastName
            age = settings.userAge > 0 ? settings.userAge : 22
            goalHours = recommendedSleepHours(forAge: age)
            photoData = settings.userPhotoData
            withAnimation(.easeOut(duration: 0.4)) { titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { contentOpacity = 1 }
        }
    }

    private func updateGoalForAge() { goalHours = recommendedSleepHours(forAge: age) }

    private func saveProfile() {
        settings.userName = firstName
        settings.userLastName = lastName
        settings.userAge = age
        settings.sleepGoalHours = goalHours
        settings.userPhotoData = photoData
        authService.syncSettings(settings)
    }

    // MARK: - Sleep feedback card

    private var sleepFeedbackCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(colors: [.indigo, .cyan],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: 36)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("You need \(String(format: "%.1f", recommendedSleepHours(forAge: age))) hours/night")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(recommendedSleepRationale(forAge: age))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.indigo.opacity(0.25), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: age)
    }
}

// MARK: - ForcedPasswordUpdateView

private struct ForcedPasswordUpdateView: View {

    let onCompleted: () -> Void
    let onCancelled: () -> Void

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isUpdating = false
    @State private var errorMessage: String? = nil
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case newPass, confirm }

    private var requirementsMet: Bool {
        PasswordRequirementsView.evaluate(newPassword).allSatisfy { $0.met }
    }

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    private var canSubmit: Bool { requirementsMet && passwordsMatch && !isUpdating }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Spacer(minLength: 20)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)

                    Text("Update Your Password")
                        .font(.title2).fontWeight(.bold)

                    Text("Your current password doesn't meet our security requirements. Please set a new one to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("New Password")
                                .font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                            SecureField("New password", text: $newPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .newPass)
                                .padding(12).background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .submitLabel(.next)
                                .onSubmit { focusedField = .confirm }

                            PasswordRequirementsView(password: newPassword)
                                .padding(.top, 2)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                            SecureField("Re-enter new password", text: $confirmPassword)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirm)
                                .padding(12).background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil; Task { await updatePassword() } }

                            if !confirmPassword.isEmpty && !passwordsMatch {
                                Text("Passwords don't match")
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal, 32)

                    if let error = errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    if isUpdating {
                        ProgressView().padding(.vertical, 8)
                    } else {
                        PrimaryButton(title: "Update Password") {
                            Task { await updatePassword() }
                        }
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1.0 : 0.5)
                        .padding(.horizontal, 32)
                    }

                    Button("Sign Out", role: .destructive) {
                        onCancelled()
                    }
                    .font(.subheadline)
                    .padding(.top, 4)

                    Text("Need help? Contact \(SignInPage.supportEmail)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled()
        }
    }

    @MainActor
    private func updatePassword() async {
        guard canSubmit else { return }
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Not signed in. Please sign in again."
            return
        }
        isUpdating = true
        errorMessage = nil
        defer { isUpdating = false }

        do {
            try await user.updatePassword(to: newPassword)
            AppLogger.auth.info("🔐 Password updated for \(user.uid)")
            onCompleted()
        } catch {
            let code = (error as NSError).code
            if code == 17014 {
                // requiresRecentLogin — shouldn't happen since they just
                // signed in seconds ago, but cover the case.
                errorMessage = "Please sign out and sign in again, then try once more."
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - VerifyEmailPage

private struct VerifyEmailPage: View {

    let onContinue: () -> Void

    @State private var isChecking = false
    @State private var isResending = false
    @State private var errorMessage: String? = nil
    @State private var resentMessage: String? = nil

    private var email: String {
        Auth.auth().currentUser?.email ?? "your inbox"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)

                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.cyan)

                Text("Verify your email")
                    .font(.title).fontWeight(.bold)

                VStack(spacing: 8) {
                    Text("We sent a verification link to")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(email)
                        .font(.subheadline).fontWeight(.semibold)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Text("Open the email on this device and tap the link. Then come back here and tap Continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let error = errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                if let resent = resentMessage {
                    Text(resent).font(.caption).foregroundStyle(.green)
                        .padding(.horizontal, 32)
                }

                VStack(spacing: 12) {
                    if isChecking {
                        ProgressView().padding(.vertical, 8)
                    } else {
                        PrimaryButton(title: "I've verified — Continue") {
                            Task { await checkVerification() }
                        }
                        .padding(.horizontal, 32)
                    }

                    Button {
                        Task { await resendVerification() }
                    } label: {
                        if isResending {
                            ProgressView()
                        } else {
                            Text("Resend email")
                                .font(.subheadline).foregroundStyle(.cyan)
                        }
                    }
                    .disabled(isResending)
                }

                Spacer(minLength: 20)

                Text("Need help? Contact \(SignInPage.supportEmail)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
    }

    @MainActor
    private func checkVerification() async {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "You're not signed in. Please sign in again."
            return
        }
        isChecking = true
        errorMessage = nil
        resentMessage = nil
        defer { isChecking = false }

        do {
            try await user.reload()
            if user.isEmailVerified {
                AppLogger.auth.info("🔐 Email verified for \(user.uid)")
                onContinue()
            } else {
                errorMessage = "We haven't seen the verification yet. Tap the link in the email, then try again."
            }
        } catch {
            errorMessage = "Couldn't check verification: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func resendVerification() async {
        guard let user = Auth.auth().currentUser else { return }
        isResending = true
        errorMessage = nil
        resentMessage = nil
        defer { isResending = false }

        do {
            try await user.sendEmailVerification()
            resentMessage = "Sent! Check your inbox."
        } catch {
            errorMessage = "Couldn't resend: \(error.localizedDescription)"
        }
    }
}

// MARK: - SignInPage

private struct SignInPage: View {

    /// `isNewUser` drives whether AccountSetupPage is shown next.
    /// `needsEmailVerification` drives whether VerifyEmailPage is shown next.
    let onContinue: (_ isNewUser: Bool, _ needsEmailVerification: Bool) -> Void

    @Environment(AuthenticationService.self) private var authService
    @Environment(SleepSettings.self) private var settings
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var didSignIn = false
    @State private var showEmailForm = false
    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var failedAttempts = 0
    @State private var lockoutUntil: Date? = nil
    @State private var showingNoAccountAlert = false
    @State private var showingForgotPasswordPrompt = false
    @State private var showingForgotPasswordSent = false
    @State private var showingForcedPasswordUpdate = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password }

    static let supportEmail = "alberico007@gannon.edu"
    static let maxFailedAttempts = 10
    static let softPromptAtFailedAttempts = 3
    static let lockoutDuration: TimeInterval = 2 * 60 * 60

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 50)

                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.cyan)
                    .opacity(titleOpacity)

                Text("Your Account")
                    .font(.title).fontWeight(.bold)
                    .opacity(titleOpacity)

                Text("Sign in to securely save your sleep data.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(contentOpacity)

                if didSignIn {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48)).foregroundStyle(.green)
                        Text("Signed in successfully!")
                            .font(.headline)
                    }
                    .transition(.scale.combined(with: .opacity))

                } else {
                    VStack(spacing: 16) {

                        // MARK: Sign in with Apple
                        SignInWithAppleButton(.signIn) { request in
                            AppLogger.auth.info("🔐 Sign In with Apple request initiated")
                            request.requestedScopes = [.fullName, .email]
                            let hashedNonce = authService.prepareNonce()
                            request.nonce = hashedNonce
                        } onCompletion: { result in
                            switch result {
                            case .success(let auth):
                                AppLogger.auth.info("🔐 Sign In with Apple succeeded")
                                authService.lastSignInIsNewUser = nil
                                authService.handleAuthorization(result: auth)
                                withAnimation { didSignIn = true }
                                Task { @MainActor in
                                    // Wait up to 5s for the Firebase exchange to finish
                                    // so we can read the real isNewUser flag.
                                    var waited = 0
                                    while authService.lastSignInIsNewUser == nil && waited < 25 {
                                        try? await Task.sleep(for: .milliseconds(200))
                                        waited += 1
                                    }
                                    let isNew = authService.lastSignInIsNewUser ?? false
                                    // Mirror Apple-provided name into SleepSettings so the
                                    // Profile field is auto-populated. Apple only returns
                                    // fullName on the very first sign-in for this app.
                                    if let given = authService.userGivenName, !given.isEmpty,
                                       settings.userName.isEmpty {
                                        settings.userName = given
                                    }
                                    if let family = authService.userFamilyName, !family.isEmpty,
                                       settings.userLastName.isEmpty {
                                        settings.userLastName = family
                                    }
                                    // Apple pre-verifies email → never needs verification.
                                    onContinue(isNew, false)
                                }
                            case .failure(let error):
                                AppLogger.auth.error("🔐 Apple sign-in failed: \(error.localizedDescription)")
                            }
                        }
                        .signInWithAppleButtonStyle(.whiteOutline)
                        .frame(height: 50)

                        // Divider
                        HStack {
                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                            Text("or").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                            Rectangle().fill(Color.secondary.opacity(0.3)).frame(height: 1)
                        }

                        // MARK: Email option
                        if showEmailForm {
                            VStack(spacing: 14) {

                                // Email field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Email").font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                                    TextField("your@email.com", text: $email)
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .focused($focusedField, equals: .email)
                                        .padding(12).background(.regularMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .submitLabel(.next)
                                        .onSubmit { focusedField = .password }
                                }

                                // Password field
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Password").font(.subheadline).fontWeight(.medium).foregroundStyle(.secondary)
                                    SecureField("Password", text: $password)
                                        .textContentType(isSignUp ? .newPassword : .password)
                                        .focused($focusedField, equals: .password)
                                        .padding(12).background(.regularMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .submitLabel(.done)
                                        .onSubmit { focusedField = nil; handleAuth() }

                                    if isSignUp {
                                        PasswordRequirementsView(password: password)
                                            .padding(.top, 2)
                                    } else {
                                        HStack {
                                            Spacer()
                                            Button("Forgot password?") {
                                                Task { await sendPasswordReset() }
                                            }
                                            .font(.caption)
                                            .foregroundStyle(.cyan)
                                            .disabled(normalizedEmail.isEmpty)
                                        }
                                    }
                                }

                                // Error message
                                if let error = errorMessage {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                        .multilineTextAlignment(.center)
                                }

                                // Submit button
                                if isLoading {
                                    ProgressView().padding()
                                } else {
                                    PrimaryButton(title: isSignUp ? "Create Account" : "Sign In") {
                                        handleAuth()
                                    }
                                    .disabled(!canSubmit)
                                    .opacity(canSubmit ? 1.0 : 0.5)
                                }

                                // Toggle sign in / sign up
                                Button {
                                    withAnimation { isSignUp.toggle(); errorMessage = nil }
                                } label: {
                                    Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Create one")
                                        .font(.subheadline).foregroundStyle(.cyan)
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))

                        } else {
                            // Show email button
                            Button {
                                withAnimation { showEmailForm = true }
                            } label: {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                    Text("Continue with Email").font(.headline)
                                }
                                .frame(maxWidth: .infinity).padding()
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 40)
                    .opacity(contentOpacity)
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                    Text("Your data is encrypted and private.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .opacity(contentOpacity)

                Spacer()

                Text("Need help? Contact \(Self.supportEmail)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 30)
                    .opacity(contentOpacity)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { contentOpacity = 1 }
            loadFailedState()
        }
        .onChange(of: email) { _, _ in loadFailedState() }
        .alert("No Account Found", isPresented: $showingNoAccountAlert) {
            Button("Create Account") {
                withAnimation {
                    isSignUp = true
                    errorMessage = nil
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("No account exists for \(email). Would you like to create one?")
        }
        .alert("Forgot Password?", isPresented: $showingForgotPasswordPrompt) {
            Button("Send Reset Email") {
                Task { await sendPasswordReset() }
            }
            Button("Keep Trying", role: .cancel) { }
        } message: {
            let remaining = Self.maxFailedAttempts - failedAttempts
            Text("That's \(failedAttempts) failed attempts. Would you like to reset your password? You have \(remaining) attempt\(remaining == 1 ? "" : "s") left before your account is locked for 2 hours.")
        }
        .alert("Password Reset Sent", isPresented: $showingForgotPasswordSent) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Check \(email) for reset instructions. If you don't see it, check your spam folder or contact \(Self.supportEmail).")
        }
        .fullScreenCover(isPresented: $showingForcedPasswordUpdate) {
            ForcedPasswordUpdateView(
                onCompleted: {
                    showingForcedPasswordUpdate = false
                    withAnimation { didSignIn = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        onContinue(false, false)
                    }
                },
                onCancelled: {
                    showingForcedPasswordUpdate = false
                    authService.signOut()
                    password = ""
                }
            )
        }
    }

    private var passwordMeetsRequirements: Bool {
        PasswordRequirementsView.evaluate(password).allSatisfy { $0.met }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isEmailValid: Bool {
        let regex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: normalizedEmail)
    }

    private var canSubmit: Bool {
        !normalizedEmail.isEmpty &&
        isEmailValid &&
        !password.isEmpty &&
        (!isSignUp || passwordMeetsRequirements)
    }

    private var isLockedOut: Bool {
        guard let until = lockoutUntil else { return false }
        return until > Date()
    }

    private func failedAttemptsKey(for email: String) -> String { "authFailedAttempts_\(email)" }
    private func lockoutKey(for email: String) -> String { "authLockoutUntil_\(email)" }

    private func loadFailedState() {
        guard !normalizedEmail.isEmpty else {
            failedAttempts = 0
            lockoutUntil = nil
            return
        }
        failedAttempts = UserDefaults.standard.integer(forKey: failedAttemptsKey(for: normalizedEmail))
        let ts = UserDefaults.standard.double(forKey: lockoutKey(for: normalizedEmail))
        if ts > 0 {
            let date = Date(timeIntervalSince1970: ts)
            lockoutUntil = date > Date() ? date : nil
            if date <= Date() {
                UserDefaults.standard.removeObject(forKey: lockoutKey(for: normalizedEmail))
                UserDefaults.standard.removeObject(forKey: failedAttemptsKey(for: normalizedEmail))
                failedAttempts = 0
            }
        } else {
            lockoutUntil = nil
        }
    }

    private func recordFailedAttempt() {
        failedAttempts += 1
        UserDefaults.standard.set(failedAttempts, forKey: failedAttemptsKey(for: normalizedEmail))
        if failedAttempts >= Self.maxFailedAttempts {
            let until = Date().addingTimeInterval(Self.lockoutDuration)
            lockoutUntil = until
            UserDefaults.standard.set(until.timeIntervalSince1970, forKey: lockoutKey(for: normalizedEmail))
            AppLogger.auth.warning("🔐 Account locked after \(failedAttempts) failed attempts")
        }
    }

    private func resetFailedAttempts() {
        failedAttempts = 0
        lockoutUntil = nil
        UserDefaults.standard.removeObject(forKey: failedAttemptsKey(for: normalizedEmail))
        UserDefaults.standard.removeObject(forKey: lockoutKey(for: normalizedEmail))
    }

    private func lockoutMessage(until: Date) -> String {
        let minutes = max(1, Int(until.timeIntervalSinceNow / 60))
        let hours = minutes / 60
        let remainder = minutes % 60
        let remaining = hours > 0 ? "\(hours)h \(remainder)m" : "\(remainder)m"
        return "Too many failed attempts. Try again in \(remaining). For help, contact \(Self.supportEmail)."
    }

    private func handleAuth() {
        guard canSubmit else { return }
        loadFailedState()
        if let until = lockoutUntil, isLockedOut {
            errorMessage = lockoutMessage(until: until)
            return
        }
        isLoading = true
        errorMessage = nil
        focusedField = nil

        Task {
            do {
                let isNewUser: Bool
                let needsVerification: Bool

                if isSignUp {
                    let result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
                    let uid = result.user.uid
                    let db = Firestore.firestore()
                    try await db.collection("users").document(uid).setData([
                        "email": normalizedEmail,
                        "createdAt": FieldValue.serverTimestamp(),
                        "lastSynced": FieldValue.serverTimestamp(),
                        "platform": "ios"
                    ], merge: true)
                    AppLogger.auth.info("🔐 New account created — uid: \(uid)")

                    // Send the Firebase verification link to the user's inbox.
                    try? await result.user.sendEmailVerification()
                    AppLogger.auth.info("🔐 Verification email sent to \(normalizedEmail)")

                    isNewUser = true
                    needsVerification = true
                } else {
                    let result = try await Auth.auth().signIn(withEmail: normalizedEmail, password: password)
                    AppLogger.auth.info("🔐 Signed in — uid: \(result.user.uid)")
                    resetFailedAttempts()
                    isNewUser = false
                    needsVerification = false

                    // Grandfathered weak password? Force an update before
                    // letting them into the app.
                    if !passwordMeetsRequirements {
                        await MainActor.run {
                            isLoading = false
                            showingForcedPasswordUpdate = true
                        }
                        return
                    }
                }

                await MainActor.run {
                    isLoading = false
                    withAnimation { didSignIn = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        onContinue(isNewUser, needsVerification)
                    }
                }
            } catch {
                if isSignUp {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = friendlyError(error)
                    }
                } else {
                    await handleSignInFailure(error: error)
                }
            }
        }
    }

    @MainActor
    private func handleSignInFailure(error: Error) async {
        isLoading = false
        let code = (error as NSError).code

        switch code {
        case 17008:
            // Malformed email — don't touch attempts.
            errorMessage = friendlyError(error)

        case 17011:
            // Firebase confirmed no account exists (Email Enumeration
            // Protection off) — offer to create.
            showingNoAccountAlert = true

        case 17009, 17004:
            // 17009 = wrongPassword (enumeration off)
            // 17004 = invalidCredential (enumeration on — could be wrong
            // password OR missing account, Firebase hides which).
            // Treat as a credentials failure; the "Don't have an account?
            // Create one" toggle below the submit button covers the other case.
            recordFailedAttempt()
            if let until = lockoutUntil, isLockedOut {
                errorMessage = lockoutMessage(until: until)
            } else if failedAttempts >= Self.softPromptAtFailedAttempts {
                errorMessage = "Incorrect email or password (\(failedAttempts)/\(Self.maxFailedAttempts) attempts used)."
                showingForgotPasswordPrompt = true
            } else {
                errorMessage = "Incorrect email or password. If you don't have an account, tap \"Create one\" below."
            }

        default:
            errorMessage = friendlyError(error)
        }
    }

    @MainActor
    private func sendPasswordReset() async {
        guard !normalizedEmail.isEmpty else {
            errorMessage = "Enter your email above first."
            return
        }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
            AppLogger.auth.info("🔐 Password reset email sent")
            showingForgotPasswordSent = true
        } catch {
            let code = (error as NSError).code
            if code == 17011 {
                showingNoAccountAlert = true
            } else {
                errorMessage = friendlyError(error)
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case 17007: return "An account with this email already exists."
        case 17009: return "Incorrect password. Please try again."
        case 17011: return "No account found with this email."
        case 17026: return "Password does not meet the requirements."
        case 17008: return "Please enter a valid email address."
        default: return "\(error.localizedDescription) If this persists, contact \(Self.supportEmail)."
        }
    }
}

// MARK: - PasswordRequirementsView

private struct PasswordRequirementsView: View {

    let password: String

    struct Requirement: Identifiable {
        let id = UUID()
        let text: String
        let met: Bool
    }

    static func evaluate(_ password: String) -> [Requirement] {
        let specials = "!@#$%^&*()-_=+[]{};:,.<>?/\\|`~\"'"
        return [
            Requirement(text: "At least 8 characters", met: password.count >= 8),
            Requirement(text: "One uppercase letter", met: password.contains(where: { $0.isUppercase })),
            Requirement(text: "One lowercase letter", met: password.contains(where: { $0.isLowercase })),
            Requirement(text: "One number", met: password.contains(where: { $0.isNumber })),
            Requirement(text: "One special character (!@#$…)", met: password.contains(where: { specials.contains($0) }))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Self.evaluate(password)) { req in
                HStack(spacing: 6) {
                    Image(systemName: req.met ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(req.met ? .green : .secondary)
                    Text(req.text)
                        .font(.caption)
                        .foregroundStyle(req.met ? .primary : .secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: password)
    }
}

// MARK: - PermissionsPage

private struct PermissionsPage: View {

    let permissionService: PermissionService
    let onContinue: () -> Void

    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var visibleRows: Int = 0
    @State private var buttonOpacity: Double = 0
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .top, endPoint: .bottom))
                .opacity(titleOpacity)

            Text("Permissions")
                .font(.title).fontWeight(.bold).opacity(titleOpacity)

            Text("Slumberscope needs a few permissions to track your sleep effectively.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
                .opacity(subtitleOpacity)

            VStack(spacing: 16) {
                let rows: [(icon: String, color: Color, title: String, desc: String, granted: Bool)] = [
                    ("mic.fill", .yellow, "Microphone", "Detects snoring patterns", permissionService.microphoneGranted),
                    ("move.3d", .green, "Motion", "Accelerometer (no permission needed)", permissionService.motionAvailable),
                    ("heart.fill", .red, "HealthKit", "Syncs with Apple Health", permissionService.healthKitAuthorized),
                    ("bell.fill", .blue, "Notifications", "Bedtime reminders & summaries", permissionService.notificationsAuthorized),
                    ("location.fill", .cyan, "Location", "Weather when you wake up", permissionService.locationAuthorized)
                ]
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    PermissionRow(icon: row.icon, color: row.color, title: row.title, description: row.desc, granted: row.granted)
                        .opacity(visibleRows > index ? 1 : 0)
                        .offset(x: visibleRows > index ? 0 : 20)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(Double(index) * 0.1), value: visibleRows)
                }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    isRequesting = true
                    Task {
                        await permissionService.requestAllPermissions()
                        isRequesting = false
                        onContinue()
                    }
                } label: {
                    HStack {
                        if isRequesting { ProgressView().tint(.white).padding(.trailing, 4) }
                        Text(isRequesting ? "Requesting\u{2026}" : "Grant Permissions & Continue").font(.headline)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 32).opacity(buttonOpacity).disabled(isRequesting)

                Button("Skip for Now") { onContinue() }
                    .font(.subheadline).foregroundStyle(.secondary).opacity(buttonOpacity)
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { subtitleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.1).delay(0.35)) { visibleRows = 4 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.7)) { buttonOpacity = 1 }
        }
    }
}

// MARK: - MediaSetupPage

private struct MediaSetupPage: View {

    let onContinue: () -> Void

    @Environment(SleepSettings.self) private var settings
    @Environment(MediaPlaybackService.self) private var mediaService
    @State private var isRequestingAppleMusic = false
    @State private var appleMusicAuthorized = false
    @State private var titleOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 60)

                Image(systemName: "music.note.list")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(colors: [.red, .purple], startPoint: .leading, endPoint: .trailing)
                    )
                    .opacity(titleOpacity)

                Text("Sleep Audio")
                    .font(.title).fontWeight(.bold)
                    .opacity(titleOpacity)

                Text("Fall asleep to Apple Music or a podcast. Optional — flip either one on if you want it in your wind-down chooser.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(contentOpacity)

                VStack(spacing: 14) {
                    // Apple Music — toggling on triggers Apple's system auth
                    // prompt. Roll back if the user declines.
                    mediaRow(
                        icon: "music.note",
                        iconColor: .red,
                        title: "Apple Music",
                        subtitle: appleMusicAuthorized
                            ? "Connected — you can pick songs or playlists"
                            : "Toggle on to pick songs and playlists at bedtime",
                        isOn: Binding(
                            get: { settings.appleMusicEnabled },
                            set: { newValue in
                                if newValue && !settings.appleMusicEnabled {
                                    Task { await authorizeAppleMusic() }
                                } else {
                                    settings.appleMusicEnabled = newValue
                                }
                            }
                        ),
                        trailing: { AnyView(EmptyView()) }
                    )

                    // Podcasts
                    mediaRow(
                        icon: "waveform.badge.mic",
                        iconColor: .purple,
                        title: "Podcasts",
                        subtitle: "Search any podcast via Apple's directory and play inside the app",
                        isOn: $settings.podcastsEnabled,
                        trailing: { AnyView(EmptyView()) }
                    )
                }
                .padding(.horizontal, 20)
                .opacity(contentOpacity)

                Spacer(minLength: 20)

                PrimaryButton(title: "Continue") { onContinue() }
                    .padding(.horizontal, 32)
                    .opacity(contentOpacity)

                Button("Skip for Now") { onContinue() }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.bottom, 30)
                    .opacity(contentOpacity)
            }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            appleMusicAuthorized = MusicAuthorization.currentStatus == .authorized
            withAnimation(.easeOut(duration: 0.4)) { titleOpacity = 1 }
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) { contentOpacity = 1 }
        }
    }

    private func mediaRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        trailing: @escaping () -> AnyView
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
            trailing()
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @MainActor
    private func authorizeAppleMusic() async {
        isRequestingAppleMusic = true
        defer { isRequestingAppleMusic = false }
        let status = await mediaService.requestAppleMusicAuthorization()
        appleMusicAuthorized = status == .authorized
        // Only commit the user-visible toggle if Apple actually authorized us.
        // Otherwise the Binding stays off and the user sees no "on" state for
        // something that wouldn't actually work.
        settings.appleMusicEnabled = appleMusicAuthorized
    }
}

// MARK: - Reusable Components

private struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline)
                .frame(maxWidth: .infinity).padding()
                .background(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
        }
    }
}

// MARK: - FeatureShowcasePage
//
// A scrollable gallery of the app's differentiators, each card animating in
// as the user scrolls. The goal: users know these features exist before they
// ever hit a sleep session, because a feature nobody knows about might as
// well not ship.

private struct FeatureShowcasePage: View {

    let onContinue: @MainActor () -> Void

    // MARK: - Animation state
    //
    // A single Equatable struct holds every property that the keyframeAnimator
    // drives. Each track below operates on a \.keyPath of this type, so all
    // properties animate in parallel from a single timeline — no chained
    // Task.sleep + withAnimation blocks.

    fileprivate struct AnimState: Equatable {
        var sceneOpacity: Double = 0
        var cameraScale: CGFloat = 1.0
        var cameraOffsetY: CGFloat = 0
        var waveformProgress: Double = 0
        var dawnProgress: Double = 0
        var micOpacity: Double = 0
        var motionOpacity: Double = 0
        var proximityOpacity: Double = 0
        var scoreScale: CGFloat = 0.7
        var scoreOpacity: Double = 0
        var coachScale: CGFloat = 0.7
        var coachOpacity: Double = 0
        var captionStep: Double = 0   // 0..6, rounded → index into captionStrings
        var endCardOpacity: Double = 0
    }

    /// Replay counter held in a Sendable observable so the keyframeAnimator's
    /// `@Sendable` content closure can capture it without violating Swift 6
    /// strict concurrency. `@unchecked Sendable` is safe here because every
    /// mutation happens via the dispatch wrapper below (always on MainActor).
    @Observable
    fileprivate final class ReplayTrigger: @unchecked Sendable {
        var tick: Int = 0
    }

    @State private var trigger = ReplayTrigger()

    var body: some View {
        // The keyframeAnimator content closure is @Sendable. To satisfy
        // Swift 6 strict concurrency we wrap onContinue + onReplay into
        // local @Sendable closures that dispatch back to MainActor — that
        // way nothing the closure captures crosses an actor boundary.
        let sendableContinue: @Sendable () -> Void = { [onContinue] in
            Task { @MainActor in onContinue() }
        }
        let trigger = self.trigger // local capture; ReplayTrigger is Sendable
        let sendableReplay: @Sendable () -> Void = {
            Task { @MainActor in trigger.tick += 1 }
        }

        return Color.clear
            .keyframeAnimator(initialValue: AnimState(), trigger: trigger.tick) { _, s in
                AnimatedScene(
                    state: s,
                    onContinue: sendableContinue,
                    onReplay: sendableReplay
                )
            } keyframes: { _ in
                // Scene-wide opacity: instant fade in over first 0.9s
                KeyframeTrack(\.sceneOpacity) {
                    LinearKeyframe(0, duration: 0.0)
                    CubicKeyframe(1.0, duration: 0.9)
                }

                // Camera zoom — hold 1.2s, then ease to 2.15x over 2s
                KeyframeTrack(\.cameraScale) {
                    LinearKeyframe(1.0, duration: 1.2)
                    CubicKeyframe(2.15, duration: 2.0)
                }
                KeyframeTrack(\.cameraOffsetY) {
                    LinearKeyframe(0, duration: 1.2)
                    CubicKeyframe(30, duration: 2.0)
                }

                // Callouts — each springs in after the zoom settles, then
                // fades out as morning arrives
                KeyframeTrack(\.micOpacity) {
                    LinearKeyframe(0, duration: 3.2)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                    LinearKeyframe(1.0, duration: 3.3)
                    LinearKeyframe(0, duration: 0.8)
                }
                KeyframeTrack(\.motionOpacity) {
                    LinearKeyframe(0, duration: 3.7)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                    LinearKeyframe(1.0, duration: 2.8)
                    LinearKeyframe(0, duration: 0.8)
                }
                KeyframeTrack(\.proximityOpacity) {
                    LinearKeyframe(0, duration: 4.2)
                    SpringKeyframe(1.0, duration: 0.5, spring: .bouncy)
                    LinearKeyframe(1.0, duration: 2.3)
                    LinearKeyframe(0, duration: 0.8)
                }

                // Waveform drawing across the phone screen (tracking)
                KeyframeTrack(\.waveformProgress) {
                    LinearKeyframe(0, duration: 5.2)
                    CubicKeyframe(1.0, duration: 1.3)
                }

                // Morning gradient (night → dawn cross-fade)
                KeyframeTrack(\.dawnProgress) {
                    LinearKeyframe(0, duration: 6.5)
                    CubicKeyframe(1.0, duration: 1.5)
                }

                // Score card spring-pops in during morning
                KeyframeTrack(\.scoreOpacity) {
                    LinearKeyframe(0, duration: 7.0)
                    SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
                }
                KeyframeTrack(\.scoreScale) {
                    LinearKeyframe(0.7, duration: 7.0)
                    SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
                }

                // Coach bubble
                KeyframeTrack(\.coachOpacity) {
                    LinearKeyframe(0, duration: 8.5)
                    SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
                }
                KeyframeTrack(\.coachScale) {
                    LinearKeyframe(0.7, duration: 8.5)
                    SpringKeyframe(1.0, duration: 0.6, spring: .bouncy)
                }

                // Caption index — instant jumps at stage boundaries
                KeyframeTrack(\.captionStep) {
                    LinearKeyframe(0, duration: 1.2)
                    MoveKeyframe(1)
                    LinearKeyframe(1, duration: 2.0)
                    MoveKeyframe(2)
                    LinearKeyframe(2, duration: 2.0)
                    MoveKeyframe(3)
                    LinearKeyframe(3, duration: 1.3)
                    MoveKeyframe(4)
                    LinearKeyframe(4, duration: 2.5)
                    MoveKeyframe(5)
                    LinearKeyframe(5, duration: 2.3)
                    MoveKeyframe(6)
                }

                // End card cross-fade at the end
                KeyframeTrack(\.endCardOpacity) {
                    LinearKeyframe(0, duration: 10.8)
                    CubicKeyframe(1.0, duration: 0.5)
                }
            }
            // The `trigger:` variant of keyframeAnimator only plays on
            // *changes* to the trigger — on first appear it sits at initial
            // values (all opacities 0 → black screen). Bump the trigger once
            // after the view appears so the timeline starts.
            .onAppear {
                if trigger.tick == 0 { trigger.tick = 1 }
            }
    }

}

// MARK: - AnimatedScene
//
// Separate View struct so it can be instantiated from keyframeAnimator's
// @Sendable content closure (View struct init is always nonisolated).

private struct AnimatedScene: View {

    let state: FeatureShowcasePage.AnimState
    // Sendable closures so this struct can be constructed inside a
    // keyframeAnimator's @Sendable content closure under Swift 6.
    let onContinue: @Sendable () -> Void
    let onReplay: @Sendable () -> Void

    private static let captionStrings = [
        "You place your phone down…",                  // 0
        "…and it keeps watch.",                         // 1
        "Three sensors. One quiet night.",              // 2
        "Listening. Measuring. Learning.",              // 3
        "A score waiting for you in the morning.",      // 4
        "An AI coach, on by default.",                  // 5
        ""                                              // 6
    ]

    // Star field — (x, y, size, baseAlpha, phaseOffset). Phase offset gives
    // each star its own twinkle cycle inside TimelineView.
    private let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, alpha: Double, phase: Double)] = [
        (30, 40, 2.0, 0.80, 0.0), (80, 25, 1.5, 0.60, 0.7),
        (180, 30, 2.5, 0.90, 1.4), (250, 50, 1.0, 0.50, 2.1),
        (320, 20, 2.0, 0.70, 2.8), (130, 60, 1.2, 0.40, 3.5),
        (200, 45, 1.8, 0.85, 4.2), (280, 70, 1.5, 0.55, 4.9),
        (50, 80, 1.0, 0.50, 5.6), (350, 90, 1.5, 0.70, 6.3),
        (360, 130, 1.2, 0.50, 0.3), (20, 110, 1.6, 0.60, 1.1)
    ]

    var body: some View {
        ZStack {
            scene
                .opacity(1 - state.endCardOpacity)
                .allowsHitTesting(state.endCardOpacity < 0.5)
                .contentShape(Rectangle())
                // Triple-tap anywhere on the animation skips straight to the
                // next onboarding step. The endCard layer below absorbs taps
                // once it fades in, so this only fires during playback.
                .onTapGesture(count: 3) { onContinue() }
                .overlay(alignment: .bottom) { skipHint }

            endCard
                .opacity(state.endCardOpacity)
                .allowsHitTesting(state.endCardOpacity > 0.5)
        }
    }

    // MARK: - Skip hint
    //
    // Tiny caption at the bottom edge during the first few seconds so users
    // know the triple-tap gesture is available. Fades in with the scene and
    // out once the callouts start appearing (~3.5 s in).

    private var skipHint: some View {
        let hintFade = min(state.sceneOpacity, max(0, 1 - state.micOpacity - state.motionOpacity))
        return Text("Triple-tap anywhere to skip")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.bottom, 24)
            .opacity(hintFade)
            .animation(.easeInOut(duration: 0.3), value: hintFade)
            .allowsHitTesting(false)
    }

    // MARK: - Scene

    private var scene: some View {
        VStack {
            Spacer(minLength: 50)

            ZStack {
                // The "camera" group: night + stars + bed + phone share a
                // single scale/offset so the zoom feels like one motion.
                ZStack {
                    night
                    starField(dawnFade: 1 - state.dawnProgress)
                    bedAndPhone(waveformProgress: state.waveformProgress)
                }
                .scaleEffect(state.cameraScale, anchor: .center)
                .offset(y: state.cameraOffsetY)
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 24))
                // Vignette: radial fade to black at the edges for a
                // cinematic letterbox feel.
                .overlay(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.60)],
                        center: .center,
                        startRadius: 140,
                        endRadius: 300
                    )
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                )

                // Callouts render unscaled on top of the zoomed scene
                calloutBubble(symbol: "mic.fill", title: "Microphone", color: .cyan)
                    .opacity(state.micOpacity)
                    .scaleEffect(0.6 + 0.4 * state.micOpacity)
                    .position(x: 70, y: 295)
                calloutBubble(symbol: "gyroscope", title: "Motion sensors", color: .purple)
                    .opacity(state.motionOpacity)
                    .scaleEffect(0.6 + 0.4 * state.motionOpacity)
                    .position(x: 300, y: 185)
                calloutBubble(symbol: "sensor.fill", title: "Proximity", color: .orange)
                    .opacity(state.proximityOpacity)
                    .scaleEffect(0.6 + 0.4 * state.proximityOpacity)
                    .position(x: 85, y: 90)

                scoreCard
                    .opacity(state.scoreOpacity)
                    .scaleEffect(state.scoreScale)
                    .position(x: 190, y: 120)

                coachBubble
                    .opacity(state.coachOpacity)
                    .scaleEffect(state.coachScale)
                    .position(x: 190, y: 275)
            }
            .frame(height: 360)

            Spacer(minLength: 20)

            Text(Self.captionStrings[captionIndex])
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .opacity(state.sceneOpacity)
                .animation(.easeInOut(duration: 0.35), value: captionIndex)

            Spacer(minLength: 40)
        }
        .opacity(state.sceneOpacity)
        .padding(.horizontal, 20)
    }

    private var captionIndex: Int {
        let rounded = Int(state.captionStep.rounded())
        return max(0, min(Self.captionStrings.count - 1, rounded))
    }

    private var night: some View {
        // Cross-fade night → dawn by stacking with opacity.
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.55, blue: 0.50),
                    Color(red: 0.45, green: 0.28, blue: 0.52)
                ],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.15),
                    .black
                ],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(1 - state.dawnProgress)
        }
    }

    // MARK: - TimelineView-driven continuous effects
    //
    // Stars twinkle and the phone screen glow breathes off a wall clock, so
    // they keep moving regardless of keyframe timing and reset cleanly on
    // replay (no leftover repeatForever animations to unwind).

    private func starField(dawnFade: Double) -> some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(stars.indices, id: \.self) { i in
                    let wave = 0.5 + 0.5 * sin(t * 1.3 + stars[i].phase)
                    let twinkle = 0.35 + 0.65 * wave
                    Circle()
                        .fill(.white.opacity(stars[i].alpha * twinkle * dawnFade))
                        .frame(width: stars[i].size, height: stars[i].size)
                        .position(x: stars[i].x, y: stars[i].y)
                }
            }
        }
    }

    // MARK: - Morning card + coach bubble

    private var scoreCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 3)
                    .frame(width: 34, height: 34)
                Circle()
                    .trim(from: 0, to: 0.85)
                    .stroke(
                        LinearGradient(colors: [.green, .cyan],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 34, height: 34)
                Text("85").font(.caption).fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Sleep Score").font(.caption2).foregroundStyle(.white.opacity(0.8))
                Text("Great recovery").font(.caption2).fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10)
    }

    private var coachBubble: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile.fill")
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .purple],
                                   startPoint: .top, endPoint: .bottom)
                )
                .font(.callout)
            Text("Rest well — HRV up 8%.")
                .font(.caption2).fontWeight(.medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.purple.opacity(0.6), lineWidth: 1))
        .shadow(color: .purple.opacity(0.3), radius: 8)
    }

    private func bedAndPhone(waveformProgress: Double) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 32)
                    .fill(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.72)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 260, height: 90)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

                phone(waveformProgress: waveformProgress).offset(y: -36)
            }
            Rectangle()
                .fill(Color(red: 0.18, green: 0.10, blue: 0.22))
                .frame(height: 80)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                }
        }
    }

    private func phone(waveformProgress: Double) -> some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let pulse = 1.0 + 0.035 * sin(t * .pi * 1.4)

            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(white: 0.10))
                    .frame(width: 92, height: 162)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.15), .black],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 80, height: 150)

                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 72, height: 40)
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle().frame(width: 72 * waveformProgress)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 72, height: 40)
                    )
            }
            .shadow(color: .cyan.opacity(0.30 * pulse), radius: 20 * pulse)
            .scaleEffect(pulse)
        }
    }

    private func calloutBubble(symbol: String, title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.caption)
            Text(title)
                .font(.caption2).fontWeight(.semibold)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
        .shadow(color: color.opacity(0.3), radius: 6)
    }

    // MARK: - End card

    private var endCard: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(colors: [.cyan, .indigo, .purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text("What makes Slumberscope different")
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("Your phone becomes a sleep lab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer(minLength: 20)

            PrimaryButton(title: "Let's go") { onContinue() }
                .padding(.horizontal, 32)

            Button {
                onReplay()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Replay Animation")
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 16)
    }
}
