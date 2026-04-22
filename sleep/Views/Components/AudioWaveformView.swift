//
//  AudioWaveformView.swift
//  sleep
//
//

import SwiftUI

// MARK: - AudioWaveformView

struct AudioWaveformView: View {
    let amplitudes: [Float]
    var accentColor: Color = .purple
    var barWidth: CGFloat = 2
    var spacing: CGFloat = 1
    var playbackProgress: Double = 0 // 0.0 to 1.0

    var body: some View {
        GeometryReader { geo in
            let totalBars = max(1, Int(geo.size.width / (barWidth + spacing)))
            let sampledAmplitudes = resample(amplitudes, to: totalBars)
            let maxAmp = max(sampledAmplitudes.max() ?? 1, 0.01)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<sampledAmplitudes.count, id: \.self) { index in
                    let normalized = CGFloat(sampledAmplitudes[index] / maxAmp)
                    let height = max(2, normalized * geo.size.height * 0.9)
                    let isPlayed = Double(index) / Double(max(sampledAmplitudes.count - 1, 1)) <= playbackProgress

                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(isPlayed ? accentColor : accentColor.opacity(0.3))
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resample(_ data: [Float], to count: Int) -> [Float] {
        guard !data.isEmpty, count > 0 else { return Array(repeating: 0, count: max(count, 1)) }
        if data.count <= count { return data }

        let chunkSize = Double(data.count) / Double(count)
        return (0..<count).map { i in
            let start = Int(Double(i) * chunkSize)
            let end = min(max(start + 1, Int(Double(i + 1) * chunkSize)), data.count)
            let chunk = data[start..<end]
            return chunk.isEmpty ? 0 : chunk.reduce(0, +) / Float(chunk.count)
        }
    }
}

// MARK: - Simulated waveform for events without raw audio

extension AudioWaveformView {
    /// Generate a plausible waveform from a SnoringEvent's amplitude and duration
    static func simulatedAmplitudes(averageAmplitude: Double, duration: TimeInterval, sampleCount: Int = 50) -> [Float] {
        (0..<sampleCount).map { i in
            let phase = Double(i) / Double(sampleCount)
            let envelope = sin(phase * .pi) // Bell curve envelope
            let noise = Double.random(in: 0.7...1.3)
            return Float(averageAmplitude * envelope * noise)
        }
    }
}
