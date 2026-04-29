//
//  SmartAlarmService.swift
//  sleep
//

import AudioToolbox
import Foundation
import os

// MARK: - AlarmSound

enum AlarmSound: String, CaseIterable, Identifiable {
    case gentle = "Gentle Chime"
    case sunrise = "Sunrise"
    case birds = "Morning Birds"
    case waves = "Ocean Waves"
    case bells = "Soft Bells"
    case harp = "Harp"
    case piano = "Piano"
    case forest = "Forest"
    case rain = "Light Rain"
    case systemDefault = "Default"

    var id: String { rawValue }

    var systemSoundID: UInt32 {
        switch self {
        case .gentle: 1013
        case .sunrise: 1016
        case .birds: 1025
        case .waves: 1023
        case .bells: 1012
        case .harp: 1014
        case .piano: 1015
        case .forest: 1020
        case .rain: 1021
        case .systemDefault: 1005
        }
    }

    var icon: String {
        switch self {
        case .gentle: "bell.fill"
        case .sunrise: "sunrise.fill"
        case .birds: "bird.fill"
        case .waves: "water.waves"
        case .bells: "bell.and.waves.left.and.right.fill"
        case .harp: "harp"
        case .piano: "pianokeys"
        case .forest: "tree.fill"
        case .rain: "cloud.rain.fill"
        case .systemDefault: "alarm.fill"
        }
    }
}

@Observable
@MainActor
final class SmartAlarmService {

    // MARK: - Observable State

    var isMonitoring = false
    var alarmTriggered = false
    var snoozedUntil: Date?
    var isGradualWakeActive = false
    var gradualWakeProgress: Double = 0
    var selectedSound: AlarmSound = .gentle
    var latestRationale: String?

    // MARK: - Private

    private var alarmTime: Date?
    private var windowMinutes: Int = 30
    private var alarmEnabled = false

    private var monitoringTimer: Timer?
    private var alarmRepeatTimer: Timer?
    private var gradualWakeTimer: Timer?

    // MARK: - Configuration

    func configure(time: Date, windowMinutes: Int, enabled: Bool) {
        self.alarmTime = time
        self.windowMinutes = windowMinutes
        self.alarmEnabled = enabled
    }

    // MARK: - Monitoring

    func startMonitoring(motionService: MotionService, notificationService: NotificationService, healthKitService: HealthKitService? = nil, intelligenceService: IntelligenceService? = nil) {
        guard alarmEnabled, alarmTime != nil else { return }
        isMonitoring = true
        alarmTriggered = false
        snoozedUntil = nil
        AppLogger.alarm.info("⏰ Smart alarm monitoring started — target: \(String(describing: self.alarmTime)), window: \(self.windowMinutes)m")

        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard !self.alarmTriggered else { return }

                if let snoozed = self.snoozedUntil, Date() < snoozed { return }
                guard self.isInAlarmWindow() else { return }

                if let hk = healthKitService {
                    let recentStart = Date().addingTimeInterval(-120)
                    let recentStages = await hk.fetchAppleWatchStages(from: recentStart, to: Date())
                    let latest = recentStages.last
                    switch latest?.stage {
                    case .light, .awake, .rem:
                        AppLogger.alarm.info("⏰ Triggering — Apple Watch reports \(latest!.stage.rawValue) stage")
                        let minsEarly = self.minutesEarlyVsLatest()
                        self.storeRationale(stage: latest!.stage.rawValue, minsEarly: minsEarly)
                        self.triggerAlarm()
                        notificationService.sendAlarmFiredNotification()
                        return
                    case .deep:
                        AppLogger.alarm.debug("⏰ Holding — Watch reports deep sleep")
                        return
                    default:
                        break
                    }
                }

                if motionService.currentIntensity > 0.08 {
                    AppLogger.alarm.info("⏰ Triggering — motion intensity \(motionService.currentIntensity)")
                    let minsEarly = self.minutesEarlyVsLatest()
                    self.storeRationale(stage: "light", minsEarly: minsEarly)
                    self.triggerAlarm()
                    notificationService.sendAlarmFiredNotification()
                } else {
                    AppLogger.alarm.debug("⏰ Holding — motion \(motionService.currentIntensity) below threshold")
                }
            }
        }
    }

    // MARK: - Trigger Alarm

    func triggerAlarm() {
        guard !alarmTriggered else { return }
        alarmTriggered = true
        AppLogger.alarm.info("⏰ Smart alarm triggered!")

        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        AudioServicesPlayAlertSound(1005)

        alarmRepeatTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.alarmTriggered else { return }
                AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
                AudioServicesPlayAlertSound(1005)
            }
        }
    }

    // MARK: - Snooze

    func snooze(minutes: Int) {
        AppLogger.alarm.info("💤 Alarm snoozed for \(minutes) minutes")
        alarmTriggered = false
        alarmRepeatTimer?.invalidate()
        alarmRepeatTimer = nil
        snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    // MARK: - Dismiss

    func dismiss() {
        alarmTriggered = false
        alarmRepeatTimer?.invalidate()
        alarmRepeatTimer = nil
        stopMonitoring()
    }

    // MARK: - Gradual Wake

    func startGradualWake(durationMinutes: Int) {
        isGradualWakeActive = true
        gradualWakeProgress = 0
        let totalSteps = durationMinutes * 60 / 5
        var step = 0

        gradualWakeTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                step += 1
                self.gradualWakeProgress = min(Double(step) / Double(max(totalSteps, 1)), 1.0)

                if step % 12 == 0 {
                    AudioServicesPlaySystemSound(SystemSoundID(self.selectedSound.systemSoundID))
                }

                if self.gradualWakeProgress >= 1.0 {
                    self.gradualWakeTimer?.invalidate()
                    self.gradualWakeTimer = nil
                    self.isGradualWakeActive = false
                    self.triggerFullAlarm()
                }
            }
        }
    }

    private func triggerFullAlarm() {
        alarmTriggered = true
        AudioServicesPlaySystemSound(SystemSoundID(selectedSound.systemSoundID))
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    func stopGradualWake() {
        gradualWakeTimer?.invalidate()
        gradualWakeTimer = nil
        isGradualWakeActive = false
        gradualWakeProgress = 0
    }

    func continueSleeping() {
        alarmTriggered = false
        stopGradualWake()
    }

    // MARK: - Stop Monitoring

    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        alarmRepeatTimer?.invalidate()
        alarmRepeatTimer = nil
        isMonitoring = false
    }

    // MARK: - Rationale

    private func minutesEarlyVsLatest() -> Int {
        guard let alarmTime else { return 0 }
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.hour, .minute], from: alarmTime)
        guard let latest = calendar.date(
            bySettingHour: components.hour ?? 7,
            minute: components.minute ?? 0,
            second: 0,
            of: now
        ) else { return 0 }
        return max(0, Int(latest.timeIntervalSince(now) / 60))
    }

    private func storeRationale(stage: String, minsEarly: Int) {
        let fallback = minsEarly <= 0
            ? "Woke you at your latest alarm — you hadn't hit a light stage yet."
            : "Woke you \(minsEarly) min early during a \(stage) stage for an easier wake-up."
        self.latestRationale = fallback
        AppLogger.alarm.info("⏰ Rationale: \(fallback)")
    }

    // MARK: - Window Check

    private func isInAlarmWindow() -> Bool {
        guard let alarmTime = alarmTime else { return false }
        let calendar = Calendar.current
        let now = Date()
        let alarmComponents = calendar.dateComponents([.hour, .minute], from: alarmTime)
        guard let todayAlarm = calendar.date(bySettingHour: alarmComponents.hour ?? 7,
                                              minute: alarmComponents.minute ?? 0,
                                              second: 0,
                                              of: now) else { return false }
        let windowStart = todayAlarm.addingTimeInterval(TimeInterval(-windowMinutes * 60))
        return now >= windowStart && now <= todayAlarm
    }
}
