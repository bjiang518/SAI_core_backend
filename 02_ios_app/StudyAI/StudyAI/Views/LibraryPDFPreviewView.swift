//
//  LibraryPDFPreviewView.swift
//  StudyAI
//
//  PDF preview for questions exported from the Library.
//  Text-only path — image size controls are hidden.
//

import SwiftUI
import PDFKit
import MessageUI

struct LibraryPDFPreviewView: View {
    let questions: [QuestionSummary]
    let subject: String

    @StateObject private var pdfGenerator = PDFGeneratorService()
    @State private var pdfDocument: PDFDocument?
    @State private var isLoading = true
    @State private var showingOptions = false
    @State private var showingEmailComposer = false
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?
    @State private var options = PDFExportOptions()

    @Environment(\.dismiss) private var dismiss

    /// True when any selected question has a non-empty image path — shows image size controls.
    private var hasImages: Bool {
        questions.contains { q in
            if let url = q.questionImageUrl { return !url.isEmpty }
            return false
        }
    }

    var body: some View {
        NavigationView {
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
            .navigationTitle(NSLocalizedString("pdfPreview.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
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
            .task { await generatePDF() }
            .sheet(isPresented: $showingOptions) {
                PDFOptionsSheet(options: $options, hasImages: hasImages) {
                    Task { await generatePDF() }
                }
            }
            .sheet(isPresented: $showingEmailComposer) {
                if let url = pdfURL {
                    PDFMailComposeView(
                        subject: String.localizedStringWithFormat(NSLocalizedString("library.pdf.email.subject", comment: ""), subject),
                        messageBody: emailBody,
                        attachmentURL: url,
                        attachmentName: "library-questions-\(subject.lowercased().replacingOccurrences(of: " ", with: "-")).pdf"
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
            Text(NSLocalizedString("library.pdf.generating", comment: ""))
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
            Text(NSLocalizedString("library.pdf.error", comment: ""))
                .font(.headline)
                .foregroundColor(.secondary)
            Button(NSLocalizedString("common.retry", comment: "")) { Task { await generatePDF() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionBar: some View {
        HStack(spacing: 16) {
            ActionButton(icon: "printer.fill",             title: NSLocalizedString("pdfPreview.print", comment: ""), color: .blue,   action: handlePrint)
            ActionButton(icon: "envelope.fill",            title: NSLocalizedString("pdfPreview.email", comment: ""), color: .green,  action: { showingEmailComposer = true })
            ActionButton(icon: "square.and.arrow.up.fill", title: NSLocalizedString("pdfPreview.share", comment: ""), color: .orange, action: { showingShareSheet = true })
        }
        .padding()
        .background(Color(.systemBackground))
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -1)
    }

    // MARK: - PDF Generation

    private func generatePDF() async {
        isLoading = true
        pdfURL = nil
        let document = await pdfGenerator.generateLibraryPDF(
            questions: questions,
            subject: subject,
            options: options
        )
        pdfDocument = document
        if let document = document { await savePDF(document) }
        isLoading = false
    }

    private func savePDF(_ document: PDFDocument) async {
        let name = "library-\(subject.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Date().timeIntervalSince1970).pdf"
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
        printInfo.jobName = String.localizedStringWithFormat(NSLocalizedString("library.pdf.email.subject", comment: ""), subject)
        printController.printInfo = printInfo
        printController.printingItem = url
        printController.present(animated: true) { _, _, _ in }
    }

    private var emailBody: String {
        String.localizedStringWithFormat(
            NSLocalizedString("library.pdf.emailBody", comment: ""),
            questions.count, subject
        )
    }
}

#Preview {
    LibraryPDFPreviewView(questions: [], subject: "Mathematics")
}
