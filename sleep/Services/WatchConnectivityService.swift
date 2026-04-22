//
//  WatchConnectivityService.swift
//  sleep
//
//

import Foundation
import os
import WatchConnectivity

// MARK: - WatchConnectivityService

/// Manages communication between the iPhone app and the Apple Watch companion app.
/// On the iPhone side this service activates the WCSession and exposes Watch state.
/// The Watch companion app mirrors tracking state and displays summary data.
@Observable
@MainActor
final class WatchConnectivityService: NSObject {

    // MARK: - Observable State

    /// Whether a paired Apple Watch is reachable right now
    var isWatchReachable = false

    /// Whether a Watch companion app is installed
    var isWatchAppInstalled = false

    /// Last heart rate received live from Watch during sleep (bpm)
    var liveHeartRate: Double?

    /// Timestamp of the last heart rate sample received from Watch
    var liveHeartRateTimestamp: Date?

    // MARK: - Pending state
    //
    // When a push is attempted before WCSession is activated, we cache the
    // intent here and replay it the moment activation completes. Without
    // this, every first launch after an app update raced: `.onAppear`
    // pushed user state while WCSession was still activating, nothing
    // reached the watch, and the watch sat on "Set up on iPhone first".

    private struct PendingUserState {
        let signedIn: Bool
        let userName: String
        let userAge: Int
        let sleepGoalHours: Double
    }
    private var pendingUserState: PendingUserState?
    private var pendingTrackingState: (isTracking: Bool, startTime: Date?)?
    private var pendingHistoryJSON: String?

    // MARK: - Init

    override init() {
        super.init()
        // Rehydrate last-known state from UserDefaults so a cold launch can
        // answer the Watch's requestState even before sleepApp's .onAppear
        // has populated fresh values.
        let d = UserDefaults.standard
        if d.object(forKey: "wc_cachedSignedIn") != nil {
            pendingUserState = PendingUserState(
                signedIn: d.bool(forKey: "wc_cachedSignedIn"),
                userName: d.string(forKey: "wc_cachedUserName") ?? "",
                userAge: d.integer(forKey: "wc_cachedUserAge"),
                sleepGoalHours: d.double(forKey: "wc_cachedSleepGoal")
            )
            let state = pendingUserState
            AppLogger.general.info("⌚ Rehydrated user state from UserDefaults — signedIn: \(state?.signedIn ?? false), name: '\(state?.userName ?? "")'")
        }
        activate()
    }

    // MARK: - Activation

    private func activate() {
        guard WCSession.isSupported() else {
            AppLogger.general.info("⌚ WatchConnectivity not supported on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        AppLogger.general.info("⌚ WCSession activation requested")
    }

    // MARK: - Send to Watch

    /// Sends the current tracking state to the Watch so it can mirror the session
    func sendTrackingState(isTracking: Bool, startTime: Date?) {
        pendingTrackingState = (isTracking, startTime)

        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else {
            AppLogger.general.debug("⌚ Caching tracking state — WCSession not activated yet")
            return
        }

        var context = WCSession.default.applicationContext
        context["isTracking"] = isTracking
        if let start = startTime {
            context["startTime"] = start.timeIntervalSince1970
        } else {
            context.removeValue(forKey: "startTime")
        }

        do {
            try WCSession.default.updateApplicationContext(context)
            AppLogger.general.info("⌚ Sent tracking state to watch — isTracking: \(isTracking)")
        } catch {
            AppLogger.error("WatchConnectivity: failed to update context", error: error)
        }
    }

    /// Pushes iPhone sign-in / profile state to the Watch. Without this, a
    /// fresh Watch install shows stale "Last night" data before the user has
    /// even set up the iPhone app. The Watch uses `signedIn` + `userName` to
    /// decide whether to show its Start Tracking UI or a "set up on iPhone
    /// first" prompt.
    func sendUserState(signedIn: Bool, userName: String, userAge: Int = 0, sleepGoalHours: Double = 0) {
        // Always remember the latest intent so we can replay it if WCSession
        // isn't ready yet (e.g. first launch after an app update).
        pendingUserState = PendingUserState(
            signedIn: signedIn,
            userName: userName,
            userAge: userAge,
            sleepGoalHours: sleepGoalHours
        )
        // Also persist so a cold launch can answer the Watch's requestState
        // without having to wait for sleepApp's .onAppear to repopulate.
        let d = UserDefaults.standard
        d.set(signedIn, forKey: "wc_cachedSignedIn")
        d.set(userName, forKey: "wc_cachedUserName")
        d.set(userAge, forKey: "wc_cachedUserAge")
        d.set(sleepGoalHours, forKey: "wc_cachedSleepGoal")

        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else {
            AppLogger.general.debug("⌚ Caching user state — WCSession not activated yet")
            return
        }

        // Merge into the last-known context rather than overwriting — otherwise
        // this call blows away any history we pushed earlier in the same launch.
        var context = WCSession.default.applicationContext
        context["phoneSignedIn"] = signedIn
        context["phoneUserName"] = userName
        context["phoneUserAge"] = userAge
        context["phoneSleepGoalHours"] = sleepGoalHours
        do {
            try WCSession.default.updateApplicationContext(context)
            AppLogger.general.info("⌚ Sent user state to watch — signedIn: \(signedIn), name: \(userName.isEmpty ? "(empty)" : userName), age: \(userAge)")
        } catch {
            AppLogger.error("WatchConnectivity: failed to send user state", error: error)
        }
    }

    /// Pushes the last 7 completed sessions to the Watch so its History tab
    /// can render offline. Sessions are trimmed to a compact snapshot
    /// (no per-sample audio clips, no movement series) to fit the
    /// applicationContext size budget.
    func sendSleepHistory(_ sessions: [SleepSession]) {
        guard WCSession.isSupported() else { return }

        let entries: [WatchSleepHistoryEntry] = sessions
            .sorted { $0.startTime > $1.startTime }
            .prefix(7)
            .map { session in
                let avg = session.averageHeartRateBPM ?? 0
                let minHR = session.minimumHeartRateBPM ?? 0
                var samples: [Double] = []
                if let data = session.watchHeartRateSamplesData,
                   let decoded = try? JSONDecoder().decode([Double].self, from: data) {
                    samples = decoded
                }
                let maxHR = samples.max() ?? minHR
                // Cap per-session events at 60 so the 7-session payload stays
                // under the WC applicationContext budget.
                let events: [WatchClassifiedEventSummary] = session.snoringEvents
                    .sorted { $0.startTime < $1.startTime }
                    .prefix(60)
                    .map {
                        WatchClassifiedEventSummary(
                            label: $0.classification,
                            duration: $0.duration,
                            timestamp: $0.startTime
                        )
                    }
                return WatchSleepHistoryEntry(
                    id: UUID(),
                    startTime: session.startTime,
                    endTime: session.endTime,
                    score: session.sleepScore,
                    qualityLabel: session.quality.label,
                    hrMin: minHR,
                    hrMax: maxHR,
                    hrAvg: avg,
                    hrSamples: samples,
                    snoringCount: session.snoringCount,
                    events: events
                )
            }

        guard let data = try? JSONEncoder.watchHistoryEncoder.encode(entries),
              let json = String(data: data, encoding: .utf8) else {
            AppLogger.general.warning("⌚ Could not encode sleep history")
            return
        }

        // Cache so we can replay if WCSession activates later.
        pendingHistoryJSON = json

        guard WCSession.default.activationState == .activated else {
            AppLogger.general.debug("⌚ Caching \(entries.count) history entries — WCSession not activated yet")
            return
        }

        var context = WCSession.default.applicationContext
        context["sleepHistoryJSON"] = json
        do {
            try WCSession.default.updateApplicationContext(context)
            AppLogger.general.info("⌚ Sent \(entries.count) history entries to watch")
        } catch {
            AppLogger.error("WatchConnectivity: failed to send history", error: error)
        }
    }

    /// Pushes a morning summary to the Watch with full sleep data
    func sendMorningSummary(score: Int, duration: TimeInterval, quality: String,
                            stages: [SleepStageEntry] = [], movementPoints: [MovementDataPoint] = [],
                            hrMin: Double = 0, hrMax: Double = 0, hrAvg: Double = 0,
                            snoringCount: Int = 0,
                            events: [WatchClassifiedEventSummary] = []) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else {
            AppLogger.general.warning("⌚ Cannot send morning summary — session not activated")
            return
        }

        var message: [String: Any] = [
            "type": "morningSummary",
            "score": score,
            "duration": duration,
            "quality": quality,
            "snoringCount": snoringCount,
            "hrMin": hrMin,
            "hrMax": hrMax,
            "hrAvg": hrAvg
        ]

        // Encode stages and movement as JSON strings
        if let stagesData = try? JSONEncoder().encode(stages),
           let stagesString = String(data: stagesData, encoding: .utf8) {
            message["stagesJSON"] = stagesString
        }

        // Downsample movement to every 5th point to keep payload small
        let downsampled = movementPoints.enumerated().compactMap { i, p in i % 5 == 0 ? p : nil }
        if let movData = try? JSONEncoder().encode(downsampled),
           let movString = String(data: movData, encoding: .utf8) {
            message["movementJSON"] = movString
        }

        // Classified events (dog, cat, voice, snoring, …) so the watch's
        // post-sleep Summary card shows a per-category breakdown instead of
        // a single "snoring" count.
        if let evData = try? JSONEncoder.watchHistoryEncoder.encode(events.prefix(60).map { $0 }),
           let evString = String(data: evData, encoding: .utf8) {
            message["eventsJSON"] = evString
        }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                AppLogger.error("Failed to send morning summary to watch via message", error: error)
            }
            AppLogger.general.info("⌚ Sent morning summary to watch via message — score: \(score)")
        } else {
            do {
                try WCSession.default.updateApplicationContext(message)
                AppLogger.general.info("⌚ Sent morning summary to watch via context — score: \(score)")
            } catch {
                AppLogger.error("Failed to send morning summary to watch via context", error: error)
            }
        }
    }

    /// Sends current snoring event count to Watch during tracking
    func sendSnoringCount(_ count: Int) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["snoringCount": count], replyHandler: nil) { error in
            AppLogger.error("Failed to send snoring count to watch", error: error)
        }
        AppLogger.general.debug("⌚ Sent snoring count to watch: \(count)")
    }
}

// MARK: - WCSessionDelegate

// MARK: - JSON encoder shared with Watch side

extension JSONEncoder {
    /// Encoder used for WatchConnectivity payloads. Matches the decoder in
    /// sleepWatch/Services/WatchSessionManager.swift — both sides must use
    /// the same date strategy or Watch-side decoding returns empty arrays.
    static let watchHistoryEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    /// Matches watchHistoryEncoder so iPhone-side code can round-trip payloads
    /// (e.g. the morning-summary eventsJSON bounced through NotificationCenter).
    static let watchHistoryDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension WatchConnectivityService: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        let installed = session.isWatchAppInstalled
        let stateRaw = activationState.rawValue
        let errDesc = error?.localizedDescription
        let activated = (activationState == .activated)
        Task { @MainActor [weak self] in
            self?.isWatchReachable = reachable
            self?.isWatchAppInstalled = installed
            if let errDesc {
                AppLogger.general.error("⌚ Watch activation failed: \(errDesc)")
            } else {
                AppLogger.general.info("⌚ Watch activation completed — reachable: \(reachable), app installed: \(installed), state: \(stateRaw)")
            }
            if activated {
                // Flush anything that tried to push before activation.
                self?.flushPendingContext()
                // Also tell the app it can query for fresh state (e.g. sleep
                // history from SwiftData) and push now.
                NotificationCenter.default.post(name: .watchReadyToReceive, object: nil)
            }
        }
    }

    /// Re-send any cached user state / tracking state / history that tried
    /// to push while WCSession was still activating. Called on activation
    /// complete and when reachability flips to true.
    private func flushPendingContext() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }

        var context = WCSession.default.applicationContext
        var changed = false

        if let state = pendingUserState {
            context["phoneSignedIn"] = state.signedIn
            context["phoneUserName"] = state.userName
            context["phoneUserAge"] = state.userAge
            context["phoneSleepGoalHours"] = state.sleepGoalHours
            changed = true
        }
        if let tracking = pendingTrackingState {
            context["isTracking"] = tracking.isTracking
            if let start = tracking.startTime {
                context["startTime"] = start.timeIntervalSince1970
            } else {
                context.removeValue(forKey: "startTime")
            }
            changed = true
        }
        if let json = pendingHistoryJSON {
            context["sleepHistoryJSON"] = json
            changed = true
        }

        guard changed else { return }
        do {
            try WCSession.default.updateApplicationContext(context)
            AppLogger.general.info("⌚ Flushed pending context to watch (userState: \(self.pendingUserState != nil), history: \(self.pendingHistoryJSON != nil))")
        } catch {
            AppLogger.error("WatchConnectivity: failed to flush pending context", error: error)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            let wasReachable = self.isWatchReachable
            self.isWatchReachable = reachable
            AppLogger.general.info("⌚ Watch reachability changed: \(wasReachable) → \(reachable)")

            NotificationCenter.default.post(
                name: .watchReachabilityChanged,
                object: nil,
                userInfo: ["reachable": reachable]
            )
            if reachable {
                self.flushPendingContext()
                NotificationCenter.default.post(name: .watchReadyToReceive, object: nil)
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        AppLogger.general.info("⌚ Watch session became inactive")
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        AppLogger.general.info("⌚ Watch session deactivated — reactivating")
        WCSession.default.activate()
    }

    /// Receives messages from the Watch (heart rate, commands, movement data)
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        AppLogger.general.debug("⌚ Received message from watch: \(message.keys.joined(separator: ", "))")
        nonisolated(unsafe) let snapshot = message
        Task { @MainActor [weak self] in
            self?.handleIncomingWatchData(snapshot)
        }
    }

    /// sendMessage with replyHandler variant. The Watch's `requestState`
    /// uses this path: the iPhone computes the current profile + history
    /// inline and ships it back in the reply, avoiding any reliance on the
    /// updateApplicationContext delivery queue.
    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        AppLogger.general.debug("⌚ Received message (with reply) from watch: \(message.keys.joined(separator: ", "))")
        nonisolated(unsafe) let snapshot = message
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor [weak self] in
            guard let self else {
                reply([:])
                return
            }
            if let command = snapshot["command"] as? String, command == "requestState" {
                let payload = self.currentStateSnapshotPayload()
                let signedIn = payload["phoneSignedIn"] as? Bool ?? false
                let name = payload["phoneUserName"] as? String ?? "(nil)"
                let age = payload["phoneUserAge"] as? Int ?? 0
                let historyLen = (payload["sleepHistoryJSON"] as? String)?.count ?? 0
                AppLogger.general.info("⌚ Replying to watch requestState — signedIn: \(signedIn), name: \(name), age: \(age), historyJSON: \(historyLen) chars, keys: \(payload.keys.joined(separator: ", "))")
                if payload.isEmpty {
                    AppLogger.general.warning("⌚ WARNING: replying with empty payload — pendingUserState=\(self.pendingUserState != nil), pendingHistory=\(self.pendingHistoryJSON != nil), pendingTracking=\(self.pendingTrackingState != nil)")
                }
                reply(payload)
            } else {
                self.handleIncomingWatchData(snapshot)
                reply([:])
            }
        }
    }

    /// Send the current cached state directly to the Watch via
    /// sendMessage. Works even when updateApplicationContext is silently
    /// dropped, as long as the Watch app is foreground (isReachable).
    /// If the Watch isn't reachable, falls back to transferUserInfo so
    /// iOS queues and delivers later.
    func pushStateToWatchViaMessage() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else {
            AppLogger.general.warning("⌚ pushStateToWatchViaMessage: WCSession not activated")
            return
        }

        // Build the payload. If we have nothing cached, still ship a ping
        // with ack=true so the Watch at least knows we received the request
        // and can surface that in its diagnostics.
        var typed = currentStateSnapshotPayload()
        typed["messageType"] = "stateSnapshot"
        typed["phoneAck"] = true
        let signedIn = typed["phoneSignedIn"] as? Bool ?? false
        let name = typed["phoneUserName"] as? String ?? "(nil)"
        let historyLen = (typed["sleepHistoryJSON"] as? String)?.count ?? 0

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(typed, replyHandler: nil) { error in
                AppLogger.general.error("⌚ sendMessage(stateSnapshot) failed: \(error.localizedDescription)")
            }
            AppLogger.general.info("⌚ Pushed state via sendMessage — signedIn: \(signedIn), name: \(name), historyJSON: \(historyLen) chars, keys: \(typed.keys.joined(separator: ", "))")
        } else {
            WCSession.default.transferUserInfo(typed)
            AppLogger.general.info("⌚ Watch not reachable — queued state via transferUserInfo")
        }
    }

    /// Build a payload that mirrors the applicationContext shape so the
    /// Watch's handlePayload can parse it identically.
    private func currentStateSnapshotPayload() -> [String: Any] {
        var payload: [String: Any] = [:]
        if let state = pendingUserState {
            payload["phoneSignedIn"] = state.signedIn
            payload["phoneUserName"] = state.userName
            payload["phoneUserAge"] = state.userAge
            payload["phoneSleepGoalHours"] = state.sleepGoalHours
        }
        if let json = pendingHistoryJSON {
            payload["sleepHistoryJSON"] = json
        }
        if let tracking = pendingTrackingState {
            payload["isTracking"] = tracking.isTracking
            if let start = tracking.startTime {
                payload["startTime"] = start.timeIntervalSince1970
            }
        }
        return payload
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        AppLogger.general.debug("⌚ Received application context from watch: \(applicationContext.keys.joined(separator: ", "))")
        nonisolated(unsafe) let snapshot = applicationContext
        Task { @MainActor [weak self] in
            self?.handleIncomingWatchData(snapshot)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        AppLogger.general.debug("⌚ Received user info from watch: \(userInfo.keys.joined(separator: ", "))")
        nonisolated(unsafe) let snapshot = userInfo
        Task { @MainActor [weak self] in
            self?.handleIncomingWatchData(snapshot)
        }
    }

    private func handleIncomingWatchData(_ data: [String: Any]) {
        // Heart rate with timestamp
        if let hr = data["heartRate"] as? Double {
            self.liveHeartRate = hr
            if let ts = data["heartRateTimestamp"] as? TimeInterval {
                self.liveHeartRateTimestamp = Date(timeIntervalSince1970: ts)
            } else {
                self.liveHeartRateTimestamp = Date()
            }
            AppLogger.general.debug("⌚ Heart rate from watch: \(Int(hr)) BPM")
        }

        // Commands from watch (start/stop tracking, request state). Tag
        // userInfo with source=watch so the app-level handler can auto-save
        // on stop (the user isn't going to open Morning Review on their wrist).
        if let command = data["command"] as? String {
            AppLogger.general.info("⌚ Received command from watch: \(command)")
            switch command {
            case "startTracking":
                NotificationCenter.default.post(
                    name: .startTrackingIntent,
                    object: nil,
                    userInfo: ["source": "watch"]
                )
            case "stopTracking":
                NotificationCenter.default.post(
                    name: .stopTrackingIntent,
                    object: nil,
                    userInfo: ["source": "watch"]
                )
            case "requestState":
                // Watch just activated and is asking for current profile +
                // history. Respond with whatever we have cached (even if
                // incomplete) so the Watch's UI unsticks, then signal
                // sleepApp to fetch fresh SwiftData-backed history and
                // repush via both transport paths.
                let payload = self.currentStateSnapshotPayload()
                AppLogger.general.info("⌚ requestState received — cached payload: \(payload.keys.joined(separator: ", ")), signedIn: \(payload["phoneSignedIn"] as? Bool ?? false), name: '\(payload["phoneUserName"] as? String ?? "")'")
                self.flushPendingContext()
                self.pushStateToWatchViaMessage()
                NotificationCenter.default.post(name: .watchReadyToReceive, object: nil)
            default:
                AppLogger.general.warning("⌚ Unknown watch command: \(command)")
            }
        }

        // Movement data from watch accelerometer
        if let movJSON = data["movementJSON"] as? String,
           let movData = movJSON.data(using: .utf8),
           let points = try? JSONDecoder().decode([MovementDataPoint].self, from: movData) {
            AppLogger.general.info("⌚ Received \(points.count) movement data points from watch")
            NotificationCenter.default.post(name: .watchMovementData, object: nil,
                                            userInfo: ["points": points])
        }

        // Classifier event from Watch's own audio pipeline. Watch sends
        // {"type": "watchClassifierEvent", "label": ..., "confidence": ...}
        // when its mic caught something the YAMNet server labeled as a
        // snore/bark/meow/etc.
        if data["type"] as? String == "watchClassifierEvent",
           let label = data["label"] as? String,
           let confidence = data["confidence"] as? Double {
            AppLogger.general.info("⌚ Received classifier event from watch: \(label) (\(String(format: "%.2f", confidence)))")
            NotificationCenter.default.post(
                name: .watchClassifierEvent,
                object: nil,
                userInfo: [
                    "label": label,
                    "confidence": confidence,
                    "timestamp": (data["timestamp"] as? TimeInterval) ?? Date().timeIntervalSince1970
                ]
            )
        }
    }
}
