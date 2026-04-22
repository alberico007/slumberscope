//
//  SleepSettings.swift
//  sleep
//
//

import Foundation

/// CDC/National Sleep Foundation recommended sleep hours by age
func recommendedSleepHours(forAge age: Int) -> Double {
    switch age {
    case 13...17: return 9.0   // CDC: 8-10h
    case 18...25: return 8.0   // CDC: 7-9h
    case 26...64: return 8.0   // CDC: 7-9h
    case 65...:   return 7.5   // CDC: 7-8h
    default:      return 8.0
    }
}

func recommendedSleepLabel(forAge age: Int) -> String {
    switch age {
    case 13...17: return "8-10 hours (teens)"
    case 18...25: return "7-9 hours (young adults)"
    case 26...64: return "7-9 hours (adults)"
    case 65...:   return "7-8 hours (older adults)"
    default:      return "7-9 hours"
    }
}

/// One-sentence explanation for the recommended sleep hours, tailored to age
/// band. Used in the onboarding age step as live feedback under the stepper.
func recommendedSleepRationale(forAge age: Int) -> String {
    switch age {
    case 13...17:
        return "Teens are still growing; the CDC recommends 8–10 hours a night for healthy development."
    case 18...25:
        return "Young adult sleep needs stay in the 7–9 hour range — less than 7 is linked to worse mood and focus."
    case 26...64:
        return "Most adults do best on 7–9 hours a night; consistent timing matters as much as total hours."
    case 65...:
        return "After 65, 7–8 hours tends to be enough, but quality and daytime naps matter more than hitting a number."
    default:
        return "Adults typically need 7–9 hours a night for full physical and cognitive recovery."
    }
}

@Observable
final class SleepSettings {

    // MARK: - Keys

    private enum Keys {
        static let trackMotion = "sleep_trackMotion"
        static let trackAudio = "sleep_trackAudio"
        static let syncHealthKit = "sleep_syncHealthKit"
        static let bedtimeReminderEnabled = "sleep_bedtimeReminderEnabled"
        static let bedtimeReminderTime = "sleep_bedtimeReminderTime"
        static let showSleepScore = "sleep_showSleepScore"
        static let sensitivityLevel = "sleep_sensitivityLevel"
        static let morningSummaryEnabled = "sleep_morningSummaryEnabled"
        static let weeklyDigestEnabled = "sleep_weeklyDigestEnabled"
        static let calibrationEnabled = "sleep_calibrationEnabled"
        static let hasCompletedOnboarding = "sleep_hasCompletedOnboarding"
        // New keys
        static let sleepGoalHours = "sleep_sleepGoalHours"
        static let scheduledBedtime = "sleep_scheduledBedtime"
        static let scheduledWakeTime = "sleep_scheduledWakeTime"
        static let weekendBedtime = "sleep_weekendBedtime"
        static let weekendWakeTime = "sleep_weekendWakeTime"
        static let useWeekendSchedule = "sleep_useWeekendSchedule"
        static let gradualWakeEnabled = "sleep_gradualWakeEnabled"
        static let gradualWakeMinutes = "sleep_gradualWakeMinutes"
        static let soundTimerMinutes = "sleep_soundTimerMinutes"
        static let autoStopTracking = "sleep_autoStopTracking"
        static let enableSleepFocus = "sleep_enableSleepFocus"
        static let windDownReminderMinutes = "sleep_windDownReminderMinutes"
        static let vacationMode = "sleep_vacationMode"
        static let vacationEndDate = "sleep_vacationEndDate"
        static let scheduleMode = "sleep_scheduleMode" // "regular", "shiftWork", "custom"
        static let shiftPatterns = "sleep_shiftPatterns" // JSON encoded
        static let customDaySchedules = "sleep_customDaySchedules" // JSON encoded
        static let audioStorageCloud = "sleep_audioStorageCloud"
        static let aiCoachingEnabled = "sleep_aiCoachingEnabled"
        static let userName = "sleep_userName"
        static let userLastName = "sleep_userLastName"
        static let userAge = "sleep_userAge"
        static let userPhotoData = "sleep_userPhotoData"
        static let userGender = "sleep_userGender"
        static let snoringSensitivity = "sleep_snoringSensitivity"
        static let minimumSnoreDuration = "sleep_minimumSnoreDuration"
        // Sleep audio + new start-flow keys
        static let appleMusicEnabled = "sleep_appleMusicEnabled"
        static let podcastsEnabled = "sleep_podcastsEnabled"
        static let skipBedIntentConfirmation = "sleep_skipBedIntentConfirmation"
        static let defaultSleepTimerMinutes = "sleep_defaultSleepTimerMinutes"
        static let environmentalNoiseFilteringEnabled = "sleep_environmentalNoiseFilteringEnabled"
        static let cloudSnoringClassifierEnabled = "sleep_cloudSnoringClassifierEnabled"
    }

    // MARK: - Properties

    var trackMotion: Bool {
        didSet { save() }
    }

    var trackAudio: Bool {
        didSet { save() }
    }

    var syncHealthKit: Bool {
        didSet { save() }
    }

    var bedtimeReminderEnabled: Bool {
        didSet { save() }
    }

    var bedtimeReminderTime: Date {
        didSet { save() }
    }

    var showSleepScore: Bool {
        didSet { save() }
    }

    var sensitivityLevel: Double {
        didSet { save() }
    }


    var morningSummaryEnabled: Bool {
        didSet { save() }
    }

    var weeklyDigestEnabled: Bool {
        didSet { save() }
    }

    var calibrationEnabled: Bool {
        didSet { save() }
    }

    var hasCompletedOnboarding: Bool {
        didSet { save() }
    }

    // MARK: - New Properties

    var sleepGoalHours: Double {
        didSet { save() }
    }

    var scheduledBedtime: Date {
        didSet { save() }
    }

    var scheduledWakeTime: Date {
        didSet { save() }
    }

    var weekendBedtime: Date {
        didSet { save() }
    }

    var weekendWakeTime: Date {
        didSet { save() }
    }

    var useWeekendSchedule: Bool {
        didSet { save() }
    }

    var gradualWakeEnabled: Bool {
        didSet { save() }
    }

    var gradualWakeMinutes: Int {
        didSet { save() }
    }

    var soundTimerMinutes: Int {
        didSet { save() }
    }

    var autoStopTracking: Bool {
        didSet { save() }
    }

    var enableSleepFocus: Bool {
        didSet { save() }
    }

    var windDownReminderMinutes: Int {
        didSet { save() }
    }

    var vacationMode: Bool {
        didSet { save() }
    }

    var vacationEndDate: Date {
        didSet { save() }
    }

    var scheduleMode: String {
        didSet { save() }
    }

    var audioStorageCloud: Bool {
        didSet { save() }
    }

    var aiCoachingEnabled: Bool {
        didSet { save() }
    }

    var userName: String {
        didSet { save() }
    }

    var userLastName: String {
        didSet { save() }
    }

    var userAge: Int {
        didSet { save() }
    }

    var userGender: String {
        didSet { save() }
    }

    /// JPEG data of the user's profile photo. Displayed in the profile page
    /// and embedded in PDF exports so clinicians can visually identify the
    /// patient whose sleep report they're reviewing.
    var userPhotoData: Data? {
        didSet { save() }
    }

    /// 0.0 = very sensitive (light snorer), 1.0 = least sensitive (heavy snorer)
    var snoringSensitivity: Double {
        didSet { save() }
    }

    /// Minimum snore duration in seconds (0.5 - 3.0)
    var minimumSnoreDuration: Double {
        didSet { save() }
    }

    // MARK: - Sleep audio + new start-flow

    /// Show the Apple Music tab during the Get Ready for Bed chooser.
    var appleMusicEnabled: Bool {
        didSet { save() }
    }

    /// Show the Podcasts tab during the Get Ready for Bed chooser.
    var podcastsEnabled: Bool {
        didSet { save() }
    }

    /// Skip the "I'm ready to sleep" intent screen before baseline.
    var skipBedIntentConfirmation: Bool {
        didSet { save() }
    }

    /// Default sleep-timer duration (minutes) pre-selected on the chooser.
    /// 0 means "until I wake up" (no timer).
    var defaultSleepTimerMinutes: Int {
        didSet { save() }
    }

    /// Filter out non-snore sounds (fans, AC, dogs, speech) via SoundAnalysis.
    var environmentalNoiseFilteringEnabled: Bool {
        didSet { save() }
    }

    /// Send detected snoring clips to an Azure-hosted YAMNet classifier for a
    /// more accurate label. Off by default — bedroom audio leaving the device
    /// is opt-in.
    var cloudSnoringClassifierEnabled: Bool {
        didSet { save() }
    }

    // MARK: - Defaults

    private static func defaultTime(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? .now
    }

    // MARK: - Init

    init() {
        let defaults = UserDefaults.standard
        let hasExistingData = defaults.object(forKey: Keys.trackMotion) != nil

        if hasExistingData {
            self.trackMotion = defaults.bool(forKey: Keys.trackMotion)
            self.trackAudio = defaults.bool(forKey: Keys.trackAudio)
            self.syncHealthKit = defaults.bool(forKey: Keys.syncHealthKit)
            self.bedtimeReminderEnabled = defaults.bool(forKey: Keys.bedtimeReminderEnabled)
            self.showSleepScore = defaults.bool(forKey: Keys.showSleepScore)
            self.sensitivityLevel = defaults.double(forKey: Keys.sensitivityLevel)
            self.morningSummaryEnabled = defaults.bool(forKey: Keys.morningSummaryEnabled)
            self.weeklyDigestEnabled = defaults.bool(forKey: Keys.weeklyDigestEnabled)
            self.calibrationEnabled = defaults.bool(forKey: Keys.calibrationEnabled)
            self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)

            if let bedtimeData = defaults.object(forKey: Keys.bedtimeReminderTime) as? Date {
                self.bedtimeReminderTime = bedtimeData
            } else {
                self.bedtimeReminderTime = Self.defaultTime(hour: 22, minute: 30)
            }

            // New properties with defaults
            let goalVal = defaults.double(forKey: Keys.sleepGoalHours)
            self.sleepGoalHours = goalVal > 0 ? goalVal : 8.0
            self.scheduledBedtime = (defaults.object(forKey: Keys.scheduledBedtime) as? Date) ?? Self.defaultTime(hour: 23, minute: 0)
            self.scheduledWakeTime = (defaults.object(forKey: Keys.scheduledWakeTime) as? Date) ?? Self.defaultTime(hour: 7, minute: 0)
            self.weekendBedtime = (defaults.object(forKey: Keys.weekendBedtime) as? Date) ?? Self.defaultTime(hour: 0, minute: 0)
            self.weekendWakeTime = (defaults.object(forKey: Keys.weekendWakeTime) as? Date) ?? Self.defaultTime(hour: 8, minute: 30)
            self.useWeekendSchedule = defaults.bool(forKey: Keys.useWeekendSchedule)
            self.gradualWakeEnabled = defaults.bool(forKey: Keys.gradualWakeEnabled)
            let gradVal = defaults.integer(forKey: Keys.gradualWakeMinutes)
            self.gradualWakeMinutes = gradVal > 0 ? gradVal : 5
            let timerVal = defaults.integer(forKey: Keys.soundTimerMinutes)
            self.soundTimerMinutes = timerVal > 0 ? timerVal : 30
            self.autoStopTracking = defaults.bool(forKey: Keys.autoStopTracking)
            self.enableSleepFocus = defaults.bool(forKey: Keys.enableSleepFocus)
            let windVal = defaults.integer(forKey: Keys.windDownReminderMinutes)
            self.windDownReminderMinutes = windVal > 0 ? windVal : 30
            self.vacationMode = defaults.bool(forKey: Keys.vacationMode)
            self.vacationEndDate = (defaults.object(forKey: Keys.vacationEndDate) as? Date) ?? Date()
            self.scheduleMode = (defaults.string(forKey: Keys.scheduleMode)) ?? "regular"
            self.audioStorageCloud = defaults.bool(forKey: Keys.audioStorageCloud)
            self.aiCoachingEnabled = defaults.object(forKey: Keys.aiCoachingEnabled) == nil ? true : defaults.bool(forKey: Keys.aiCoachingEnabled)
            self.userName = defaults.string(forKey: Keys.userName) ?? ""
            self.userLastName = defaults.string(forKey: Keys.userLastName) ?? ""
            let ageVal = defaults.integer(forKey: Keys.userAge)
            self.userAge = ageVal > 0 ? ageVal : 30
            self.userGender = defaults.string(forKey: Keys.userGender) ?? "Not specified"
            self.userPhotoData = defaults.data(forKey: Keys.userPhotoData)
            let senVal = defaults.object(forKey: Keys.snoringSensitivity) as? Double
            self.snoringSensitivity = senVal ?? 0.5
            let durVal = defaults.object(forKey: Keys.minimumSnoreDuration) as? Double
            // One-time migration: the old default was 0.8s, too long for
            // many real snores. If the user never touched the slider (value
            // still equals the old default), bump it down to the new 0.4s
            // default so they don't need to hunt through Settings.
            if let stored = durVal, stored == 0.8 {
                self.minimumSnoreDuration = 0.4
                defaults.set(0.4, forKey: Keys.minimumSnoreDuration)
            } else {
                self.minimumSnoreDuration = durVal ?? 0.4
            }
            self.appleMusicEnabled = defaults.bool(forKey: Keys.appleMusicEnabled)
            self.podcastsEnabled = defaults.bool(forKey: Keys.podcastsEnabled)
            self.skipBedIntentConfirmation = defaults.bool(forKey: Keys.skipBedIntentConfirmation)
            let sleepTimerVal = defaults.object(forKey: Keys.defaultSleepTimerMinutes) as? Int
            self.defaultSleepTimerMinutes = sleepTimerVal ?? 30
            self.environmentalNoiseFilteringEnabled = defaults.object(forKey: Keys.environmentalNoiseFilteringEnabled) == nil
                ? true
                : defaults.bool(forKey: Keys.environmentalNoiseFilteringEnabled)
            self.cloudSnoringClassifierEnabled = defaults.object(forKey: Keys.cloudSnoringClassifierEnabled) == nil
                ? true
                : defaults.bool(forKey: Keys.cloudSnoringClassifierEnabled)
        } else {
            // First launch — set all defaults
            self.trackMotion = true
            self.trackAudio = true
            self.syncHealthKit = false
            self.bedtimeReminderEnabled = false
            self.bedtimeReminderTime = Self.defaultTime(hour: 22, minute: 30)
            self.showSleepScore = true
            self.sensitivityLevel = 0.5
            self.morningSummaryEnabled = true
            self.weeklyDigestEnabled = true
            self.calibrationEnabled = true
            self.hasCompletedOnboarding = false
            // New defaults
            self.sleepGoalHours = 8.0
            self.scheduledBedtime = Self.defaultTime(hour: 23, minute: 0)
            self.scheduledWakeTime = Self.defaultTime(hour: 7, minute: 0)
            self.weekendBedtime = Self.defaultTime(hour: 0, minute: 0)
            self.weekendWakeTime = Self.defaultTime(hour: 8, minute: 30)
            self.useWeekendSchedule = false
            self.gradualWakeEnabled = false
            self.gradualWakeMinutes = 5
            self.soundTimerMinutes = 30
            self.autoStopTracking = true
            self.enableSleepFocus = true
            self.windDownReminderMinutes = 30
            self.vacationMode = false
            self.vacationEndDate = Date()
            self.scheduleMode = "regular"
            self.audioStorageCloud = false
            self.aiCoachingEnabled = true
            self.userName = ""
            self.userLastName = ""
            self.userAge = 30
            self.userGender = "Not specified"
            self.userPhotoData = nil
            self.snoringSensitivity = 0.5
            self.minimumSnoreDuration = 0.4
            self.appleMusicEnabled = false
            self.podcastsEnabled = false
            self.skipBedIntentConfirmation = false
            self.defaultSleepTimerMinutes = 30
            self.environmentalNoiseFilteringEnabled = true
            self.cloudSnoringClassifierEnabled = true
        }
    }

    // MARK: - Save

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(trackMotion, forKey: Keys.trackMotion)
        defaults.set(trackAudio, forKey: Keys.trackAudio)
        defaults.set(syncHealthKit, forKey: Keys.syncHealthKit)
        defaults.set(bedtimeReminderEnabled, forKey: Keys.bedtimeReminderEnabled)
        defaults.set(bedtimeReminderTime, forKey: Keys.bedtimeReminderTime)
        defaults.set(showSleepScore, forKey: Keys.showSleepScore)
        defaults.set(sensitivityLevel, forKey: Keys.sensitivityLevel)
        defaults.set(morningSummaryEnabled, forKey: Keys.morningSummaryEnabled)
        defaults.set(weeklyDigestEnabled, forKey: Keys.weeklyDigestEnabled)
        defaults.set(calibrationEnabled, forKey: Keys.calibrationEnabled)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        // New properties
        defaults.set(sleepGoalHours, forKey: Keys.sleepGoalHours)
        defaults.set(scheduledBedtime, forKey: Keys.scheduledBedtime)
        defaults.set(scheduledWakeTime, forKey: Keys.scheduledWakeTime)
        defaults.set(weekendBedtime, forKey: Keys.weekendBedtime)
        defaults.set(weekendWakeTime, forKey: Keys.weekendWakeTime)
        defaults.set(useWeekendSchedule, forKey: Keys.useWeekendSchedule)
        defaults.set(gradualWakeEnabled, forKey: Keys.gradualWakeEnabled)
        defaults.set(gradualWakeMinutes, forKey: Keys.gradualWakeMinutes)
        defaults.set(soundTimerMinutes, forKey: Keys.soundTimerMinutes)
        defaults.set(autoStopTracking, forKey: Keys.autoStopTracking)
        defaults.set(enableSleepFocus, forKey: Keys.enableSleepFocus)
        defaults.set(windDownReminderMinutes, forKey: Keys.windDownReminderMinutes)
        defaults.set(vacationMode, forKey: Keys.vacationMode)
        defaults.set(vacationEndDate, forKey: Keys.vacationEndDate)
        defaults.set(scheduleMode, forKey: Keys.scheduleMode)
        defaults.set(audioStorageCloud, forKey: Keys.audioStorageCloud)
        defaults.set(aiCoachingEnabled, forKey: Keys.aiCoachingEnabled)
        defaults.set(userName, forKey: Keys.userName)
        defaults.set(userLastName, forKey: Keys.userLastName)
        defaults.set(userAge, forKey: Keys.userAge)
        defaults.set(userGender, forKey: Keys.userGender)
        defaults.set(userPhotoData, forKey: Keys.userPhotoData)
        defaults.set(snoringSensitivity, forKey: Keys.snoringSensitivity)
        defaults.set(minimumSnoreDuration, forKey: Keys.minimumSnoreDuration)
        defaults.set(appleMusicEnabled, forKey: Keys.appleMusicEnabled)
        defaults.set(podcastsEnabled, forKey: Keys.podcastsEnabled)
        defaults.set(skipBedIntentConfirmation, forKey: Keys.skipBedIntentConfirmation)
        defaults.set(defaultSleepTimerMinutes, forKey: Keys.defaultSleepTimerMinutes)
        defaults.set(environmentalNoiseFilteringEnabled, forKey: Keys.environmentalNoiseFilteringEnabled)
        defaults.set(cloudSnoringClassifierEnabled, forKey: Keys.cloudSnoringClassifierEnabled)
    }
}
