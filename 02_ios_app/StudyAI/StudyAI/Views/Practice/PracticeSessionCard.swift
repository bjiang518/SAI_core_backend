//
//  PracticeSessionCard.swift
//  StudyAI
//
//  Card component for each practice session in the library.
//  Layout: [PDF thumbnail] | [icon · subject · date / type chip / question statuses / progress]
//

import SwiftUI
import PDFKit

struct PracticeSessionCard: View {
    let session: PracticeSession
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var sessionManager = PracticeSessionManager.shared

    @State private var showingPDF = false

    // MARK: – Per-question status

    private enum QuestionStatus { case correct, incorrect, unanswered }

    private var questionStatuses: [QuestionStatus] {
        session.questions.map { q in
            let qId = q.id.uuidString
            guard session.completedQuestionIds.contains(qId) else { return .unanswered }
            let isCorrect = (session.answers[qId]?["is_correct"] as? Bool) ?? false
            return isCorrect ? .correct : .incorrect
        }
    }

    // MARK: – Body

    var body: some View {
        HStack(alignment: .center, spacing: 10) {

            // ── Left box: PDF thumbnail ───────────────────────────────────
            pdfThumbnailBox

            // ── Right box: session info ───────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {

                // Row 1: type icon + subject + date
                HStack(spacing: 8) {
                    Image(systemName: session.generationTypeIcon)
                        .font(.subheadline.bold())
                        .foregroundColor(session.generationTypeColor)

                    Text(PracticeSessionManager.localizeSubject(session.subject))
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(dateLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Row 2: generation type chip
                Text(localizedGenerationType)
                    .font(.caption)
                    .foregroundColor(session.generationTypeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(session.generationTypeColor.opacity(0.12))
                    .cornerRadius(6)

                // Row 3: per-question status symbols + circular progress
                HStack(spacing: 0) {
                    HStack(spacing: 5) {
                        ForEach(questionStatuses.indices, id: \.self) { i in
                            statusSymbol(for: questionStatuses[i])
                        }
                    }
                    Spacer()
                    circularProgress
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colorScheme == .dark ? Color(hex: "2C2A26") : Color.white)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(session.generationTypeColor.opacity(0.35), lineWidth: 0.8)
            )
        }
        .onAppear {
            // Lazily generate PDF for sessions created before this feature
            if session.pdfFileName == nil {
                Task { await PracticeSessionManager.shared.generateAndStorePDF(for: session) }
            }
        }
        .sheet(isPresented: $showingPDF) {
            if let url = currentSession?.pdfFileURL {
                PracticeSessionPDFView(pdfURL: url, session: session)
            }
        }
    }

    /// Look up the live session to get the latest pdfFileURL after background generation.
    private var currentSession: PracticeSession? {
        sessionManager.allSessionsPublished.first(where: { $0.id == session.id }) ?? session
    }

    // MARK: – PDF thumbnail box (standalone card)

    @ViewBuilder
    private var pdfThumbnailBox: some View {
        let liveSession = currentSession
        let hasURL = liveSession?.pdfFileURL != nil

        ZStack {
            colorScheme == .dark ? Color(hex: "2C2A26") : Color.white

            if hasURL, let url = liveSession?.pdfFileURL {
                PDFFirstPageThumbnail(pdfURL: url)
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 22))
                        .foregroundColor(session.generationTypeColor.opacity(0.5))
                    Text("PDF")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(session.generationTypeColor.opacity(0.5))
                }
            }
        }
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(session.generationTypeColor.opacity(0.35), lineWidth: 0.8)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if currentSession?.pdfFileURL != nil { showingPDF = true }
        }
    }

    // MARK: – Circular progress arc

    private var circularProgress: some View {
        let progress = session.progressPercentage
        let size: CGFloat = 36
        let lineWidth: CGFloat = 3.0

        return ZStack {
            Circle()
                .stroke(session.generationTypeColor.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(session.generationTypeColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(progress > 0 ? session.generationTypeColor : .secondary.opacity(0.4))
        }
        .frame(width: size, height: size)
    }

    // MARK: – Status symbol

    @ViewBuilder
    private func statusSymbol(for status: QuestionStatus) -> some View {
        let (iconName, color): (String, Color) = {
            switch status {
            case .correct:    return ("checkmark",  .green)
            case .incorrect:  return ("xmark",      Color(hex: "F26B50"))
            case .unanswered: return ("minus",       Color.secondary.opacity(0.30))
            }
        }()
        Image(systemName: iconName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
    }

    // MARK: – Helpers

    private var localizedGenerationType: String {
        switch session.generationType {
        case "Random Practice":
            return NSLocalizedString("practiceLibrary.typeRandom",       value: "随机练习", comment: "")
        case "Conversation-Based", "Conversation-Based Practice":
            return NSLocalizedString("practiceLibrary.typeConversation", value: "对话复习", comment: "")
        case "Mistake-Based", "Mistake-Based Practice":
            return NSLocalizedString("practiceLibrary.typeMistake",      value: "错题练习", comment: "")
        case "Library-Selection":
            return NSLocalizedString("practiceLibrary.typeLibrary",      value: "题库练习", comment: "")
        default:
            return session.generationType
        }
    }

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(session.createdDate) {
            return NSLocalizedString("common.today", value: "Today", comment: "")
        } else if cal.isDateInYesterday(session.createdDate) {
            return NSLocalizedString("common.yesterday", value: "Yesterday", comment: "")
        }
        let days = cal.dateComponents([.day], from: session.createdDate, to: Date()).day ?? 0
        if days < 7 {
            return String(format: NSLocalizedString("common.daysAgo", value: "%dd ago", comment: ""), days)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: session.createdDate)
    }
}

// MARK: - PDF First-Page Thumbnail

/// Renders the first page of a PDF file as a SwiftUI Image.
private struct PDFFirstPageThumbnail: View {
    let pdfURL: URL

    @State private var thumbnail: UIImage? = nil

    var body: some View {
        Group {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
            } else {
                Color.clear
                    .onAppear { loadThumbnail() }
            }
        }
    }

    private func loadThumbnail() {
        Task.detached(priority: .utility) {
            guard let doc = PDFDocument(url: pdfURL),
                  let page = doc.page(at: 0) else { return }
            let pageRect = page.bounds(for: .mediaBox)
            // Scale to roughly 2× card width for crispness
            let scale: CGFloat = 144 / pageRect.width
            let img = page.thumbnail(of: CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            ), for: .mediaBox)
            await MainActor.run { thumbnail = img }
        }
    }
}

// MARK: - Practice Session PDF Viewer

struct PracticeSessionPDFView: View {
    let pdfURL: URL
    let session: PracticeSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            PDFKitRepresentedView(document: PDFDocument(url: pdfURL) ?? PDFDocument())
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(PracticeSessionManager.localizeSubject(session.subject))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(NSLocalizedString("common.close", value: "Close", comment: "")) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ShareLink(item: pdfURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

