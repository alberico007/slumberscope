//
//  MotionService.swift
//  sleep
//
//

import CoreMotion
import Foundation
import os

@Observable
@MainActor
final class MotionService {

    // MARK: - Observable State

    var isTracking = false
    var currentIntensity: Double = 0.0
    var dataPoints: [MovementDataPoint] = []

    // MARK: - Private

    private let motionManager = CMMotionManager()
    private var recentAccelerations: [Double] = []
    private var samplingTimer: Timer?

    // MARK: - Tracking

    func startTracking(sensitivity: Double) {
        guard !isTracking else { return }
        AppLogger.motion.info("🏃 Motion tracking started with sensitivity: \(sensitivity)")

        dataPoints = []
        recentAccelerations = []
        isTracking = true

        // Prefer CMDeviceMotion over raw accelerometer: Apple's sensor-fusion
        // pipeline separates user acceleration from gravity and drops a lot of
        // noise that a raw magnitude calculation would include. If device
        // motion isn't available (very old devices / simulator), fall back.
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1 // 10 Hz
            motionManager.startDeviceMotionUpdates(to: OperationQueue()) { @Sendable data, error in
                guard let data = data, error == nil else { return }
                let ua = data.userAcceleration // gravity-separated acceleration
                let magnitude = sqrt(ua.x * ua.x + ua.y * ua.y + ua.z * ua.z)
                let intensity = max(0, magnitude) * sensitivity
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentIntensity = intensity
                    self.recentAccelerations.append(intensity)
                }
            }
        } else if motionManager.isAccelerometerAvailable {
            // Fallback path for older devices.
            motionManager.accelerometerUpdateInterval = 0.1
            motionManager.startAccelerometerUpdates(to: OperationQueue()) { @Sendable data, error in
                guard let data = data, error == nil else { return }
                let x = data.acceleration.x
                let y = data.acceleration.y
                let z = data.acceleration.z
                let magnitude = sqrt(x * x + y * y + z * z)
                // Subtract gravity (1.0 g) and scale by sensitivity.
                let intensity = max(0, (magnitude - 1.0)) * sensitivity
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentIntensity = intensity
                    self.recentAccelerations.append(intensity)
                }
            }
        } else {
            AppLogger.motion.error("Neither device motion nor accelerometer available")
            isTracking = false
            return
        }

        // 30-second sampling timer to aggregate data points
        samplingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.aggregateRecentData()
            }
        }
    }

    func stopTracking() {
        guard isTracking else { return }
        AppLogger.motion.info("🏃 Motion tracking stopped")

        // Final aggregation of remaining data
        aggregateRecentData()

        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        if motionManager.isAccelerometerActive {
            motionManager.stopAccelerometerUpdates()
        }
        samplingTimer?.invalidate()
        samplingTimer = nil
        isTracking = false
        currentIntensity = 0.0
    }

    // MARK: - Private Aggregation

    private func aggregateRecentData() {
        guard !recentAccelerations.isEmpty else { return }

        let average = recentAccelerations.reduce(0, +) / Double(recentAccelerations.count)
        let point = MovementDataPoint(
            timestamp: Date(),
            intensity: average
        )
        dataPoints.append(point)
        AppLogger.motion.debug("Movement intensity: \(average)")
        recentAccelerations = []
    }
}
