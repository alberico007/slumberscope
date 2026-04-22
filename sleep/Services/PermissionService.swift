//
//  PermissionService.swift
//  sleep
//
//

import AVFoundation
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import os
import UserNotifications

@MainActor
@Observable
final class PermissionService {

    static let shared = PermissionService()

    // MARK: - Observable State

    var microphoneGranted = false
    var motionAvailable = false
    var healthKitAuthorized = false
    var notificationsAuthorized = false
    var locationAuthorized = false

    // MARK: - Private

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()

    private init() {
        motionAvailable = CMMotionManager().isAccelerometerAvailable
        updateCurrentStatuses()
    }

    // MARK: - Status Refresh

    private func updateCurrentStatuses() {
        // Microphone
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }

        // HealthKit
        if HKHealthStore.isHealthDataAvailable() {
            let sleepType = HKCategoryType(.sleepAnalysis)
            let status = healthStore.authorizationStatus(for: sleepType)
            healthKitAuthorized = status == .sharingAuthorized
        }

        // Notifications
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAuthorized = settings.authorizationStatus == .authorized
        }

        // Location
        let locStatus = locationManager.authorizationStatus
        locationAuthorized = locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways
    }

    // MARK: - Request Microphone

    func requestMicrophone() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        microphoneGranted = granted
        AppLogger.general.info("🎤 Microphone permission: \(granted)")
    }

    // MARK: - Request HealthKit

    func requestHealthKit() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let sleepType = HKCategoryType(.sleepAnalysis)
        let typesToShare: Set<HKSampleType> = [sleepType]
        let typesToRead: Set<HKObjectType> = [sleepType]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
            let status = healthStore.authorizationStatus(for: sleepType)
            healthKitAuthorized = status == .sharingAuthorized
            AppLogger.healthKit.info("🏥 HealthKit permission: \(self.healthKitAuthorized)")
        } catch {
            AppLogger.healthKit.error("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Request Notifications

    func requestNotifications() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
            notificationsAuthorized = granted
            AppLogger.notification.info("🔔 Notification permission: \(granted)")
        } catch {
            AppLogger.notification.error("Notification authorization failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Request Location

    func requestLocation() {
        locationManager.requestWhenInUseAuthorization()
        let status = locationManager.authorizationStatus
        locationAuthorized = status == .authorizedWhenInUse || status == .authorizedAlways
        AppLogger.general.info("📍 Location permission: \(self.locationAuthorized)")
    }

    // MARK: - Request All

    func requestAllPermissions() async {
        await requestMicrophone()
        await requestHealthKit()
        await requestNotifications()
        requestLocation()
        motionAvailable = CMMotionManager().isAccelerometerAvailable
    }
}
