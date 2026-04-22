//
//  WatchSleepHistoryEntry.swift
//  sleep
//
//  Compact sleep-session snapshot sent from iPhone to Watch so the Watch's
//  History tab can show recent sessions without re-running any analytics.
//  Fields and JSON encoding MUST stay in sync with the equivalent struct
//  in sleepWatch/Models/WatchModels.swift.
//

import Foundation

struct WatchSleepHistoryEntry: Codable, Identifiable, Sendable {
    var id: UUID
    var startTime: Date
    var endTime: Date
    var score: Int
    var qualityLabel: String
    var hrMin: Double
    var hrMax: Double
    var hrAvg: Double
    var hrSamples: [Double]
    var snoringCount: Int
    /// Compact list of classified sound events for per-category + per-event
    /// display on the watch's history detail view. May be empty on older
    /// sessions pushed from iPhones that predate this field.
    var events: [WatchClassifiedEventSummary] = []

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
}

/// Watch-side compact view of a classified sound event. Must JSON-match the
/// watch target's `WatchClassifiedEventSummary` in sleepWatch/Models/.
struct WatchClassifiedEventSummary: Codable, Sendable {
    var label: String
    var duration: TimeInterval
    var timestamp: Date
}
