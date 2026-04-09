//
//  DigitalHomeworkPDFPreviewView.swift
//  StudyAI
//
//  PDF Preview for Digital Homework Export.
//  Includes a customisation sheet (PDFOptionsSheet) where the user can adjust
//  font size, question gap, and image size. The image section is always shown
//  here because this path always contains images.
//

import SwiftUI
import PDFKit
import MessageUI

struct DigitalHomeworkPDFPreviewView: View {
    let subject: String
    let questionCount: Int
    let questions: [ProgressiveQuestionWithGrade]
    let croppedImages: [String: UIImage]

    @StateObject private var pdfGenerator = PDFGeneratorService()
    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true

    @State private var showingOptions = false
    @State private var showingEmailComposer = false
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?

    @State private var options = PDFExportOptions()

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if let document = pdfDocument {
                    VStack(spacing: 0) {
                        PDFKitView(document: document)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        actionBar
                    }
                } else {
                    errorView
                }
            }
            .navigationTitle(NSLocalizedString("pdfPreview.title", comment: "PDF Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.done", comment: "Done")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingOptions = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                AppLogger.forFeature("PDFGen").info("▶︎ DigitalHomeworkPDFPreviewView appeared — questions=\(questions.count) croppedImages=\(croppedImages.count)")
                await generatePDF()
            }
            .sheet(isPresented: $showingOptions) {
                PDFOptionsSheet(options: $options, hasImages: true) {
                    Task { await generatePDF() }
                }
            }
            .sheet(isPresented: $showingEmailComposer) {
                if let url = pdfURL {
                    PDFMailComposeView(
                        subject: "StudyAgent - \(subject) Digital Homework",
                        messageBody: emailBody,
                        attachmentURL: url,
                        attachmentName: "digital-homework-\(subject.lowercased().replacingOccurrences(of: " ", with: "-")).pdf"
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = pdfURL { ShareSheet(items: [url]) }
            }
        }
    }

    // MARK: - Sub-views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView(value: pdfGenerator.generationProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                .frame(width: 200)
            Text("Generating PDF…")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("\(Int(pdfGenerator.generationProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Failed to generate PDF")
                .font(.headline)
                .foregroundColor(.secondary)
            Button("Retry") { Task { await generatePDF() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            ActionButton(
                icon: "printer.fill",
                title: NSLocalizedString("pdfPreview.print", comment: "Print"),
                color: .blue,
                action: { handlePrint() }
            )
            ActionButton(
                icon: "envelope.fill",
                title: NSLocalizedString("pdfPreview.email", comment: "Email"),
                color: .green,
                action: { showingEmailComposer = true }
            )
            ActionButton(
                icon: "square.and.arrow.up.fill",
                title: NSLocalizedString("pdfPreview.share", comment: "Share"),
                color: .orange,
                action: { showingShareSheet = true }
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -1)
    }

    // MARK: - PDF Generation

    private func generatePDF() async {
        let log = AppLogger.forFeature("PDFGen")
        log.info("▶︎ DigitalHomeworkPDFPreviewView.generatePDF() — questions=\(questions.count) croppedImages=\(croppedImages.count) subject='\(subject)'")

        isLoading = true
        pdfURL = nil
        let document = await pdfGenerator.generateProModePDF(
            questions: questions,
            subject: subject,
            croppedImages: croppedImages,
            includeArchived: true,
            options: options
        )
        log.info("  generateProModePDF returned: \(document != nil ? "✓ doc with \(document!.pageCount) pages" : "nil")")
        pdfDocument = document
        if let document = document { await savePDF(document) }
        isLoading = false
    }

    private func savePDF(_ document: PDFDocument) async {
        let name = "digital-homework-\(subject.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Date().timeIntervalSince1970).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if let data = document.dataRepresentation() {
            try? data.write(to: url)
            pdfURL = url
        }
    }

    // MARK: - Actions

    private func handlePrint() {
        guard let url = pdfURL else { return }
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "StudyAgent - \(subject) Digital Homework"
        printController.printInfo = printInfo
        printController.printingItem = url
        printController.present(animated: true) { _, _, _ in }
    }

    private var emailBody: String {
        """
        Hi there!

        I've attached my digital homework for \(subject) from StudyAgent.

        Subject: \(subject)
        Number of questions: \(questionCount)
        Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none))

        Generated by StudyAgent - Your AI Study Companion

        Best regards
        """
    }
}

// MARK: - Preview

#Preview {
    DigitalHomeworkPDFPreviewView(
        subject: "Mathematics",
        questionCount: 3,
        questions: [],
        croppedImages: [:]
    )
}
