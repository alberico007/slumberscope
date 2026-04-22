//
//  HeartRateService.swift
//  sleepWatch

import Combine
import Foundation
import HealthKit
import os

@MainActor
final class HeartRateService: NSObject, ObservableObject {

    @Published var currentBPM: Double?

    /// Called with each new BPM sample — wired up by ContentView to relay HR to iPhone
    var onHeartRateSample: ((Double) -> Void)?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            WatchLogger.heartRate.warning("HealthKit not available on this device")
            return
        }
        do {
            try await healthStore.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [HKQuantityType(.heartRate)]
            )
            WatchLogger.heartRate.info("HealthKit authorization granted")
        } catch {
            WatchLogger.heartRate.error("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Session Lifecycle

    /// Starts an HKWorkoutSession to keep the Watch process alive in background during sleep.
    /// Without an active workout session watchOS suspends the app within seconds of wrist lowering.
    func startMonitoring() {
        guard HKHealthStore.isHealthDataAvailable() else {
            WatchLogger.heartRate.warning("Cannot start monitoring — HealthKit unavailable")
            return
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .other   // .sleep is not a valid HKWorkoutActivityType
        config.locationType = .indoor
        guard let session = try? HKWorkoutSession(healthStore: healthStore,
                                                  configuration: config) else {
            WatchLogger.heartRate.error("Failed to create HKWorkoutSession")
            return
        }
        let liveBuilder = session.associatedWorkoutBuilder()
        liveBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                          workoutConfiguration: config)
        session.delegate = self
        liveBuilder.delegate = self
        workoutSession = session
        builder = liveBuilder
        session.startActivity(with: Date())
        liveBuilder.beginCollection(withStart: Date()) { success, error in
            if let error = error {
                WatchLogger.heartRate.error("Failed to begin workout collection: \(error.localizedDescription)")
            } else {
                WatchLogger.heartRate.info("Workout collection started — HR monitoring active")
            }
        }
    }

    func stopMonitoring() {
        WatchLogger.heartRate.info("Stopping HR monitoring")
        workoutSession?.end()
        builder?.endCollection(withEnd: Date()) { _, error in
            if let error = error {
                WatchLogger.heartRate.error("Failed to end workout collection: \(error.localizedDescription)")
            }
            Task { @MainActor [weak self] in
                guard let builder = self?.builder else { return }
                do {
                    _ = try await builder.finishWorkout()
                    WatchLogger.heartRate.info("Workout finished successfully")
                } catch {
                    WatchLogger.heartRate.error("Failed to finish workout: \(error.localizedDescription)")
                }
            }
        }
        workoutSession = nil
        builder = nil
        currentBPM = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HeartRateService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        WatchLogger.heartRate.info("Workout session state: \(fromState.rawValue) → \(toState.rawValue)")
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        WatchLogger.heartRate.error("Workout session failed: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HeartRateService: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)),
              let stats = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
              let recent = stats.mostRecentQuantity() else { return }
        let bpm = recent.doubleValue(for: HKUnit(from: "count/min"))
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.currentBPM = bpm
            self.onHeartRateSample?(bpm)
            WatchLogger.heartRate.debug("HR sample: \(Int(bpm)) BPM")
        }
    }
}
