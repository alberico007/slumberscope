//
//  WatchModels.swift
//  sleepWatch
//
//  Lightweight copies of iPhone model structs for watch target.
//  JSON encoding must match SleepSession.swift exactly.

import SwiftUI

// MARK: - SleepStageType

enum SleepStageType: String, Codable, CaseIterable, Identifiable {
    case awake
    case light
    case deep
    case rem

    var id: String { rawValue }

    var label: String {
        switch self {
        case .awake: "Awake"
        case .light: "Light"
        case .deep: "Deep"
        case .rem: "REM"
        }
    }

    var color: Color {
        switch self {
        case .awake: .orange
        case .light: .cyan
        case .deep: .indigo
        case .rem: .purple
        }
    }
}

// MARK: - MovementDataPoint

struct MovementDataPoint: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var timestamp: Date
    var intensity: Double
}

// MARK: - SleepStageEntry

struct SleepStageEntry: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var startTime: Date
    var endTime: Date
    var stage: SleepStageType
}

// MARK: - WatchSleepHistoryEntry

/// Compact snapshot of a completed sleep session sent from iPhone to Watch.
/// Fields mirror SleepSession on the phone — JSON encoding must match so the
/// Watch can decode arrays pushed via updateApplicationContext / transferUserInfo.
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
    /// Per-event breakdown synced from iPhone. Empty on older sessions.
    var events: [WatchClassifiedEventSummary] = []

    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
}

/// Compact classified event mirrored from iPhone SnoringEvent. JSON-identical
/// to the iPhone WatchClassifiedEventSummary.
struct WatchClassifiedEventSummary: Codable, Sendable {
    var label: String
    var duration: TimeInterval
    var timestamp: Date
}

// MARK: - WatchFormatHelpers

enum WatchFormatHelpers {
    /// Human-friendly duration. Most classified sound events are < 1 minute,
    /// so "0m" was useless — show seconds for short ranges.
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

// MARK: - WatchClassifiedEvent

/// One live classifier hit on the watch (on-device SNClassifier or cloud
/// YAMNet). Rendered on TrackingView so the user sees dog / cat / voice
/// events accumulating the same way ActiveTrackingView does on iPhone.
struct WatchClassifiedEvent: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let confidence: Double
    let timestamp: Date
}

// MARK: - WatchEventBucket

/// Mirrors iPhone EventClassificationBucket so the watch groups classifier
/// labels into the same Snoring / Dogs / Cats / Voice / Other categories.
enum WatchEventBucket: String, CaseIterable, Sendable {
    case snoring, dog, cat, voice, other

    var displayName: String {
        switch self {
        case .snoring: "Snoring"
        case .dog:     "Dogs"
        case .cat:     "Cats"
        case .voice:   "Voice"
        case .other:   "Other"
        }
    }

    var icon: String {
        switch self {
        case .snoring: "zzz"
        case .dog:     "dog.fill"
        case .cat:     "cat.fill"
        case .voice:   "waveform.badge.mic"
        case .other:   "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .snoring: .purple
        case .dog:     .orange
        case .cat:     .pink
        case .voice:   .cyan
        case .other:   .secondary
        }
    }

    static func classify(_ label: String) -> WatchEventBucket {
        switch label.lowercased() {
        case "snoring", "snort":
            return .snoring
        case "dog", "bark", "howl", "growling", "whimper (dog)", "yip", "bow-wow":
            return .dog
        case "cat", "meow", "purr", "hiss", "caterwaul":
            return .cat
        case "speech", "cough", "child speech, kid speaking", "conversation", "narration, monologue", "whispering", "laughter":
            return .voice
        default:
            return .other
        }
    }
}
