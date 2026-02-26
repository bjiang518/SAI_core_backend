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
            .navigationTitle("PDF Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
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
                // Library questions are text-only — hide image controls
                PDFOptionsSheet(options: $options, hasImages: false) {
                    Task { await generatePDF() }
                }
            }
            .sheet(isPresented: $showingEmailComposer) {
                if let url = pdfURL {
                    PDFMailComposeView(
                        subject: "Library Questions — \(subject)",
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
            ActionButton(icon: "printer.fill",             title: "Print",  color: .blue,   action: handlePrint)
            ActionButton(icon: "envelope.fill",            title: "Email",  color: .green,  action: { showingEmailComposer = true })
            ActionButton(icon: "square.and.arrow.up.fill", title: "Share",  color: .orange, action: { showingShareSheet = true })
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
        printInfo.jobName = "Library Questions — \(subject)"
        printController.printInfo = printInfo
        printController.printingItem = url
        printController.present(animated: true) { _, _, _ in }
    }

    private var emailBody: String {
        """
        Hi there!

        I've attached \(questions.count) library question(s) for \(subject) from StudyMates.

        Generated by StudyMates — Your AI Study Companion

        Best regards
        """
    }
}

#Preview {
    LibraryPDFPreviewView(questions: [], subject: "Mathematics")
}
