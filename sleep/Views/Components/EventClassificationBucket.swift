//
//  EventClassificationBucket.swift
//  sleep
//
//  Groups a SnoringEvent's classification string into a small set of display
//  buckets (Snoring, Dogs, Cats, Voice, Other) so the post-session review
//  can render events in meaningful sections instead of a flat list.
//

import SwiftUI

enum EventClassificationBucket: String, CaseIterable, Sendable {
    case snoring, dog, cat, voice, other

    var displayName: String {
        switch self {
        case .snoring: return "Snoring"
        case .dog:     return "Dogs"
        case .cat:     return "Cats"
        case .voice:   return "Voice"
        case .other:   return "Other"
        }
    }

    /// SF Symbol for the section header.
    var icon: String {
        switch self {
        case .snoring: return "zzz"
        case .dog:     return "dog.fill"
        case .cat:     return "cat.fill"
        case .voice:   return "waveform.badge.mic"
        case .other:   return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .snoring: return .purple
        case .dog:     return .orange
        case .cat:     return .pink
        case .voice:   return .cyan
        case .other:   return .secondary
        }
    }

    /// Map a raw classification label (server remote label or local
    /// SoundAnalysis verdict) to one of the five display buckets. Case
    /// insensitive; unknown labels fall through to `.other`.
    static func classify(_ label: String) -> EventClassificationBucket {
        let lowered = label.lowercased()
        switch lowered {
        case "snoring", "snort":
            return .snoring
        case "dog", "bark", "howl", "growling", "whimper (dog)", "yip", "bow-wow":
            return .dog
        case "cat", "meow", "purr", "hiss", "caterwaul":
            return .cat
        case "speech", "cough", "child speech, kid speaking", "conversation", "narration, monologue":
            return .voice
        default:
            return .other
        }
    }
}

extension Array where Element == SnoringEvent {
    /// Groups events into display buckets, preserving bucket enum order so
    /// the section list is stable across renders.
    func groupedByClassification() -> [(bucket: EventClassificationBucket, events: [SnoringEvent])] {
        let grouped = Dictionary(grouping: self) { EventClassificationBucket.classify($0.classification) }
        return EventClassificationBucket.allCases.compactMap { bucket in
            guard let events = grouped[bucket], !events.isEmpty else { return nil }
            // Sort each bucket by event start time for stable ordering.
            return (bucket, events.sorted { $0.startTime < $1.startTime })
        }
    }
}
