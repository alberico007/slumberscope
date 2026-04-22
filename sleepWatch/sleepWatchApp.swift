//
//  sleepWatchApp.swift
//  sleepWatch

import os
import SwiftUI

@main
struct sleepWatchApp: App {

    @StateObject private var sessionManager = WatchSessionManager()
    @StateObject private var heartRateService = HeartRateService()
    @StateObject private var watchMotionService = WatchMotionService()
    @StateObject private var watchAudioService = WatchAudioService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .environmentObject(heartRateService)
                .environmentObject(watchMotionService)
                .environmentObject(watchAudioService)
                .onAppear {
                    WatchLogger.general.info("Watch app launched")
                    sessionManager.activate()
                    watchAudioService.onClassifiedEvent = { [weak sessionManager] label, confidence in
                        sessionManager?.sendClassifiedEvent(label: label, confidence: confidence)
                    }
                }
        }
    }
}
