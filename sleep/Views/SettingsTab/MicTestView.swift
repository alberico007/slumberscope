//
//  MicTestView.swift
//  sleep
//
//  Diagnostic tool: record a short clip, ship it to the YAMNet classifier,
//  show the label as proof the pipeline is working, and keep every test on
//  disk so we have a history to compare against.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

/// Thread-safe accumulator for raw int16 PCM bytes captured by the audio
/// engine's input tap. Reference type so the tap closure and the view can
/// both hold a pointer to the same buffer without @State/MainActor hops.
private final class PCMAccumulator: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ bytes: UnsafeBufferPointer<UInt8>) {
        lock.lock()
        buffer.append(bytes.baseAddress!, count: bytes.count)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        let snap = buffer
        lock.unlock()
        return snap
    }

    func reset() {
        lock.lock()
        buffer = Data()
        lock.unlock()
    }
}

/// Sendable bridge for the meter level. Lives outside the View so the
/// AVAudioEngine tap closure can update it without capturing @MainActor
/// state — capturing @State on the View from a @Sendable closure triggers
/// Swift 6's _swift_task_checkIsolatedSwift assertion when the tap fires
/// on AVFoundation's RealtimeMessenger queue.
private final class MeterLevelBox: ObservableObject, @unchecked Sendable {
    @Published var level: Float = 0
    func update(_ v: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.level = v
        }
    }
}

struct MicTestView: View {
    @Environment(SnoringClassifierClient.self) private var classifier

    @State private var engine: AVAudioEngine?
    @State private var accumulator: PCMAccumulator?
    @State private var captureSampleRate: Double = 48_000
    @State private var recordingStart: Date?
    @State private var session = AVAudioSession.sharedInstance()
    @State private var isRecording = false
    @State private var elapsed: TimeInterval = 0
    @StateObject private var meter = MeterLevelBox()
    @State private var elapsedTimer: Timer?

    @State private var busy = false
    @State private var lastResult: TestResult?
    @State private var errorText: String?

    @State private var history: [TestResult] = []

    @State private var player: AVAudioPlayer?
    @State private var playingID: UUID?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text(isRecording
                         ? String(format: "Recording… %.1fs", elapsed)
                         : (busy ? "Analyzing…" : "Tap to record"))
                        .font(.headline)

                    // Simple level meter
                    ProgressView(value: Double(max(0, min(1, normalizedMeter(meter.level)))))
                        .progressViewStyle(.linear)
                        .tint(isRecording ? .red : .secondary)

                    Button {
                        isRecording ? stopAndClassify() : startRecording()
                    } label: {
                        Label(isRecording ? "Stop" : "Record",
                              systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRecording ? .red : .blue)
                    .disabled(busy)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Records a clip, signs and ships it to the classifier, saves it on the device with the returned label. Use this to verify the round-trip is working.")
            }

            if let result = lastResult {
                Section {
                    resultRow(result)
                } header: {
                    Text("App label")
                } footer: {
                    Text("Server buckets the raw YAMNet label into {Snoring, Snort, Breathing, Speech, Cough} — anything else becomes \"Other\". Check the raw YAMNet top-5 below to see what the classifier actually heard.")
                }

                if !result.top5.isEmpty {
                    Section("Raw YAMNet top 5") {
                        ForEach(result.top5, id: \.label) { entry in
                            HStack {
                                Text(entry.label).font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", entry.confidence))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let err = errorText {
                Section {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
            }

            if !history.isEmpty {
                Section("History (\(history.count))") {
                    ForEach(history) { result in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.label).font(.subheadline)
                                Text(result.timestamp, format: .dateTime.hour().minute().second().month().day())
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(String(format: "conf %.2f · %d KB", result.confidence, result.bytes / 1024))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                togglePlay(result)
                            } label: {
                                Image(systemName: playingID == result.id ? "stop.fill" : "play.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                delete(result)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Mic Test")
        .onAppear(perform: onAppearSetup)
        .onDisappear { teardown() }
    }

    @ViewBuilder private func resultRow(_ result: TestResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.label).font(.title3).bold()
                Text(String(format: "confidence %.2f", result.confidence))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                togglePlay(result)
            } label: {
                Image(systemName: playingID == result.id ? "stop.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
        }
    }

    // MARK: - Lifecycle

    private func onAppearSetup() {
        classifier.enabled = true
        history = Self.loadHistory()
    }

    private func activateRecordSession() {
        // Cycle the session so that `.measurement` mode actually lands — if
        // AudioService has already activated `.playAndRecord` with a different
        // mode, iOS will silently keep the old mode unless we deactivate
        // first. Also drop `.allowBluetoothHFP` so a connected AirPods set
        // can't route us through the HFP narrowband audio path (16 kHz, heavy
        // processing), which would mangle YAMNet inputs.
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            errorText = "Record session setup failed: \(error.localizedDescription)"
        }
    }

    private func activatePlaybackSession() {
        do {
            try session.setActive(false, options: [.notifyOthersOnDeactivation])
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            errorText = "Playback session setup failed: \(error.localizedDescription)"
        }
    }

    private func teardown() {
        elapsedTimer?.invalidate()
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        accumulator = nil
        player?.stop()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Recording
    //
    // Uses AVAudioEngine with voice processing explicitly disabled on the
    // input node to bypass iPhone's hardware AGC / noise-suppression /
    // beam-forming DSP. Captured float32 samples are converted inline to
    // little-endian int16 and appended to a thread-safe PCMAccumulator —
    // NOT written to AVAudioFile, whose deinit-driven WAV-header flush was
    // racing with our classify read.

    private func startRecording() {
        errorText = nil
        lastResult = nil
        activateRecordSession()

        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Disable iOS voice processing at the hardware level. Only available
        // on iOS 13+; if it throws we still try to record (better than
        // nothing) and surface the error.
        do {
            try input.setVoiceProcessingEnabled(false)
        } catch {
            errorText = "Couldn't disable voice processing: \(error.localizedDescription)"
        }

        let hwFormat = input.outputFormat(forBus: 0)
        let accumulator = PCMAccumulator()

        // Build the tap handler via a nonisolated helper so the @Sendable
        // closure does NOT inherit @MainActor isolation from this View.
        // A closure formed inside a @MainActor method captures the main
        // actor's executor; when AVFoundation invokes it on its realtime
        // queue, Swift 6's runtime executor check crashes the process.
        input.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: hwFormat,
            block: Self.makeTapHandler(accumulator: accumulator, meter: meter)
        )

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            errorText = "Engine start failed: \(error.localizedDescription)"
            return
        }

        self.engine = engine
        self.accumulator = accumulator
        self.captureSampleRate = hwFormat.sampleRate
        let started = Date()
        self.recordingStart = started
        isRecording = true
        elapsed = 0

        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                elapsed = Date().timeIntervalSince(started)
                if elapsed > 30 { stopAndClassify() }
            }
        }
    }

    private func stopAndClassify() {
        guard let engine, let accumulator else { return }
        elapsedTimer?.invalidate(); elapsedTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        let sampleRate = captureSampleRate
        let pcm = accumulator.snapshot()
        self.accumulator = nil
        recordingStart = nil
        isRecording = false

        guard !pcm.isEmpty else {
            errorText = "Recording was empty — check mic permission or try holding longer."
            return
        }

        let wav = SnoringClassifierClient.makeWAVData(
            pcm16Samples: pcm,
            sampleRate: sampleRate,
            channels: 1
        )

        busy = true
        Task {
            do {
                let result = try await classifier.classify(wavData: wav, sampleRate: sampleRate)
                let record = TestResult(
                    id: UUID(),
                    timestamp: Date(),
                    label: result.label,
                    confidence: result.confidence,
                    top5: result.top5.map { .init(label: $0.label, confidence: $0.confidence) },
                    bytes: wav.count,
                    filename: "" // populated by persist
                )
                let saved = try Self.persist(record: record, wavData: wav)
                await MainActor.run {
                    lastResult = saved
                    history = Self.loadHistory()
                    busy = false
                }
            } catch {
                await MainActor.run {
                    errorText = "Classify failed: \(describe(error))"
                    busy = false
                }
            }
        }
    }

    /// Factory for the audio tap handler. `nonisolated` so the returned
    /// closure inherits no actor — safe to invoke on AVFoundation's
    /// RealtimeMessenger queue under Swift 6 strict concurrency.
    nonisolated private static func makeTapHandler(
        accumulator: PCMAccumulator,
        meter: MeterLevelBox
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            guard let ch = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            var int16s = [Int16]()
            int16s.reserveCapacity(frames)
            for i in 0..<frames {
                let f = max(-1.0, min(1.0, ch[0][i]))
                int16s.append(Int16(f * 32767))
            }
            int16s.withUnsafeBufferPointer { ptr in
                ptr.baseAddress?.withMemoryRebound(to: UInt8.self, capacity: ptr.count * 2) { bytePtr in
                    accumulator.append(UnsafeBufferPointer(start: bytePtr, count: ptr.count * 2))
                }
            }
            meter.update(Self.rmsDBFS(buffer))
        }
    }

    /// RMS of an audio buffer, expressed in dBFS (-160 … 0) to match the
    /// previous AVAudioRecorder meter range that `normalizedMeter` expects.
    nonisolated private static func rmsDBFS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -160 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return -160 }
        let samples = channelData[0]
        var sumSquares: Float = 0
        for i in 0..<frames {
            let s = samples[i]
            sumSquares += s * s
        }
        let rms = sqrtf(sumSquares / Float(frames))
        if rms <= 0.0000001 { return -160 }
        return 20 * log10f(rms)
    }

    // MARK: - Playback

    private func togglePlay(_ result: TestResult) {
        if playingID == result.id {
            player?.stop(); player = nil; playingID = nil
            return
        }
        activatePlaybackSession()
        let url = Self.micTestsDir().appendingPathComponent(result.filename)
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
            playingID = result.id
            // Clear playingID when done — AVAudioPlayerDelegate would be cleaner
            // but this Timer is fine for a diagnostic tool.
            Timer.scheduledTimer(withTimeInterval: p.duration + 0.05, repeats: false) { _ in
                Task { @MainActor in
                    if playingID == result.id { playingID = nil; player = nil }
                }
            }
        } catch {
            errorText = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func delete(_ result: TestResult) {
        if playingID == result.id { player?.stop(); playingID = nil }
        try? FileManager.default.removeItem(at: Self.micTestsDir().appendingPathComponent(result.filename))
        try? FileManager.default.removeItem(at: Self.micTestsDir().appendingPathComponent("\(result.id.uuidString).json"))
        history = Self.loadHistory()
        if lastResult?.id == result.id { lastResult = nil }
    }

    // MARK: - Disk

    private static func micTestsDir() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mic_tests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func persist(record: TestResult, wavData: Data) throws -> TestResult {
        let dir = micTestsDir()
        let safe = record.label.filter { $0.isLetter || $0.isNumber }
        let wavName = "test_\(Int(record.timestamp.timeIntervalSince1970))_\(safe).wav"
        let wavURL = dir.appendingPathComponent(wavName)
        try? FileManager.default.removeItem(at: wavURL)
        try wavData.write(to: wavURL, options: .atomic)

        var stored = record
        stored.filename = wavName
        let metaURL = dir.appendingPathComponent("\(record.id.uuidString).json")
        let data = try JSONEncoder().encode(stored)
        try data.write(to: metaURL, options: .atomic)
        return stored
    }

    private static func loadHistory() -> [TestResult] {
        let dir = micTestsDir()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoded: [TestResult] = files.compactMap { url in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(TestResult.self, from: data)
        }
        return decoded.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Helpers

    private func normalizedMeter(_ db: Float) -> Float {
        // AVAudioRecorder returns power in dBFS, -160 (silence) to 0 (full scale).
        let clamped = max(-60, min(0, db))
        return (clamped + 60) / 60
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case SnoringClassifierError.disabled: return "client disabled"
        case SnoringClassifierError.noEndpoint: return "no endpoint configured"
        case SnoringClassifierError.noSecret: return "HMAC secret missing"
        case SnoringClassifierError.auth: return "HMAC rejected (401)"
        case SnoringClassifierError.server(let code): return "server \(code)"
        case SnoringClassifierError.invalidResponse: return "invalid response"
        case SnoringClassifierError.resample: return "audio resample failed"
        case SnoringClassifierError.network(let inner): return "network: \(inner.localizedDescription)"
        default: return error.localizedDescription
        }
    }
}

// MARK: - Model

private struct TestResult: Identifiable, Codable {
    struct Entry: Codable { let label: String; let confidence: Double }
    let id: UUID
    let timestamp: Date
    let label: String
    let confidence: Double
    let top5: [Entry]
    let bytes: Int
    var filename: String
}
