//
//  PDFPreviewView.swift
//  StudyAI
//
//  PDF Preview for Mistake Review export.
//  Text-only path — image section is hidden in the options sheet.
//

import SwiftUI
import PDFKit
import MessageUI

struct PDFPreviewView: View {
    let questions: [MistakeQuestion]
    let subject: String
    let timeRange: MistakeTimeRange

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
            VStack {
                if isLoading {
                    VStack(spacing: 16) {
                        ProgressView(value: pdfGenerator.generationProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            .frame(width: 200)
                        Text(pdfGenerator.isGenerating ? "Generating PDF..." : "Loading...")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        if pdfGenerator.isGenerating {
                            Text("\(Int(pdfGenerator.generationProgress * 100))% complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document = pdfDocument {
                    VStack(spacing: 0) {
                        PDFKitView(document: document)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        HStack(spacing: 16) {
                            ActionButton(icon: "printer.fill",    title: "Print",  color: .blue,   action: { handlePrint() })
                            ActionButton(icon: "envelope.fill",   title: "Email",  color: .green,  action: { showingEmailComposer = true })
                            ActionButton(icon: "square.and.arrow.up.fill", title: "Share", color: .orange, action: { showingShareSheet = true })
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: -1)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Failed to generate PDF")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Please try again later")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Retry") { Task { await generatePDF() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                // No images in mistake review PDFs
                PDFOptionsSheet(options: $options, hasImages: false) {
                    Task { await generatePDF() }
                }
            }
            .sheet(isPresented: $showingEmailComposer) {
                if let url = pdfURL {
                    PDFMailComposeView(
                        subject: "Study Practice Questions - \(subject)",
                        messageBody: emailBody,
                        attachmentURL: url,
                        attachmentName: "practice-questions.pdf"
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = pdfURL { ShareSheet(items: [url]) }
            }
        }
    }

    // MARK: - Generation

    private func generatePDF() async {
        isLoading = true
        let document = await pdfGenerator.generateMistakesPDF(
            questions: questions,
            subject: subject,
            timeRange: timeRange,
            options: options
        )
        if let document = document {
            self.pdfDocument = document
            await savePDFToTempDirectory(document)
        }
        isLoading = false
    }

    private func savePDFToTempDirectory(_ document: PDFDocument) async {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "practice-questions-\(subject.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Date().timeIntervalSince1970).pdf"
        let url = tempDir.appendingPathComponent(fileName)
        if let data = document.dataRepresentation() {
            try? data.write(to: url)
            self.pdfURL = url
        }
    }

    private func handlePrint() {
        guard let url = pdfURL else { return }
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "StudyMates Practice Questions"
        printController.printInfo = printInfo
        printController.printingItem = url
        printController.present(animated: true) { _, _, _ in }
    }

    private var emailBody: String {
        """
        Hi there!

        I've attached practice questions for \(subject) from my StudyMates study session.

        These are questions I previously got wrong, so I'm practicing them again to reinforce my learning.

        Time period: \(timeRange.rawValue)
        Number of questions: \(questions.count)

        Generated by StudyMates - Your AI Study Companion

        Best regards
        """
    }
}


#Preview {
    PDFPreviewView(
        questions: [
            MistakeQuestion(
                id: "1", subject: "Mathematics", question: "What is 2 + 2?",
                correctAnswer: "4", studentAnswer: "5", explanation: "Simple addition",
                createdAt: Date(), confidence: 0.9, pointsEarned: 0.0, pointsPossible: 1.0,
                tags: [], notes: ""
            )
        ],
        subject: "Mathematics",
        timeRange: .thisWeek
    )
}
