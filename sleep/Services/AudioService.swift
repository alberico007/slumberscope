//
//  AudioService.swift
//  sleep
//
//

import AVFoundation
import Accelerate
import Foundation
import os

// MARK: - Audio Analysis Result (produced off main thread)

private struct AudioAnalysis: Sendable {
    let amplitude: Double
    let snoringBandRatio: Double // energy in 100-500Hz vs total
    let sampleRate: Double
}

@Observable
@MainActor
final class AudioService {
    var isTracking = false
    var currentAmplitude: Double = 0.0
    var snoringBandEnergy: Double = 0.0
    var snoringEvents: [SnoringEvent] = []

    /// Number of events whose remote classification is still in flight or
    /// being retried. SleepTrackingService polls this on session end so it
    /// can wait briefly for reconciliations to finish before persisting.
    private(set) var pendingRemoteCount: Int = 0

    /// Remote YAMNet classifier. When attached and `.enabled == true`, each
    /// committed snoring event gets re-classified against the Azure endpoint
    /// and its label + confidence overwritten. The local SoundAnalysis veto
    /// still runs first, so obvious non-snores never reach the cloud.
    private(set) weak var remoteClassifier: SnoringClassifierClient?

    private var remoteQueueContinuation: AsyncStream<PendingRemoteItem>.Continuation?
    private var remoteWorker: Task<Void, Never>?

    private struct PendingRemoteItem: Sendable {
        let eventID: UUID
        let clipURL: URL
        let sampleRate: Double
        var attempts: Int = 0
    }

    // Adaptive baseline
    private var ambientBaseline: Double = 0.0
    private var baselineSamples: [Double] = []
    private var baselineCalibrated = false
    private let baselineCalibrationSeconds: TimeInterval = 15
    private var trackingStartTime: Date?

    // Configurable thresholds — set via configure(settings:)
    private var relativeThresholdMultiplier: Double = 1.8
    private var absoluteMinimumThreshold: Double = 0.015
    private var minimumSnoringBandRatio: Double = 0.20
    private var minimumBurstDuration: TimeInterval = 0.8

    // Burst detection
    private var recentBursts: [(time: Date, duration: TimeInterval, amplitude: Double)] = []
    private let burstGroupingWindow: TimeInterval = 30.0
    private let burstsRequiredForEvent: Int = 1

    private var burstStartTime: Date?
    private var burstAmplitudes: [Double] = []

    private var audioEngine: AVAudioEngine?

    // Snoring clip recording via buffer capture (avoids AVAudioRecorder/AVAudioEngine conflict)
    private var audioBufferRing: [AVAudioPCMBuffer] = []
    private var audioBufferFormat: AVAudioFormat?
    private let maxBufferSeconds: Int = 15 // keep last 15 seconds
    private var isRecordingClip = false

    /// Optional environmental-sound classifier. When set, each candidate
    /// snoring event is cross-checked — events overlapping with fan/AC/dog/
    /// speech detections are suppressed. Inject via `attachClassifier`.
    private(set) weak var classifier: SoundClassificationService?

    /// When this reports `isPlaying == true` we ignore any candidate
    /// snoring event — the mic is hearing our own Apple Music / podcast
    /// playback bleed, not the sleeper. Set via `attachMediaPlayback`.
    private(set) weak var mediaPlayback: MediaPlaybackService?

    /// Whether the user has enabled environmental filtering in Settings.
    /// Set at tracking start from SleepSettings.environmentalNoiseFilteringEnabled.
    var environmentalFilteringEnabled: Bool = true

    /// Configure detection thresholds from user settings
    func configure(sensitivity: Double, minDuration: Double) {
        // sensitivity: 0.0 = very sensitive, 1.0 = least sensitive.
        // Band ratio thresholds loosened because the snore band is now
        // 80–900Hz (wider) and the classifier already filters out most
        // non-snore noise; we don't need the FFT to be a second-gate.
        relativeThresholdMultiplier = 1.3 + (sensitivity * 1.4) // 1.3 to 2.7
        minimumSnoringBandRatio = 0.10 + (sensitivity * 0.15)   // 0.10 to 0.25
        absoluteMinimumThreshold = 0.008 + (sensitivity * 0.02) // 0.008 to 0.028
        minimumBurstDuration = minDuration
        AppLogger.audio.info("🎙️ Snoring thresholds — multiplier: \(self.relativeThresholdMultiplier), bandRatio: \(self.minimumSnoringBandRatio), minAmp: \(self.absoluteMinimumThreshold), minDuration: \(minDuration)")
    }

    func startTracking() {
        guard !isTracking else { return }
        snoringEvents = []
        recentBursts = []
        burstStartTime = nil
        burstAmplitudes = []
        ambientBaseline = 0.0
        baselineSamples = []
        baselineCalibrated = false
        trackingStartTime = Date()

        configureAudioSession()

        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        audioBufferFormat = format
        audioBufferRing = []

        // Attach environmental classifier before starting the engine so the
        // first buffers flow through both the FFT analyzer and SoundAnalysis.
        classifier?.attach(to: engine)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, time in
            let analysis = Self.analyzeBuffer(buffer: buffer, sampleRate: format.sampleRate)
            // Copy buffer for snoring clip recording AND classifier feed.
            let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
            if let copy {
                copy.frameLength = buffer.frameLength
                if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                    for ch in 0..<Int(buffer.format.channelCount) {
                        dst[ch].update(from: src[ch], count: Int(buffer.frameLength))
                    }
                }
            }
            nonisolated(unsafe) let copyForActor = copy
            let sampleTime = time.sampleTime
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.processAnalysis(analysis)
                if let copyForActor {
                    self.appendBuffer(copyForActor)
                    self.classifier?.analyzeCopy(copyForActor, sampleTime: sampleTime)
                }
            }
        }

        do {
            try engine.start()
            isTracking = true
            startRemoteWorker()
            AppLogger.audio.info("🎙️ Audio tracking started")
        } catch {
            AppLogger.audio.error("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    /// Inject the environmental-noise classifier. Call before `startTracking`.
    func attachClassifier(_ classifier: SoundClassificationService) {
        self.classifier = classifier
        // Subscribe to classifier-driven events. These catch bark / meow /
        // speech bursts that are too brief or too high-frequency to pass the
        // amplitude + band-ratio gate. AudioService weak-retains the
        // classifier so the closure below is safe with weak self.
        classifier.onTargetEvent = { [weak self] label, confidence in
            // The classifier callback isn't actor-isolated; commitClassifier-
            // DrivenEvent touches @MainActor state (snoringEvents). Dispatch.
            Task { @MainActor in
                self?.commitClassifierDrivenEvent(label: label, confidence: confidence)
            }
        }
    }

    /// Commit an event that was already classified by the Watch's own
    /// audio pipeline. The Watch did the HTTPS+HMAC classify round-trip
    /// itself, so we trust its label and skip the local cloud reconciler.
    @MainActor
    func commitWatchClassifiedEvent(label: String, confidence: Double, at eventTime: Date) {
        guard isTracking else { return }
        // Dedupe against anything we committed in the last ~2 s.
        if let last = snoringEvents.last,
           eventTime.timeIntervalSince(last.startTime) < 2.0 {
            return
        }
        let start = eventTime.addingTimeInterval(-1.0)
        var event = SnoringEvent(startTime: start, duration: 2.0, averageAmplitude: 0.0)
        event.classification = Self.displayLabel(forAppleLabel: label)
        event.classificationConfidence = confidence
        event.remoteClassificationPending = false
        snoringEvents.append(event)
        AppLogger.audio.notice("⌚ Watch classifier event → \(event.classification) conf=\(String(format: "%.2f", confidence))")
        // The iPhone mic is running its own tap during tracking — capture a
        // clip from OUR ring buffer so the Reports tab can play back the
        // watch-detected sound instead of showing "No recording".
        recordSnoringClip(for: event)
    }

    /// Commit a SnoringEvent driven by the on-device classifier. Bypasses the
    /// amplitude + band-ratio + burst-grouping gates (tuned for snoring) so
    /// shorter non-snoring sounds (barks, meows, speech) still get captured
    /// and categorized. Still goes through the cloud reconciler downstream.
    @MainActor
    private func commitClassifierDrivenEvent(label: String, confidence: Double) {
        // Only run during active tracking, and only after the baseline has
        // calibrated so we don't spam events from the first second of setup.
        guard isTracking, baselineCalibrated else { return }

        // Deduplicate against the amplitude path — if an event was just
        // committed by finalizeBurst() in the last ~2s, don't double-count.
        let now = Date()
        if let last = snoringEvents.last,
           now.timeIntervalSince(last.startTime) < 2.0 {
            return
        }

        // Synthetic event timing: centered on "now", duration = sustain
        // window (~1.5 s — between sustainSeconds and cooldownSeconds).
        // Amplitude 0 because we bypassed the RMS measurement; UI uses
        // audioFileURL for playback so the 0 only affects the waveform viz.
        let eventStart = now.addingTimeInterval(-1.0)
        var event = SnoringEvent(startTime: eventStart, duration: 1.5, averageAmplitude: 0.0)
        event.classification = Self.displayLabel(forAppleLabel: label)
        event.classificationConfidence = confidence
        let remoteEnabled = remoteClassifier?.enabled ?? false
        event.remoteClassificationPending = remoteEnabled
        snoringEvents.append(event)
        let eventID = event.id
        AppLogger.audio.notice("🧩 Classifier-driven event — \(event.classification) conf=\(String(format: "%.2f", confidence))")

        recordSnoringClip(for: event)

        // Queue for cloud YAMNet reconciliation (same path as amplitude flow).
        if remoteEnabled,
           let idx = snoringEvents.firstIndex(where: { $0.id == eventID }),
           let clipURL = snoringEvents[idx].audioFileURL {
            let sr = audioBufferFormat?.sampleRate ?? 44_100
            let item = PendingRemoteItem(eventID: eventID, clipURL: clipURL, sampleRate: sr)
            pendingRemoteCount += 1
            remoteQueueContinuation?.yield(item)
        }
    }

    /// Translate Apple's SNClassifier label format (lowercase_underscore) into
    /// the display strings our SnoringEvent.classification conventions use.
    /// Keeps the category bucketing in the morning-review UI consistent.
    private static func displayLabel(forAppleLabel appleLabel: String) -> String {
        switch appleLabel {
        case "dog", "bark": return "Dog"
        case "cat", "meow": return "Cat"
        case "speech", "whispering", "laughter": return "Speech"
        case "snoring": return "snoring"          // lowercase matches legacy
        case "cough": return "Cough"
        case "sneeze": return "Sneeze"
        default: return appleLabel.capitalized
        }
    }

    /// Inject the remote YAMNet classifier. Call once at app startup. Only
    /// has effect when `client.enabled == true` and the user has opted in.
    func attachRemoteClassifier(_ client: SnoringClassifierClient) {
        self.remoteClassifier = client
    }

    /// Inject the MediaPlaybackService so we can suppress snoring events
    /// while the user's chosen sleep audio is actively playing. Call once at
    /// app startup — this is a weak reference so it won't leak.
    func attachMediaPlayback(_ service: MediaPlaybackService) {
        self.mediaPlayback = service
    }

    func stopTracking() {
        AppLogger.audio.info("🎙️ Audio tracking stopped")
        finalizeBurst()
        flushBurstsToEvent()
        classifier?.detach()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isTracking = false
        currentAmplitude = 0
        snoringBandEnergy = 0
        // Close the remote queue but leave the worker running — it'll drain
        // whatever is still queued, then exit once the stream finishes.
        remoteQueueContinuation?.finish()
        remoteQueueContinuation = nil
    }

    /// Wait (up to `timeout`) for every queued remote classification to
    /// either succeed or give up. Returns after the queue drains or the
    /// timeout fires, whichever comes first. Call from SleepTrackingService
    /// before persisting the session so the saved event labels reflect
    /// remote verdicts when possible.
    func awaitRemoteDrain(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while pendingRemoteCount > 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
        }
        if pendingRemoteCount > 0 {
            AppLogger.audio.info("⏱️ Remote classification drain timed out with \(self.pendingRemoteCount) events still pending")
        }
    }

    // MARK: - Remote classification worker

    private func startRemoteWorker() {
        guard remoteWorker == nil else { return }
        let (stream, continuation) = AsyncStream<PendingRemoteItem>.makeStream(bufferingPolicy: .unbounded)
        remoteQueueContinuation = continuation
        remoteWorker = Task { @MainActor [weak self] in
            for await item in stream {
                await self?.processRemoteItem(item)
            }
            self?.remoteWorker = nil
        }
    }

    private func processRemoteItem(_ initial: PendingRemoteItem) async {
        var item = initial
        guard let client = remoteClassifier else {
            decrementPending(for: item.eventID)
            return
        }
        let maxAttempts = 3
        while item.attempts < maxAttempts {
            item.attempts += 1
            do {
                let result = try await client.classify(clipURL: item.clipURL, sampleRate: item.sampleRate)
                applyRemoteResult(to: item.eventID, label: result.label, confidence: result.confidence)
                return
            } catch SnoringClassifierError.disabled, SnoringClassifierError.noEndpoint, SnoringClassifierError.noSecret {
                // Remote classifier isn't configured — leave the local label in place.
                applyRemoteFailure(to: item.eventID)
                return
            } catch {
                AppLogger.audio.error("Remote classify attempt \(item.attempts) failed: \(String(describing: error))")
                if item.attempts < maxAttempts {
                    let delay = UInt64(pow(2.0, Double(item.attempts)) * 500_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
        applyRemoteFailure(to: item.eventID)
    }

    private func applyRemoteResult(to eventID: UUID, label: String, confidence: Double) {
        guard let idx = snoringEvents.firstIndex(where: { $0.id == eventID }) else {
            decrementPending(for: eventID)
            return
        }
        if label == "Snoring" || label == "Snort" {
            snoringEvents[idx].classification = label
            snoringEvents[idx].classificationConfidence = confidence
        } else {
            // Remote says this wasn't a snore — demote the event so
            // reports and the score don't count it as one.
            snoringEvents[idx].classification = label
            snoringEvents[idx].classificationConfidence = confidence
        }
        snoringEvents[idx].remoteClassificationPending = false
        snoringEvents[idx].remoteClassificationFailed = false
        decrementPending(for: eventID)
        AppLogger.audio.info("✅ Remote classify → \(label) (\(String(format: "%.2f", confidence))) for event \(eventID.uuidString.prefix(8))")
    }

    private func applyRemoteFailure(to eventID: UUID) {
        if let idx = snoringEvents.firstIndex(where: { $0.id == eventID }) {
            snoringEvents[idx].remoteClassificationPending = false
            snoringEvents[idx].remoteClassificationFailed = true
        }
        decrementPending(for: eventID)
    }

    private func decrementPending(for _: UUID) {
        if pendingRemoteCount > 0 { pendingRemoteCount -= 1 }
    }

    // MARK: - Static Analysis (runs on background thread)

    nonisolated private static func analyzeBuffer(buffer: AVAudioPCMBuffer, sampleRate: Double) -> AudioAnalysis {
        guard let channelData = buffer.floatChannelData else {
            return AudioAnalysis(amplitude: 0, snoringBandRatio: 0, sampleRate: sampleRate)
        }
        let frameCount = Int(buffer.frameLength)
        let data = channelData[0]
        var rms: Float = 0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(frameCount))
        let amplitude = Double(rms)
        let snoringBandRatio = computeSnoringBandRatio(data: data, frameCount: frameCount, sampleRate: sampleRate)
        return AudioAnalysis(amplitude: amplitude, snoringBandRatio: snoringBandRatio, sampleRate: sampleRate)
    }

    nonisolated private static func computeSnoringBandRatio(data: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Double) -> Double {
        let log2n = vDSP_Length(floor(log2(Double(frameCount))))
        let fftSize = Int(1 << log2n)
        guard fftSize >= 256 else { return 0 }
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)
        var windowedData = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(data, 1, &window, 1, &windowedData, 1, vDSP_Length(fftSize))

        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowedData.withUnsafeMutableBufferPointer { bufferPtr in
                    bufferPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        let freqPerBin = sampleRate / Double(fftSize)
        // Widened from 100–500Hz to 80–900Hz. Real snores have fundamentals
        // anywhere from ~60Hz (deep throat snores) up to ~800Hz (nasal
        // vibration and harmonics). The narrower 100–500Hz band was missing
        // many legitimate snore sounds, especially from users testing with
        // their mouth rather than an actual sleep snore.
        let lowBin = max(1, Int(80.0 / freqPerBin))
        let highBin = min(fftSize / 2 - 1, Int(900.0 / freqPerBin))

        var totalEnergy: Float = 0
        vDSP_sve(magnitudes, 1, &totalEnergy, vDSP_Length(magnitudes.count))
        guard totalEnergy > 0 else { return 0 }

        var bandEnergy: Float = 0
        let bandLength = highBin - lowBin + 1
        guard bandLength > 0 else { return 0 }
        magnitudes.withUnsafeBufferPointer { ptr in
            let bandPtr = ptr.baseAddress! + lowBin
            vDSP_sve(bandPtr, 1, &bandEnergy, vDSP_Length(bandLength))
        }
        return Double(bandEnergy / totalEnergy)
    }

    // MARK: - Main Actor Processing

    private func processAnalysis(_ analysis: AudioAnalysis) {
        currentAmplitude = analysis.amplitude
        snoringBandEnergy = analysis.snoringBandRatio
        updateBaseline(amplitude: analysis.amplitude, snoringBandRatio: analysis.snoringBandRatio)
        let isSnoringSound = detectSnoring(amplitude: analysis.amplitude, snoringBandRatio: analysis.snoringBandRatio)
        if isSnoringSound {
            if burstStartTime == nil {
                burstStartTime = Date()
                burstAmplitudes = []
            }
            burstAmplitudes.append(analysis.amplitude)
        } else {
            finalizeBurst()
        }
    }

    private func updateBaseline(amplitude: Double, snoringBandRatio: Double) {
        guard let start = trackingStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        if !baselineCalibrated {
            if snoringBandRatio < 0.25 { baselineSamples.append(amplitude) }
            if elapsed >= baselineCalibrationSeconds {
                if baselineSamples.isEmpty {
                    ambientBaseline = 0.01
                } else {
                    let sorted = baselineSamples.sorted()
                    ambientBaseline = sorted[sorted.count / 2]
                }
                baselineCalibrated = true
            }
        } else {
            if amplitude < ambientBaseline * 1.5 && snoringBandRatio < 0.25 {
                ambientBaseline = ambientBaseline * 0.995 + amplitude * 0.005
            }
        }
    }

    private func detectSnoring(amplitude: Double, snoringBandRatio: Double) -> Bool {
        let adaptiveThreshold = max(ambientBaseline * relativeThresholdMultiplier, absoluteMinimumThreshold)
        let passesAmp = amplitude >= adaptiveThreshold
        let passesBand = snoringBandRatio >= minimumSnoringBandRatio
        // Every ~2 seconds log a snapshot of what the mic sees so users /
        // testers can diagnose why snores aren't detected. Uses a coarse
        // counter to keep log volume reasonable (~5 lines / 10s).
        diagnosticSampleCounter += 1
        if diagnosticSampleCounter >= diagnosticSampleLogEvery {
            diagnosticSampleCounter = 0
            AppLogger.audio.debug("🎙️ mic sample — amp=\(String(format: "%.4f", amplitude)) bandRatio=\(String(format: "%.2f", snoringBandRatio)) baseline=\(String(format: "%.4f", self.ambientBaseline)) ampNeeded=\(String(format: "%.4f", adaptiveThreshold)) bandNeeded=\(String(format: "%.2f", self.minimumSnoringBandRatio)) → amp\(passesAmp ? "✅" : "❌") band\(passesBand ? "✅" : "❌")")
        }
        return passesAmp && passesBand
    }

    // Log throttle counters for detectSnoring diagnostics.
    private var diagnosticSampleCounter: Int = 0
    private let diagnosticSampleLogEvery: Int = 22 // ~2s at 11 samples/sec

    private func finalizeBurst() {
        guard let start = burstStartTime else { return }
        let duration = Date().timeIntervalSince(start)
        if duration >= minimumBurstDuration && !burstAmplitudes.isEmpty {
            let avgAmplitude = burstAmplitudes.reduce(0, +) / Double(burstAmplitudes.count)
            recentBursts.append((time: start, duration: duration, amplitude: avgAmplitude))
            checkForSnoringEvent()
        }
        burstStartTime = nil
        burstAmplitudes = []
    }

    private func checkForSnoringEvent() {
        let cutoff = Date().addingTimeInterval(-burstGroupingWindow)
        recentBursts.removeAll { $0.time < cutoff }
        if recentBursts.count >= burstsRequiredForEvent { flushBurstsToEvent() }
    }

    private func flushBurstsToEvent() {
        guard !recentBursts.isEmpty else { return }
        let cutoff = Date().addingTimeInterval(-burstGroupingWindow)
        let windowBursts = recentBursts.filter { $0.time >= cutoff }
        guard windowBursts.count >= burstsRequiredForEvent || !isTracking else { return }
        guard !windowBursts.isEmpty else { return }
        let eventStart = windowBursts.first!.time
        let eventEnd = windowBursts.last!.time.addingTimeInterval(windowBursts.last!.duration)
        let totalDuration = eventEnd.timeIntervalSince(eventStart)
        let avgAmplitude = windowBursts.reduce(0.0) { $0 + $1.amplitude } / Double(windowBursts.count)

        // Media-playing gate. If the user is falling asleep to Apple Music,
        // a podcast, or a sleep sound, the mic picks up our own speaker.
        // Rather than suppressing ALL bursts (which drops real snores that
        // happen over quiet media), require the classifier to see a real
        // snoring signal before we accept the event.
        var classification = "snoring"
        var confidence = 1.0
        let mediaIsPlaying = mediaPlayback?.isPlaying ?? false

        if mediaIsPlaying, let classifier = classifier {
            let snoringConf = classifier.snoringConfidence(forWindow: eventStart, duration: totalDuration)
            if snoringConf < SoundClassificationService.affirmSnoringConfidenceWhileMediaPlaying {
                AppLogger.audio.info("🔇 Dropped snore candidate — media is playing and classifier saw no snore signal (\(String(format: "%.2f", snoringConf)))")
                recentBursts.removeAll()
                return
            }
            // Signal is strong enough — let the event through and annotate.
            classification = "snoring"
            confidence = snoringConf
            AppLogger.audio.info("✅ Snore through media — snoring confidence \(String(format: "%.2f", snoringConf))")
        } else if mediaIsPlaying, classifier == nil {
            // No classifier attached — fall back to the old behavior of
            // blanket-suppressing while media is playing.
            AppLogger.audio.info("🔇 Dropped snore candidate — media is playing and no classifier available")
            recentBursts.removeAll()
            return
        }

        // Environmental noise gate. If the classifier is attached and the
        // user has opted into filtering, veto candidate events that the
        // classifier flags as fan / AC / dog / speech / other domestic noise.
        if environmentalFilteringEnabled, let classifier = classifier {
            let verdict = classifier.verdict(forWindow: eventStart, duration: totalDuration)
            classification = verdict.label
            confidence = verdict.confidence
            if !verdict.keep {
                AppLogger.audio.info("🔇 Dropped snore candidate — classified as \(verdict.label) (\(String(format: "%.2f", verdict.confidence)))")
                recentBursts.removeAll()
                return
            }
        }

        var event = SnoringEvent(startTime: eventStart, duration: totalDuration, averageAmplitude: avgAmplitude)
        event.classification = classification
        event.classificationConfidence = confidence
        let remoteEnabled = remoteClassifier?.enabled ?? false
        event.remoteClassificationPending = remoteEnabled
        snoringEvents.append(event)
        let eventID = event.id
        AppLogger.audio.notice("😴 Snoring event — amp: \(avgAmplitude), dur: \(totalDuration), label: \(classification) (\(String(format: "%.2f", confidence)))")
        recentBursts.removeAll()

        // Record a 10-second clip of the snoring
        recordSnoringClip(for: event)

        // If the remote classifier is on, queue this event for YAMNet. The
        // worker task runs off-main and reconciles the event row in place.
        if remoteEnabled,
           let idx = snoringEvents.firstIndex(where: { $0.id == eventID }),
           let clipURL = snoringEvents[idx].audioFileURL {
            let sr = audioBufferFormat?.sampleRate ?? 44_100
            let item = PendingRemoteItem(eventID: eventID, clipURL: clipURL, sampleRate: sr)
            pendingRemoteCount += 1
            remoteQueueContinuation?.yield(item)
        }
    }

    // MARK: - Buffer Ring Management

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        audioBufferRing.append(buffer)
        // Keep only last ~15 seconds of buffers (44100 sample rate / 4096 buffer = ~10.7 buffers/sec)
        let maxBuffers = maxBufferSeconds * 11
        if audioBufferRing.count > maxBuffers {
            audioBufferRing.removeFirst(audioBufferRing.count - maxBuffers)
        }
    }

    // MARK: - Snoring Clip Recording

    private func recordSnoringClip(for event: SnoringEvent) {
        guard !audioBufferRing.isEmpty, let format = audioBufferFormat else {
            AppLogger.audio.info("🎙️ Skip clip — bufferCount=\(self.audioBufferRing.count), hasFormat=\(self.audioBufferFormat != nil)")
            return
        }

        let clipsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnoringClips", isDirectory: true)
        try? FileManager.default.createDirectory(at: clipsDir, withIntermediateDirectories: true)

        // Unique enough to avoid collisions when multiple snores occur in
        // the same wall-clock second.
        let fileName = "snore_\(Int(event.startTime.timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).wav"
        let fileURL = clipsDir.appendingPathComponent(fileName)

        // Only save the trailing audio around the event — not the whole ~15s
        // ring. Events are typically < 2s; take event.duration + a small
        // pre-roll so the user hears the exact bark / snore / meow, not a
        // minute of silence. (Previously we wrote the entire ring, producing
        // huge clips, and the isRecordingClip gate dropped concurrent events
        // entirely — leaving most SnoringEvents with no audio at all.)
        let targetSeconds = min(5.0, max(1.5, event.duration + 1.0))
        let sampleRate = format.sampleRate
        let maxFrames = AVAudioFrameCount(targetSeconds * sampleRate)
        var accumulatedFrames: AVAudioFrameCount = 0
        var buffersToWrite: [AVAudioPCMBuffer] = []
        for buffer in audioBufferRing.reversed() {
            buffersToWrite.insert(buffer, at: 0)
            accumulatedFrames += buffer.frameLength
            if accumulatedFrames >= maxFrames { break }
        }

        do {
            // Explicitly specify commonFormat + interleaved so the WAV file
            // matches the AVAudioPCMBuffer format exactly. Without this
            // AVAudioFile can silently create a mismatched header whose
            // AVAudioPlayer reports duration 0 and plays silence.
            let audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: format.settings,
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            var totalFrames: AVAudioFrameCount = 0
            for buffer in buffersToWrite {
                try audioFile.write(from: buffer)
                totalFrames += buffer.frameLength
            }

            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            AppLogger.audio.info("🎙️ Snoring clip saved: \(fileName) (\(buffersToWrite.count) buffers, \(totalFrames) frames, \(fileSize) bytes, target \(String(format: "%.1fs", targetSeconds)))")

            guard totalFrames > 0, fileSize > 64 else {
                AppLogger.audio.error("🎙️ Clip file looks empty — skipping URL assignment")
                try? FileManager.default.removeItem(at: fileURL)
                return
            }

            // Attach the clip to the event that triggered this call, not
            // blindly to `snoringEvents.last` — with concurrent events the
            // last index may have moved on and we'd orphan the wrong clip.
            if let idx = snoringEvents.firstIndex(where: { $0.id == event.id }) {
                snoringEvents[idx].audioFileURL = fileURL
            } else if let lastIdx = snoringEvents.indices.last {
                snoringEvents[lastIdx].audioFileURL = fileURL
            }
        } catch {
            AppLogger.audio.error("🎙️ Failed to save snoring clip: \(error.localizedDescription)")
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Mode `.measurement` disables iOS voice processing (AGC, noise
            // suppression, beam-forming) that would otherwise mangle the raw
            // audio before YAMNet / SoundAnalysis sees it. Yields noticeably
            // better classifier confidence for non-voice sounds (bark, meow,
            // snore).
            try session.setCategory(.playAndRecord,
                                    mode: .measurement,
                                    options: [.mixWithOthers, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            AppLogger.audio.error("Audio session configuration failed: \(error.localizedDescription)")
        }
    }
}
