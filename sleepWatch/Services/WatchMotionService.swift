//
//  WatchMotionService.swift
//  sleepWatch
//
//  Accelerometer-based movement detection on Apple Watch.
//  Mirrors iPhone MotionService algorithm: 10Hz sampling, 30s aggregation.

import Combine
import Foundation
import os
#if canImport(CoreMotion)
import CoreMotion
#endif

@MainActor
final class WatchMotionService: ObservableObject {

    @Published var isTracking = false
    @Published var currentIntensity: Double = 0.0
    @Published var dataPoints: [MovementDataPoint] = []

    /// Called every 5 minutes with the latest batch of movement points
    var onMovementBatch: (([MovementDataPoint]) -> Void)?

    #if canImport(CoreMotion)
    private let motionManager = CMMotionManager()
    #endif
    private var recentAccelerations: [Double] = []
    private var samplingTimer: Timer?
    private var batchTimer: Timer?
    private var lastBatchIndex = 0
    private var sensitivity: Double = 1.5

    func startTracking(sensitivity: Double = 1.5) {
        guard !isTracking else {
            WatchLogger.motion.warning("startTracking called but already tracking")
            return
        }

        #if canImport(CoreMotion)
        guard motionManager.isAccelerometerAvailable else {
            WatchLogger.motion.error("Accelerometer not available on this device")
            return
        }
        #endif

        self.sensitivity = sensitivity
        dataPoints = []
        recentAccelerations = []
        lastBatchIndex = 0
        isTracking = true

        WatchLogger.motion.info("Motion tracking started — sensitivity: \(sensitivity)")

        #if canImport(CoreMotion)
        motionManager.accelerometerUpdateInterval = 0.1 // 10 Hz
        let sens = self.sensitivity

        motionManager.startAccelerometerUpdates(to: OperationQueue()) { @Sendable data, error in
            guard let data = data, error == nil else {
                if let error = error {
                    WatchLogger.motion.error("Accelerometer error: \(error.localizedDescription)")
                }
                return
            }

            let x = data.acceleration.x
            let y = data.acceleration.y
            let z = data.acceleration.z
            let magnitude = sqrt(x * x + y * y + z * z)
            let intensity = max(0, (magnitude - 1.0)) * sens

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentIntensity = intensity
                self.recentAccelerations.append(intensity)
            }
        }
        #endif

        // 30-second aggregation timer
        samplingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.aggregateRecentData() }
        }

        // 5-minute batch timer to send data to iPhone
        batchTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sendBatch() }
        }
    }

    func stopTracking() {
        guard isTracking else { return }

        WatchLogger.motion.info("Motion tracking stopping — \(self.dataPoints.count) total data points")

        // Final aggregation and send before stopping
        aggregateRecentData()
        sendBatch()

        #if canImport(CoreMotion)
        motionManager.stopAccelerometerUpdates()
        #endif
        samplingTimer?.invalidate()
        samplingTimer = nil
        batchTimer?.invalidate()
        batchTimer = nil
        isTracking = false
        currentIntensity = 0.0

        WatchLogger.motion.info("Motion tracking stopped")
    }

    private func aggregateRecentData() {
        guard !recentAccelerations.isEmpty else { return }
        let average = recentAccelerations.reduce(0, +) / Double(recentAccelerations.count)
        dataPoints.append(MovementDataPoint(timestamp: Date(), intensity: average))
        WatchLogger.motion.debug("Aggregated \(self.recentAccelerations.count) samples → intensity: \(String(format: "%.4f", average))")
        recentAccelerations = []
    }

    private func sendBatch() {
        guard lastBatchIndex < dataPoints.count else { return }
        let batch = Array(dataPoints[lastBatchIndex...])
        lastBatchIndex = dataPoints.count
        WatchLogger.motion.info("Sending batch of \(batch.count) movement points to iPhone")
        onMovementBatch?(batch)
    }
}
