//
//  WatchAudioService.swift
//  sleepWatch
//
//  Mirrors sleep/Services/AudioService.swift + SnoringClassifierClient
//  on the watch. Records mic audio at 16 kHz mono int16 PCM, detects
//  amplitude bursts, uploads ~2 s clips to the classifier over HTTPS,
//  and relays the labeled result back to the iPhone via WCSession so
//  the event lands in the saved session.
//

@preconcurrency import AVFoundation
import Combine
import Foundation
import os
@preconcurrency import SoundAnalysis

@MainActor
final class WatchAudioService: ObservableObject {

    @Published var isRecording = false
    @Published var lastLabel: String?
    @Published var lastConfidence: Double = 0
    @Published var detectedEvents: Int = 0
    /// Chronological list of reportable classifier hits during this tracking
    /// session. Capped at 30 for memory — TrackingView groups into Snoring /
    /// Dogs / Cats / Voice / Other buckets, same as the iPhone.
    @Published var recentEvents: [WatchClassifiedEvent] = []
    private static let maxRecentEvents = 30

    private let engine = AVAudioEngine()
    private let classifier: WatchClassifierClient

    // On-device sound classifier (mirrors iPhone SoundClassificationService).
    // Fires events directly from the SNClassifySoundRequest at 0.6 confidence
    // after 0.5 s sustain, so a brief dog bark is caught without waiting for
    // the 2 s cloud YAMNet round-trip.
    private let analysisQueue = DispatchQueue(label: "sleepWatch.sound-classification", qos: .userInitiated)
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var classifyRequest: SNClassifySoundRequest?
    private let resultsObserver = SNResultsObserverBox()
    private var targetSustainStart: [String: Date] = [:]
    private var targetLastEmitted: [String: Date] = [:]

    /// Target labels that fire events directly from the on-device classifier.
    /// Matches iPhone SoundClassificationService.targetEventLabels.
    private static let targetEventLabels: Set<String> = [
        "dog", "bark",
        "cat", "meow",
        "speech", "whispering", "laughter",
        "snoring",
        "cough", "sneeze",
    ]
    private static let targetConfidenceThreshold: Double = 0.6
    private static let targetSustainSeconds: TimeInterval = 0.5
    private static let targetCooldownSeconds: TimeInterval = 3.0

    // Accumulator for int16 LE PCM at 16 kHz mono. Flushed every 2 seconds.
    private final class PCMAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        func append(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            buffer.append(data)
        }
        func drain() -> Data {
            lock.lock(); defer { lock.unlock() }
            let out = buffer
            buffer = Data()
            return out
        }
        func current() -> Data {
            lock.lock(); defer { lock.unlock() }
            return buffer
        }
    }

    private var accumulator: PCMAccumulator?
    private var flushTimer: Timer?

    /// Callback fired when the classifier labels a clip above threshold.
    /// Used by WatchSessionManager to forward the event to iPhone.
    var onClassifiedEvent: ((_ label: String, _ confidence: Double) -> Void)?

    /// Labels we consider "real events" and forward to iPhone. Matches the
    /// iPhone-side targetEventLabels set in SoundClassificationService.
    private static let reportableLabels: Set<String> = [
        "snoring", "snort", "breathing",
        "dog", "bark", "bow-wow", "yip", "howl", "growling",
        "cat", "meow", "cat communication",
        "speech", "conversation", "narration, monologue",
        "cough", "sneeze", "groan", "whistle"
    ]

    // 2 s flush window at 16 kHz mono = 32 000 samples = 64 000 bytes
    private let sampleRate: Double = 16_000
    private let clipDuration: TimeInterval = 2.0
    private let minAmplitudeToClassify: Double = 0.012

    init(classifier: WatchClassifierClient = WatchClassifierClient()) {
        self.classifier = classifier
    }

    // MARK: - Start / Stop

    func startRecording() {
        guard !isRecording else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            WatchLogger.session.error("Audio session setup failed: \(error.localizedDescription)")
            return
        }

        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        WatchLogger.session.info("🎙️ Watch audio: HW format \(hwFormat.sampleRate) Hz, \(hwFormat.channelCount) ch")

        // Target 16 kHz mono int16 — matches what the classifier expects.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            WatchLogger.session.error("Failed to build AVAudioConverter")
            return
        }

        let acc = PCMAccumulator()
        self.accumulator = acc

        // Attach on-device SNClassifySoundRequest. Uses hwFormat (same tap
        // format) so no conversion is needed before analyze().
        resultsObserver.onResult = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleOnDeviceResult(event)
            }
        }
        let analyzer = SNAudioStreamAnalyzer(format: hwFormat)
        do {
            let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer.add(req, withObserver: resultsObserver)
            self.streamAnalyzer = analyzer
            self.classifyRequest = req
            WatchLogger.session.info("🧠 On-device classifier attached at \(hwFormat.sampleRate) Hz")
        } catch {
            WatchLogger.session.error("On-device classifier attach failed: \(error.localizedDescription)")
        }

        nonisolated(unsafe) let analyzerRef = streamAnalyzer
        let analysisQ = analysisQueue

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { @Sendable buffer, time in
            // 1. Feed the on-device SNAudioStreamAnalyzer off-main so dog /
            //    bark / snore can fire at ~0.5 s latency.
            if let a = analyzerRef {
                nonisolated(unsafe) let buf = buffer
                nonisolated(unsafe) let localAnalyzer = a
                let sampleTime = time.sampleTime
                analysisQ.async {
                    localAnalyzer.analyze(buf, atAudioFramePosition: sampleTime)
                }
            }

            // 2. Convert hardware-format buffer to 16 kHz mono int16 for the
            //    cloud YAMNet accumulator (backup path).
            let targetCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * 16_000 / hwFormat.sampleRate + 128
            )
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else { return }

            final class FeedState: @unchecked Sendable { var fed = false }
            let state = FeedState()
            nonisolated(unsafe) let input = buffer
            var err: NSError?
            converter.convert(to: outBuf, error: &err) { _, status in
                if state.fed { status.pointee = .endOfStream; return nil }
                state.fed = true
                status.pointee = .haveData
                return input
            }
            guard err == nil, let src = outBuf.int16ChannelData?[0] else { return }
            let frames = Int(outBuf.frameLength)
            let byteCount = frames * MemoryLayout<Int16>.size
            let data = src.withMemoryRebound(to: UInt8.self, capacity: byteCount) {
                Data(bytes: $0, count: byteCount)
            }
            acc.append(data)
        }

        do {
            try engine.start()
            isRecording = true
            WatchLogger.session.info("🎙️ Watch audio recording started")
        } catch {
            WatchLogger.session.error("engine.start failed: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
            return
        }

        // Every 2 seconds, drain the accumulator and classify.
        flushTimer = Timer.scheduledTimer(withTimeInterval: clipDuration, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.flushAndClassify()
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        flushTimer?.invalidate(); flushTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        accumulator = nil
        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
        classifyRequest = nil
        targetSustainStart.removeAll()
        targetLastEmitted.removeAll()
        recentEvents.removeAll()
        detectedEvents = 0
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        WatchLogger.session.info("🎙️ Watch audio recording stopped")
    }

    // MARK: - On-device classifier handling

    /// Mirrors iPhone SoundClassificationService.checkTargetEvents — fires
    /// onClassifiedEvent when a target label has sustained above threshold
    /// for targetSustainSeconds and is outside its per-label cooldown.
    private func handleOnDeviceResult(_ event: ClassifiedSoundEvent) {
        lastLabel = event.label
        lastConfidence = event.confidence

        let now = event.timestamp
        var currentTargets: [String: Double] = [:]
        for entry in event.allLabels where Self.targetEventLabels.contains(entry.label) {
            currentTargets[entry.label] = entry.confidence
        }

        for label in Self.targetEventLabels {
            let conf = currentTargets[label] ?? 0
            if conf >= Self.targetConfidenceThreshold {
                if targetSustainStart[label] == nil {
                    targetSustainStart[label] = now
                }
            } else {
                targetSustainStart[label] = nil
            }
        }

        for label in Self.targetEventLabels {
            guard let sustainStart = targetSustainStart[label] else { continue }
            guard now.timeIntervalSince(sustainStart) >= Self.targetSustainSeconds else { continue }
            if let last = targetLastEmitted[label],
               now.timeIntervalSince(last) < Self.targetCooldownSeconds {
                continue
            }
            let conf = currentTargets[label] ?? 0
            targetLastEmitted[label] = now
            targetSustainStart[label] = nil
            detectedEvents += 1
            recordEvent(label: label, confidence: conf, timestamp: now)
            WatchLogger.session.info("🎯 Watch on-device → \(label) conf=\(String(format: "%.2f", conf)) — relaying to iPhone")
            onClassifiedEvent?(label, conf)
            break
        }
    }

    private func recordEvent(label: String, confidence: Double, timestamp: Date) {
        let entry = WatchClassifiedEvent(label: label, confidence: confidence, timestamp: timestamp)
        recentEvents.append(entry)
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - Self.maxRecentEvents)
        }
    }

    // MARK: - Classify

    private func flushAndClassify() {
        guard let acc = accumulator else { return }
        let pcm = acc.drain()
        guard !pcm.isEmpty else { return }

        let amplitude = Self.peakAmplitude(pcm16LE: pcm)
        if amplitude < minAmplitudeToClassify {
            // Too quiet — don't waste a round-trip.
            return
        }

        let wav = WatchClassifierClient.makeWAVData(
            pcm16Samples: pcm,
            sampleRate: sampleRate,
            channels: 1
        )
        WatchLogger.session.info("🎙️ Watch → classifier: \(pcm.count) bytes, peak \(String(format: "%.3f", amplitude))")

        Task { [weak self, classifier] in
            do {
                let result = try await classifier.classify(wavData: wav, sampleRate: 16_000)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.lastLabel = result.label
                    self.lastConfidence = result.confidence
                    let lower = result.label.lowercased()
                    if Self.reportableLabels.contains(lower) && result.confidence >= 0.3 {
                        self.detectedEvents += 1
                        self.recordEvent(label: result.label, confidence: result.confidence, timestamp: Date())
                        WatchLogger.session.info("🧠 Watch YAMNet → \(result.label) (\(String(format: "%.2f", result.confidence))) — relaying to iPhone")
                        self.onClassifiedEvent?(result.label, result.confidence)
                    } else {
                        WatchLogger.session.debug("🧠 Watch YAMNet → \(result.label) (\(String(format: "%.2f", result.confidence))) — ignored")
                    }
                }
            } catch {
                WatchLogger.session.error("Watch classify failed: \(String(describing: error))")
            }
        }
    }

    /// Peak amplitude of a little-endian int16 PCM payload, normalized to [0, 1].
    private static func peakAmplitude(pcm16LE: Data) -> Double {
        var peak: Int16 = 0
        pcm16LE.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: Int16.self).baseAddress else { return }
            let count = pcm16LE.count / 2
            for i in 0..<count {
                let abs = base[i] == Int16.min ? Int16.max : Swift.abs(base[i])
                if abs > peak { peak = abs }
            }
        }
        return Double(peak) / 32767.0
    }
}

// MARK: - On-device classifier plumbing

struct ClassifiedSoundEvent: Sendable {
    let timestamp: Date
    let label: String
    let confidence: Double
    let allLabels: [(label: String, confidence: Double)]
}

final class SNResultsObserverBox: NSObject, SNResultsObserving, @unchecked Sendable {
    var onResult: ((ClassifiedSoundEvent) -> Void)?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult,
              let top = classification.classifications.first else { return }
        let ranked: [(label: String, confidence: Double)] = classification.classifications
            .prefix(5)
            .map { ($0.identifier, $0.confidence) }
        let event = ClassifiedSoundEvent(
            timestamp: Date(),
            label: top.identifier,
            confidence: top.confidence,
            allLabels: ranked
        )
        onResult?(event)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        WatchLogger.session.error("On-device classifier failed: \(error.localizedDescription)")
    }

    func requestDidComplete(_ request: SNRequest) {
        WatchLogger.session.info("On-device classifier request completed")
    }
}
