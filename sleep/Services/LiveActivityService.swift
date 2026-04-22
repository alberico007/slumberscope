//
//  LiveActivityService.swift
//  sleep
//
//

import Foundation
import ActivityKit
import os

// MARK: - LiveActivityService

@Observable
@MainActor
final class LiveActivityService {

    // MARK: - Observable State

    var currentActivity: Activity<SleepTrackingAttributes>?
    var isActivityActive: Bool { currentActivity != nil }

    // MARK: - Start Live Activity

    func startLiveActivity(startTime: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            AppLogger.liveActivity.warning("Live Activities are not enabled")
            return
        }

        // End any existing activity before starting a new one
        if currentActivity != nil {
            endActivity()
        }

        let attributes = SleepTrackingAttributes(sessionStartTime: startTime)
        let initialState = SleepTrackingAttributes.ContentState(
            elapsedSeconds: 0,
            snoringCount: 0,
            currentPhase: "Starting"
        )

        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            let activity = try Activity<SleepTrackingAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            currentActivity = activity
            AppLogger.liveActivity.info("📱 Started live activity")
        } catch {
            AppLogger.liveActivity.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Activity

    func updateActivity(elapsed: TimeInterval, snoringCount: Int, phase: String) {
        guard currentActivity != nil else { return }

        let updatedState = SleepTrackingAttributes.ContentState(
            elapsedSeconds: Int(elapsed),
            snoringCount: snoringCount,
            currentPhase: phase
        )

        let content = ActivityContent(state: updatedState, staleDate: nil)

        Task { @MainActor [weak self] in
            guard let activity = self?.currentActivity else { return }
            nonisolated(unsafe) let act = activity
            await act.update(content)
        }
    }

    // MARK: - End Activity

    func endActivity() {
        guard currentActivity != nil else { return }
        AppLogger.liveActivity.info("📱 Ending live activity")

        let finalState = SleepTrackingAttributes.ContentState(
            elapsedSeconds: 0,
            snoringCount: 0,
            currentPhase: "Completed"
        )

        let content = ActivityContent(state: finalState, staleDate: nil)

        Task { @MainActor [weak self] in
            guard let activity = self?.currentActivity else { return }
            nonisolated(unsafe) let act = activity
            await act.end(content, dismissalPolicy: .default)
            self?.currentActivity = nil
        }
    }

    // MARK: - End All Activities

    /// Cleans up any orphaned activities from previous sessions.
    func endAllActivities() {
        Task {
            for activity in Activity<SleepTrackingAttributes>.activities {
                let finalState = SleepTrackingAttributes.ContentState(
                    elapsedSeconds: 0,
                    snoringCount: 0,
                    currentPhase: "Completed"
                )
                let content = ActivityContent(state: finalState, staleDate: nil)
                await activity.end(content, dismissalPolicy: .immediate)
            }
            await MainActor.run {
                self.currentActivity = nil
            }
        }
    }

    // MARK: - Helpers

    var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
}
