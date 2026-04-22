//
//  AppLogger.swift
//  sleep
//
//

import Foundation
import os

// MARK: - AppLogger

enum AppLogger {

    // MARK: - Subsystem

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.smarterpillow.sleep"

    // MARK: - Category Loggers

    static let general = Logger(subsystem: subsystem, category: "general")
    static let tracking = Logger(subsystem: subsystem, category: "tracking")
    static let motion = Logger(subsystem: subsystem, category: "motion")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let healthKit = Logger(subsystem: subsystem, category: "healthkit")
    static let storeKit = Logger(subsystem: subsystem, category: "storekit")
    static let intelligence = Logger(subsystem: subsystem, category: "intelligence")
    static let liveActivity = Logger(subsystem: subsystem, category: "liveactivity")
    static let cloudSync = Logger(subsystem: subsystem, category: "cloudsync")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let sound = Logger(subsystem: subsystem, category: "sound")
    static let notification = Logger(subsystem: subsystem, category: "notification")
    static let alarm = Logger(subsystem: subsystem, category: "alarm")
    static let focus = Logger(subsystem: subsystem, category: "focus")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let data = Logger(subsystem: subsystem, category: "data")
    static let crash = Logger(subsystem: subsystem, category: "crash")

    // MARK: - Convenience

    /// Log app lifecycle events
    static func appEvent(_ message: String) {
        general.info("🟢 APP: \(message, privacy: .public)")
    }

    /// Log errors with full context
    static func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        if let error = error {
            general.error("🔴 ERROR [\(fileName, privacy: .public):\(line)] \(function, privacy: .public): \(message, privacy: .public) — \(error.localizedDescription, privacy: .public)")
        } else {
            general.error("🔴 ERROR [\(fileName, privacy: .public):\(line)] \(function, privacy: .public): \(message, privacy: .public)")
        }
    }

    /// Log warnings
    static func warning(_ message: String, file: String = #file, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        general.warning("🟡 WARN [\(fileName, privacy: .public):\(line)]: \(message, privacy: .public)")
    }
}

// MARK: - SignpostID for performance

extension AppLogger {
    static let performanceLog = OSLog(subsystem: subsystem, category: .pointsOfInterest)

    static func signpostBegin(_ name: StaticString) {
        os_signpost(.begin, log: performanceLog, name: name)
    }

    static func signpostEnd(_ name: StaticString) {
        os_signpost(.end, log: performanceLog, name: name)
    }
}
