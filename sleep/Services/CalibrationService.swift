//
//  CalibrationService.swift
//  sleep
//
//

import Foundation
import os
import SwiftUI

// MARK: - Calibration Phase

enum CalibrationPhase: Equatable {
    case notStarted
    case calibrating(progress: Double)
    case completed(baseline: Double)
    case skipped
}

// MARK: - Calibration Log Entry

struct CalibrationLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: LogCategory
    let message: String

    enum LogCategory: String {
        case system = "SYS"
        case motion = "MOT"
        case audio = "AUD"
        case fft = "FFT"
        case result = "RES"

        var color: Color {
            switch self {
            case .system: .gray
            case .motion: .green
            case .audio: .blue
            case .fft: .purple
            case .result: .orange
            }
        }
    }
}

// MARK: - Calibration Service

@Observable
@MainActor
final class CalibrationService {

    // MARK: - Observable State

    var phase: CalibrationPhase = .notStarted
    var baseline: Double = 0.0
    var logEntries: [CalibrationLogEntry] = []

    // MARK: - Private

    private var calibrationTimer: Timer?
    private var calibrationSamples: [Double] = []
    private var sampleCount: Int = 0
    private var calibrationStartTime: Date?

    /// Matches the 15-second baseline animation shown by GetReadyForBedView
    /// so calibration finishes exactly when the user can tap Start Tracking.
    /// If mismatched, SleepTrackingService sees phase != .completed and
    /// kicks off a second round of calibration.
    private let calibrationDuration: TimeInterval = 15
    private let sampleInterval: TimeInterval = 0.5

    private let baselineKey = "sleep_calibration_baseline"

    // MARK: - Start Calibration

    func startCalibration(motionService: MotionService, audioService: AudioService) {
        logEntries = []
        calibrationSamples = []
        sampleCount = 0
        calibrationStartTime = Date()

        log(.system, "Calibration system initializing...")
        log(.system, "Duration: \(Int(calibrationDuration))s | Sample rate: \(sampleInterval)s")
        log(.system, "Environment sensors: Motion + Audio + FFT analysis")
        log(.system, "Place device on pillow/mattress and remain still")

        phase = .calibrating(progress: 0)

        calibrationTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { _ in
            Task { @MainActor [weak self, weak motionService, weak audioService] in
                guard let self = self else { return }
                guard let motionService, let audioService else { return }
                guard let startTime = self.calibrationStartTime else { return }

                let elapsed = Date().timeIntervalSince(startTime)
                let progress = min(elapsed / self.calibrationDuration, 1.0)

                self.sampleCount += 1
                let motionIntensity = motionService.currentIntensity
                self.calibrationSamples.append(motionIntensity)

                // Every 2nd sample: log motion data
                if self.sampleCount % 2 == 0 {
                    let samples = self.calibrationSamples
                    let avg = samples.reduce(0, +) / Double(samples.count)
                    let minVal = samples.min() ?? 0
                    let maxVal = samples.max() ?? 0
                    self.log(.motion, String(
                        format: "intensity=%.6f avg=%.6f min=%.6f max=%.6f",
                        motionIntensity, avg, minVal, maxVal
                    ))
                }

                // Every 4th sample: log audio data
                if self.sampleCount % 4 == 0 {
                    let amplitude = audioService.currentAmplitude
                    let dB = amplitude > 0 ? 20.0 * log10(amplitude) : -160.0
                    self.log(.audio, String(
                        format: "amplitude=%.6f level=%.1f dB",
                        amplitude, dB
                    ))

                    let snoringRatio = audioService.snoringBandEnergy
                    self.log(.fft, String(
                        format: "snoring_band_ratio=%.6f",
                        snoringRatio
                    ))
                }

                // Every 20th sample: log progress
                if self.sampleCount % 20 == 0 {
                    let remaining = max(0, self.calibrationDuration - elapsed)
                    self.log(.system, String(
                        format: "Progress: %.1f%% | Samples: %d | Remaining: %.0fs",
                        progress * 100, self.sampleCount, remaining
                    ))
                }

                self.phase = .calibrating(progress: progress)

                if elapsed >= self.calibrationDuration {
                    self.finishCalibration()
                }
            }
        }
    }

    // MARK: - Finish Calibration

    private func finishCalibration() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil

        guard !calibrationSamples.isEmpty else {
            log(.result, "Calibration failed: no samples collected")
            phase = .notStarted
            return
        }

        let sorted = calibrationSamples.sorted()
        let count = Double(calibrationSamples.count)
        let mean = calibrationSamples.reduce(0, +) / count
        let median = sorted[sorted.count / 2]
        let variance = calibrationSamples.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / count
        let stdDev = sqrt(variance)
        let minVal = sorted.first ?? 0
        let maxVal = sorted.last ?? 0

        baseline = median
        UserDefaults.standard.set(baseline, forKey: baselineKey)
        AppLogger.tracking.info("📏 Calibration baseline: \(median)")

        log(.result, "--- Calibration Complete ---")
        log(.result, String(format: "Total samples: %d", calibrationSamples.count))
        log(.result, String(format: "Mean:     %.6f", mean))
        log(.result, String(format: "Median:   %.6f", median))
        log(.result, String(format: "Std Dev:  %.6f", stdDev))
        log(.result, String(format: "Min:      %.6f", minVal))
        log(.result, String(format: "Max:      %.6f", maxVal))
        log(.result, String(format: "Baseline set to: %.6f (median)", baseline))

        phase = .completed(baseline: baseline)
    }

    // MARK: - Skip / Clear / Apply / Load

    func skipCalibration() {
        calibrationTimer?.invalidate()
        calibrationTimer = nil
        phase = .skipped
        log(.system, "Calibration skipped by user")
    }

    func clearBaseline() {
        UserDefaults.standard.removeObject(forKey: baselineKey)
        baseline = 0.0
        phase = .notStarted
        logEntries = []
    }

    func applyCalibration(to intensity: Double) -> Double {
        guard baseline > 0 else { return intensity }
        return max(0, intensity - baseline)
    }

    func loadSavedBaseline() {
        let saved = UserDefaults.standard.double(forKey: baselineKey)
        if saved > 0 {
            baseline = saved
            phase = .completed(baseline: saved)
        }
    }

    // MARK: - Private Logging

    private func log(_ category: CalibrationLogEntry.LogCategory, _ message: String) {
        let entry = CalibrationLogEntry(
            timestamp: Date(),
            category: category,
            message: message
        )
        logEntries.append(entry)

        // Cap at 500 entries
        if logEntries.count > 500 {
            logEntries.removeFirst(logEntries.count - 500)
        }
    }
}
