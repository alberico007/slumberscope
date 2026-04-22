//
//  FormatHelpers.swift
//  sleep
//
//

import Foundation

enum FormatHelpers {

    /// Formats a duration with seconds when short:
    ///   ≥ 1h → "7h 32m"
    ///   ≥ 1m → "3m 12s"
    ///   < 1m → "14s"
    /// Most classified sound events are < 1 minute, so "0m" was useless.
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    /// Formats elapsed time as "02:15:30"
    static func elapsedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// Formats a date as time of day: "10:30 PM"
    static func timeOfDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Formats a date as short date: "Mar 15"
    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    /// Formats a date as weekday abbreviation: "Mon"
    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    /// Formats a double as a percentage: "85%"
    static func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
