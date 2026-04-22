//
//  HistoryView.swift
//  sleep
//
//

import SwiftData
import SwiftUI

struct HistoryView: View {

    @Query(sort: \SleepSession.startTime, order: .reverse)
    private var sessions: [SleepSession]

    @Environment(\.modelContext) private var modelContext
    @Environment(SleepSettings.self) private var settings

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No Sleep Data",
                        systemImage: "moon.zzz",
                        description: Text("Start tracking your sleep to see your history here.")
                    )
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(destination: SleepDetailView(session: session)) {
                                SessionRow(session: session, showScore: settings.showSleepScore)
                            }
                        }
                        .onDelete(perform: deleteSessions)
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sessions[index])
        }
        try? modelContext.save()
    }
}

// MARK: - SessionRow

private struct SessionRow: View {

    let session: SleepSession
    let showScore: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.startTime, style: .date)
                    .font(.headline)
                Spacer()
                if showScore {
                    Text("\(session.sleepScore)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(scoreColor)
                }
            }

            HStack {
                Text(FormatHelpers.duration(session.durationSeconds))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Audio indicator — tells the user there are recorded clips
                // they can play back in the detail view. Without this, the
                // playback feature is invisible from the list.
                if session.snoringCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                        Text("\(session.snoringCount)")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.cyan.opacity(0.12))
                    .clipShape(Capsule())
                }

                Spacer()

                // Quality stars
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= session.qualityRating ? "star.fill" : "star")
                            .font(.caption2)
                            .foregroundStyle(star <= session.qualityRating ? .yellow : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var scoreColor: Color {
        let score = session.sleepScore
        if score >= 80 { return .green }
        if score >= 60 { return .yellow }
        if score >= 40 { return .orange }
        return .red
    }
}
