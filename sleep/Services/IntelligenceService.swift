//
//  IntelligenceService.swift
//  sleep
//
//

import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
@MainActor
final class IntelligenceService {

    // MARK: - Observable State

    var isAvailable: Bool {
        #if targetEnvironment(simulator)
        // FoundationModels isn't reliably available on simulator.
        return false
        #else
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            // Proper availability check: the device must be Apple Intelligence
            // capable AND the user must have Apple Intelligence turned on in
            // Settings. Older / cheaper devices won't have the model ready.
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
            #else
            return false
            #endif
        }
        return false
        #endif
    }

    var isGenerating = false

    // MARK: - System Prompt

    private static let sleepCoachSystemPrompt = """
    You are a knowledgeable sleep coach inside the Slumberscope app.

    HARD RULES:
    • Use only numbers that appear in the prompt. Never invent values, trends, or dates.
    • If a metric is missing, don't mention it — don't guess what it might be.
    • 2–3 sentences max. Warm but direct. No filler, no medical advice, no diagnoses.
    • When referencing data, use the actual numbers provided (e.g. "your 32ms HRV").
    """

    // MARK: - Generate Coaching Tip

    func generateCoachingTip(sessions: [SleepSession], factors: [SleepFactor]) async -> String? {
        guard !sessions.isEmpty else { return nil }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Generating coaching tip...")
                let prompt = buildCoachingPrompt(sessions: sessions, factors: factors)
                let instructions = Instructions(Self.sleepCoachSystemPrompt)
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                AppLogger.intelligence.info("🤖 Coaching tip generated successfully")
                return response.content
            } catch {
                AppLogger.intelligence.error("Intelligence coaching tip generation failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        // Fallback to rule-based tips
        AppLogger.intelligence.info("Using rule-based fallback")
        return FactorService.generateCoachingTip(sessions: sessions, factors: factors)
    }

    // MARK: - Generate Morning Summary

    func generateMorningSummary(session: SleepSession) async -> String? {
        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Generating morning summary...")
                let prompt = buildMorningSummaryPrompt(session: session)
                let instructions = Instructions(Self.sleepCoachSystemPrompt)
                let languageSession = LanguageModelSession(instructions: instructions)
                let response = try await languageSession.respond(to: prompt)
                AppLogger.intelligence.info("🤖 Morning summary generated successfully")
                return response.content
            } catch {
                AppLogger.intelligence.error("Intelligence morning summary generation failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        // Fallback: formatted string with key metrics
        return buildFallbackMorningSummary(session: session)
    }

    // MARK: - Generate Factor Insight

    func generateFactorInsight(correlation: FactorCorrelation) async -> String? {
        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Generating factor insight...")
                let prompt = buildFactorInsightPrompt(correlation: correlation)
                let instructions = Instructions(Self.sleepCoachSystemPrompt)
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                AppLogger.intelligence.info("🤖 Factor insight generated successfully")
                return response.content
            } catch {
                AppLogger.intelligence.error("Intelligence factor insight generation failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        // Fallback: return the pre-computed insight string
        return correlation.insight
    }

    // MARK: - Prompt Builders

    private func buildCoachingPrompt(sessions: [SleepSession], factors: [SleepFactor]) -> String {
        let recentSessions = Array(sessions.prefix(7))
        let count = max(recentSessions.count, 1)
        let scores: [Int] = recentSessions.map { $0.sleepScore }
        let avgScore = scores.reduce(0, +) / count
        let durations: [Double] = recentSessions.map { $0.durationSeconds / 3600.0 }
        let avgHours = durations.reduce(0, +) / Double(count)
        let snoringCounts: [Int] = recentSessions.map { $0.snoringCount }
        let avgSnoring = snoringCounts.reduce(0, +) / count

        let factorLabels: [String] = factors.prefix(14).map { $0.displayLabel }
        let recentFactors = factorLabels.joined(separator: ", ")

        return """
        Based on the user's recent sleep data, provide a personalized coaching tip.

        Recent stats (last \(recentSessions.count) nights):
        - Average sleep score: \(avgScore)/100
        - Average duration: \(String(format: "%.1f", avgHours)) hours
        - Average snoring events per night: \(avgSnoring)
        - Recent factors logged: \(recentFactors.isEmpty ? "none" : recentFactors)

        Provide one specific, actionable tip in 2-3 sentences.
        """
    }

    private func buildMorningSummaryPrompt(session: SleepSession) -> String {
        let totalSeconds = Int(session.durationSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let stages = session.sleepStages
        let deepStages = stages.filter { $0.stage == .deep }
        let deepSeconds = deepStages.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        let deepMinutes = deepSeconds / 60.0
        let remStages = stages.filter { $0.stage == .rem }
        let remSeconds = remStages.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        let remMinutes = remSeconds / 60.0

        var biometrics: [String] = []
        if let avg = session.averageHeartRateBPM, let min = session.minimumHeartRateBPM {
            biometrics.append("Heart rate: avg \(Int(avg.rounded())) bpm, low \(Int(min.rounded())) bpm")
        }
        if let hrv = session.hrvAverageMS {
            biometrics.append("HRV (recovery indicator): \(Int(hrv.rounded())) ms")
        }
        if let resting = session.restingHeartRateBPM {
            biometrics.append("Baseline resting HR: \(Int(resting.rounded())) bpm")
        }
        if let resp = session.respiratoryRateBPM {
            biometrics.append("Respiratory rate: \(String(format: "%.1f", resp)) breaths/min")
        }
        if let spo2 = session.bloodOxygenPercent {
            biometrics.append("Blood oxygen: \(String(format: "%.1f", spo2))%")
        }
        let biometricsBlock = biometrics.isEmpty ? "" : "\n\nApple Watch biometrics:\n- " + biometrics.joined(separator: "\n- ")

        return """
        Write a brief, friendly morning sleep summary for the user.

        Last night's sleep data:
        - Total time: \(hours)h \(minutes)m
        - Sleep score: \(session.sleepScore)/100
        - Quality rating: \(session.quality.label)
        - Deep sleep: \(Int(deepMinutes)) minutes
        - REM sleep: \(Int(remMinutes)) minutes
        - Snoring events: \(session.snoringCount)
        - Awakenings: \(session.awakeningCount)
        - Sleep efficiency: \(Int(session.sleepEfficiency * 100))%\(biometricsBlock)

        Summarize in 2-3 friendly sentences with one concrete insight. If Apple Watch biometrics are present, reference them (HRV indicates recovery, low heart rate is good overnight, etc).
        """
    }

    private func buildFactorInsightPrompt(correlation: FactorCorrelation) -> String {
        return """
        Explain this sleep factor correlation in plain language with actionable advice.

        Factor: \(correlation.factorType.label)
        Metric affected: \(correlation.metric)
        Average \(correlation.metric) with factor: \(String(format: "%.1f", correlation.withFactor))
        Average \(correlation.metric) without factor: \(String(format: "%.1f", correlation.withoutFactor))
        Nights with factor: \(correlation.nightsWithFactor)
        Nights without factor: \(correlation.nightsWithoutFactor)
        Percent change: \(String(format: "%.1f", correlation.percentChange))%
        Direction: \(correlation.isPositive ? "positive" : "negative")

        Provide a 2-3 sentence explanation of what this means and one suggestion.
        """
    }

    // MARK: - Journal → Factor Extraction
    //
    // Parses free-text like "coffee at 4, gym, stressed about exam" and
    // returns the FactorTypes it mentions plus a 1–5 intensity guess.
    // Falls back to a keyword matcher on devices without Apple Intelligence.

    struct ExtractedFactor: Sendable {
        let type: FactorType
        let intensity: Int
        let customLabel: String
    }

    func extractFactors(from text: String) async -> [ExtractedFactor] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Extracting factors from journal text…")
                let instructions = Instructions("""
                You extract sleep-affecting lifestyle factors from a user's short journal entry. \
                Respond with a compact JSON array. Each element: {"type":"caffeine|alcohol|exercise|screenTime|lateMeal|stress|medication|custom","intensity":1-5,"label":""}. \
                Use "custom" with a short "label" for things that don't fit the standard types. \
                Return [] if no factors mentioned. Intensity 1 = light, 5 = heavy. \
                Output ONLY the JSON array — no prose.
                """)
                let prompt = "Journal entry: \(trimmed)"
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let parsed = Self.parseExtractedFactorsJSON(response.content)
                AppLogger.intelligence.info("🤖 Extracted \(parsed.count) factors via AI")
                if !parsed.isEmpty { return parsed }
            } catch {
                AppLogger.intelligence.error("Factor extraction failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        let fallback = Self.keywordExtractFactors(from: trimmed)
        AppLogger.intelligence.info("🔎 Keyword factor extraction returned \(fallback.count)")
        return fallback
    }

    private static func parseExtractedFactorsJSON(_ raw: String) -> [ExtractedFactor] {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return [] }
        struct Raw: Decodable { let type: String; let intensity: Int?; let label: String? }
        guard let rows = try? JSONDecoder().decode([Raw].self, from: data) else { return [] }
        return rows.compactMap { row in
            guard let t = FactorType(rawValue: row.type) else { return nil }
            let intensity = max(1, min(5, row.intensity ?? 3))
            return ExtractedFactor(type: t, intensity: intensity, customLabel: row.label ?? "")
        }
    }

    private static func keywordExtractFactors(from text: String) -> [ExtractedFactor] {
        let lower = text.lowercased()
        var out: [ExtractedFactor] = []
        let map: [(FactorType, [String])] = [
            (.caffeine, ["coffee", "espresso", "latte", "caffeine", "energy drink", "red bull", "matcha", "tea"]),
            (.alcohol, ["wine", "beer", "cocktail", "drinks", "alcohol", "whiskey", "vodka", "tequila", "bourbon"]),
            (.exercise, ["gym", "ran", "run", "workout", "lifted", "yoga", "cardio", "swim", "cycled", "biked"]),
            (.screenTime, ["scrolling", "tiktok", "instagram", "phone", "laptop", "netflix", "youtube", "screen"]),
            (.lateMeal, ["dinner late", "late meal", "midnight snack", "late eat", "big meal", "heavy meal"]),
            (.stress, ["stress", "anxious", "anxiety", "worried", "overwhelmed", "deadline", "exam", "presentation"]),
            (.medication, ["medication", "melatonin", "ambien", "advil", "benadryl", "ibuprofen", "pill"])
        ]
        for (type, keywords) in map where keywords.contains(where: { lower.contains($0) }) {
            out.append(ExtractedFactor(type: type, intensity: 3, customLabel: ""))
        }
        return out
    }

    // MARK: - Dream Theme Tagging

    func tagDreamThemes(from text: String) async -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return [] }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Tagging dream themes…")
                let instructions = Instructions("""
                You extract 2–5 short theme tags from a sleep dream description. \
                Themes should be 1–2 words each, lowercase, like "falling", "chase", "flying", "water", "school", "family", "work stress". \
                Respond with ONLY a JSON string array, nothing else.
                """)
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: "Dream: \(trimmed)")
                if let tags = Self.parseStringArrayJSON(response.content), !tags.isEmpty {
                    let joined = tags.joined(separator: ", ")
                    AppLogger.intelligence.info("🤖 Dream tags: \(joined)")
                    return tags
                }
            } catch {
                AppLogger.intelligence.error("Dream tagging failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        return Self.keywordDreamThemes(from: trimmed)
    }

    private static func parseStringArrayJSON(_ raw: String) -> [String]? {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return arr.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
    }

    private static func keywordDreamThemes(from text: String) -> [String] {
        let lower = text.lowercased()
        let map: [(String, [String])] = [
            ("falling", ["fall", "falling", "dropped"]),
            ("chase", ["chase", "chased", "running from"]),
            ("flying", ["fly", "flying", "soar"]),
            ("water", ["water", "ocean", "sea", "river", "pool", "flood"]),
            ("work", ["work", "office", "meeting", "boss", "deadline"]),
            ("school", ["school", "class", "exam", "test", "teacher"]),
            ("family", ["mom", "dad", "brother", "sister", "family", "parent"]),
            ("lost", ["lost", "confused", "searching"]),
            ("nightmare", ["scary", "terror", "nightmare", "dark"])
        ]
        return map.compactMap { (tag, kw) in kw.contains(where: { lower.contains($0) }) ? tag : nil }
    }

    // MARK: - Chat Q&A Against Sleep History

    func answerQuestion(_ question: String, sessions: [SleepSession]) async -> String? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // No history → nothing to reason over. Return a friendly empty-state
        // message instead of letting the model invent numbers.
        guard !sessions.isEmpty else {
            return "I don't have any sleep sessions to look at yet. Track a night and I'll be able to answer questions about your patterns."
        }

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Answering sleep question over \(sessions.count) nights…")
                let stats = Self.buildHistoryContext(sessions: sessions)
                let earliestNight = sessions.last.map {
                    let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
                    return df.string(from: $0.startTime)
                } ?? "N/A"
                let latestNight = sessions.first.map {
                    let df = DateFormatter(); df.dateFormat = "MMM d, yyyy"
                    return df.string(from: $0.startTime)
                } ?? "N/A"
                let instructions = Instructions("""
                You are a personal sleep coach answering questions about the user's own tracked sleep.

                HARD RULES — violating these is worse than being unhelpful:
                1. Use ONLY the data provided below. Never invent dates, numbers, or trends.
                2. If the question asks about a date or metric NOT in the data, say exactly: \
                   "I don't have data for that." Then suggest what they could track.
                3. Never estimate what you don't know. Never say "probably" about specific numbers.
                4. No medical diagnoses or medical advice. Describe patterns, not conditions.
                5. Keep answers under 4 sentences. Be concrete, cite actual numbers from the data.
                6. If a metric is missing for a specific night (e.g. no HRV), say "no HRV recorded that night".

                Tone: warm, direct, like a friend who happens to track sleep. No disclaimers.
                """)
                let session = LanguageModelSession(instructions: instructions)
                let prompt = """
                DATA SCOPE: \(sessions.count) nights, from \(earliestNight) to \(latestNight). \
                Nothing outside this range is available.

                NIGHTS (newest first):
                \(stats)

                QUESTION: \(trimmed)
                """
                let response = try await session.respond(to: prompt)
                AppLogger.intelligence.info("🤖 Chat answer generated (\(response.content.count) chars)")
                return response.content
            } catch {
                AppLogger.intelligence.error("Chat answer failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        return "Ask me anything about your sleep — I work best on an Apple Intelligence-capable iPhone. Meanwhile your \(sessions.count) tracked nights averaged a score of \(Self.avgScore(sessions))/100."
    }

    private static func buildHistoryContext(sessions: [SleepSession]) -> String {
        // Cap at 180 nights (~6 months) to stay well under the on-device
        // model's context window while still covering virtually every
        // question a user could reasonably ask about their patterns.
        let window = Array(sessions.prefix(180))
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d yyyy"
        return window.map { s -> String in
            let hours = s.durationSeconds / 3600.0
            var line = "• \(df.string(from: s.startTime)): score \(s.sleepScore), \(String(format: "%.1f", hours))h, snores \(s.snoringCount), mood \(s.morningMood)"
            if let hrv = s.hrvAverageMS { line += ", HRV \(Int(hrv))ms" }
            if let hr = s.averageHeartRateBPM { line += ", avgHR \(Int(hr))" }
            if let minHR = s.minimumHeartRateBPM { line += ", minHR \(Int(minHR))" }
            if let rr = s.respiratoryRateBPM { line += ", resp \(String(format: "%.1f", rr))" }
            if let spo2 = s.bloodOxygenPercent { line += ", SpO2 \(Int(spo2))%" }
            if !s.dreamThemesRaw.isEmpty { line += ", dreams[\(s.dreamThemesRaw)]" }
            return line
        }.joined(separator: "\n")
    }

    private static func avgScore(_ sessions: [SleepSession]) -> Int {
        guard !sessions.isEmpty else { return 0 }
        return sessions.map(\.sleepScore).reduce(0, +) / sessions.count
    }

    // MARK: - Weekly Narrative

    func generateWeeklyNarrative(sessions: [SleepSession]) async -> String? {
        guard !sessions.isEmpty else { return nil }
        let week = Array(sessions.prefix(7))

        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Generating weekly narrative…")
                let stats = Self.buildHistoryContext(sessions: week)
                let instructions = Instructions("""
                Write a short weekly sleep recap. Max 4 sentences.

                HARD RULES:
                • Use only nights and numbers that appear in the data below. Never invent a night.
                • Open with the week's overall pattern using the actual average.
                • Call out one notable night (best OR worst) — cite the real date and numbers.
                • Only connect data to a cause if the prompt shows a clear pattern (e.g. lowest HRV on late-bed night).
                • End with one forward-looking tip. No medical claims, no cheesy phrasing.
                """)
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: "Last week:\n\(stats)")
                return response.content
            } catch {
                AppLogger.intelligence.error("Weekly narrative failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        let avg = Self.avgScore(week)
        return "Last week you tracked \(week.count) nights and averaged a sleep score of \(avg)/100. Your best night was \(week.max(by: { $0.sleepScore < $1.sleepScore })?.sleepScore ?? 0) and your shortest was \(String(format: "%.1f", (week.min(by: { $0.durationSeconds < $1.durationSeconds })?.durationSeconds ?? 0) / 3600))h. Keep tracking for sharper insights."
    }

    // MARK: - Personalized Meditation Script

    func generatePersonalMeditation(name: String?, recentStress: String?, lengthMinutes: Int = 3) async -> String? {
        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Generating personal meditation…")
                let instructions = Instructions("""
                You write soothing, spoken sleep meditations for text-to-speech playback. \
                Write prose only — no stage directions, no headers, no markdown. \
                Use short sentences with natural pauses via periods and commas. \
                Second-person ("you"). Calming, warm, slow cadence. \
                Include 1–2 breath cues and one body-scan moment. \
                Target about \(lengthMinutes) minutes of read-aloud time (~\(lengthMinutes * 140) words).
                """)
                let nameLine = (name?.isEmpty == false) ? "The listener's name is \(name!)." : ""
                let stressLine = (recentStress?.isEmpty == false) ? "Today they mentioned: \(recentStress!). Gently acknowledge then release it." : ""
                let prompt = """
                Write a bedtime meditation. \(nameLine) \(stressLine)
                Open with an invitation to settle in. End with silence and sleep.
                """
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                AppLogger.intelligence.error("Personal meditation gen failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        // Fallback canned script
        let who = (name?.isEmpty == false) ? ", \(name!)" : ""
        return "Settle into bed\(who). Take a slow breath in… and a slower breath out. Feel your shoulders soften, your jaw loosen, your eyes heavy. Let today's thoughts drift by like clouds. Breathe in peace. Breathe out tension. Sleep is coming."
    }

    // MARK: - Metric Explainer

    func explainMetric(name: String, value: String, session: SleepSession, recent: [SleepSession]) async -> String? {
        await MainActor.run { isGenerating = true }
        defer { Task { @MainActor in isGenerating = false } }

        let baseline = Self.buildMetricBaseline(name: name, recent: recent)

        #if !targetEnvironment(simulator)
        if #available(iOS 26, *) {
            #if canImport(FoundationModels)
            do {
                AppLogger.intelligence.info("🤖 Explaining metric \(name)…")
                let instructions = Instructions("""
                Explain ONE sleep metric in 2–3 plain sentences.

                HARD RULES:
                • Use only the numbers in the prompt. If no baseline is given, say "not enough history yet" — don't invent one.
                • Compare tonight's value to the baseline if both are present.
                • Suggest at most one concrete next step. No medical claims.
                • Do not speculate about causes unless the prompt names a specific factor.
                """)
                let session = LanguageModelSession(instructions: instructions)
                let prompt = """
                Metric: \(name)
                Tonight's value: \(value)
                \(baseline)

                Explain what this means for this user tonight.
                """
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                AppLogger.intelligence.error("Metric explain failed: \(error.localizedDescription)")
            }
            #endif
        }
        #endif

        return "\(name) tonight: \(value). \(baseline.isEmpty ? "" : baseline) Keep tracking to see how this trends."
    }

    private static func buildMetricBaseline(name: String, recent: [SleepSession]) -> String {
        let lower = name.lowercased()
        if lower.contains("hrv") {
            let values = recent.compactMap(\.hrvAverageMS)
            guard !values.isEmpty else { return "" }
            let avg = values.reduce(0, +) / Double(values.count)
            return "30-day avg HRV: \(Int(avg)) ms."
        }
        if lower.contains("snore") {
            let counts = recent.map(\.snoringCount)
            guard !counts.isEmpty else { return "" }
            let avg = counts.reduce(0, +) / counts.count
            return "30-day avg snore events: \(avg)."
        }
        if lower.contains("heart") {
            let values = recent.compactMap(\.averageHeartRateBPM)
            guard !values.isEmpty else { return "" }
            let avg = values.reduce(0, +) / Double(values.count)
            return "30-day avg overnight HR: \(Int(avg)) bpm."
        }
        return ""
    }

    // MARK: - Fallback Helpers

    private func buildFallbackMorningSummary(session: SleepSession) -> String {
        let totalSeconds = Int(session.durationSeconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let stages = session.sleepStages
        let deepStages = stages.filter { $0.stage == .deep }
        let deepSec = deepStages.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        let deepMinutes = Int(deepSec / 60.0)
        let remStages = stages.filter { $0.stage == .rem }
        let remSec = remStages.reduce(0.0) { $0 + $1.endTime.timeIntervalSince($1.startTime) }
        let remMinutes = Int(remSec / 60.0)

        var summary = "You slept \(hours)h \(minutes)m with a sleep score of \(session.sleepScore)/100."

        if deepMinutes > 0 || remMinutes > 0 {
            summary += " You got \(deepMinutes)m of deep sleep and \(remMinutes)m of REM sleep."
        }

        if session.snoringCount > 0 {
            summary += " \(session.snoringCount) snoring event\(session.snoringCount == 1 ? " was" : "s were") detected."
        }

        if session.sleepScore >= 80 {
            summary += " Great night!"
        } else if session.sleepScore < 50 {
            summary += " Try to get to bed earlier tonight for better rest."
        }

        return summary
    }
}
