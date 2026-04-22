//
//  SleepSession.swift
//  sleep
//
//

import Foundation
import os
import SwiftData
import SwiftUI

// MARK: - SleepQuality

enum SleepQuality: Int, Codable, CaseIterable, Identifiable {
    case veryPoor = 1
    case poor = 2
    case fair = 3
    case good = 4
    case excellent = 5

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .veryPoor: "Very Poor"
        case .poor: "Poor"
        case .fair: "Fair"
        case .good: "Good"
        case .excellent: "Excellent"
        }
    }

    var icon: String {
        switch self {
        case .veryPoor: "star"
        case .poor: "star.leadinghalf.filled"
        case .fair: "star.fill"
        case .good: "star.fill"
        case .excellent: "star.fill"
        }
    }

    var starCount: Int { rawValue }
}

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

// MARK: - SnoringEvent

struct SnoringEvent: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var startTime: Date
    var duration: TimeInterval
    var averageAmplitude: Double
    var audioFileURL: URL?
    /// Top label from the classifier — either the on-device SoundAnalysis
    /// verdict ("snoring", "mechanical_fan", …) or, when the remote YAMNet
    /// classifier is enabled, its collapsed label ("Snoring", "Other", …).
    /// Empty string for legacy events.
    var classification: String = "snoring"
    /// Confidence (0.0–1.0) of the top classification label.
    var classificationConfidence: Double = 1.0
    /// True while the remote classifier is still working on this event or
    /// hasn't been able to reach the server yet.
    var remoteClassificationPending: Bool = false
    /// True once the remote classifier has given up after retries. The
    /// local `classification` value is the one we fell back to.
    var remoteClassificationFailed: Bool = false
}

// MARK: - SleepStageEntry

struct SleepStageEntry: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var startTime: Date
    var endTime: Date
    var stage: SleepStageType
}

// MARK: - SleepSession

@Model
final class SleepSession {
    var startTime: Date
    var endTime: Date
    var qualityRating: Int
    var notes: String
    var syncedToHealthKit: Bool

    // JSON-encoded blob storage
    var movementData: Data?
    var snoringData: Data?
    var stageData: Data?

    // Summary scalars for efficient @Query sorting/filtering
    var durationSeconds: Double
    var averageMovement: Double
    var snoringCount: Int

    // Morning mood (1-5 scale, 0 = not set)
    var morningMood: Int

    // Sleep onset latency (seconds from session start to first non-awake stage)
    var onsetLatencySeconds: Double

    // MARK: Apple Watch biometrics (nil when no watch data for this window)

    /// Average heart rate (bpm) during the sleep window. Sourced from
    /// HealthKit if the user wore an Apple Watch.
    var averageHeartRateBPM: Double?

    /// Minimum heart rate during the sleep window — usually the overnight
    /// low which is a strong recovery indicator.
    var minimumHeartRateBPM: Double?

    /// JSON-encoded [Double] of downsampled (~40 point) HR samples from
    /// the paired Apple Watch during this session. Used by the Watch
    /// History detail view to draw a compact trend graph.
    var watchHeartRateSamplesData: Data?

    /// Heart Rate Variability (SDNN, milliseconds). Apple Watch's HRV is
    /// within ~10 ms of clinical ECG per Apple's 2025 validation study.
    var hrvAverageMS: Double?

    /// Average respiratory rate (breaths per minute) from Apple Watch.
    var respiratoryRateBPM: Double?

    /// Blood oxygen saturation (percentage, 0–100). Only populated on
    /// Watch Series 6+.
    var bloodOxygenPercent: Double?

    /// Sleeping wrist temperature (Celsius). iOS 17+, Watch Series 8+.
    var wristTemperatureCelsius: Double?

    /// User's baseline resting heart rate (from HealthKit), for comparing
    /// overnight low vs the rolling-average resting HR.
    var restingHeartRateBPM: Double?

    // MARK: Journaling (AI features)

    /// Optional "what did today look like" free-text dictated pre-bed.
    /// Used by IntelligenceService to auto-extract SleepFactor entries.
    var dayJournal: String = ""

    /// Optional "what did you dream" free-text captured in Morning Review.
    /// Used by IntelligenceService to tag dream themes.
    var dreamJournal: String = ""

    /// Comma-joined dream theme tags from the on-device model. Not loaded
    /// into SwiftData as an array to keep the schema migration-free.
    var dreamThemesRaw: String = ""

    /// Human-readable explanation of why the smart alarm triggered when
    /// it did (e.g. "woke you 9 min early at end of a light cycle").
    var alarmRationale: String = ""

    var dreamThemes: [String] {
        get { dreamThemesRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } }
        set { dreamThemesRaw = newValue.joined(separator: ", ") }
    }

    var onsetLatencyFormatted: String {
        if onsetLatencySeconds <= 0 { return "N/A" }
        let minutes = Int(onsetLatencySeconds / 60)
        if minutes < 1 { return "<1 min" }
        return "\(minutes) min"
    }

    // MARK: Computed - Quality

    var quality: SleepQuality {
        get { SleepQuality(rawValue: qualityRating) ?? .fair }
        set { qualityRating = newValue.rawValue }
    }

    // MARK: Computed - Movement points

    var movementPoints: [MovementDataPoint] {
        get {
            guard let data = movementData else { return [] }
            return (try? JSONDecoder().decode([MovementDataPoint].self, from: data)) ?? []
        }
        set {
            movementData = try? JSONEncoder().encode(newValue)
            averageMovement = newValue.isEmpty ? 0 : newValue.map(\.intensity).reduce(0, +) / Double(newValue.count)
        }
    }

    // MARK: Computed - Snoring events

    var snoringEvents: [SnoringEvent] {
        get {
            guard let data = snoringData else { return [] }
            return (try? JSONDecoder().decode([SnoringEvent].self, from: data)) ?? []
        }
        set {
            snoringData = try? JSONEncoder().encode(newValue)
            snoringCount = newValue.count
        }
    }

    // MARK: Computed - Sleep stages

    var sleepStages: [SleepStageEntry] {
        get {
            guard let data = stageData else { return [] }
            return (try? JSONDecoder().decode([SleepStageEntry].self, from: data)) ?? []
        }
        set {
            stageData = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: Computed - Sleep Score (0-100)
    //
    // When Apple Watch data is available (HRV + overnight heart rate drop),
    // we redistribute points to give 20 to a physiological Recovery component
    // and shrink Movement to 10 and Snoring to 10. Total still sums to 100.
    // When no Watch data is available, we fall back to the original 4-component
    // split (35 + 30 + 20 + 15).

    var sleepScore: Int {
        var score: Double = 0
        let hasRecoveryData = hrvAverageMS != nil || minimumHeartRateBPM != nil
        let movementWeight: Double = hasRecoveryData ? 10 : 20
        let snoringWeight: Double = hasRecoveryData ? 10 : 15
        let recoveryWeight: Double = hasRecoveryData ? 15 : 0
        var breakdown: [String: Int] = [:]

        // Duration component (max 35 points) — ideal 7-9 hours
        let hours = durationSeconds / 3600.0
        let durationPts: Double
        if hours >= 7 && hours <= 9 { durationPts = 35 }
        else if hours >= 6 && hours < 7 { durationPts = 25 }
        else if hours > 9 && hours <= 10 { durationPts = 28 }
        else if hours >= 5 && hours < 6 { durationPts = 15 }
        else { durationPts = max(0, 10 - abs(hours - 8) * 2) }
        score += durationPts
        breakdown["duration"] = Int(durationPts)

        // Quality component (max 30 points) — the user's morning rating
        let qualityPts = Double(qualityRating) / 5.0 * 30.0
        score += qualityPts
        breakdown["quality"] = Int(qualityPts)

        // Movement component — lower averageMovement is better
        let movementScore = min(movementWeight, max(0, movementWeight - averageMovement * 40))
        score += movementScore
        breakdown["movement"] = Int(movementScore)

        // Snoring component — each event costs proportional points
        let perEventPenalty = snoringWeight / 5.0 // ~2–3 points per snore
        let snoringPenalty = min(snoringWeight, Double(snoringCount) * perEventPenalty)
        let snoringPts = snoringWeight - snoringPenalty
        score += snoringPts
        breakdown["snoring"] = Int(snoringPts)

        // Recovery component (HRV + overnight HR drop) — only when Watch data
        // is available. Research: HRV correlates strongly with recovery; a
        // well-rested adult commonly sits in the 30–70 ms range. Overnight
        // HR should drop meaningfully below resting baseline.
        if hasRecoveryData {
            var recoveryPoints: Double = 0
            let hrvMidpoint: Double = 50
            let hrvSpread: Double = 40
            if let hrv = hrvAverageMS {
                let normalized = max(0, min(1, (hrv - (hrvMidpoint - hrvSpread)) / (2 * hrvSpread)))
                recoveryPoints += normalized * (recoveryWeight * 0.6)
            }
            if let minHR = minimumHeartRateBPM, let resting = restingHeartRateBPM, resting > 0 {
                let drop = max(0, resting - minHR)
                let normalized = max(0, min(1, drop / 15.0))
                recoveryPoints += normalized * (recoveryWeight * 0.4)
            } else if hrvAverageMS != nil {
                recoveryPoints += recoveryWeight * 0.3
            }
            let capped = min(recoveryWeight, recoveryPoints)
            score += capped
            breakdown["recovery"] = Int(capped)
        }

        let final = max(0, min(100, Int(score.rounded())))
        // One-line breakdown for Xcode debugging — emits on every read of
        // sleepScore, filter by category `tracking` to see it.
        AppLogger.tracking.debug("🧮 sleepScore=\(final) breakdown=\(breakdown), hasRecovery=\(hasRecoveryData)")
        return final
    }

    // MARK: Init

    // MARK: Computed - Sleep Efficiency

    var sleepEfficiency: Double {
        let totalInBed = durationSeconds
        guard totalInBed > 0 else { return 0 }
        let awakeTime = sleepStages.filter { $0.stage == .awake }
            .reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        let asleepTime = totalInBed - awakeTime
        return asleepTime / totalInBed
    }

    // MARK: Computed - Awakenings count

    var awakeningCount: Int {
        let stages = sleepStages
        guard stages.count > 1 else { return 0 }
        var count = 0
        for i in 1..<stages.count where stages[i].stage == .awake && stages[i - 1].stage != .awake {
            count += 1
        }
        return count
    }

    // MARK: Init

    init(
        startTime: Date,
        endTime: Date,
        quality: SleepQuality = .fair,
        notes: String = "",
        syncedToHealthKit: Bool = false,
        movementPoints: [MovementDataPoint] = [],
        snoringEvents: [SnoringEvent] = [],
        sleepStages: [SleepStageEntry] = [],
        morningMood: Int = 0,
        onsetLatencySeconds: Double = 0
    ) {
        self.startTime = startTime
        self.endTime = endTime
        self.qualityRating = quality.rawValue
        self.notes = notes
        self.syncedToHealthKit = syncedToHealthKit
        self.durationSeconds = endTime.timeIntervalSince(startTime)
        self.averageMovement = movementPoints.isEmpty
            ? 0
            : movementPoints.map(\.intensity).reduce(0, +) / Double(movementPoints.count)
        self.snoringCount = snoringEvents.count
        self.morningMood = morningMood
        self.onsetLatencySeconds = onsetLatencySeconds

        self.movementData = movementPoints.isEmpty ? nil : try? JSONEncoder().encode(movementPoints)
        self.snoringData = snoringEvents.isEmpty ? nil : try? JSONEncoder().encode(snoringEvents)
        self.stageData = sleepStages.isEmpty ? nil : try? JSONEncoder().encode(sleepStages)
    }
}
