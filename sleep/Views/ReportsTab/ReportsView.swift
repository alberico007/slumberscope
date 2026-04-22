//
//  ReportsView.swift
//  sleep
//
//

import Charts
import SwiftData
import SwiftUI

// MARK: - ReportsPeriod

enum ReportsPeriod: String, CaseIterable, Identifiable {
    case week = "7 Days"
    case month = "30 Days"
    case threeMonths = "90 Days"
    case year = "1 Year"

    var id: String { rawValue }
    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .threeMonths: 90
        case .year: 365
        }
    }
}

// MARK: - ReportsTab

enum ReportsTab: String, CaseIterable, Identifiable {
    case trends = "Trends"
    case factors = "Factors"
    case recordings = "Recordings"
    case history = "History"
    case chat = "Ask AI"

    var id: String { rawValue }
}

// MARK: - ReportsView

struct ReportsView: View {

    @Query(sort: \SleepSession.startTime, order: .reverse)
    private var allSessions: [SleepSession]

    @Query(sort: \SleepFactor.date, order: .reverse)
    private var allFactors: [SleepFactor]

    @Environment(SleepSettings.self) private var settings
    @Environment(IntelligenceService.self) private var intelligenceService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: ReportsTab = .trends
    @State private var selectedPeriod: ReportsPeriod = .week
    @State private var selectedEventFilter: AudioEventType? = nil
    @State private var storeKitService = StoreKitService()
    @State private var showingPDFExport = false
    @State private var showingCSVExport = false

    // Weekly narrative
    @State private var weeklyNarrative: String? = nil
    @State private var isGeneratingNarrative = false

    // Chat with sleep
    @State private var chatInput: String = ""
    @State private var chatMessages: [ChatMessage] = []
    @State private var isChatAnswering = false

    private var filteredSessions: [SleepSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedPeriod.days, to: .now) ?? .now
        return allSessions.filter { $0.startTime >= cutoff }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Section", selection: $selectedTab) {
                    ForEach(ReportsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Period selector (for trends/factors)
                if selectedTab == .trends || selectedTab == .factors {
                    Picker("Period", selection: $selectedPeriod) {
                        ForEach(ReportsPeriod.allCases) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 6)
                }

                // Content
                if (selectedTab == .trends || selectedTab == .factors) &&
                    (selectedPeriod == .threeMonths || selectedPeriod == .year) &&
                    !storeKitService.isPremium {
                    PremiumLockOverlay(feature: "90-day and 1-year trends require Premium. Upgrade to see long-term patterns.")
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            switch selectedTab {
                            case .trends:
                                trendsContent
                            case .factors:
                                factorContent
                            case .recordings:
                                recordingsContent
                            case .history:
                                historyContent
                            case .chat:
                                chatContent
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Reports")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingPDFExport = true
                        } label: {
                            Label("Export PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            showingCSVExport = true
                        } label: {
                            Label("Export CSV", systemImage: "tablecells")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingPDFExport) {
                PDFExportView(sessions: allSessions)
            }
            .sheet(isPresented: $showingCSVExport) {
                CSVExportView(sessions: allSessions)
            }
        }
    }

    // MARK: - Trends

    @ViewBuilder
    private var trendsContent: some View {
        if filteredSessions.isEmpty {
            ContentUnavailableView("No Data", systemImage: "chart.line.uptrend.xyaxis", description: Text("Track sleep to see trends."))
        } else {
            weeklyNarrativeCard

            // Average score
            if settings.showSleepScore {
                let avgScore = filteredSessions.map(\.sleepScore).reduce(0, +) / filteredSessions.count
                GlassCard {
                    VStack(spacing: 8) {
                        Text("Average Sleep Score")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(avgScore)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(avgScore >= 80 ? .green : avgScore >= 60 ? .yellow : .orange)
                        Text("out of 100")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Summary stats
            let avgDuration = filteredSessions.map(\.durationSeconds).reduce(0, +) / Double(filteredSessions.count)
            let avgQuality = filteredSessions.map { Double($0.qualityRating) }.reduce(0, +) / Double(filteredSessions.count)
            let avgEfficiency = filteredSessions.map(\.sleepEfficiency).reduce(0, +) / Double(filteredSessions.count)

            GlassCard {
                VStack(spacing: 12) {
                    StatRow(icon: "clock", label: "Avg Duration", value: FormatHelpers.duration(avgDuration))
                    Divider()
                    StatRow(icon: "star.fill", label: "Avg Quality", value: String(format: "%.1f/5", avgQuality))
                    Divider()
                    StatRow(icon: "percent", label: "Avg Efficiency", value: FormatHelpers.percentage(avgEfficiency))
                    Divider()
                    StatRow(icon: "bed.double.fill", label: "Nights Tracked", value: "\(filteredSessions.count)")
                }
            }

            // Score trend
            InfoFlipCard(
                title: "Sleep Score Trend",
                explanation: "This chart plots your overall Sleep Score for every night in the selected range. Each score is calculated out of 100 points and combines four signals: time slept (up to 35 points, best at 7 to 9 hours), the star rating you gave your morning review (up to 30 points), how still you were during the night (up to 20 points from motion data), and how few snoring events were detected (up to 15 points). A rising line usually means your routine is paying off."
            ) {
                Chart(filteredSessions.reversed()) { session in
                    LineMark(
                        x: .value("Date", session.startTime, unit: .day),
                        y: .value("Score", session.sleepScore)
                    )
                    .foregroundStyle(.cyan)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", session.startTime, unit: .day),
                        y: .value("Score", session.sleepScore)
                    )
                    .foregroundStyle(.cyan)
                    .symbolSize(30)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
            }

            // Duration trend
            InfoFlipCard(
                title: "Duration Trend",
                explanation: "This bar chart shows how long you slept each night. The target range for most adults is 7 to 9 hours. The vertical axis adapts to your longest night so short naps or test runs are still readable in 15 or 30 minute increments, while a regular full night shows clean whole hour ticks."
            ) {
                DurationTrendChart(sessions: filteredSessions.reversed())
                    .frame(height: 180)
            }

            // Bedtime consistency
            InfoFlipCard(
                title: "Bedtime Consistency",
                explanation: "Each dot is the hour of the night you started tracking. A tight cluster means you are going to bed around the same time every night, which research links to better sleep quality. A scattered plot means your schedule is irregular, which can make it harder to fall asleep and wake up refreshed."
            ) {
                Chart(filteredSessions.reversed()) { session in
                    let hour = Calendar.current.component(.hour, from: session.startTime)
                    let minute = Calendar.current.component(.minute, from: session.startTime)
                    let timeValue = Double(hour) + Double(minute) / 60.0
                    PointMark(
                        x: .value("Date", session.startTime, unit: .day),
                        y: .value("Bedtime", timeValue)
                    )
                    .foregroundStyle(.indigo)
                    .symbolSize(40)
                }
                .frame(height: 150)
            }
        }
    }

    // MARK: - Weekly Narrative

    @ViewBuilder
    private var weeklyNarrativeCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "text.book.closed.fill")
                        .foregroundStyle(.indigo)
                    Text("This Week's Story")
                        .font(.headline)
                    Spacer()
                    if intelligenceService.isAvailable {
                        Text("Apple Intelligence")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await generateNarrative() }
                    } label: {
                        Image(systemName: isGeneratingNarrative ? "hourglass" : "arrow.clockwise")
                            .font(.caption)
                    }
                    .disabled(isGeneratingNarrative)
                }

                if isGeneratingNarrative {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Writing your week…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if let text = weeklyNarrative {
                    Text(text)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tap to generate a short narrative about this week's sleep patterns.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Generate") {
                        Task { await generateNarrative() }
                    }
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.15))
                    .foregroundStyle(.indigo)
                    .clipShape(Capsule())
                }
            }
        }
    }

    @MainActor
    private func generateNarrative() async {
        isGeneratingNarrative = true
        defer { isGeneratingNarrative = false }
        weeklyNarrative = await intelligenceService.generateWeeklyNarrative(sessions: filteredSessions)
    }

    // MARK: - Chat with Sleep

    struct ChatMessage: Identifiable {
        let id = UUID()
        let isUser: Bool
        let text: String
    }

    @ViewBuilder
    private var chatContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassCard {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask your sleep").font(.headline)
                        Text(intelligenceService.isAvailable
                             ? "Apple Intelligence answers questions using your own \(allSessions.count) nights of data. On-device, private."
                             : "Requires an Apple Intelligence-capable iPhone. Basic answers still work from your data.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if allSessions.isEmpty {
                GlassCard {
                    HStack(spacing: 10) {
                        Image(systemName: "bed.double.fill").foregroundStyle(.secondary)
                        Text("Track at least one night to unlock chat answers.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if chatMessages.isEmpty {
                exampleChips
            }

            ForEach(chatMessages) { msg in
                HStack {
                    if msg.isUser { Spacer() }
                    Text(msg.text)
                        .font(.subheadline)
                        .padding(10)
                        .background(msg.isUser ? Color.cyan.opacity(0.18) : Color.secondary.opacity(0.1))
                        .foregroundStyle(msg.isUser ? .cyan : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: 340, alignment: msg.isUser ? .trailing : .leading)
                    if !msg.isUser { Spacer() }
                }
            }

            if isChatAnswering {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Ask anything about your sleep", text: $chatInput, axis: .vertical)
                    .lineLimit(1...3)
                    .padding(10)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button {
                    Task { await sendChat() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(chatInput.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary : Color.cyan)
                }
                .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || isChatAnswering)
            }
        }
    }

    private var exampleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chatExamples, id: \.self) { q in
                    Button(q) {
                        chatInput = q
                        Task { await sendChat() }
                    }
                    .font(.caption).fontWeight(.semibold)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.15))
                    .foregroundStyle(.cyan)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var chatExamples: [String] {
        ["Why did I sleep worse last night?",
         "What's my best night this week?",
         "Am I getting enough REM?",
         "What factor hurts me most?"]
    }

    @MainActor
    private func sendChat() async {
        let trimmed = chatInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        chatMessages.append(ChatMessage(isUser: true, text: trimmed))
        chatInput = ""
        isChatAnswering = true
        defer { isChatAnswering = false }
        if let reply = await intelligenceService.answerQuestion(trimmed, sessions: allSessions) {
            chatMessages.append(ChatMessage(isUser: false, text: reply))
        } else {
            chatMessages.append(ChatMessage(isUser: false, text: "Couldn't generate an answer. Try a different question."))
        }
    }

    // MARK: - Factors

    @ViewBuilder
    private var factorContent: some View {
        let correlations = FactorService.analyzeCorrelations(factors: allFactors, sessions: Array(filteredSessions))

        if correlations.isEmpty {
            ContentUnavailableView("Not Enough Data", systemImage: "chart.bar.fill", description: Text("Log factors before sleep to see correlations. Minimum 3 nights with and without each factor."))
        } else {
            ForEach(correlations) { corr in
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: corr.factorType.icon)
                                .foregroundStyle(corr.factorType.color)
                            Text(corr.factorType.label)
                                .font(.headline)
                            Spacer()
                            Image(systemName: corr.isPositive ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .foregroundStyle(corr.isPositive ? .green : .red)
                        }

                        Text(corr.insight)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 0) {
                            VStack {
                                Text("\(Int(corr.withFactor.rounded()))")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("With")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(corr.nightsWithFactor) nights")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)

                            Text("vs")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            VStack {
                                Text("\(Int(corr.withoutFactor.rounded()))")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("Without")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(corr.nightsWithoutFactor) nights")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recordings

    @ViewBuilder
    private var recordingsContent: some View {
        let sessionsWithSnoring = allSessions.filter { $0.snoringCount > 0 }
        if sessionsWithSnoring.isEmpty {
            ContentUnavailableView("No Recordings", systemImage: "waveform", description: Text("Audio events will appear here after sleep tracking."))
        } else {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(label: "All", isSelected: selectedEventFilter == nil) {
                        selectedEventFilter = nil
                    }
                    ForEach(AudioEventType.allCases) { eventType in
                        FilterChip(
                            label: eventType.rawValue,
                            icon: eventType.icon,
                            color: eventType.color,
                            isSelected: selectedEventFilter == eventType
                        ) {
                            selectedEventFilter = eventType
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Event count summary
            let allEvents = sessionsWithSnoring.flatMap(\.snoringEvents)
            let classifiedEvents = allEvents.map { event in
                (event: event, type: AudioEventType.classify(amplitude: event.averageAmplitude, duration: event.duration))
            }
            let filteredEvents = selectedEventFilter == nil
                ? classifiedEvents
                : classifiedEvents.filter { $0.type == selectedEventFilter }

            GlassCard {
                HStack {
                    Label("\(filteredEvents.count) events", systemImage: "waveform")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    if let filter = selectedEventFilter {
                        Text(filter.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(filter.color.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }

            // Sessions with events
            ForEach(sessionsWithSnoring.prefix(20)) { session in
                let sessionEvents = session.snoringEvents.map { event in
                    (event: event, type: AudioEventType.classify(amplitude: event.averageAmplitude, duration: event.duration))
                }
                let visibleEvents = selectedEventFilter == nil
                    ? sessionEvents
                    : sessionEvents.filter { $0.type == selectedEventFilter }

                if !visibleEvents.isEmpty {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(session.startTime, style: .date)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(visibleEvents.count) events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(visibleEvents.prefix(5), id: \.event.id) { item in
                                AudioPlayerView(event: item.event, eventType: item.type)
                                if item.event.id != visibleEvents.prefix(5).last?.event.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - FilterChip

    private struct FilterChip: View {
        let label: String
        var icon: String? = nil
        var color: Color = .cyan
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption2)
                    }
                    Text(label)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.1))
                .foregroundStyle(isSelected ? color : .secondary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - History

    @ViewBuilder
    private var historyContent: some View {
        if allSessions.isEmpty {
            ContentUnavailableView("No Sleep Data", systemImage: "moon.zzz", description: Text("Start tracking your sleep to see history."))
        } else {
            ForEach(allSessions) { session in
                NavigationLink(destination: SleepDetailView(session: session)) {
                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.startTime, style: .date)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(FormatHelpers.duration(session.durationSeconds))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if settings.showSleepScore {
                                Text("\(session.sleepScore)")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(session.sleepScore >= 80 ? .green : session.sleepScore >= 60 ? .yellow : .orange)
                            }

                            HStack(spacing: 2) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= session.qualityRating ? "star.fill" : "star")
                                        .font(.system(size: 8))
                                        .foregroundStyle(star <= session.qualityRating ? .yellow : .secondary)
                                }
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
