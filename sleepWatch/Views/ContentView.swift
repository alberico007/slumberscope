//
//  ContentView.swift
//  sleepWatch

import os
import SwiftUI

struct ContentView: View {

    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var heartRateService: HeartRateService
    @EnvironmentObject var watchMotionService: WatchMotionService
    @EnvironmentObject var watchAudioService: WatchAudioService

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.08, green: 0.04, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            switch sessionManager.appState {
            case .idle:
                if sessionManager.phoneSignedIn && !sessionManager.phoneUserName.isEmpty {
                    MainTabs()
                        .onAppear { WatchLogger.ui.info("View → Tabs (idle + signed in)") }
                } else {
                    NavigationStack {
                        IdleView()
                    }
                    .onAppear {
                        WatchLogger.ui.info("View → Idle (setup prompt)")
                        // If we're stuck on the setup prompt it's almost
                        // always because iPhone hasn't pushed state yet.
                        // Ping it actively so the Watch doesn't linger here.
                        sessionManager.requestStateFromPhone()
                    }
                }
            case .tracking(let startTime):
                TrackingView(startTime: startTime)
                    .onAppear {
                        WatchLogger.ui.info("View → Tracking — starting services")

                        // Wire HR callback to send data to iPhone
                        heartRateService.onHeartRateSample = { bpm in
                            sessionManager.sendHeartRate(bpm)
                        }

                        // Wire motion callback to send batches to iPhone
                        watchMotionService.onMovementBatch = { points in
                            sessionManager.sendMovementData(points)
                        }

                        // Start services
                        Task {
                            await heartRateService.requestAuthorization()
                            heartRateService.startMonitoring()
                            WatchLogger.heartRate.info("Heart rate monitoring started")
                        }
                        watchMotionService.startTracking()
                        watchAudioService.startRecording()
                    }
                    .onDisappear {
                        WatchLogger.ui.info("TrackingView disappearing — stopping services")
                        heartRateService.stopMonitoring()
                        heartRateService.onHeartRateSample = nil
                        watchMotionService.stopTracking()
                        watchMotionService.onMovementBatch = nil
                        watchAudioService.stopRecording()
                    }
            case .summary(let data):
                SummaryView(summaryData: data)
                    .onAppear {
                        WatchLogger.ui.info("View → Summary (score: \(data.score))")
                    }
            }
        }
    }
}

// MARK: - MainTabs

/// Three-tab layout for the signed-in Watch app: Tracking, History, Settings.
/// Each tab is its own NavigationStack so pushes (session detail, legal
/// pages) stay scoped to the tab the user is on.
private struct MainTabs: View {
    var body: some View {
        TabView {
            NavigationStack {
                IdleView()
            }

            NavigationStack {
                HistoryView()
            }

            NavigationStack {
                WatchSettingsView()
            }
        }
        .tabViewStyle(.page)
    }
}
