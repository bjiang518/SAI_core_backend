//
//  HomeworkQuestionsPDFPreviewView.swift
//  StudyAI
//
//  PDF Preview for homework album records.
//  Automatically detects whether the record contains images (Pro Mode data)
//  and shows/hides the image-size controls in the options sheet accordingly.
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
    @State private var showingOptions = false
    @State private var showingShareSheet = false
    @State private var showingEmailSheet = false
    @State private var pdfURL: URL?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var options = PDFExportOptions()

    /// True when the record contains Pro Mode data with images.
    /// Drives whether the Images section appears in the options sheet.
    private var hasImages: Bool {
        homeworkRecord.proModeData != nil
    }

    var body: some View {
        NavigationView {
            VStack {
                if isGenerating {
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
                    PDFKitRepresentedView(document: document)
                        .ignoresSafeArea(edges: .bottom)
                } else {
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
                        Button("Close") { dismiss() }
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
                    Button("Close") { dismiss() }
                }
                if pdfDocument != nil && !isGenerating {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack(spacing: 16) {
                            Button {
                                showingOptions = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                            }
                            Button(action: handlePrint) {
                                Image(systemName: "printer")
                            }
                            Button { showingShareSheet = true } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                            if MFMailComposeViewController.canSendMail() {
                                Button { showingEmailSheet = true } label: {
                                    Image(systemName: "envelope")
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            PDFOptionsSheet(options: $options, hasImages: hasImages) {
                Task { await generatePDF() }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL { ShareSheet(items: [url]) }
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
        .task { await generatePDF() }
    }

    // MARK: - PDF Generation

    private func generatePDF() async {
        isGenerating = true

        if let proModeData = homeworkRecord.proModeData,
           let digitalHomework = try? JSONDecoder().decode(DigitalHomeworkData.self, from: proModeData) {
            let document = await pdfGenerator.generateProModePDF(
                digitalHomework: digitalHomework,
                subject: homeworkRecord.subject,
                date: homeworkRecord.submittedDate,
                options: options
            )
            isGenerating = false
            if let document = document {
                pdfDocument = document
                savePDFToTemp(document)
            } else {
                errorMessage = "Failed to generate Pro Mode PDF."
                showingError = true
            }
            return
        }

        guard let rawQuestions = homeworkRecord.rawQuestions, !rawQuestions.isEmpty else {
            errorMessage = "No questions found in this homework record."
            isGenerating = false
            return
        }

        let document = await pdfGenerator.generateRawQuestionsPDF(
            rawQuestions: rawQuestions,
            pageImages: homeworkRecord.imageFileNames.compactMap {
                HomeworkImageStorageService.shared.loadImageByFileName($0)
            },
            subject: homeworkRecord.subject,
            date: homeworkRecord.submittedDate,
            accuracy: homeworkRecord.accuracy,
            questionCount: homeworkRecord.questionCount,
            options: options
        )
        isGenerating = false
        if let document = document {
            pdfDocument = document
            savePDFToTemp(document)
        } else {
            errorMessage = "Failed to generate PDF document."
            showingError = true
        }
    }

    // MARK: - Actions

    private func savePDFToTemp(_ document: PDFDocument) {
        let fileName = "Homework_Questions_\(homeworkRecord.subject)_\(UUID().uuidString).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        if document.write(to: tempURL) { pdfURL = tempURL }
    }

    private func handlePrint() {
        guard let url = pdfURL else { return }
        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = "Homework Questions - \(homeworkRecord.subject)"
        printController.printInfo = printInfo
        printController.printingItem = url
        printController.present(animated: true) { _, _, error in
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
