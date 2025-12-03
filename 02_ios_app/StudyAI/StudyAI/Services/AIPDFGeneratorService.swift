//
//  AIPDFGeneratorService.swift
//  StudyAI
//
//  AI-driven PDF generation service for Pro Mode homework
//  Uses AI to generate HTML layout, then renders to PDF locally
//
//  Architecture:
//  1. Prepare data (questions + image metadata, NO base64 images)
//  2. Call backend AI to generate HTML template with placeholders
//  3. Inject base64 images into HTML placeholders locally
//  4. Render HTML to PDF using WKWebView
//

import Foundation
import PDFKit
import WebKit
import UIKit
import Combine

@MainActor
class AIPDFGeneratorService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var isGenerating = false
    @Published var generationProgress: Double = 0.0
    @Published var currentStatus: String = ""

    // MARK: - Dependencies

    private let networkService = NetworkService.shared

    // MARK: - Main Entry Point

    /// Generate Pro Mode PDF using AI-controlled layout
    /// - Parameters:
    ///   - digitalHomework: Digital homework data
    ///   - croppedImages: Question ID → Cropped image mapping
    ///   - subject: Subject name
    ///   - date: Homework date
    /// - Returns: PDFDocument if successful, nil otherwise
    func generateProModePDF(
        digitalHomework: DigitalHomeworkData,
        croppedImages: [Int: UIImage],
        subject: String,
        date: Date
    ) async -> PDFDocument? {
        isGenerating = true
        generationProgress = 0.0
        currentStatus = "Preparing data..."

        defer {
            isGenerating = false
            generationProgress = 0.0
            currentStatus = ""
        }

        // Step 1: Prepare data (metadata only, no images)
        print("📊 [PDF] Step 1: Preparing data...")
        generationProgress = 0.2
        currentStatus = "Analyzing questions..."

        let requestData = prepareDataForAI(
            digitalHomework: digitalHomework,
            croppedImages: croppedImages,
            subject: subject,
            date: date
        )

        // Step 2: Get HTML template from AI
        print("🤖 [PDF] Step 2: Generating HTML layout with AI...")
        generationProgress = 0.4
        currentStatus = "AI is designing layout..."

        guard let htmlTemplate = await generateHTMLTemplate(data: requestData) else {
            print("❌ [PDF] Failed to generate HTML template")
            return nil
        }

        print("✅ [PDF] HTML template generated: \(htmlTemplate.count) characters")

        // Step 3: Inject actual images into HTML
        print("🖼️ [PDF] Step 3: Injecting \(croppedImages.count) images...")
        generationProgress = 0.6
        currentStatus = "Adding images..."

        let finalHTML = injectImages(into: htmlTemplate, images: croppedImages)

        print("✅ [PDF] Images injected, final HTML: \(finalHTML.count) characters")

        // Step 4: Render HTML to PDF
        print("📄 [PDF] Step 4: Rendering HTML to PDF...")
        generationProgress = 0.8
        currentStatus = "Rendering PDF..."

        let pdfDocument = await renderHTMLToPDF(html: finalHTML)

        if let pdfDocument = pdfDocument {
            print("✅ [PDF] PDF generated successfully: \(pdfDocument.pageCount) pages")
        } else {
            print("❌ [PDF] Failed to render PDF")
        }

        generationProgress = 1.0
        currentStatus = "Complete!"

        return pdfDocument
    }

    // MARK: - Step 1: Prepare Data (Metadata Only)

    private func prepareDataForAI(
        digitalHomework: DigitalHomeworkData,
        croppedImages: [Int: UIImage],
        subject: String,
        date: Date
    ) -> [String: Any] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var questionsData: [[String: Any]] = []

        for questionWithGrade in digitalHomework.questions {
            let question = questionWithGrade.question
            var questionData: [String: Any] = [
                "questionNumber": question.questionNumber ?? "\(question.id)",
                "questionText": question.displayText,
                "studentAnswer": question.displayStudentAnswer
            ]

            // Add image metadata (if available) - NO base64 data
            if let image = croppedImages[question.id] {
                let imageId = "img_q\(question.id)"
                questionData["hasImage"] = true
                questionData["imageMetadata"] = [
                    "id": imageId,
                    "width": Int(image.size.width),
                    "height": Int(image.size.height),
                    "aspectRatio": Double(image.size.width / image.size.height)
                ]

                print("  📐 Image metadata for Q\(question.id): \(Int(image.size.width))x\(Int(image.size.height)) (ratio: \(String(format: "%.2f", image.size.width / image.size.height)))")
            } else {
                questionData["hasImage"] = false
            }

            // Handle parent-child questions
            if question.isParentQuestion {
                questionData["parentContent"] = question.parentContent ?? ""

                if let subquestions = question.subquestions {
                    questionData["subquestions"] = subquestions.map { subq in
                        return [
                            "id": subq.id,
                            "questionText": subq.questionText,
                            "studentAnswer": subq.studentAnswer
                        ]
                    }
                }
            }

            questionsData.append(questionData)
        }

        let data: [String: Any] = [
            "subject": subject,
            "date": dateFormatter.string(from: date),
            "totalQuestions": digitalHomework.questions.count,
            "pageSize": [
                "width": 612,
                "height": 792,
                "unit": "points"
            ],
            "questions": questionsData
        ]

        print("📦 [PDF] Prepared data: \(questionsData.count) questions, \(croppedImages.count) images")

        return data
    }

    // MARK: - Step 2: Generate HTML Template from AI

    private func generateHTMLTemplate(data: [String: Any]) async -> String? {
        do {
            let html = try await networkService.generatePDFHTML(data: data)
            return html
        } catch {
            print("❌ [PDF] Failed to generate HTML: \(error)")
            return nil
        }
    }

    // MARK: - Step 3: Inject Base64 Images

    private func injectImages(into html: String, images: [Int: UIImage]) -> String {
        var processedHTML = html
        var injectedCount = 0

        for (questionId, image) in images {
            let imageId = "img_q\(questionId)"

            // Convert image to base64
            guard let base64String = imageToBase64(image: image) else {
                print("⚠️ [PDF] Failed to convert Q\(questionId) image to base64")
                continue
            }

            // Replace placeholder with actual image
            // Look for: data-image-id="img_q1"
            // Replace with: data-image-id="img_q1" src="data:image/jpeg;base64,..."
            let placeholder = "data-image-id=\"\(imageId)\""
            let replacement = "data-image-id=\"\(imageId)\" src=\"\(base64String)\""

            if processedHTML.contains(placeholder) {
                processedHTML = processedHTML.replacingOccurrences(
                    of: placeholder,
                    with: replacement
                )
                injectedCount += 1
                print("  ✅ Injected image for Q\(questionId) (\(base64String.count) chars)")
            } else {
                print("  ⚠️ Placeholder not found for Q\(questionId)")
            }
        }

        print("📸 [PDF] Injected \(injectedCount)/\(images.count) images")

        return processedHTML
    }

    private func imageToBase64(image: UIImage) -> String? {
        // Compress image to reasonable size (0.8 quality JPEG)
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        let base64String = imageData.base64EncodedString()
        return "data:image/jpeg;base64,\(base64String)"
    }

    // MARK: - Step 4: Render HTML to PDF

    private func renderHTMLToPDF(html: String) async -> PDFDocument? {
        return await withCheckedContinuation { continuation in
            // Create WKWebView for rendering
            let configuration = WKWebViewConfiguration()
            configuration.suppressesIncrementalRendering = false  // Allow progressive rendering

            let webView = WKWebView(frame: .zero, configuration: configuration)

            // Set up navigation delegate to detect when page is fully loaded
            let delegate = WebViewNavigationDelegate { [weak webView] success in
                guard let webView = webView else {
                    print("❌ [PDF] WebView deallocated")
                    continuation.resume(returning: nil)
                    return
                }

                if !success {
                    print("❌ [PDF] Page failed to load")
                    continuation.resume(returning: nil)
                    return
                }

                print("✅ [PDF] Page loaded, waiting for rendering...")

                // Wait longer for images to decode and render (5 seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    let pdfConfiguration = WKPDFConfiguration()
                    pdfConfiguration.rect = .zero  // Use entire page (respects @page CSS)

                    print("📄 [PDF] Creating PDF from rendered page...")

                    webView.createPDF(configuration: pdfConfiguration) { result in
                        switch result {
                        case .success(let pdfData):
                            print("✅ [PDF] PDF data created: \(pdfData.count) bytes")
                            let pdfDocument = PDFDocument(data: pdfData)
                            continuation.resume(returning: pdfDocument)
                        case .failure(let error):
                            print("❌ [PDF] Rendering failed: \(error.localizedDescription)")
                            print("   Error domain: \(error._domain)")
                            print("   Error code: \(error._code)")
                            continuation.resume(returning: nil)
                        }
                    }
                }
            }

            webView.navigationDelegate = delegate

            // Load HTML
            print("📄 [PDF] Loading HTML into WebView...")
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

// MARK: - WebView Navigation Delegate

private class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {
    let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ [PDF] WebView finished loading")
        completion(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ [PDF] WebView failed to load: \(error.localizedDescription)")
        completion(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ [PDF] WebView provisional load failed: \(error.localizedDescription)")
        completion(false)
    }
}
