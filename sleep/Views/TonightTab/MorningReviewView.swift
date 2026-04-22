//
//  MorningReviewView.swift
//  sleep
//
//

import os
import SwiftData
import SwiftUI

struct MorningReviewView: View {

    @Environment(SleepTrackingService.self) private var trackingService
    @Environment(WeatherService.self) private var weatherService
    @Environment(CloudSyncService.self) private var cloudService
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SleepSession.startTime, order: .reverse)
    private var recentSessions: [SleepSession]

    @State private var selectedQuality: SleepQuality = .fair
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var heartRate: HeartRateStats?
    @State private var heartRateLoaded = false
    @State private var biometrics: BiometricStats?
    @State private var selectedMood: MorningMood? = nil
    @State private var aiSummary: String? = nil
    @State private var intelligenceService = IntelligenceService()
    @State private var showingShareSheet = false

    // Dream journal (AI theme tagging)
    @State private var dreamJournal: String = ""
    @State private var dreamThemes: [String] = []
    @State private var isTaggingDream = false

    // Metric explainer
    @State private var explainer: MetricExplainerRequest? = nil
    @State private var explainerText: String? = nil
    @State private var isExplaining = false

    private var previousSessions: [SleepSession] {
        Array(recentSessions.prefix(7))
    }

    private var averagePreviousScore: Double? {
        guard !previousSessions.isEmpty else { return nil }
        let total = previousSessions.reduce(0) { $0 + $1.sleepScore }
        return Double(total) / Double(previousSessions.count)
    }

    private var previewSession: SleepSession? {
        guard let start = trackingService.startTime else { return nil }
        return SleepSession(
            startTime: start,
            endTime: Date(),
            quality: selectedQuality,
            movementPoints: trackingService.motionService.dataPoints,
            snoringEvents: trackingService.audioService.snoringEvents,
            sleepStages: trackingService.deriveSleepStages(
                from: trackingService.motionService.dataPoints,
                start: start,
                end: Date()
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 12)

                // Header
                VStack(spacing: 6) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)
                        )
                        .symbolEffect(.breathe)

                    Text("Good Morning!")
                        .font(.title)
                        .fontWeight(.semibold)

                    Text("How did you sleep?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // AI Morning Summary
                if let summary = aiSummary {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "brain.head.profile.fill")
                                    .foregroundStyle(.purple)
                                Text("AI Summary")
                                    .font(.headline)
                                Spacer()
                                if intelligenceService.isAvailable {
                                    Text("Apple Intelligence")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Weather Card
                WeatherCard(weatherService: weatherService)

                // Biometrics Card (Apple Watch)
                if heartRateLoaded {
                    BiometricsCard(
                        heartRate: heartRate,
                        biometrics: biometrics,
                        onExplain: { name, value in
                            triggerExplainer(name: name, value: value)
                        }
                    )
                }

                // Score Breakdown
                if let session = previewSession {
                    ScoreBreakdownCard(session: session)
                }

                // Sleep Stage Timeline
                if let session = previewSession, !session.sleepStages.isEmpty {
                    StageTimelineCard(stages: session.sleepStages)
                }

                // Audio Highlights — playback of recorded snoring clips with
                // "Not me" button so users can drop false positives before
                // the session is saved. Logs each action for Xcode console.
                if !trackingService.audioService.snoringEvents.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Audio Highlights", systemImage: "waveform")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    triggerExplainer(
                                        name: "Snore events",
                                        value: "\(trackingService.audioService.snoringEvents.count) tonight"
                                    )
                                } label: {
                                    HStack(spacing: 3) {
                                        Text("\(trackingService.audioService.snoringEvents.count) event\(trackingService.audioService.snoringEvents.count == 1 ? "" : "s")")
                                            .font(.caption)
                                        Image(systemName: "info.circle")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            Text("Tap ▶ to listen. Remove anything that isn't you snoring.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            ForEach(Array(trackingService.audioService.snoringEvents
                                            .groupedByClassification().enumerated()),
                                    id: \.offset) { _, group in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: group.bucket.icon)
                                            .font(.subheadline)
                                            .foregroundStyle(group.bucket.tint)
                                        Text(group.bucket.displayName)
                                            .font(.subheadline).fontWeight(.semibold)
                                        Text("\(group.events.count)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.top, 2)

                                    ForEach(group.events) { event in
                                        let eventType = AudioEventType.classify(
                                            amplitude: event.averageAmplitude,
                                            duration: event.duration
                                        )
                                        HStack(alignment: .center, spacing: 8) {
                                            AudioPlayerView(event: event, eventType: eventType)
                                            // Surface the precise classifier
                                            // label (e.g. Bark, Meow) even
                                            // inside its bucket so the user
                                            // knows which specific sound it
                                            // was. Skip plain "snoring" since
                                            // that's the section header.
                                            if !event.classification.isEmpty,
                                               event.classification.lowercased() != "snoring" {
                                                Text(event.classification.replacingOccurrences(of: "_", with: " "))
                                                    .font(.caption2)
                                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                                    .background(group.bucket.tint.opacity(0.15))
                                                    .foregroundStyle(group.bucket.tint)
                                                    .clipShape(Capsule())
                                            }
                                            Button {
                                                removeSnoreEvent(id: event.id)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Remove as false positive")
                                        }
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                        }
                    }
                }

                // Sleep Comparison Card
                if let avgScore = averagePreviousScore {
                    SleepComparisonCard(previousSessions: previousSessions, averageScore: avgScore)
                }

                // Morning Mood
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How do you feel?")
                            .font(.headline)

                        HStack(spacing: 16) {
                            ForEach(MorningMood.allCases) { mood in
                                Button {
                                    selectedMood = mood
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(mood.emoji)
                                            .font(.title)
                                        Text(mood.label)
                                            .font(.caption2)
                                            .foregroundStyle(selectedMood == mood ? .primary : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selectedMood == mood ? Color.cyan.opacity(0.15) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Quality picker
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sleep Quality")
                            .font(.headline)

                        HStack(spacing: 12) {
                            ForEach(SleepQuality.allCases) { quality in
                                QualityButton(
                                    quality: quality,
                                    isSelected: selectedQuality == quality
                                ) {
                                    selectedQuality = quality
                                }
                            }
                        }
                    }
                }

                // Notes
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)

                        TextField("How did you feel? Any dreams?", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                    }
                }

                // Dream journal — AI theme tagging
                dreamJournalCard

                // Save button
                if isSaving {
                    ProgressView("Saving...")
                        .padding()
                } else {
                    GlassButton(title: "Save Session", icon: "checkmark.circle.fill") {
                        AppLogger.ui.info("User saving session — quality: \(selectedQuality.label), mood: \(selectedMood?.label ?? "none")")
                        isSaving = true
                        Task {
                            let savedSession = await trackingService.saveSession(
                                quality: selectedQuality,
                                notes: notes,
                                modelContext: modelContext,
                                cloudService: cloudService
                            )
                            if let session = savedSession {
                                if let mood = selectedMood {
                                    session.morningMood = mood.rawValue
                                }
                                if !dreamJournal.isEmpty {
                                    session.dreamJournal = dreamJournal
                                    if !dreamThemes.isEmpty {
                                        session.dreamThemes = dreamThemes
                                    }
                                }
                                do {
                                    try modelContext.save()
                                    AppLogger.data.info("Morning mood/dream saved on session score: \(session.sleepScore)")
                                } catch {
                                    AppLogger.error("Failed to save morning mood/dream", error: error)
                                }
                            }
                            isSaving = false
                        }
                    }
                }

                // Share an image card — the viral-growth surface. Rendered
                // on the fly from the current session + AI summary.
                if let start = trackingService.startTime {
                    let tempSession = SleepSession(
                        startTime: start,
                        endTime: Date(),
                        quality: selectedQuality,
                        movementPoints: trackingService.motionService.dataPoints,
                        snoringEvents: trackingService.audioService.snoringEvents
                    )
                    SleepCardShareLink(session: tempSession, aiSummary: aiSummary)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [.cyan.opacity(0.8), .indigo.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .sheet(item: $explainer) { req in
            MetricExplainerSheet(
                metricName: req.name,
                metricValue: req.value,
                isLoading: isExplaining,
                text: explainerText
            )
            .presentationDetents([.medium])
        }
        .task {
            AppLogger.ui.info("Morning review loading data...")
            await weatherService.fetchWakeUpWeather()

            if let start = trackingService.startTime {
                AppLogger.healthKit.info("Fetching biometrics for session starting \(start.formatted())")
                heartRate = await trackingService.healthKitService.fetchHeartRate(
                    from: start,
                    to: Date()
                )
                biometrics = await trackingService.healthKitService.fetchAllBiometrics(from: start, to: Date())
                AppLogger.healthKit.info("Biometrics loaded — HR: \(heartRate != nil ? "yes" : "no"), biometrics: \(biometrics != nil ? "yes" : "no")")
            }
            heartRateLoaded = true

            if let start = trackingService.startTime {
                let tempSession = SleepSession(
                    startTime: start,
                    endTime: Date(),
                    quality: selectedQuality,
                    movementPoints: trackingService.motionService.dataPoints,
                    snoringEvents: trackingService.audioService.snoringEvents
                )
                aiSummary = await intelligenceService.generateMorningSummary(session: tempSession)
                AppLogger.intelligence.info("AI summary: \(aiSummary != nil ? "generated" : "unavailable")")
            }
        }
    }

    // MARK: - Dream journal card

    @ViewBuilder
    private var dreamJournalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Dream Journal", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Spacer()
                    if intelligenceService.isAvailable {
                        Text("AI")
                            .font(.caption2).fontWeight(.bold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(LinearGradient(colors: [.purple, .indigo], startPoint: .leading, endPoint: .trailing))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }

                TextField("Describe what you dreamt (optional)", text: $dreamJournal, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)

                HStack {
                    Button {
                        Task { await tagDreamNow() }
                    } label: {
                        HStack(spacing: 6) {
                            if isTaggingDream {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "tag.fill")
                            }
                            Text(isTaggingDream ? "Tagging…" : "Tag themes")
                        }
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                    }
                    .disabled(dreamJournal.trimmingCharacters(in: .whitespaces).count < 10 || isTaggingDream)
                    Spacer()
                }

                if !dreamThemes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(dreamThemes, id: \.self) { theme in
                                Text(theme)
                                    .font(.caption2).fontWeight(.semibold)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.purple.opacity(0.15))
                                    .foregroundStyle(.purple)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func tagDreamNow() async {
        let text = dreamJournal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 10 else { return }
        isTaggingDream = true
        defer { isTaggingDream = false }
        dreamThemes = await intelligenceService.tagDreamThemes(from: text)
        AppLogger.intelligence.info("🤖 Dream journal → \(dreamThemes.count) themes")
    }

    // MARK: - Metric explainer

    private func triggerExplainer(name: String, value: String) {
        explainer = MetricExplainerRequest(name: name, value: value)
        explainerText = nil
        guard let session = previewSession else { return }
        isExplaining = true
        Task {
            let text = await intelligenceService.explainMetric(
                name: name,
                value: value,
                session: session,
                recent: previousSessions
            )
            await MainActor.run {
                explainerText = text
                isExplaining = false
            }
        }
    }

    /// Remove a snoring event the user flagged as "not me". Runs before the
    /// session is persisted, so the false positive never reaches SwiftData or
    /// Firestore. Also deletes the audio clip file if one exists. Logs to
    /// `AppLogger.audio` so you can verify in Xcode.
    private func removeSnoreEvent(id: UUID) {
        let events = trackingService.audioService.snoringEvents
        guard let event = events.first(where: { $0.id == id }) else { return }
        AppLogger.audio.info("🗑️ User removed snore event — id: \(id.uuidString), classification: \(event.classification) (\(String(format: "%.2f", event.classificationConfidence)))")
        if let url = event.audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        trackingService.audioService.snoringEvents.removeAll { $0.id == id }
    }

    private func buildShareText(startTime: Date) -> String {
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let snoringCount = trackingService.audioService.snoringEvents.count

        var text = "Slumberscope Sleep Report\n"
        text += "Date: \(startTime.formatted(date: .abbreviated, time: .omitted))\n"
        text += "Duration: \(hours)h \(minutes)m\n"
        text += "Quality: \(selectedQuality.label)\n"
        text += "Snoring Events: \(snoringCount)\n"
        if let summary = aiSummary {
            text += "\n\(summary)\n"
        }
        text += "\nTracked with Slumberscope"
        return text
    }
}

// MARK: - ShareSheet

private struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - WeatherCard

private struct WeatherCard: View {

    let weatherService: WeatherService

    var body: some View {
        GlassCard {
            if weatherService.isLoading {
                HStack {
                    ProgressView()
                    Text("Getting weather…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if let weather = weatherService.weather {
                HStack(spacing: 16) {
                    Image(systemName: weather.symbolName)
                        .font(.system(size: 42))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 56)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(weather.cityName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Text(weather.temperature)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(weather.condition)
                            .font(.subheadline)

                        HStack(spacing: 8) {
                            Text(weather.feelsLike)
                            Text("·")
                            Text(weather.humidity)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            } else {
                HStack {
                    Image(systemName: "icloud.slash")
                        .foregroundStyle(.secondary)
                    Text("Weather unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - SleepComparisonCard

private struct SleepComparisonCard: View {

    let previousSessions: [SleepSession]
    let averageScore: Double

    private var lastSession: SleepSession? { previousSessions.first }

    private var trend: ComparisonTrend {
        guard let last = lastSession else { return .same }
        let diff = Double(last.sleepScore) - averageScore
        if diff > 5 { return .better }
        if diff < -5 { return .worse }
        return .same
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Sleep Trend", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)

                HStack(spacing: 0) {
                    if let last = lastSession {
                        StatBlock(
                            value: "\(last.sleepScore)",
                            label: "Last Night",
                            color: scoreColor(last.sleepScore)
                        )
                    }

                    Divider().frame(height: 40)

                    StatBlock(
                        value: "\(Int(averageScore.rounded()))",
                        label: "\(previousSessions.count)-Night Avg",
                        color: .secondary
                    )

                    Divider().frame(height: 40)

                    TrendBadge(trend: trend)
                        .frame(maxWidth: .infinity)
                }

                if previousSessions.count > 1 {
                    ScoreSparkline(sessions: previousSessions)
                        .frame(height: 32)
                }
            }
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 60..<80: return .yellow
        default: return .red
        }
    }
}

// MARK: - StatBlock

private struct StatBlock: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - TrendBadge

private enum ComparisonTrend { case better, worse, same }

private struct TrendBadge: View {
    let trend: ComparisonTrend

    private var icon: String {
        switch trend {
        case .better: return "arrow.up.circle.fill"
        case .worse: return "arrow.down.circle.fill"
        case .same: return "equal.circle.fill"
        }
    }
    private var color: Color {
        switch trend {
        case .better: return .green
        case .worse: return .red
        case .same: return .secondary
        }
    }
    private var label: String {
        switch trend {
        case .better: return "Better"
        case .worse: return "Worse"
        case .same: return "Similar"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - ScoreSparkline

private struct ScoreSparkline: View {
    let sessions: [SleepSession]

    var body: some View {
        GeometryReader { geo in
            let scores = sessions.reversed().map { Double($0.sleepScore) }
            let maxScore = max(scores.max() ?? 100, 1.0)
            let minScore = min(scores.min() ?? 0, maxScore - 1)
            let range = maxScore - minScore
            let w = geo.size.width
            let h = geo.size.height
            let step = w / max(Double(scores.count - 1), 1)

            Path { path in
                for (i, score) in scores.enumerated() {
                    let x = Double(i) * step
                    let y = h - ((score - minScore) / range * h)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(
                LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )

            ForEach(Array(scores.enumerated()), id: \.offset) { i, score in
                let x = Double(i) * step
                let y = h - ((score - minScore) / range * h)
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5)
                    .position(x: x, y: y)
            }
        }
    }
}

// MARK: - QualityButton

private struct QualityButton: View {

    let quality: SleepQuality
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: quality.icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .yellow : .secondary)

                Text(quality.label)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? Color.yellow.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - BiometricsCard

private struct BiometricsCard: View {
    let heartRate: HeartRateStats?
    let biometrics: BiometricStats?
    var onExplain: ((String, String) -> Void)? = nil

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Biometrics", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer()
                    if heartRate?.isFromWatch == true {
                        Label("Apple Watch", systemImage: "applewatch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let hr = heartRate {
                    HStack(spacing: 0) {
                        BiometricStatBlock(value: hr.averageFormatted, label: "Avg HR", icon: "heart.fill", color: .red)
                            .onTapGesture { onExplain?("Avg Heart Rate", hr.averageFormatted) }
                        Divider().frame(height: 40)
                        BiometricStatBlock(value: hr.minimumFormatted, label: "Lowest", icon: "arrow.down", color: .blue)
                            .onTapGesture { onExplain?("Lowest Heart Rate", hr.minimumFormatted) }
                        Divider().frame(height: 40)
                        BiometricStatBlock(value: hr.maximumFormatted, label: "Highest", icon: "arrow.up", color: .orange)
                    }
                }

                if let bio = biometrics {
                    Divider()

                    HStack(spacing: 0) {
                        if let hrv = bio.hrvAverage {
                            BiometricStatBlock(value: "\(Int(hrv)) ms", label: "HRV", icon: "waveform.path.ecg", color: .green)
                                .onTapGesture { onExplain?("HRV", "\(Int(hrv)) ms") }
                        }
                        if let rr = bio.respiratoryRate {
                            if bio.hrvAverage != nil { Divider().frame(height: 40) }
                            BiometricStatBlock(value: String(format: "%.1f", rr), label: "Resp Rate", icon: "lungs.fill", color: .cyan)
                        }
                        if let spo2 = bio.bloodOxygen {
                            if bio.respiratoryRate != nil || bio.hrvAverage != nil { Divider().frame(height: 40) }
                            BiometricStatBlock(value: "\(Int(spo2))%", label: "SpO2", icon: "drop.fill", color: .blue)
                        }
                    }

                    if let temp = bio.wristTemperature {
                        Divider()
                        HStack {
                            Image(systemName: "thermometer.medium")
                                .foregroundStyle(.orange)
                            Text("Wrist Temperature")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.1f\u{00B0}C", temp))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                } else if heartRate == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "applewatch.slash")
                            .foregroundStyle(.secondary)
                        Text("No biometric data — pair an Apple Watch to see metrics during sleep.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct BiometricStatBlock: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ScoreBreakdownCard

private struct ScoreBreakdownCard: View {
    let session: SleepSession

    private var hasRecoveryData: Bool {
        session.hrvAverageMS != nil || session.minimumHeartRateBPM != nil
    }

    private var movementMax: Int { hasRecoveryData ? 10 : 20 }
    private var snoringMax: Int { hasRecoveryData ? 10 : 15 }
    private var recoveryMax: Int { hasRecoveryData ? 15 : 0 }

    private var durationScore: Int {
        let hours = session.durationSeconds / 3600.0
        if hours >= 7 && hours <= 9 { return 35 }
        else if hours >= 6 && hours < 7 { return 25 }
        else if hours > 9 && hours <= 10 { return 28 }
        else if hours >= 5 && hours < 6 { return 15 }
        else { return max(0, Int(10 - abs(hours - 8) * 2)) }
    }

    private var qualityScore: Int {
        Int(Double(session.qualityRating) / 5.0 * 30.0)
    }

    private var movementScore: Int {
        Int(max(0, Double(movementMax) - session.averageMovement * 40))
    }

    private var snoringScore: Int {
        let perEvent = Double(snoringMax) / 5.0
        return Int(Double(snoringMax) - min(Double(snoringMax), Double(session.snoringCount) * perEvent))
    }

    private var recoveryScore: Int {
        guard hasRecoveryData else { return 0 }
        var points: Double = 0
        if let hrv = session.hrvAverageMS {
            let normalized = max(0, min(1, (hrv - 10) / 80))
            points += normalized * Double(recoveryMax) * 0.6
        }
        if let minHR = session.minimumHeartRateBPM,
           let resting = session.restingHeartRateBPM, resting > 0 {
            let drop = max(0, resting - minHR)
            let normalized = max(0, min(1, drop / 15.0))
            points += normalized * Double(recoveryMax) * 0.4
        } else if session.hrvAverageMS != nil {
            points += Double(recoveryMax) * 0.3
        }
        return Int(min(Double(recoveryMax), points).rounded())
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Score Breakdown").font(.headline)
                    if hasRecoveryData {
                        Spacer()
                        Label("Apple Watch", systemImage: "applewatch")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ScoreRow(label: "Duration", score: durationScore, maxScore: 35, color: .cyan, icon: "clock.fill")
                ScoreRow(label: "Quality", score: qualityScore, maxScore: 30, color: .yellow, icon: "star.fill")
                ScoreRow(label: "Restfulness", score: movementScore, maxScore: movementMax, color: .green, icon: "figure.walk")
                ScoreRow(label: "Breathing", score: snoringScore, maxScore: snoringMax, color: .purple, icon: "lungs.fill")
                if hasRecoveryData {
                    ScoreRow(label: "Recovery", score: recoveryScore, maxScore: recoveryMax, color: .pink, icon: "waveform.path.ecg")
                }

                Divider()

                HStack {
                    Text("Total Score")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(session.sleepScore)/100")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(session.sleepScore >= 80 ? .green : session.sleepScore >= 60 ? .yellow : .orange)
                }
            }
        }
    }
}

private struct ScoreRow: View {
    let label: String
    let score: Int
    let maxScore: Int
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(label)
                .font(.caption)
            Spacer()
            ProgressView(value: Double(score), total: Double(maxScore))
                .tint(color)
                .frame(width: 80)
            Text("\(score)/\(maxScore)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - StageTimelineCard

private struct StageTimelineCard: View {
    let stages: [SleepStageEntry]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep Stages")
                    .font(.headline)

                if stages.isEmpty {
                    Text("No stage data available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    SleepStagesChart(stages: stages)
                        .frame(height: 120)

                    let total = stages.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
                    HStack(spacing: 12) {
                        ForEach(SleepStageType.allCases) { stageType in
                            let duration = stages.filter { $0.stage == stageType }
                                .reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
                            if duration > 0 {
                                let _ = duration / max(total, 1)
                                let mins = Int(duration / 60)
                                VStack(spacing: 2) {
                                    Circle().fill(stageType.color).frame(width: 8, height: 8)
                                    Text("\(mins)m")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                    Text(stageType.label)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Metric Explainer

struct MetricExplainerRequest: Identifiable {
    let id = UUID()
    let name: String
    let value: String
}

private struct MetricExplainerSheet: View {
    let metricName: String
    let metricValue: String
    let isLoading: Bool
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.purple)
                Text(metricName).font(.headline)
                Spacer()
                Text(metricValue).font(.subheadline).foregroundStyle(.secondary)
            }

            Divider()

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Analyzing your baseline…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } else if let text, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Not enough data yet. Keep tracking to build your baseline.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()

            Text("On-device analysis — your data never leaves your iPhone.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
