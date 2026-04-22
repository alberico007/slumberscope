//
//  PDFReportGenerator.swift
//  sleep
//
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - PDFReportGenerator

enum PDFReportGenerator {

    // MARK: Page constants

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 50
    private static let contentWidth: CGFloat = 612 - 100 // pageWidth - 2*margin

    // MARK: Generate

    static func generate(
        sessions: [SleepSession],
        from startDate: Date,
        to endDate: Date,
        patientName: String? = nil,
        patientAge: Int? = nil,
        patientPhoto: Data? = nil
    ) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()
            var yPosition: CGFloat = margin

            // Explicit colors — avoid dynamic semantic colors which resolve to
            // white in dark mode and render invisible in PDF viewers.
            let primaryTextColor = UIColor.black
            let secondaryTextColor = UIColor.darkGray
            let tertiaryTextColor = UIColor.gray
            let separatorColor = UIColor.lightGray

            // Patient header (photo + name + age) — clinician needs to ID the
            // person whose report they're holding before glancing at numbers.
            let trimmedName = patientName?.trimmingCharacters(in: .whitespaces) ?? ""
            if !trimmedName.isEmpty || patientPhoto != nil {
                let photoSide: CGFloat = 56
                if let photoData = patientPhoto, let uiImage = UIImage(data: photoData) {
                    let photoRect = CGRect(x: margin, y: yPosition, width: photoSide, height: photoSide)
                    let path = UIBezierPath(ovalIn: photoRect)
                    if let ctx = UIGraphicsGetCurrentContext() {
                        ctx.saveGState()
                        path.addClip()
                        uiImage.draw(in: photoRect)
                        ctx.restoreGState()
                    }
                }
                let textOriginX = (patientPhoto != nil ? margin + photoSide + 14 : margin)
                let nameAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: primaryTextColor
                ]
                let detailAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: secondaryTextColor
                ]
                let nameText = trimmedName.isEmpty ? "Slumberscope User" : trimmedName
                nameText.draw(at: CGPoint(x: textOriginX, y: yPosition + 6),
                              withAttributes: nameAttributes)
                if let age = patientAge, age > 0 {
                    "Age \(age)".draw(at: CGPoint(x: textOriginX, y: yPosition + 28),
                                      withAttributes: detailAttributes)
                }
                yPosition += photoSide + 16
            }

            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: primaryTextColor
            ]
            let title = "Slumberscope Sleep Report"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 36

            // Date range
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let rangeText = "\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))"
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: secondaryTextColor
            ]
            rangeText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: subtitleAttributes)
            yPosition += 30

            // Separator line
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: margin, y: yPosition))
            linePath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            separatorColor.setStroke()
            linePath.lineWidth = 1
            linePath.stroke()
            yPosition += 20

            // Filter sessions in range
            let filtered = sessions.filter { $0.startTime >= startDate && $0.startTime <= endDate }
                .sorted { $0.startTime < $1.startTime }

            // If no sessions at all, use all sessions regardless of date
            let reportSessions = filtered.isEmpty ? sessions.sorted { $0.startTime < $1.startTime } : filtered

            // Summary stats
            let sectionTitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: primaryTextColor
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: primaryTextColor
            ]

            "Summary".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionTitleAttributes)
            yPosition += 28

            let totalSessions = reportSessions.count
            let avgDuration = reportSessions.isEmpty ? 0 : reportSessions.map(\.durationSeconds).reduce(0, +) / Double(reportSessions.count)
            let avgScore = reportSessions.isEmpty ? 0 : reportSessions.map { Double($0.sleepScore) }.reduce(0, +) / Double(reportSessions.count)
            let avgQuality = reportSessions.isEmpty ? 0 : reportSessions.map { Double($0.qualityRating) }.reduce(0, +) / Double(reportSessions.count)

            let summaryLines = [
                "Total Sessions: \(totalSessions)",
                "Average Duration: \(FormatHelpers.duration(avgDuration))",
                "Average Sleep Score: \(Int(avgScore.rounded()))/100",
                "Average Quality: \(String(format: "%.1f", avgQuality))/5"
            ]

            for line in summaryLines {
                line.draw(at: CGPoint(x: margin + 10, y: yPosition), withAttributes: bodyAttributes)
                yPosition += 18
            }

            yPosition += 20

            // Separator
            let line2 = UIBezierPath()
            line2.move(to: CGPoint(x: margin, y: yPosition))
            line2.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
            separatorColor.setStroke()
            line2.lineWidth = 0.5
            line2.stroke()
            yPosition += 20

            // Session details header
            if reportSessions.isEmpty {
                "No sleep sessions recorded yet. Start tracking to generate reports.".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: bodyAttributes)
                yPosition += 28
            }
            "Session Details".draw(at: CGPoint(x: margin, y: yPosition), withAttributes: sectionTitleAttributes)
            yPosition += 28

            // Column headers
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: secondaryTextColor
            ]
            let columnX: [CGFloat] = [margin, margin + 80, margin + 170, margin + 260, margin + 340, margin + 410]
            let headers = ["Date", "Bedtime", "Wake Up", "Duration", "Score", "Quality"]

            for (index, header) in headers.enumerated() {
                header.draw(at: CGPoint(x: columnX[index], y: yPosition), withAttributes: headerAttributes)
            }
            yPosition += 18

            // Session rows
            let rowAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: primaryTextColor
            ]
            let shortDateFormatter = DateFormatter()
            shortDateFormatter.dateFormat = "MMM d"
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"

            for session in reportSessions {
                // Check if we need a new page
                if yPosition > pageHeight - margin - 30 {
                    context.beginPage()
                    yPosition = margin
                }

                let rowData = [
                    shortDateFormatter.string(from: session.startTime),
                    timeFormatter.string(from: session.startTime),
                    timeFormatter.string(from: session.endTime),
                    FormatHelpers.duration(session.durationSeconds),
                    "\(session.sleepScore)",
                    session.quality.label
                ]

                for (index, text) in rowData.enumerated() {
                    text.draw(at: CGPoint(x: columnX[index], y: yPosition), withAttributes: rowAttributes)
                }
                yPosition += 16

                // Notes if present
                if !session.notes.isEmpty {
                    let noteText = "  Notes: \(session.notes)"
                    let noteAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.italicSystemFont(ofSize: 9),
                        .foregroundColor: secondaryTextColor
                    ]
                    let constraintSize = CGSize(width: contentWidth - 20, height: .greatestFiniteMagnitude)
                    let noteRect = (noteText as NSString).boundingRect(
                        with: constraintSize,
                        options: .usesLineFragmentOrigin,
                        attributes: noteAttributes,
                        context: nil
                    )
                    noteText.draw(
                        in: CGRect(x: margin + 10, y: yPosition, width: contentWidth - 20, height: noteRect.height),
                        withAttributes: noteAttributes
                    )
                    yPosition += noteRect.height + 4
                }
            }

            // Footer
            yPosition = pageHeight - margin
            let footerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8, weight: .regular),
                .foregroundColor: tertiaryTextColor
            ]
            let footerDateFormatter = DateFormatter()
            footerDateFormatter.dateStyle = .medium
            footerDateFormatter.timeStyle = .short
            let footer = "Generated by Slumberscope on \(footerDateFormatter.string(from: .now))"
            footer.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: footerAttributes)
        }

        return data
    }
}

// MARK: - PDFDocument (Transferable)

struct PDFTransferableDocument: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { document in
            document.data
        }
    }
}

// MARK: - PDFExportView

struct PDFExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SleepSettings.self) private var settings

    let sessions: [SleepSession]

    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var endDate: Date = .now
    @State private var generatedPDF: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("Date Range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("To", selection: $endDate, displayedComponents: .date)
                }

                Section {
                    Button("Generate Report") {
                        let fullName = [settings.userName, settings.userLastName]
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                        generatedPDF = PDFReportGenerator.generate(
                            sessions: sessions,
                            from: startDate,
                            to: endDate,
                            patientName: fullName,
                            patientAge: settings.userAge,
                            patientPhoto: settings.userPhotoData
                        )
                    }
                }

                if let pdfData = generatedPDF {
                    Section {
                        let document = PDFTransferableDocument(data: pdfData)
                        ShareLink(
                            item: document,
                            preview: SharePreview("Slumberscope Report", image: Image(systemName: "doc.richtext"))
                        ) {
                            Label("Share PDF Report", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .navigationTitle("Export PDF Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
