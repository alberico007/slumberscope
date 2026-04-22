//
//  sleepApp.swift
//  sleep
//
//

import FirebaseCore
import os
import SwiftData
import SwiftUI

// MARK: - Model Container with migration handling

private let sleepModelContainer: ModelContainer = {
    let schema = Schema([SleepSession.self, SleepFactor.self, SoundPreset.self])
    let config = ModelConfiguration(schema: schema)
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        AppLogger.error("SwiftData container failed — deleting store and retrying", error: error)
        let storeURL = config.url
        try? FileManager.default.removeItem(at: storeURL)
        let walURL = storeURL.appendingPathExtension("wal")
        let shmURL = storeURL.appendingPathExtension("shm")
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer even after reset: \(error)")
        }
    }
}()

@main
struct sleepApp: App {

    @Environment(\.scenePhase) private var scenePhase

    @State private var settings = SleepSettings()
    @State private var trackingService = SleepTrackingService()
    @State private var weatherService = WeatherService()
    @State private var watchService = WatchConnectivityService()
    @State private var storeKitService = StoreKitService()
    @State private var authService = AuthenticationService()
    @State private var cloudService = CloudSyncService()
    @State private var soundService = SoundService()
    @State private var mediaService = MediaPlaybackService()
    @State private var podcastService = PodcastService()
    @State private var soundClassifier = SoundClassificationService()
    @State private var intelligenceService = IntelligenceService()
    @State private var snoringClassifierClient = SnoringClassifierClient()

    init() {
        FirebaseApp.configure()
        if let app = FirebaseApp.app() {
            AppLogger.appEvent("Firebase configured — project: \(app.options.projectID ?? "unknown")")
        } else {
            AppLogger.error("Firebase failed to configure", error: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(trackingService)
                .environment(weatherService)
                .environment(watchService)
                .environment(storeKitService)
                .environment(authService)
                .environment(cloudService)
                .environment(soundService)
                .environment(mediaService)
                .environment(podcastService)
                .environment(soundClassifier)
                .environment(intelligenceService)
                .environment(snoringClassifierClient)
                .onAppear {
                    AppLogger.appEvent("App launched — configuring services")
                    trackingService.configure(settings: settings, watchService: watchService)
                    trackingService.intelligenceService = intelligenceService
                    // Give AuthenticationService a handle to settings so that
                    // Firebase sign-in can restore the user's name/age/gender
                    // from Firestore when Apple doesn't hand back fullName.
                    authService.settings = settings
                    // Wire the environmental classifier into AudioService so
                    // fan/AC/dog/speech don't get counted as snores.
                    trackingService.audioService.attachClassifier(soundClassifier)
                    trackingService.audioService.environmentalFilteringEnabled = settings.environmentalNoiseFilteringEnabled
                    // Wire the remote YAMNet classifier. It stays dormant
                    // until the user enables the Cloud Snoring Classifier
                    // toggle in Settings.
                    trackingService.audioService.attachRemoteClassifier(snoringClassifierClient)
                    snoringClassifierClient.enabled = settings.cloudSnoringClassifierEnabled
                    // Tell AudioService who's playing so it can suppress
                    // snoring while the user's own audio is coming out of
                    // the speaker.
                    trackingService.audioService.attachMediaPlayback(mediaService)
                    // Give MediaPlaybackService a handle to SoundService for
                    // the sleep-sound / meditation / story routing.
                    mediaService.soundService = soundService
                    Task {
                        await cloudService.checkCloudStatus()
                    }
                    // Push current sign-in state to the Watch so it knows
                    // whether to show its Idle UI or a "set up on iPhone
                    // first" prompt.
                    watchService.sendUserState(
                        signedIn: authService.isSignedIn,
                        userName: settings.userName,
                        userAge: settings.userAge,
                        sleepGoalHours: settings.sleepGoalHours
                    )
                    pushSleepHistoryToWatch()
                }
                .onChange(of: authService.isSignedIn) { _, signedIn in
                    watchService.sendUserState(
                        signedIn: signedIn,
                        userName: settings.userName,
                        userAge: settings.userAge,
                        sleepGoalHours: settings.sleepGoalHours
                    )
                    pushSleepHistoryToWatch()
                }
                .onChange(of: settings.userName) { _, newName in
                    watchService.sendUserState(
                        signedIn: authService.isSignedIn,
                        userName: newName,
                        userAge: settings.userAge,
                        sleepGoalHours: settings.sleepGoalHours
                    )
                }
                .onChange(of: settings.userAge) { _, newAge in
                    watchService.sendUserState(
                        signedIn: authService.isSignedIn,
                        userName: settings.userName,
                        userAge: newAge,
                        sleepGoalHours: settings.sleepGoalHours
                    )
                }
                .onChange(of: settings.sleepGoalHours) { _, newGoal in
                    watchService.sendUserState(
                        signedIn: authService.isSignedIn,
                        userName: settings.userName,
                        userAge: settings.userAge,
                        sleepGoalHours: newGoal
                    )
                }
                .onChange(of: settings.environmentalNoiseFilteringEnabled) { _, newValue in
                    trackingService.audioService.environmentalFilteringEnabled = newValue
                }
                .onChange(of: settings.cloudSnoringClassifierEnabled) { _, newValue in
                    snoringClassifierClient.enabled = newValue
                }
                .onChange(of: trackingService.phase) { _, newPhase in
                    AppLogger.tracking.info("Phase changed → \(String(describing: newPhase))")
                    switch newPhase {
                    case .tracking, .calibrating:
                        watchService.sendTrackingState(isTracking: true, startTime: trackingService.startTime)
                    case .idle, .done:
                        watchService.sendTrackingState(isTracking: false, startTime: nil)
                        pushSleepHistoryToWatch()
                    case .completing:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchMorningSummary)) { notification in
                    guard let info = notification.userInfo,
                          let score = info["score"] as? Int,
                          let duration = info["duration"] as? Double,
                          let quality = info["quality"] as? String else { return }

                    // Decode stages and movement if available
                    var stages: [SleepStageEntry] = []
                    var movement: [MovementDataPoint] = []
                    if let stagesJSON = info["stagesJSON"] as? String,
                       let data = stagesJSON.data(using: .utf8) {
                        stages = (try? JSONDecoder().decode([SleepStageEntry].self, from: data)) ?? []
                    }
                    if let movJSON = info["movementJSON"] as? String,
                       let data = movJSON.data(using: .utf8) {
                        movement = (try? JSONDecoder().decode([MovementDataPoint].self, from: data)) ?? []
                    }
                    var events: [WatchClassifiedEventSummary] = []
                    if let evJSON = info["eventsJSON"] as? String,
                       let data = evJSON.data(using: .utf8) {
                        events = (try? JSONDecoder.watchHistoryDecoder.decode([WatchClassifiedEventSummary].self, from: data)) ?? []
                    }

                    watchService.sendMorningSummary(
                        score: score, duration: duration, quality: quality,
                        stages: stages, movementPoints: movement,
                        hrMin: info["hrMin"] as? Double ?? 0,
                        hrMax: info["hrMax"] as? Double ?? 0,
                        hrAvg: info["hrAvg"] as? Double ?? 0,
                        snoringCount: info["snoringCount"] as? Int ?? 0,
                        events: events
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchSnoringCountUpdate)) { notification in
                    if let count = notification.userInfo?["count"] as? Int {
                        watchService.sendSnoringCount(count)
                    }
                }
                .onChange(of: watchService.liveHeartRate) { _, newHR in
                    if let hr = newHR {
                        trackingService.updateWatchHR(hr)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .startTrackingIntent)) { notification in
                    let source = (notification.userInfo?["source"] as? String) ?? "iphone"
                    AppLogger.tracking.info("🟢 Received startTrackingIntent (app-level) — phase: \(String(describing: trackingService.phase)), source: \(source)")
                    if trackingService.phase == .idle {
                        trackingService.startTracking(watchInitiated: source == "watch")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .stopTrackingIntent)) { notification in
                    let source = (notification.userInfo?["source"] as? String) ?? "iphone"
                    AppLogger.tracking.info("🔴 Received stopTrackingIntent (app-level) — phase: \(String(describing: trackingService.phase)), source: \(source)")
                    if trackingService.phase == .tracking || trackingService.phase == .calibrating {
                        trackingService.stopTracking()
                    }
                    // A stop triggered from the Watch (or any non-iPhone
                    // surface) can't fill out the Morning Review, so auto-save
                    // with a default fair quality rating. Runs async so the
                    // remote classifier drain inside saveSession can complete.
                    if source == "watch" {
                        Task {
                            AppLogger.tracking.info("💾 Auto-saving session from Watch-initiated stop")
                            let context = ModelContext(sleepModelContainer)
                            let saved = await trackingService.saveSession(
                                quality: .fair,
                                notes: "Stopped from Apple Watch",
                                modelContext: context,
                                cloudService: cloudService
                            )
                            if let saved {
                                AppLogger.tracking.info("✅ Auto-saved Watch session — score: \(saved.sleepScore), duration: \(Int(saved.durationSeconds))s")
                            } else {
                                AppLogger.tracking.warning("⚠️ Auto-save returned nil — nothing to save?")
                            }
                            pushSleepHistoryToWatch()
                        }
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Every time the iPhone app comes to foreground, re-push
                    // the latest user state and history to the Watch. Covers
                    // the after-install / after-sign-up cases where the Watch
                    // was stuck on "Set up on iPhone first" because the initial
                    // push raced with WCSession activation.
                    if newPhase == .active {
                        AppLogger.general.info("📱 Scene active — re-pushing watch state (signedIn: \(authService.isSignedIn), name: '\(settings.userName)', age: \(settings.userAge), goal: \(settings.sleepGoalHours)h)")
                        watchService.sendUserState(
                            signedIn: authService.isSignedIn,
                            userName: settings.userName,
                            userAge: settings.userAge,
                            sleepGoalHours: settings.sleepGoalHours
                        )
                        pushSleepHistoryToWatch()
                        // Also try direct sendMessage — more reliable than
                        // updateApplicationContext on fresh sim pairs.
                        watchService.pushStateToWatchViaMessage()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchClassifierEvent)) { notification in
                    guard let info = notification.userInfo,
                          let label = info["label"] as? String,
                          let confidence = info["confidence"] as? Double else { return }
                    let ts = (info["timestamp"] as? TimeInterval).map { Date(timeIntervalSince1970: $0) } ?? Date()
                    AppLogger.tracking.info("⌚ Handling watch classifier event: \(label) (\(String(format: "%.2f", confidence)))")
                    trackingService.audioService.commitWatchClassifiedEvent(
                        label: label,
                        confidence: confidence,
                        at: ts
                    )
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchReadyToReceive)) { _ in
                    // WCSession just activated / Watch asked for state.
                    // Push via sendMessage (fast + reliable) and via
                    // updateApplicationContext (persistent).
                    AppLogger.general.info("⌚ watchReadyToReceive — pushing state (signedIn: \(authService.isSignedIn), name: '\(settings.userName)')")
                    watchService.sendUserState(
                        signedIn: authService.isSignedIn,
                        userName: settings.userName,
                        userAge: settings.userAge,
                        sleepGoalHours: settings.sleepGoalHours
                    )
                    pushSleepHistoryToWatch()
                    watchService.pushStateToWatchViaMessage()
                }
        }
        .modelContainer(sleepModelContainer)
    }

    /// Fetches the most recent 20 sleep sessions from SwiftData and pushes
    /// the last 7 to the Watch so its History tab renders offline.
    private func pushSleepHistoryToWatch() {
        let context = ModelContext(sleepModelContainer)
        var descriptor = FetchDescriptor<SleepSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        if let sessions = try? context.fetch(descriptor) {
            watchService.sendSleepHistory(sessions)
        }
    }
}
