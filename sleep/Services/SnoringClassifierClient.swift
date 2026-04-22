//
//  SnoringClassifierClient.swift
//  sleep
//

@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import os

enum SnoringClassifierError: Error {
    case disabled
    case noEndpoint
    case noSecret
    case resample
    case network(Error)
    case auth
    case server(Int)
    case invalidResponse
}

struct RemoteClassification: Sendable {
    let label: String
    let confidence: Double
    let top5: [(label: String, confidence: Double)]
}

@Observable
@MainActor
final class SnoringClassifierClient {
    /// Endpoint like `https://smarterpillow-snoring.eastus2.cloudapp.azure.com/classify`.
    /// Read from Info.plist key `SnoringClassifierEndpoint` at init.
    var endpoint: URL?

    /// If false, every classify call returns `.disabled` without touching the network.
    var enabled: Bool = false

    private let timeout: TimeInterval = 2.0
    private let session: URLSession

    private let keychainAccount = "smarterpillow.snoring.hmac"
    private let keychainService = "smarterpillow"

    // Dev-build defaults. Info.plist values take precedence when present.
    // TODO: provision these per-user in production instead of shipping a static
    // HMAC in the app binary.
    private static let defaultEndpoint = "https://smarterpillow-snoring.eastus2.cloudapp.azure.com/classify"
    private static let defaultHMACSecretHex = "98dec3185a3cce84aa5ebe2e9d830d80007aaa43577025e0e458254acbbfaef8"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 5.0
        self.session = URLSession(configuration: config)

        let rawEndpoint = (Bundle.main.object(forInfoDictionaryKey: "SnoringClassifierEndpoint") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultEndpoint
        self.endpoint = URL(string: rawEndpoint)

        // Seed the HMAC secret into the Keychain on first launch.
        // The backend reads /etc/snoring/secret as raw bytes and HMACs with
        // those bytes as the key, so we must store the hex string's UTF-8
        // representation, not the hex-decoded bytes.
        if Self.keychainRead(service: keychainService, account: keychainAccount) == nil {
            let hex = (Bundle.main.object(forInfoDictionaryKey: "SnoringClassifierHMACSecret") as? String)
                .flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultHMACSecretHex
            if let data = hex.data(using: .utf8) {
                _ = Self.keychainWrite(secret: data, service: keychainService, account: keychainAccount)
            }
        }
    }

    func classify(clipURL: URL, sampleRate: Double) async throws -> RemoteClassification {
        let payload = try Self.downsampleToPCM16(fileURL: clipURL)
        return try await sendClassify(wav: payload, sampleRate: sampleRate)
    }

    /// Send a finished WAV (already at whatever sample rate) directly to the
    /// classifier. Unlike `classify(clipURL:sampleRate:)`, this path does no
    /// file I/O on the client — the server handles any needed resampling.
    /// Used by Mic Test to avoid the AVAudioFile header-flush race on iPhone.
    func classify(wavData: Data, sampleRate: Double) async throws -> RemoteClassification {
        return try await sendClassify(wav: wavData, sampleRate: sampleRate)
    }

    /// Shared HTTP + HMAC signing + decoding pipeline.
    private func sendClassify(wav payload: Data, sampleRate: Double) async throws -> RemoteClassification {
        guard enabled else { throw SnoringClassifierError.disabled }
        guard let endpoint else { throw SnoringClassifierError.noEndpoint }
        guard let secret = Self.keychainRead(service: keychainService, account: keychainAccount) else {
            throw SnoringClassifierError.noSecret
        }

        let boundary = "sp-\(UUID().uuidString)"
        let body = Self.buildMultipartBody(wav: payload, sampleRate: sampleRate, boundary: boundary)

        // Sign the WAV bytes (matches server which reads `file` contents).
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let signingInput = "\(timestamp)\n\(digest)"
        let key = SymmetricKey(data: secret)
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
            .map { String(format: "%02x", $0) }.joined()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SnoringClassifierError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw SnoringClassifierError.invalidResponse }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw SnoringClassifierError.auth
        default:
            throw SnoringClassifierError.server(http.statusCode)
        }

        let result = try Self.decode(data)
        let top5Str = result.top5
            .prefix(5)
            .map { String(format: "%@=%.2f", $0.label, $0.confidence) }
            .joined(separator: ", ")
        AppLogger.audio.info("🧠 YAMNet → \(result.label) (\(String(format: "%.2f", result.confidence))); top5: \(top5Str)")
        return result
    }

    // MARK: - Downsample

    /// Resample the WAV on disk to 16 kHz mono PCM int16 in-memory and return a
    /// WAV-wrapped byte blob. YAMNet's input is 16 kHz; shipping the native
    /// 44.1 kHz float32 clip wastes ~4x bandwidth.
    private static func downsampleToPCM16(fileURL: URL) throws -> Data {
        let inputFile = try AVAudioFile(forReading: fileURL)
        let inputFormat = inputFile.processingFormat

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else { throw SnoringClassifierError.resample }

        let frameCount = AVAudioFrameCount(inputFile.length)
        // A frameCount of 0 means the writer hadn't flushed the WAV header's
        // data-chunk length by the time we opened the file for reading
        // (common race when recording stops and classify starts immediately).
        // Bail out cleanly instead of tripping AVAudioFile's
        // frameCapacity != 0 assertion.
        guard frameCount > 0 else { throw SnoringClassifierError.resample }
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            throw SnoringClassifierError.resample
        }
        try inputFile.read(into: inputBuffer)

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SnoringClassifierError.resample
        }

        let estimatedOutFrames = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate + 1024
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: estimatedOutFrames) else {
            throw SnoringClassifierError.resample
        }

        final class FeedState: @unchecked Sendable { var fed = false }
        let state = FeedState()
        nonisolated(unsafe) let input = inputBuffer
        var convertError: NSError?
        converter.convert(to: outputBuffer, error: &convertError) { _, outStatus in
            if state.fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            state.fed = true
            outStatus.pointee = .haveData
            return input
        }
        if let convertError { throw SnoringClassifierError.network(convertError) }

        return try encodeWAV(from: outputBuffer)
    }

    /// Synthesize a RIFF/WAVE file from raw little-endian int16 PCM bytes.
    /// Callers that already have samples in memory (e.g. Mic Test) use this
    /// to avoid AVAudioFile's deferred header-flush behavior.
    static func makeWAVData(pcm16Samples samples: Data, sampleRate: Double, channels: Int) -> Data {
        let sr = UInt32(sampleRate)
        let bitsPerSample: UInt16 = 16
        let byteRate = sr * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels) * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count)

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian, Array.init))
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: sr.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        data.append(samples)
        return data
    }

    /// Write a minimal WAV header + PCM int16 body for an interleaved mono buffer.
    private static func encodeWAV(from buffer: AVAudioPCMBuffer) throws -> Data {
        guard let int16 = buffer.int16ChannelData else { throw SnoringClassifierError.resample }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        let sampleRate = UInt32(buffer.format.sampleRate)
        let bitsPerSample: UInt16 = 16
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels) * (bitsPerSample / 8)
        let dataSize = UInt32(frames * channels * Int(bitsPerSample / 8))

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(36 + dataSize).littleEndian, Array.init))
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init)) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(channels).littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))

        let samplesPtr = int16[0]
        let byteCount = frames * channels * MemoryLayout<Int16>.size
        samplesPtr.withMemoryRebound(to: UInt8.self, capacity: byteCount) { bytePtr in
            data.append(bytePtr, count: byteCount)
        }
        return data
    }

    // MARK: - Multipart + decode

    private static func buildMultipartBody(wav: Data, sampleRate: Double, boundary: String) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"sample_rate\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("\(Int(sampleRate))\(lineBreak)".data(using: .utf8)!)

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"clip.wav\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(wav)
        body.append(lineBreak.data(using: .utf8)!)

        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return body
    }

    private static func decode(_ data: Data) throws -> RemoteClassification {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let label = json["label"] as? String,
              let confidence = json["confidence"] as? Double else {
            throw SnoringClassifierError.invalidResponse
        }
        let top5Raw = json["top_5"] as? [[String: Any]] ?? []
        let top5 = top5Raw.compactMap { entry -> (String, Double)? in
            guard let l = entry["label"] as? String, let c = entry["confidence"] as? Double else { return nil }
            return (l, c)
        }
        return RemoteClassification(label: label, confidence: confidence, top5: top5)
    }

    // MARK: - Keychain

    static func keychainWrite(secret: Data, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = secret
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func keychainRead(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}
