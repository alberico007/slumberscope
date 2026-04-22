//
//  IdleView.swift
//  sleepWatch

import os
import SwiftUI

struct IdleView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager
    @State private var pulseAnimation = false
    @State private var retryTimer: Timer?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {

                // App icon
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.15))
                        .frame(width: 50, height: 50)
                        .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                if !sessionManager.phoneSignedIn || sessionManager.phoneUserName.isEmpty {
                    setupOnPhonePrompt
                } else {
                    // Last night's summary
                    if let score = sessionManager.lastScore,
                       let duration = sessionManager.lastDuration,
                       let quality = sessionManager.lastQuality {
                        lastNightCard(score: score, duration: duration, quality: quality)
                    } else {
                        Text("No sleep data yet")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    // Start Tracking button
                    Button {
                        WatchLogger.ui.info("User tapped Start Tracking")
                        sessionManager.sendCommand("startTracking")
                    } label: {
                        Label("Start Tracking", systemImage: "bed.double.fill")
                            .font(.system(.callout, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
            }
            .padding(.horizontal, 4)
        }
        .onAppear {
            pulseAnimation = true
            startAutoRetryIfNeeded()
        }
        .onDisappear {
            retryTimer?.invalidate()
            retryTimer = nil
        }
        .onChange(of: sessionManager.phoneSignedIn) { _, signedIn in
            // Once iPhone confirms sign-in, stop polling.
            if signedIn { stopAutoRetry() } else { startAutoRetryIfNeeded() }
        }
    }

    /// Auto-poll the iPhone every 3 s while the setup prompt is visible so
    /// the user doesn't have to tap Retry manually. Timer is torn down as
    /// soon as we receive phoneSignedIn=true or the view disappears.
    private func startAutoRetryIfNeeded() {
        guard retryTimer == nil else { return }
        guard !sessionManager.phoneSignedIn || sessionManager.phoneUserName.isEmpty else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                guard !sessionManager.phoneSignedIn || sessionManager.phoneUserName.isEmpty else {
                    stopAutoRetry()
                    return
                }
                sessionManager.requestStateFromPhone()
            }
        }
    }

    private func stopAutoRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    // MARK: - Setup prompt

    private var setupOnPhonePrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 24))
                .foregroundStyle(.cyan)
            Text("Set up on iPhone first")
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("Open Slumberscope on your iPhone and finish signing in to start tracking here.")
                .font(.system(.caption2, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            diagnosticsCard
                .padding(.top, 6)

            Button {
                WatchLogger.ui.info("User tapped Retry connection")
                sessionManager.requestStateFromPhone()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .padding(.top, 2)

        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Diagnostics")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            diagRow("Activation", activationText)
            diagRow("Reachable", sessionManager.diagIsReachable ? "yes" : "no")
            diagRow("iPhone app", sessionManager.diagIsCompanionInstalled ? "installed" : "not installed")
            if let sent = sessionManager.diagLastRequestSent {
                diagRow("Last request", relative(sent))
            }
            if let recv = sessionManager.diagLastReceived {
                diagRow("Last reply", relative(recv))
            } else {
                diagRow("Last reply", "none")
            }
            if let err = sessionManager.diagLastError {
                diagRow("Error", err).foregroundStyle(.red)
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 9, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
    }

    private var activationText: String {
        switch sessionManager.diagActivationState {
        case 0: "notActivated"
        case 1: "inactive"
        case 2: "activated"
        default: "state=\(sessionManager.diagActivationState)"
        }
    }

    private func relative(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 1 { return "now" }
        if secs < 60 { return "\(secs)s ago" }
        let m = secs / 60
        return "\(m)m ago"
    }

    // MARK: - Last Night Card

    private func lastNightCard(score: Int, duration: TimeInterval, quality: String) -> some View {
        VStack(spacing: 8) {
            Text("Last Night")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                // Score ring
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 4)
                        .frame(width: 36, height: 36)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(scoreColor(score), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90))
                    Text("\(score)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(duration))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(quality)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80:  return .cyan
        case 40..<60:  return .yellow
        default:       return .orange
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        return "\(h)h \(m)m"
    }
}
