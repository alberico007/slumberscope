//
//  BatteryService.swift
//  sleep
//
//

import Foundation
import os
import UIKit

// MARK: - Battery Warning Level

enum BatteryWarningLevel: Sendable {
    case normal
    case low      // < 20%
    case critical  // < 10%
}

@Observable
@MainActor
final class BatteryService {

    // MARK: - Observable State

    var batteryLevel: Float = 1.0
    var isCharging = false
    var warningLevel: BatteryWarningLevel = .normal

    // MARK: - Private

    private var batteryLevelObserver: NSObjectProtocol?
    private var batteryStateObserver: NSObjectProtocol?

    // MARK: - Monitoring

    func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryStatus()

        batteryLevelObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBatteryStatus()
            }
        }

        batteryStateObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBatteryStatus()
            }
        }
    }

    func stopMonitoring() {
        if let observer = batteryLevelObserver {
            NotificationCenter.default.removeObserver(observer)
            batteryLevelObserver = nil
        }
        if let observer = batteryStateObserver {
            NotificationCenter.default.removeObserver(observer)
            batteryStateObserver = nil
        }
        UIDevice.current.isBatteryMonitoringEnabled = false
    }

    // MARK: - Private

    private func updateBatteryStatus() {
        let device = UIDevice.current
        batteryLevel = device.batteryLevel
        isCharging = device.batteryState == .charging || device.batteryState == .full

        if batteryLevel < 0.10 {
            warningLevel = .critical
            AppLogger.general.warning("🔋 Battery level: \(self.batteryLevel) — CRITICAL")
        } else if batteryLevel < 0.20 {
            warningLevel = .low
            AppLogger.general.warning("🔋 Battery level: \(self.batteryLevel) — LOW")
        } else {
            warningLevel = .normal
        }
    }
}
