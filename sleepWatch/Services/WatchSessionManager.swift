//
//  WatchSessionManager.swift
//  sleepWatch

import Combine
import Foundation
import os
@preconcurrency import WatchConnectivity

// MARK: - Watch Logger

/// Centralized logger for watch app (mirrors iPhone AppLogger pattern)
enum WatchLogger {
    private static let subsystem = "com.smarterpillow.sleepWatch"

    static let general = Logger(subsystem: subsystem, category: "general")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let heartRate = Logger(subsystem: subsystem, category: "heartrate")
    static let motion = Logger(subsystem: subsystem, category: "motion")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

// MARK: - WatchAppState

enum WatchAppState {
    case idle
    case tracking(startTime: Date)
    case summary(data: SleepSummaryData)
}

struct SleepSummaryData {
    let score: Int
    let duration: TimeInterval
    let quality: String
    let stages: [SleepStageEntry]
    let movement: [MovementDataPoint]
    let hrMin: Double
    let hrMax: Double
    let hrAvg: Double
    let snoringCount: Int
    let events: [WatchClassifiedEventSummary]
}

// MARK: - WatchSessionManager

@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    @Published var appState: WatchAppState = .idle

    // Live tracking data from iPhone
    @Published var snoringCount: Int = 0

    // iPhone profile state. Default to `false` so a fresh Watch install
    // shows "set up on iPhone first" rather than a half-baked stat card
    // before it hears from the phone.
    @Published var phoneSignedIn: Bool = false
    @Published var phoneUserName: String = ""
    @Published var phoneUserAge: Int = 0
    @Published var phoneSleepGoalHours: Double = 0

    // Recent sleep history pushed from iPhone (last 7 sessions, most recent first)
    @Published var sleepHistory: [WatchSleepHistoryEntry] = []

    // Diagnostic state shown on the setup-prompt UI so the user can see
    // WHY we haven't heard from iPhone yet.
    @Published var diagActivationState: Int = 0
    @Published var diagIsReachable: Bool = false
    @Published var diagIsCompanionInstalled: Bool = false
    @Published var diagLastRequestSent: Date?
    @Published var diagLastReceived: Date?
    @Published var diagLastError: String?

    // Last sleep summary — persisted across launches
    @Published var lastScore: Int?
    @Published var lastDuration: TimeInterval?
    @Published var lastQuality: String?

    /// Timestamp of the most recent session END we know about. Used to
    /// ignore stale `isTracking:true` application contexts whose startTime
    /// predates this value — those are leftover deliveries from iOS's
    /// WatchConnectivity queue and would otherwise bounce the watch back
    /// into the tracking screen after a session ended.
    private var lastSessionEndedAt: Date?
    @Published var lastStages: [SleepStageEntry] = []
    @Published var lastMovement: [MovementDataPoint] = []
    @Published var lastHRMin: Double?
    @Published var lastHRMax: Double?
    @Published var lastHRAvg: Double?
    @Published var lastSnoringCount: Int = 0
    @Published var lastEvents: [WatchClassifiedEventSummary] = []

    override init() {
        super.init()
        loadPersistedSummary()
        WatchLogger.session.info("WatchSessionManager initialized")
    }

    /// Matches JSONEncoder.watchHistoryEncoder on iPhone side. Both sides
    /// must use .iso8601 dates or decoding returns empty arrays.
    static let watchHistoryDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func activate() {
        guard WCSession.isSupported() else {
            WatchLogger.session.warning("WCSession not supported")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        WatchLogger.session.info("WCSession activation requested")
    }

    /// Ping iPhone to push the latest profile + history context. Uses
    /// transferUserInfo (queued, iOS wakes the iPhone app if needed) so
    /// the crash-prone sendMessage-with-reply path on Swift 6 watchOS
    /// isn't involved. iPhone responds by pushing a fresh
    /// applicationContext.
    func requestStateFromPhone() {
        let s = WCSession.default
        diagActivationState = s.activationState.rawValue
        diagIsReachable = s.isReachable
        diagIsCompanionInstalled = s.isCompanionAppInstalled
        diagLastRequestSent = Date()
        WatchLogger.session.info("🔎 requestStateFromPhone — activation: \(s.activationState.rawValue), reachable: \(s.isReachable), companionInstalled: \(s.isCompanionAppInstalled)")
        guard s.activationState == .activated else {
            diagLastError = "WCSession not activated (state=\(s.activationState.rawValue))"
            return
        }
        // Real-time push when reachable: sendMessage with a nil replyHandler
        // (no @Sendable reply closure, so no Swift 6 executor-check crash).
        // Always ALSO queue via transferUserInfo as a safety net in case the
        // iPhone app is backgrounded and WC delivers sendMessage as a no-op.
        let payload: [String: Any] = ["command": "requestState"]
        if s.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { error in
                WatchLogger.session.error("❌ sendMessage(requestState) failed: \(error.localizedDescription)")
            }
            WatchLogger.session.info("📤 Requested state via sendMessage (reachable)")
        }
        WCSession.default.transferUserInfo(payload)
        WatchLogger.session.info("📤 Queued state request via transferUserInfo (reachable: \(s.isReachable))")
    }

    func sendHeartRate(_ bpm: Double) {
        guard WCSession.default.activationState == .activated else {
            WatchLogger.heartRate.warning("Cannot send HR — session not activated")
            return
        }
        let message: [String: Any] = [
            "heartRate": bpm,
            "heartRateTimestamp": Date().timeIntervalSince1970
        ]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                WatchLogger.heartRate.error("Failed to send HR via message: \(error.localizedDescription)")
            }
        } else {
            try? WCSession.default.updateApplicationContext(message)
        }
        WatchLogger.heartRate.debug("Sent HR to iPhone: \(Int(bpm)) BPM")
    }

    /// Forward a classifier-detected event (snoring, bark, meow, etc.) from
    /// the Watch's own audio pipeline to the iPhone so it can be added to
    /// the session's audio events list.
    func sendClassifiedEvent(label: String, confidence: Double) {
        guard WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = [
            "type": "watchClassifierEvent",
            "label": label,
            "confidence": confidence,
            "timestamp": Date().timeIntervalSince1970
        ]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                WatchLogger.session.error("Failed to send classified event: \(error.localizedDescription)")
            }
        } else {
            WCSession.default.transferUserInfo(message)
        }
        WatchLogger.session.info("📤 Forwarded classifier event → iPhone: \(label) (\(String(format: "%.2f", confidence)))")
    }

    func sendMovementData(_ points: [MovementDataPoint]) {
        guard WCSession.default.activationState == .activated else {
            WatchLogger.motion.warning("Cannot send movement — session not activated")
            return
        }
        guard let data = try? JSONEncoder().encode(points),
              let jsonString = String(data: data, encoding: .utf8) else {
            WatchLogger.motion.error("Failed to encode movement data")
            return
        }
        WCSession.default.transferUserInfo(["movementJSON": jsonString])
        WatchLogger.motion.info("Sent \(points.count) movement points to iPhone via transferUserInfo")
    }

    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        guard WCSession.default.activationState == .activated else {
            WatchLogger.session.warning("Cannot send command '\(command)' — session not activated")
            return false
        }

        WatchLogger.session.info("Sending command to iPhone: \(command)")

        // On watchOS, sendMessage wakes the iPhone app even if not reachable
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["command": command], replyHandler: nil) { error in
                WatchLogger.session.error("Failed to send command '\(command)': \(error.localizedDescription)")
            }
        } else {
            // Fallback: transferUserInfo queues for delivery when iPhone wakes
            WCSession.default.transferUserInfo(["command": command])
            WatchLogger.session.info("iPhone not reachable — queued command '\(command)' via transferUserInfo")
        }

        // Optimistic local state update so watch UI responds immediately
        if command == "startTracking" {
            snoringCount = 0
            appState = .tracking(startTime: Date())
            WatchLogger.ui.info("Optimistic state → tracking")
        } else if command == "stopTracking" {
            appState = .idle
            WatchLogger.ui.info("Optimistic state → idle")
        }

        return true
    }

    func dismissSummary() {
        appState = .idle
        WatchLogger.ui.info("Summary dismissed → idle")
    }

    // MARK: - Persistence

    private func loadPersistedSummary() {
        let ud = UserDefaults.standard
        phoneSignedIn = ud.bool(forKey: "phoneSignedIn")
        phoneUserName = ud.string(forKey: "phoneUserName") ?? ""
        phoneUserAge = ud.integer(forKey: "phoneUserAge")
        phoneSleepGoalHours = ud.double(forKey: "phoneSleepGoalHours")
        if let data = ud.data(forKey: "sleepHistoryJSON"),
           let decoded = try? Self.watchHistoryDecoder.decode([WatchSleepHistoryEntry].self, from: data) {
            sleepHistory = decoded
        }
        lastScore = ud.object(forKey: "lastScore") as? Int
        lastDuration = ud.object(forKey: "lastDuration") as? TimeInterval
        lastQuality = ud.string(forKey: "lastQuality")
        lastHRMin = ud.object(forKey: "lastHRMin") as? Double
        lastHRMax = ud.object(forKey: "lastHRMax") as? Double
        lastHRAvg = ud.object(forKey: "lastHRAvg") as? Double
        lastSnoringCount = ud.integer(forKey: "lastSnoringCount")

        if let stagesData = ud.data(forKey: "lastStagesJSON") {
            lastStages = (try? JSONDecoder().decode([SleepStageEntry].self, from: stagesData)) ?? []
        }
        if let movData = ud.data(forKey: "lastMovementJSON") {
            lastMovement = (try? JSONDecoder().decode([MovementDataPoint].self, from: movData)) ?? []
        }
        if let evData = ud.data(forKey: "lastEventsJSON") {
            lastEvents = (try? Self.watchHistoryDecoder.decode([WatchClassifiedEventSummary].self, from: evData)) ?? []
        }

        if lastScore != nil {
            WatchLogger.session.info("Loaded persisted summary — score: \(self.lastScore ?? 0)")
        } else {
            WatchLogger.session.info("No persisted summary found")
        }
    }

    private func persistSummary(_ data: SleepSummaryData) {
        let ud = UserDefaults.standard
        ud.set(data.score, forKey: "lastScore")
        ud.set(data.duration, forKey: "lastDuration")
        ud.set(data.quality, forKey: "lastQuality")
        ud.set(data.hrMin, forKey: "lastHRMin")
        ud.set(data.hrMax, forKey: "lastHRMax")
        ud.set(data.hrAvg, forKey: "lastHRAvg")
        ud.set(data.snoringCount, forKey: "lastSnoringCount")

        if let encoded = try? JSONEncoder().encode(data.stages) {
            ud.set(encoded, forKey: "lastStagesJSON")
        }
        if let encoded = try? JSONEncoder().encode(data.movement) {
            ud.set(encoded, forKey: "lastMovementJSON")
        }
        if let encoded = try? JSONEncoder.watchHistoryEncoder.encode(data.events) {
            ud.set(encoded, forKey: "lastEventsJSON")
        }
        WatchLogger.session.info("Persisted sleep summary — score: \(data.score)")
    }
}

private extension JSONEncoder {
    static let watchHistoryEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error = error {
            WatchLogger.session.error("WCSession activation failed: \(error.localizedDescription)")
        } else {
            WatchLogger.session.info("WCSession activated — state: \(activationState.rawValue)")
        }
        // Ask iPhone to push current profile + history. Without this, a
        // Watch launch after an iPhone sign-up sees no context until iPhone
        // happens to push on its own.
        if activationState == .activated {
            Task { @MainActor [weak self] in
                self?.requestStateFromPhone()
            }
        }
    }

    nonisolated func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        WatchLogger.session.debug("Received application context: \(applicationContext.keys.joined(separator: ", "))")
        nonisolated(unsafe) let snapshot = applicationContext
        Task { @MainActor [weak self] in
            self?.handlePayload(snapshot, fromMessage: false)
        }
    }

    nonisolated func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        WatchLogger.session.debug("Received message: \(message.keys.joined(separator: ", "))")
        nonisolated(unsafe) let snapshot = message
        Task { @MainActor [weak self] in
            self?.handlePayload(snapshot, fromMessage: true)
        }
    }

    private func handlePayload(_ payload: [String: Any], fromMessage: Bool = true) {
        DispatchQueue.main.async {
            self.diagLastReceived = Date()
            self.diagLastError = nil
            if payload["phoneAck"] as? Bool == true {
                WatchLogger.session.info("✅ iPhone acknowledged — keys: \(payload.keys.joined(separator: ", "))")
            }
            // iPhone sign-in / profile state. Sent at launch and whenever
            // the user signs in or changes their name.
            //
            // iOS delivers cached applicationContext on WCSession connect, and
            // that cache can predate the user's sign-in — so we get a stale
            // phoneSignedIn=false that kicks the watch back to the setup
            // prompt. To fix: only let an applicationContext SET
            // phoneSignedIn=true, never downgrade from true→false. Downgrades
            // only land via sendMessage (fresh, real-time).
            if let signedIn = payload["phoneSignedIn"] as? Bool {
                let shouldApply: Bool
                if fromMessage {
                    shouldApply = true
                } else if signedIn {
                    shouldApply = true
                } else {
                    shouldApply = !self.phoneSignedIn  // allow false only if already false
                }
                if shouldApply {
                    self.phoneSignedIn = signedIn
                    UserDefaults.standard.set(signedIn, forKey: "phoneSignedIn")
                    WatchLogger.session.info("📥 phoneSignedIn = \(signedIn)")
                } else {
                    WatchLogger.session.info("📥 Ignored stale phoneSignedIn=false from applicationContext (already signed in)")
                }
            }
            if let name = payload["phoneUserName"] as? String {
                self.phoneUserName = name
                UserDefaults.standard.set(name, forKey: "phoneUserName")
                WatchLogger.session.info("📥 phoneUserName = '\(name)'")
            }
            if let age = payload["phoneUserAge"] as? Int {
                self.phoneUserAge = age
                UserDefaults.standard.set(age, forKey: "phoneUserAge")
            }
            if let goal = payload["phoneSleepGoalHours"] as? Double {
                self.phoneSleepGoalHours = goal
                UserDefaults.standard.set(goal, forKey: "phoneSleepGoalHours")
            }
            if let json = payload["sleepHistoryJSON"] as? String,
               let data = json.data(using: .utf8),
               let decoded = try? Self.watchHistoryDecoder.decode([WatchSleepHistoryEntry].self, from: data) {
                self.sleepHistory = decoded
                UserDefaults.standard.set(data, forKey: "sleepHistoryJSON")
                WatchLogger.session.info("History updated — \(decoded.count) sessions")
            }

            // Snoring count update during tracking
            if let count = payload["snoringCount"] as? Int,
               payload["type"] as? String != "morningSummary" {
                self.snoringCount = count
                WatchLogger.session.debug("Snoring count updated: \(count)")
            }

            // Morning summary takes priority
            if let type = payload["type"] as? String, type == "morningSummary",
               let score = payload["score"] as? Int,
               let duration = payload["duration"] as? TimeInterval,
               let quality = payload["quality"] as? String {

                WatchLogger.session.info("Received morning summary — score: \(score), duration: \(Int(duration/3600))h")

                // Decode stages
                var stages: [SleepStageEntry] = []
                if let stagesJSON = payload["stagesJSON"] as? String,
                   let data = stagesJSON.data(using: .utf8) {
                    stages = (try? JSONDecoder().decode([SleepStageEntry].self, from: data)) ?? []
                    WatchLogger.session.debug("Decoded \(stages.count) sleep stages")
                }

                // Decode movement
                var movement: [MovementDataPoint] = []
                if let movJSON = payload["movementJSON"] as? String,
                   let data = movJSON.data(using: .utf8) {
                    movement = (try? JSONDecoder().decode([MovementDataPoint].self, from: data)) ?? []
                    WatchLogger.session.debug("Decoded \(movement.count) movement points")
                }

                // Decode classified events (dog / cat / voice / snoring / ...)
                var events: [WatchClassifiedEventSummary] = []
                if let evJSON = payload["eventsJSON"] as? String,
                   let data = evJSON.data(using: .utf8) {
                    events = (try? Self.watchHistoryDecoder.decode([WatchClassifiedEventSummary].self, from: data)) ?? []
                    WatchLogger.session.debug("Decoded \(events.count) classified events")
                }

                let summaryData = SleepSummaryData(
                    score: score, duration: duration, quality: quality,
                    stages: stages, movement: movement,
                    hrMin: payload["hrMin"] as? Double ?? 0,
                    hrMax: payload["hrMax"] as? Double ?? 0,
                    hrAvg: payload["hrAvg"] as? Double ?? 0,
                    snoringCount: payload["snoringCount"] as? Int ?? 0,
                    events: events
                )

                // Update last summary
                self.lastScore = score
                self.lastDuration = duration
                self.lastQuality = quality
                self.lastStages = stages
                self.lastMovement = movement
                self.lastHRMin = summaryData.hrMin
                self.lastHRMax = summaryData.hrMax
                self.lastHRAvg = summaryData.hrAvg
                self.lastSnoringCount = summaryData.snoringCount
                self.lastEvents = events

                self.persistSummary(summaryData)
                self.appState = .summary(data: summaryData)
                self.lastSessionEndedAt = Date()
                WatchLogger.ui.info("State → summary (score: \(score))")
                return
            }

            if let isTracking = payload["isTracking"] as? Bool {
                if isTracking, let startInterval = payload["startTime"] as? TimeInterval {
                    let startDate = Date(timeIntervalSince1970: startInterval)
                    // Guard 1: only enter tracking from .idle, so a stale
                    // context delivered while the summary is visible doesn't
                    // flip us back.
                    // Guard 2: ignore starts that predate the last session
                    // end we observed — those are leftover deliveries from
                    // the iOS delivery queue after the user already stopped.
                    let isStale = (self.lastSessionEndedAt.map { $0 > startDate } ?? false)
                    if case .idle = self.appState, !isStale {
                        self.snoringCount = 0
                        self.appState = .tracking(startTime: startDate)
                        WatchLogger.ui.info("State → tracking (from iPhone)")
                    } else if isStale {
                        WatchLogger.ui.info("Ignored stale isTracking context (startTime older than last session end)")
                    }
                } else if case .tracking = self.appState {
                    self.appState = .idle
                    self.lastSessionEndedAt = Date()
                    WatchLogger.ui.info("State → idle (tracking stopped by iPhone)")
                }
            }
        }
    }
}
