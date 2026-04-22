//
//  NotificationService.swift
//  sleep
//
//

import Foundation
import os
import UserNotifications

@Observable
@MainActor
final class NotificationService: NSObject {

    // MARK: - Observable State

    var isAuthorized = false

    // MARK: - Init

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Request Authorization

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings])
            isAuthorized = granted
        } catch {
            AppLogger.notification.error("Notification authorization failed: \(error.localizedDescription)")
            isAuthorized = false
        }
    }

    // MARK: - Bedtime Reminder

    func scheduleBedtimeReminder(at time: Date, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        let identifier = "com.sleep.bedtimeReminder"

        // Always remove existing
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard enabled else {
            AppLogger.notification.info("🔔 Bedtime reminder disabled — cleared any pending")
            return
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 22
        let minute = components.minute ?? 30

        // Make sure we actually have permission. If the user denied earlier
        // we silently couldn't schedule; now we prompt once and bail out if
        // still not granted so the UI can reflect that.
        Task {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let latest = await center.notificationSettings()
            guard latest.authorizationStatus == .authorized || latest.authorizationStatus == .provisional else {
                AppLogger.notification.error("🔔 Can't schedule bedtime reminder — notifications not authorized (status: \(latest.authorizationStatus.rawValue))")
                await MainActor.run { self.isAuthorized = false }
                return
            }
            await MainActor.run { self.isAuthorized = true }

            let content = UNMutableNotificationContent()
            content.title = "Bedtime Reminder"
            content.body = "Time to wind down and get ready for sleep."
            content.sound = .default
            content.categoryIdentifier = "BEDTIME_REMINDER"

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                AppLogger.notification.info("🔔 Scheduled bedtime reminder — fires daily at \(String(format: "%02d:%02d", hour, minute))")
            } catch {
                AppLogger.notification.error("Failed to schedule bedtime reminder: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Morning Summary

    func sendMorningSummary(duration: TimeInterval, quality: String, score: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Good Morning! Here's Your Sleep Summary"
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        content.body = "You slept \(hours)h \(minutes)m. Quality: \(quality). Sleep Score: \(score)/100."
        content.sound = .default
        content.categoryIdentifier = "MORNING_SUMMARY"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "com.sleep.morningSummary.\(UUID().uuidString)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notification.error("Failed to send morning summary: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Weekly Digest

    func scheduleWeeklyDigest(enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        let identifier = "com.sleep.weeklyDigest"

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard enabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Weekly Sleep Digest"
        content.body = "Your weekly sleep report is ready. Tap to view your trends and insights."
        content.sound = .default
        content.categoryIdentifier = "WEEKLY_DIGEST"

        // Sunday at 9:00 AM
        var dateComponents = DateComponents()
        dateComponents.weekday = 1 // Sunday
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        center.add(request) { error in
            if let error = error {
                AppLogger.notification.error("Failed to schedule weekly digest: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Wind-Down Reminder

    func scheduleWindDownReminder(bedtime: Date, minutesBefore: Int, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        let identifier = "com.sleep.windDownReminder"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled, minutesBefore > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Wind Down Time"
        content.body = "Bedtime is in \(minutesBefore) minutes. Start your wind-down routine."
        content.sound = .default
        content.categoryIdentifier = "WIND_DOWN"

        let calendar = Calendar.current
        let bedComponents = calendar.dateComponents([.hour, .minute], from: bedtime)
        guard let hour = bedComponents.hour, let minute = bedComponents.minute else { return }

        // Calculate reminder time
        var reminderDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        reminderDate = reminderDate.addingTimeInterval(-Double(minutesBefore * 60))
        let reminderComponents = calendar.dateComponents([.hour, .minute], from: reminderDate)

        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderComponents, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { AppLogger.notification.error("Failed to schedule wind-down reminder: \(error.localizedDescription)") }
        }
    }

    // MARK: - Battery Warning

    func sendBatteryWarning(level: Float) {
        let content = UNMutableNotificationContent()
        content.title = "Low Battery Warning"
        content.body = String(format: "Battery at %.0f%%. Sleep tracking may stop if battery runs out. Please plug in your device.", level * 100)
        content.sound = .default
        content.categoryIdentifier = "BATTERY_WARNING"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "com.sleep.batteryWarning.\(UUID().uuidString)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.notification.error("Failed to send battery warning: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Streak Celebration

    func sendStreakCelebration(streakCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "🎉 \(streakCount)-Night Streak!"
        content.body = "You've tracked your sleep \(streakCount) nights in a row. Keep it up!"
        content.sound = .default
        content.categoryIdentifier = "STREAK_CELEBRATION"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "com.sleep.streak.\(streakCount)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    // MARK: - Goal Achievement

    func sendGoalAchievement(hours: Double, goalHours: Double) {
        let content = UNMutableNotificationContent()
        content.title = "🎯 Sleep Goal Achieved!"
        content.body = String(format: "You slept %.1f hours — you met your %.0f-hour goal!", hours, goalHours)
        content.sound = .default
        content.categoryIdentifier = "GOAL_ACHIEVEMENT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: "com.sleep.goal.\(UUID().uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification fires while the app is in the foreground.
    /// Without this, iOS silently swallows the notification (no banner, no sound).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list, .badge])
    }
}
