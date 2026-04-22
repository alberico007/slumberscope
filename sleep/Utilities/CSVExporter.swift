//
//  CSVExporter.swift
//  sleep
//
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - CSVExporter

enum CSVExporter {

    static func generate(sessions: [SleepSession], from startDate: Date, to endDate: Date) -> String {
        let filtered = sessions.filter { $0.startTime >= startDate && $0.startTime <= endDate }
            .sorted { $0.startTime < $1.startTime }

        var csv = "Date,Start,End,Duration,Quality,Score,Avg Movement,Snoring Events,Snoring Duration,Synced to Health\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"

        for session in filtered {
            let date = dateFormatter.string(from: session.startTime)
            let start = timeFormatter.string(from: session.startTime)
            let end = timeFormatter.string(from: session.endTime)
            let duration = FormatHelpers.duration(session.durationSeconds)
            let quality = session.quality.label
            let score = "\(session.sleepScore)"
            let avgMovement = String(format: "%.3f", session.averageMovement)
            let snoringEvents = "\(session.snoringCount)"
            let snoringDuration: String = {
                let events = session.snoringEvents
                let total = events.map(\.duration).reduce(0, +)
                return FormatHelpers.duration(total)
            }()
            let synced = session.syncedToHealthKit ? "Yes" : "No"

            csv += "\(date),\(start),\(end),\(duration),\(quality),\(score),\(avgMovement),\(snoringEvents),\(snoringDuration),\(synced)\n"
        }

        return csv
    }
}

// MARK: - CSVDocument (Transferable)

struct CSVDocument: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            Data(document.text.utf8)
        }
    }
}

// MARK: - CSVExportView

struct CSVExportView: View {
    @Environment(\.dismiss) private var dismiss

    let sessions: [SleepSession]

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var generatedCSV: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }

                Section {
                    Button("Generate CSV") {
                        generatedCSV = CSVExporter.generate(
                            sessions: sessions,
                            from: startDate,
                            to: endDate
                        )
                    }
                }

                if let csvText = generatedCSV {
                    Section {
                        let document = CSVDocument(text: csvText)
                        ShareLink(
                            item: document,
                            preview: SharePreview("Slumberscope Data", image: Image(systemName: "tablecells"))
                        ) {
                            Label("Share CSV File", systemImage: "square.and.arrow.up")
                        }
                    }

                    Section("Preview") {
                        let lines = csvText.components(separatedBy: "\n").prefix(6)
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
