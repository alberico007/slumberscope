//
//  WatchClassifierClient.swift
//  sleepWatch
//
//  watchOS-side HTTPS client for the Azure-hosted YAMNet classifier.
//  Mirrors sleep/Services/SnoringClassifierClient.swift — the iPhone
//  version — but trimmed: no downsampling (we record 16 kHz directly)
//  and no SoundAnalysis on-device pass. Same HMAC signing contract.
//

import CryptoKit
import Foundation
import os

enum WatchClassifierError: Error {
    case noEndpoint
    case noSecret
    case network(Error)
    case auth
    case server(Int)
    case invalidResponse
}

struct WatchRemoteClassification: Sendable {
    let label: String
    let confidence: Double
}

@MainActor
final class WatchClassifierClient {

    var endpoint: URL?

    private let timeout: TimeInterval = 4.0
    private let session: URLSession

    private let keychainAccount = "smarterpillow.snoring.hmac"
    private let keychainService = "smarterpillow"

    // Keep these in sync with SnoringClassifierClient on iPhone. The server
    // reads /etc/snoring/secret as raw bytes and HMACs with those bytes as
    // the key — store the hex string's UTF-8 representation, not the
    // hex-decoded bytes.
    private static let defaultEndpoint = "https://smarterpillow-snoring.eastus2.cloudapp.azure.com/classify"
    private static let defaultHMACSecretHex = "98dec3185a3cce84aa5ebe2e9d830d80007aaa43577025e0e458254acbbfaef8"

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        config.timeoutIntervalForResource = 8.0
        self.session = URLSession(configuration: config)
        self.endpoint = URL(string: Self.defaultEndpoint)

        if Self.keychainRead(service: keychainService, account: keychainAccount) == nil {
            if let data = Self.defaultHMACSecretHex.data(using: .utf8) {
                _ = Self.keychainWrite(secret: data, service: keychainService, account: keychainAccount)
            }
        }
    }

    /// Classify a WAV payload. Called with a ~2 s 16 kHz mono PCM clip
    /// wrapped in a RIFF/WAVE header.
    func classify(wavData: Data, sampleRate: Double) async throws -> WatchRemoteClassification {
        guard let endpoint else { throw WatchClassifierError.noEndpoint }
        guard let secret = Self.keychainRead(service: keychainService, account: keychainAccount) else {
            throw WatchClassifierError.noSecret
        }

        let boundary = "sp-\(UUID().uuidString)"
        let body = Self.buildMultipartBody(wav: wavData, sampleRate: sampleRate, boundary: boundary)

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let digest = SHA256.hash(data: wavData).map { String(format: "%02x", $0) }.joined()
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
            throw WatchClassifierError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw WatchClassifierError.invalidResponse }
        switch http.statusCode {
        case 200:
            break
        case 401:
            throw WatchClassifierError.auth
        default:
            throw WatchClassifierError.server(http.statusCode)
        }

        return try Self.decode(data)
    }

    // MARK: - WAV helpers

    /// Wrap little-endian int16 mono PCM bytes in a minimal RIFF/WAVE header.
    static func makeWAVData(pcm16Samples samples: Data, sampleRate: Double, channels: Int = 1) -> Data {
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
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))
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

    private static func decode(_ data: Data) throws -> WatchRemoteClassification {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let label = json["label"] as? String,
              let confidence = json["confidence"] as? Double else {
            throw WatchClassifierError.invalidResponse
        }
        return WatchRemoteClassification(label: label, confidence: confidence)
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
