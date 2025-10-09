//
//  PDFPreviewView.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
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
    @State private var showingPrintOptions = false
    @State private var showingEmailComposer = false
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?
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
                        // PDF Preview
                        PDFKitView(document: document)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Action Buttons
                        HStack(spacing: 16) {
                            ActionButton(
                                icon: "printer.fill",
                                title: "Print",
                                color: .blue,
                                action: { handlePrint() }
                            )

                            ActionButton(
                                icon: "envelope.fill",
                                title: "Email",
                                color: .green,
                                action: { showingEmailComposer = true }
                            )

                            ActionButton(
                                icon: "square.and.arrow.up.fill",
                                title: "Share",
                                color: .orange,
                                action: { showingShareSheet = true }
                            )
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

                        Button("Retry") {
                            Task {
                                await generatePDF()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("PDF Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await generatePDF()
            }
            .sheet(isPresented: $showingEmailComposer) {
                if let url = pdfURL {
                    PDFMailComposeView(
                        subject: "Study Practice Questions - \(subject)",
                        messageBody: createEmailBody(),
                        attachmentURL: url,
                        attachmentName: "practice-questions.pdf"
                    )
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = pdfURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private func generatePDF() async {
        isLoading = true

        do {
            let document = await pdfGenerator.generateMistakesPDF(
                questions: questions,
                subject: subject,
                timeRange: timeRange
            )

            if let document = document {
                self.pdfDocument = document
                // Save to temporary directory for sharing
                await savePDFToTempDirectory(document)
            }
        }

        isLoading = false
    }

    private func savePDFToTempDirectory(_ document: PDFDocument) async {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "practice-questions-\(subject.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Date().timeIntervalSince1970).pdf"
        let url = tempDir.appendingPathComponent(fileName)

        if let data = document.dataRepresentation() {
            do {
                try data.write(to: url)
                self.pdfURL = url
            } catch {
                print("Failed to save PDF to temp directory: \(error)")
            }
        }
    }

    private func createEmailBody() -> String {
        return """
        Hi there!

        I've attached practice questions for \(subject) from my StudyAI study session.

        These are questions I previously got wrong, so I'm practicing them again to reinforce my learning.

        Time period: \(timeRange.rawValue)
        Number of questions: \(questions.count)

        Generated by StudyAI - Your AI Study Companion

        Best regards
        """
    }

    private func handlePrint() {
        guard let url = pdfURL else { return }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "StudyAI Practice Questions"

        printController.printInfo = printInfo
        printController.printingItem = url

        printController.present(animated: true) { (controller, completed, error) in
            if let error = error {
                print("Print error: \(error.localizedDescription)")
            }
        }
    }

}

// MARK: - Supporting Views

struct ActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.backgroundColor = UIColor.systemBackground
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        pdfView.document = document
    }
}

// MailComposeView for PDF attachments (different from the one in ContactSupportView)
struct PDFMailComposeView: UIViewControllerRepresentable {
    let subject: String
    let messageBody: String
    let attachmentURL: URL
    let attachmentName: String

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setSubject(subject)
        composer.setMessageBody(messageBody, isHTML: false)

        if let data = try? Data(contentsOf: attachmentURL) {
            composer.addAttachmentData(data, mimeType: "application/pdf", fileName: attachmentName)
        }

        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: PDFMailComposeView

        init(_ parent: PDFMailComposeView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    PDFPreviewView(
        questions: [
            MistakeQuestion(
                id: "1",
                subject: "Mathematics",
                question: "What is 2 + 2?",
                correctAnswer: "4",
                studentAnswer: "5",
                explanation: "Simple addition",
                createdAt: Date(),
                confidence: 0.9,
                pointsEarned: 0.0,
                pointsPossible: 1.0,
                tags: [],
                notes: ""
            )
        ],
        subject: "Mathematics",
        timeRange: .thisWeek
    )
}