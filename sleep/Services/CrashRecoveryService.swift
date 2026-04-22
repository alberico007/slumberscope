//
//  CrashRecoveryService.swift
//  sleep
//
//

import Foundation
import os

// MARK: - Recovery State

struct RecoveryState: Codable, Sendable {
    var startTime: Date
    var elapsedTime: TimeInterval
    var movementPoints: [MovementDataPoint]
    var snoringEvents: [SnoringEvent]
    var savedAt: Date
}

@Observable
@MainActor
final class CrashRecoveryService {

    // MARK: - Observable State

    var hasPendingRecovery = false
    var recoveredState: RecoveryState?

    // MARK: - Private

    private var saveTimer: Timer?
    private let saveInterval: TimeInterval = 300 // 5 minutes
    private let expiryInterval: TimeInterval = 43200 // 12 hours

    private var recoveryFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("sleep_recovery.json")
    }

    // MARK: - Check for Pending Recovery

    func checkForPendingRecovery() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: recoveryFileURL.path) else {
            hasPendingRecovery = false
            recoveredState = nil
            return
        }

        do {
            let data = try Data(contentsOf: recoveryFileURL)
            let state = try JSONDecoder().decode(RecoveryState.self, from: data)

            // Check expiry (12 hours)
            if Date().timeIntervalSince(state.savedAt) > expiryInterval {
                clearRecovery()
                return
            }

            recoveredState = state
            hasPendingRecovery = true
            AppLogger.crash.info("♻️ Found pending recovery state")
        } catch {
            AppLogger.crash.error("Failed to load recovery state: \(error.localizedDescription)")
            clearRecovery()
        }
    }

    // MARK: - Periodic Save

    func startPeriodicSave(dataProvider: @escaping @MainActor () -> RecoveryState?) {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let state = dataProvider() else { return }
                self.saveState(state)
            }
        }
    }

    func stopPeriodicSave() {
        saveTimer?.invalidate()
        saveTimer = nil
    }

    // MARK: - Clear Recovery

    func clearRecovery() {
        hasPendingRecovery = false
        recoveredState = nil
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: recoveryFileURL.path) {
            try? fileManager.removeItem(at: recoveryFileURL)
        }
    }

    // MARK: - Private Save

    private func saveState(_ state: RecoveryState) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(state)
            try data.write(to: recoveryFileURL, options: .atomic)
            AppLogger.crash.info("💾 Periodic crash recovery save")
        } catch {
            AppLogger.crash.error("Failed to save recovery state: \(error.localizedDescription)")
        }
    }
}
