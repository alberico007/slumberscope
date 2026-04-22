//
//  SoundClassificationService.swift
//  sleep
//
//  On-device environmental sound classification via Apple's SoundAnalysis
//  framework. Used to distinguish real snoring from mechanical fans, AC,
//  dogs barking, speech, and other domestic sounds that would otherwise
//  trip the amplitude+FFT snore detector.
//
//  All inference runs locally on-device via SNClassifierIdentifier.version1
//  which ships with iOS 15+ and covers 300+ sound labels.
//

@preconcurrency import AVFoundation
import Foundation
import os
@preconcurrency import SoundAnalysis

// MARK: - Classified Event

struct ClassifiedSoundEvent: Sendable {
    let timestamp: Date
    let label: String
    let confidence: Double
    /// Full ranked label list from the classifier (top 5). Used so the
    /// verdict function can see "snoring" confidence even when some other
    /// label like "breathing" or "silence" tops the ranking.
    let allLabels: [(label: String, confidence: Double)]
}

// MARK: - SoundClassificationService

@Observable
@MainActor
final class SoundClassificationService: NSObject {

    // MARK: - Observable state

    /// Most recent classification emitted by the analyzer.
    /// Nil until at least one buffer has been processed.
    var latest: ClassifiedSoundEvent?

    /// Rolling window of the last ~60 seconds of classifications, newest last.
    /// Used by AudioService to cross-check a candidate snoring event.
    private(set) var recentEvents: [ClassifiedSoundEvent] = []

    // MARK: - Labels that should veto a snoring event

    /// If the top label on a recent buffer matches one of these, a candidate
    /// snore event that overlaps in time is suppressed. Labels come from the
    /// version-1 built-in classifier label list (see Apple WWDC21 10036).
    static let environmentalNoiseLabels: Set<String> = [
        // Machine / household noise
        "mechanical_fan", "air_conditioner", "electric_fan", "hair_dryer",
        "vacuum_cleaner", "washing_machine", "dishwasher", "white_noise",
        "pink_noise", "traffic_noise_and_roadway_noise", "siren",
        "alarm_clock", "door_bell", "water_tap_and_faucet", "toilet_flush",
        "shower", "television", "radio", "music",
        // Animal
        "dog", "bark", "cat", "animal", "livestock",
        // Human voice / non-snore vocalizations (these are the ones that
        // catch "user barking into the mic" or "user shouting")
        "speech", "conversation", "whispering", "yell", "shout", "scream",
        "crying_sobbing", "baby_cry", "laughter", "giggle", "chuckle",
        "singing", "hum",
        // Airway / breath non-snore sounds
        "blow", "blowing_nose", "cough", "sneeze", "gasp", "pant",
        "wheeze", "hiccup", "throat_clearing", "sigh", "huff"
    ]

    /// Confidence at which we accept the classifier's "snoring" label.
    /// Must appear in the top-5 labels at or above this level for an
    /// FFT-qualified event to be counted as a snore. Lower than 0.5
    /// because Apple's general classifier is relatively weak on snoring
    /// specifically (community apps use 0.35–0.4).
    static let affirmSnoringConfidence: Double = 0.35

    /// Minimum snoring signal required to accept an event WHILE media
    /// (sleep sound / meditation / Apple Music / podcast) is playing through
    /// the speaker. Lower than affirmSnoringConfidence because the speaker
    /// is inherently competing for the mic.
    static let affirmSnoringConfidenceWhileMediaPlaying: Double = 0.2

    /// Confidence at which we veto an event if a non-snoring label dominates
    /// (e.g. "blow" at 0.6 means the user blew into the mic, not snored).
    static let environmentalVetoConfidence: Double = 0.4

    // MARK: - Classifier-driven event detection
    //
    // In addition to VETOING amplitude-based events, the classifier can now
    // directly COMMIT events of its own. Barks, meows, and voice bursts are
    // too brief or too high-frequency to pass the amplitude detector's
    // band-ratio / duration gate. When the classifier sees any of the labels
    // below at high confidence for a sustained window, it fires onTargetEvent
    // so AudioService can commit a SnoringEvent directly.

    /// Labels the classifier proactively emits as events (not just vetoes).
    /// Use Apple's SNClassifierIdentifier.version1 format (lowercase+underscore).
    static let targetEventLabels: Set<String> = [
        "dog", "bark",
        "cat", "meow",
        "speech", "whispering", "laughter",
        "snoring",
        "cough", "sneeze",
    ]

    /// Minimum confidence (peak across sustain window) to trigger an event.
    static let targetConfidenceThreshold: Double = 0.6

    /// Minimum time a target label must stay above threshold before firing.
    static let targetSustainSeconds: TimeInterval = 0.5

    /// Per-label cooldown so a 10-second bark doesn't produce 20 duplicate
    /// events. First event fires, then subsequent target hits on the same
    /// label are suppressed for this long.
    static let targetCooldownSeconds: TimeInterval = 3.0

    /// Fired when a target label has been above threshold for at least
    /// targetSustainSeconds and is outside its per-label cooldown.
    /// AudioService subscribes to commit a SnoringEvent directly.
    var onTargetEvent: ((_ label: String, _ confidence: Double) -> Void)?

    // Internal tracking: when each label first crossed threshold (reset when
    // it drops below), and when we last emitted for it.
    private var targetSustainStart: [String: Date] = [:]
    private var targetLastEmitted: [String: Date] = [:]

    // MARK: - Private

    private let analysisQueue = DispatchQueue(label: "sleep.sound-classification", qos: .userInitiated)
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private var request: SNClassifySoundRequest?
    private let resultsObserver = ResultsObserver()
    private let rollingWindowSeconds: TimeInterval = 60

    // MARK: - Lifecycle

    override init() {
        super.init()
        resultsObserver.onResult = { [weak self] event in
            self?.handleResult(event)
        }
    }

    /// Attach to the given AVAudioEngine input node. Safe to call while the
    /// engine is already running. No-ops if called twice.
    func attach(to engine: AVAudioEngine) {
        guard streamAnalyzer == nil else {
            AppLogger.audio.info("SoundClassification: already attached")
            return
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        let analyzer = SNAudioStreamAnalyzer(format: format)
        do {
            let req = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try analyzer.add(req, withObserver: resultsObserver)
            self.request = req
            self.streamAnalyzer = analyzer
            AppLogger.audio.info("SoundClassification: attached, sampleRate=\(format.sampleRate), channels=\(format.channelCount)")
        } catch {
            AppLogger.audio.error("SoundClassification: failed to attach — \(error.localizedDescription)")
        }
    }

    /// Feed a buffer from the AudioService tap. Must match the format used at
    /// attach time.
    func analyze(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime) {
        analyzeCopy(buffer, sampleTime: time.sampleTime)
    }

    /// Analyze a copied buffer with sample time. Buffer is treated as Sendable
    /// because the caller hands ownership to us — they don't read from it again.
    func analyzeCopy(_ buffer: AVAudioPCMBuffer, sampleTime: AVAudioFramePosition) {
        guard let analyzer = streamAnalyzer else { return }
        nonisolated(unsafe) let buf = buffer
        nonisolated(unsafe) let localAnalyzer = analyzer
        analysisQueue.async {
            localAnalyzer.analyze(buf, atAudioFramePosition: sampleTime)
        }
    }

    /// Detach on tracking stop so we don't leak the observer.
    func detach() {
        streamAnalyzer?.removeAllRequests()
        streamAnalyzer = nil
        request = nil
        recentEvents.removeAll()
        targetSustainStart.removeAll()
        targetLastEmitted.removeAll()
        AppLogger.audio.info("SoundClassification: detached")
    }

    // MARK: - Verdict API for AudioService

    /// Given a candidate snoring window (startTime .. startTime + duration),
    /// decide if it should be kept. Returns the best label and confidence so
    /// the caller can annotate the SnoringEvent.
    /// Best observed "snoring" confidence across classifier frames that
    /// overlap the given window. Returns 0 if the classifier hasn't produced
    /// any frames or never ranked snoring in its top 5.
    func snoringConfidence(forWindow start: Date, duration: TimeInterval) -> Double {
        let end = start.addingTimeInterval(duration)
        let overlapping = recentEvents.filter { $0.timestamp >= start.addingTimeInterval(-1) && $0.timestamp <= end.addingTimeInterval(1) }
        var best: Double = 0
        for event in overlapping {
            for entry in event.allLabels where entry.label == "snoring" {
                if entry.confidence > best { best = entry.confidence }
            }
        }
        return best
    }

    func verdict(forWindow start: Date, duration: TimeInterval) -> (keep: Bool, label: String, confidence: Double) {
        let end = start.addingTimeInterval(duration)
        let overlapping = recentEvents.filter { $0.timestamp >= start.addingTimeInterval(-1) && $0.timestamp <= end.addingTimeInterval(1) }

        // No classifier signal yet → reject. The FFT alone can't tell a snore
        // from a blow / bark / shout — all of which produce similar band
        // ratios. Without classifier confirmation we can't count the event.
        guard !overlapping.isEmpty else {
            AppLogger.audio.info("🔇 Dropped snore — no classifier signal available")
            return (keep: false, label: "unknown", confidence: 0.0)
        }

        // Collect the BEST confidence for each label across all overlapping
        // classifier windows. This lets us see that "snoring" appeared even
        // if some other label happened to top any individual frame.
        var bestPerLabel: [String: Double] = [:]
        for event in overlapping {
            for entry in event.allLabels {
                let existing = bestPerLabel[entry.label] ?? 0
                if entry.confidence > existing {
                    bestPerLabel[entry.label] = entry.confidence
                }
            }
        }

        let snoringConfidence = bestPerLabel["snoring"] ?? 0
        let topEnvironmental = Self.environmentalNoiseLabels
            .compactMap { label -> (String, Double)? in
                guard let conf = bestPerLabel[label] else { return nil }
                return (label, conf)
            }
            .max { $0.1 < $1.1 }

        // Veto: a non-snoring label dominates. Covers blowing, barking,
        // shouting, coughing, speech, fans, etc. Requires the environmental
        // label to clearly beat snoring (+0.1) so a close call doesn't drop
        // an actual snore that happens to have some "breathing" signal too.
        if let (envLabel, envConf) = topEnvironmental,
           envConf >= Self.environmentalVetoConfidence,
           envConf > snoringConfidence + 0.10 {
            AppLogger.audio.info("🔇 Dropped — classifier says \(envLabel)=\(String(format: "%.2f", envConf)) (snoring=\(String(format: "%.2f", snoringConfidence)))")
            return (keep: false, label: envLabel, confidence: envConf)
        }

        // Require affirmative snoring confidence to accept. Apple's built-in
        // classifier has a "snoring" label — if it doesn't put snoring in
        // the top-5 at or above 0.35, it's almost certainly not a real snore.
        if snoringConfidence >= Self.affirmSnoringConfidence {
            AppLogger.audio.info("✅ Kept snore — snoring=\(String(format: "%.2f", snoringConfidence))")
            return (keep: true, label: "snoring", confidence: snoringConfidence)
        }

        // Not enough snoring signal and no confident noise label either —
        // ambiguous sound. Drop to avoid false positives from user blowing/
        // barking/whispering into the mic during testing.
        let top = overlapping.max(by: { $0.confidence < $1.confidence })!
        AppLogger.audio.info("🔇 Dropped — ambiguous sound, top=\(top.label) \(String(format: "%.2f", top.confidence)), snoring=\(String(format: "%.2f", snoringConfidence))")
        return (keep: false, label: top.label, confidence: top.confidence)
    }

    // MARK: - Private

    private func handleResult(_ event: ClassifiedSoundEvent) {
        Task { @MainActor in
            self.latest = event
            self.recentEvents.append(event)
            let cutoff = Date().addingTimeInterval(-self.rollingWindowSeconds)
            self.recentEvents.removeAll { $0.timestamp < cutoff }
            self.checkTargetEvents(in: event)
        }
    }

    /// Look for target labels in this classification frame. Emits onTargetEvent
    /// when a label has been above threshold for at least targetSustainSeconds
    /// AND is outside its per-label cooldown. Runs on @MainActor.
    @MainActor
    private func checkTargetEvents(in event: ClassifiedSoundEvent) {
        let now = event.timestamp
        // Map label → confidence for just this frame, restricted to targets.
        var currentTargets: [String: Double] = [:]
        for entry in event.allLabels where Self.targetEventLabels.contains(entry.label) {
            currentTargets[entry.label] = entry.confidence
        }

        // Update sustain timers. A label is "sustaining" when its confidence
        // stays above threshold across consecutive frames.
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

        // Fire the first target that has sustained long enough and isn't in
        // cooldown. Only fire one per frame — a single event is clearer than
        // simultaneous duplicates for overlapping labels like "dog" + "bark".
        for label in Self.targetEventLabels {
            guard let sustainStart = targetSustainStart[label] else { continue }
            guard now.timeIntervalSince(sustainStart) >= Self.targetSustainSeconds else { continue }
            if let last = targetLastEmitted[label],
               now.timeIntervalSince(last) < Self.targetCooldownSeconds {
                continue
            }
            let conf = currentTargets[label] ?? 0
            targetLastEmitted[label] = now
            // Reset sustain so the next event needs another fresh sustain.
            targetSustainStart[label] = nil
            AppLogger.audio.info("🎯 Classifier target fired — \(label) conf=\(String(format: "%.2f", conf))")
            onTargetEvent?(label, conf)
            break
        }
    }
}

// MARK: - Results Observer

private final class ResultsObserver: NSObject, SNResultsObserving {
    var onResult: ((ClassifiedSoundEvent) -> Void)?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult,
              let top = classification.classifications.first else { return }
        // Capture the top 5 labels so the verdict function can see "snoring"
        // confidence even when another label like "breathing" tops the ranking.
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
        AppLogger.audio.error("SoundClassification request failed: \(error.localizedDescription)")
    }

    func requestDidComplete(_ request: SNRequest) {
        AppLogger.audio.info("SoundClassification request completed")
    }
}
