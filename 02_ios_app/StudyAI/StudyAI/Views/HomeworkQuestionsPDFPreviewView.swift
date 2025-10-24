//
//  HomeworkQuestionsPDFPreviewView.swift
//  StudyAI
//
//  Created by Claude Code on 10/24/25.
//

import SwiftUI
import PDFKit
import MessageUI

struct HomeworkQuestionsPDFPreviewView: View {
    let homeworkRecord: HomeworkImageRecord
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pdfGenerator = PDFGeneratorService()

    @State private var pdfDocument: PDFDocument?
    @State private var isGenerating = false
    @State private var showingShareSheet = false
    @State private var showingEmailSheet = false
    @State private var pdfURL: URL?
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            VStack {
                if isGenerating {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView(value: pdfGenerator.generationProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding()

                        Text("Generating PDF...")
                            .font(.headline)

                        Text(String(format: "%.0f%%", pdfGenerator.generationProgress * 100))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else if let document = pdfDocument {
                    // PDF preview
                    PDFKitRepresentedView(document: document)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    // Error state
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)

                        Text("Unable to Generate PDF")
                            .font(.headline)

                        Text("No questions found in this homework record.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Close") {
                            dismiss()
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Homework Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                if pdfDocument != nil && !isGenerating {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            // Print button
                            Button(action: handlePrint) {
                                Image(systemName: "printer")
                            }

                            // Share button
                            Button(action: {
                                showingShareSheet = true
                            }) {
                                Image(systemName: "square.and.arrow.up")
                            }

                            // Email button
                            if MFMailComposeViewController.canSendMail() {
                                Button(action: {
                                    showingEmailSheet = true
                                }) {
                                    Image(systemName: "envelope")
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showingEmailSheet) {
            if let url = pdfURL {
                PDFMailComposeView(
                    subject: "Homework Questions",
                    messageBody: "Please find attached the homework questions.",
                    attachmentURL: url,
                    attachmentName: "Homework_Questions_\(homeworkRecord.subject).pdf"
                )
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .task {
            await generatePDF()
        }
    }

    // MARK: - PDF Generation

    private func generatePDF() async {
        // Check if raw questions exist
        guard let rawQuestions = homeworkRecord.rawQuestions, !rawQuestions.isEmpty else {
            errorMessage = "No questions found in this homework record."
            return
        }

        isGenerating = true

        let document = await pdfGenerator.generateRawQuestionsPDF(
            rawQuestions: rawQuestions,
            subject: homeworkRecord.subject,
            date: homeworkRecord.submittedDate,
            accuracy: homeworkRecord.accuracy,
            questionCount: homeworkRecord.questionCount
        )

        await MainActor.run {
            isGenerating = false

            if let document = document {
                pdfDocument = document
                savePDFToTemp(document)
            } else {
                errorMessage = "Failed to generate PDF document."
                showingError = true
            }
        }
    }

    // MARK: - PDF Actions

    private func savePDFToTemp(_ document: PDFDocument) {
        let fileName = "Homework_Questions_\(homeworkRecord.subject)_\(UUID().uuidString).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        if document.write(to: tempURL) {
            pdfURL = tempURL
        }
    }

    private func handlePrint() {
        guard let url = pdfURL else { return }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "Homework Questions - \(homeworkRecord.subject)"

        printController.printInfo = printInfo
        printController.printingItem = url

        printController.present(animated: true) { controller, completed, error in
            if let error = error {
                errorMessage = "Print failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
}

// MARK: - PDFKit View

struct PDFKitRepresentedView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}
