//
//  ContentView.swift
//  sleep
//
//

import os
import SwiftUI

enum AppTab: Hashable {
    case home, track, reports, settings
}

struct ContentView: View {

    @Environment(SleepSettings.self) private var settings
    @Environment(SleepTrackingService.self) private var trackingService

    @State private var showingOnboarding = false
    @State private var selectedTab: AppTab = .home

    var body: some View {
        Group {
            if !settings.hasCompletedOnboarding {
                // Render onboarding as the root view (not as a cover over
                // the Home tab) so users don't see the main UI flicker
                // behind it at launch.
                OnboardingView {
                    settings.hasCompletedOnboarding = true
                }
                .transition(.opacity)
            } else {
                TabView(selection: $selectedTab) {
                    Tab("Home", systemImage: "house.fill", value: .home) {
                        HomeView(selectedTab: $selectedTab)
                    }

                    Tab("Track", systemImage: "moon.zzz.fill", value: .track) {
                        TonightView()
                    }

                    Tab("Reports", systemImage: "chart.line.uptrend.xyaxis", value: .reports) {
                        ReportsView()
                    }

                    Tab("Settings", systemImage: "gearshape", value: .settings) {
                        SettingsView()
                    }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: settings.hasCompletedOnboarding)
        .onAppear {
            AppLogger.ui.info("ContentView appeared — onboarding completed: \(settings.hasCompletedOnboarding)")
        }
        .onChange(of: settings.hasCompletedOnboarding) { _, completed in
            if !completed {
                selectedTab = .home
            }
        }
    }
}
