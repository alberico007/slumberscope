//
//  HealthKitService.swift
//  sleep
//
//

import Foundation
import HealthKit
import os

// MARK: - HealthKit Error

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device."
        case .notAuthorized:
            return "HealthKit authorization has not been granted."
        case .saveFailed(let error):
            return "Failed to save sleep data to HealthKit: \(error.localizedDescription)"
        }
    }
}

// MARK: - BiometricStats

struct BiometricStats {
    var heartRate: HeartRateStats?
    var hrvAverage: Double? // ms
    var respiratoryRate: Double? // breaths/min
    var bloodOxygen: Double? // percentage 0-100
    var wristTemperature: Double? // Celsius
}

// MARK: - HeartRateStats

struct HeartRateStats {
    let average: Double   // bpm
    let minimum: Double   // bpm
    let maximum: Double   // bpm
    let sampleCount: Int

    var isFromWatch: Bool { sampleCount > 0 }

    var averageFormatted: String { "\(Int(average.rounded())) bpm" }
    var minimumFormatted: String { "\(Int(minimum.rounded())) bpm" }
    var maximumFormatted: String { "\(Int(maximum.rounded())) bpm" }
}

// MARK: - HealthKitService

@Observable
@MainActor
final class HealthKitService {

    // MARK: - Observable State

    var lastError: String?

    // MARK: - Private

    private let healthStore = HKHealthStore()

    // The types this app reads — includes heart rate for Apple Watch data
    private var readTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKCategoryType(.sleepAnalysis)
        ]
        if HKHealthStore.isHealthDataAvailable() {
            types.insert(HKQuantityType(.heartRate))
            types.insert(HKQuantityType(.restingHeartRate))
            types.insert(HKQuantityType(.heartRateVariabilitySDNN))
            types.insert(HKQuantityType(.respiratoryRate))
            types.insert(HKQuantityType(.oxygenSaturation))
            if #available(iOS 17, *) {
                types.insert(HKQuantityType(.appleSleepingWristTemperature))
            }
        }
        return types
    }

    // MARK: - Availability & Authorization

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var isAuthorized: Bool {
        guard isAvailable else { return false }
        let sleepType = HKCategoryType(.sleepAnalysis)
        return healthStore.authorizationStatus(for: sleepType) == .sharingAuthorized
    }

    // MARK: - Request Authorization

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitError.notAvailable }
        AppLogger.healthKit.info("🏥 Requesting HealthKit authorization")

        let shareTypes: Set<HKSampleType> = [HKCategoryType(.sleepAnalysis)]
        try await healthStore.requestAuthorization(toShare: shareTypes, read: readTypes)
        AppLogger.healthKit.info("🏥 HealthKit authorization completed — authorized: \(self.isAuthorized)")
    }

    // MARK: - Save Sleep Session

    func saveSleepSession(_ session: SleepSession) async throws {
        AppLogger.healthKit.info("💾 Saving sleep session to HealthKit")
        guard isAvailable else {
            lastError = HealthKitError.notAvailable.errorDescription
            throw HealthKitError.notAvailable
        }

        guard isAuthorized else {
            lastError = HealthKitError.notAuthorized.errorDescription
            throw HealthKitError.notAuthorized
        }

        let sleepType = HKCategoryType(.sleepAnalysis)

        let inBedSample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.inBed.rawValue,
            start: session.startTime,
            end: session.endTime
        )

        let asleepCoreSample = HKCategorySample(
            type: sleepType,
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: session.startTime,
            end: session.endTime
        )

        do {
            try await healthStore.save([inBedSample, asleepCoreSample])
            AppLogger.healthKit.info("💾 HealthKit sleep session saved successfully")
            lastError = nil
        } catch {
            lastError = HealthKitError.saveFailed(error).errorDescription
            throw HealthKitError.saveFailed(error)
        }
    }

    // MARK: - Fetch Recent Sleep

    func fetchRecentSleep(days: Int = 7) async -> [HKCategorySample] {
        AppLogger.healthKit.info("📥 Fetching recent sleep data for \(days) days")
        guard isAvailable, isAuthorized else { return [] }

        let sleepType = HKCategoryType(.sleepAnalysis)
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        do {
            let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                    }
                }
                self.healthStore.execute(query)
            }
            return samples
        } catch {
            lastError = "Failed to fetch sleep data: \(error.localizedDescription)"
            return []
        }
    }

    // MARK: - Fetch Heart Rate During Sleep

    /// Fetches heart rate samples recorded by Apple Watch during a sleep window.
    /// Returns nil if HealthKit is unavailable or no samples were found.
    func fetchHeartRate(from start: Date, to end: Date) async -> HeartRateStats? {
        guard isAvailable else { return nil }

        // Check read authorization (HealthKit doesn't expose a direct "authorized to read" check,
        // but we can attempt the query — empty results means no data or no permission)
        let heartRateType = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: heartRateType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                    }
                }
                self.healthStore.execute(query)
            }

            guard !samples.isEmpty else { return nil }

            let beatsPerMin = HKUnit.count().unitDivided(by: .minute())
            let values = samples.map { $0.quantity.doubleValue(for: beatsPerMin) }

            return HeartRateStats(
                average: values.reduce(0, +) / Double(values.count),
                minimum: values.min() ?? 0,
                maximum: values.max() ?? 0,
                sampleCount: samples.count
            )
        } catch {
            return nil
        }
    }

    // MARK: - Fetch HRV

    func fetchHRV(from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }

        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: hrvType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                    }
                }
                self.healthStore.execute(query)
            }

            guard !samples.isEmpty else { return nil }

            let values = samples.map { $0.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli)) }
            return values.reduce(0, +) / Double(values.count)
        } catch {
            return nil
        }
    }

    // MARK: - Fetch Respiratory Rate

    func fetchRespiratoryRate(from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }

        let respType = HKQuantityType(.respiratoryRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: respType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                    }
                }
                self.healthStore.execute(query)
            }

            guard !samples.isEmpty else { return nil }

            let breathsPerMin = HKUnit.count().unitDivided(by: .minute())
            let values = samples.map { $0.quantity.doubleValue(for: breathsPerMin) }
            return values.reduce(0, +) / Double(values.count)
        } catch {
            return nil
        }
    }

    // MARK: - Fetch Blood Oxygen

    func fetchBloodOxygen(from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }

        let oxygenType = HKQuantityType(.oxygenSaturation)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: oxygenType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                    }
                }
                self.healthStore.execute(query)
            }

            guard !samples.isEmpty else { return nil }

            let values = samples.map { $0.quantity.doubleValue(for: HKUnit.percent()) * 100.0 }
            return values.reduce(0, +) / Double(values.count)
        } catch {
            return nil
        }
    }

    // MARK: - Fetch Wrist Temperature

    func fetchWristTemperature(from start: Date, to end: Date) async -> Double? {
        guard isAvailable else { return nil }

        if #available(iOS 17, *) {
            let tempType = HKQuantityType(.appleSleepingWristTemperature)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            do {
                let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                    let query = HKSampleQuery(
                        sampleType: tempType,
                        predicate: predicate,
                        limit: HKObjectQueryNoLimit,
                        sortDescriptors: [sortDescriptor]
                    ) { _, results, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                        }
                    }
                    self.healthStore.execute(query)
                }

                guard !samples.isEmpty else { return nil }

                let values = samples.map { $0.quantity.doubleValue(for: HKUnit.degreeCelsius()) }
                return values.reduce(0, +) / Double(values.count)
            } catch {
                return nil
            }
        } else {
            return nil
        }
    }

    // MARK: - Fetch Resting Heart Rate

    func fetchRestingHeartRate() async -> Double? {
        guard isAvailable else { return nil }

        let type = HKQuantityType(.restingHeartRate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        do {
            let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: nil,
                    limit: 1,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKQuantitySample]) ?? [])
                    }
                }
                self.healthStore.execute(query)
            }

            guard let sample = samples.first else { return nil }
            let beatsPerMin = HKUnit.count().unitDivided(by: .minute())
            return sample.quantity.doubleValue(for: beatsPerMin)
        } catch {
            return nil
        }
    }

    // MARK: - Fetch Apple Watch Sleep Stages

    /// Returns the stage-classified sleep samples that Apple Watch wrote
    /// during the given window, converted into our internal `SleepStageEntry`
    /// type. When this returns a non-empty array, prefer it over our own
    /// iPhone-only motion+audio estimation — Apple Watch has direct heart
    /// rate and motion data that's much more reliable.
    func fetchAppleWatchStages(from start: Date, to end: Date) async -> [SleepStageEntry] {
        guard isAvailable, isAuthorized else { return [] }
        let sleepType = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let samples: [HKCategorySample]
        do {
            samples = try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: sleepType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [sortDescriptor]
                ) { _, results, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
                    }
                }
                self.healthStore.execute(query)
            }
        } catch {
            return []
        }

        return samples.compactMap { sample -> SleepStageEntry? in
            let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
            let mapped: SleepStageType
            switch value {
            case .awake: mapped = .awake
            case .asleepCore: mapped = .light
            case .asleepDeep: mapped = .deep
            case .asleepREM: mapped = .rem
            default: return nil // inBed / asleepUnspecified — we don't merge those
            }
            return SleepStageEntry(
                startTime: sample.startDate,
                endTime: sample.endDate,
                stage: mapped
            )
        }
    }

    // MARK: - Fetch All Biometrics

    func fetchAllBiometrics(from start: Date, to end: Date) async -> BiometricStats {
        async let heartRate = fetchHeartRate(from: start, to: end)
        async let hrv = fetchHRV(from: start, to: end)
        async let respRate = fetchRespiratoryRate(from: start, to: end)
        async let oxygen = fetchBloodOxygen(from: start, to: end)
        async let temp = fetchWristTemperature(from: start, to: end)

        return BiometricStats(
            heartRate: await heartRate,
            hrvAverage: await hrv,
            respiratoryRate: await respRate,
            bloodOxygen: await oxygen,
            wristTemperature: await temp
        )
    }
}
