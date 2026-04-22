//
//  SleepFocusService.swift
//  sleep
//
//

import Foundation
import Intents
import os

#if canImport(UIKit)
import UIKit
#endif

@Observable
@MainActor
final class SleepFocusService {

    // MARK: - Observable State

    var isFocusEnabled = false
    var authorizationStatus: INFocusStatusAuthorizationStatus = .notDetermined

    // MARK: - Private

    private var focusCheckTimer: Timer?

    // MARK: - Init

    init() {
        checkFocusStatus()
    }

    // MARK: - Check Focus Status

    func checkFocusStatus() {
        let center = INFocusStatusCenter.default
        let status = center.focusStatus

        isFocusEnabled = status.isFocused ?? false
        authorizationStatus = center.authorizationStatus
        AppLogger.focus.info("🌙 Focus status: \(self.isFocusEnabled)")
    }

    // MARK: - Request Authorization

    func requestAuthorization() async {
        let center = INFocusStatusCenter.default

        let status = await center.requestAuthorization()
        self.authorizationStatus = status
        self.checkFocusStatus()
    }

    // MARK: - Enable Sleep Focus

    /// Starts monitoring Focus status when a sleep session begins.
    /// iOS does not expose a direct API to toggle Focus programmatically,
    /// but if the user has a Sleep Focus schedule, it will be detected here.
    func enableSleepFocus() {
        startFocusMonitoring()
        checkFocusStatus()
    }

    // MARK: - Disable Sleep Focus

    /// Stops monitoring Focus status when a sleep session ends.
    func disableSleepFocus() {
        stopFocusMonitoring()
        checkFocusStatus()
    }

    // MARK: - Focus Monitoring

    /// Periodically checks Focus status to keep the UI up to date during a sleep session.
    func startFocusMonitoring() {
        stopFocusMonitoring()

        focusCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFocusStatus()
            }
        }
    }

    func stopFocusMonitoring() {
        focusCheckTimer?.invalidate()
        focusCheckTimer = nil
    }

    // MARK: - Convenience

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    var statusDescription: String {
        if !isAuthorized {
            return "Focus access not authorized"
        }
        return isFocusEnabled ? "Sleep Focus is active" : "Sleep Focus is not active"
    }
}
