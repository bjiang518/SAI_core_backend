//
//  ProModePDFExporter.swift
//  StudyAI
//
//  Local PDF generation for Pro Mode homework
//  Renders questions directly from SwiftUI views (no AI, no backend)
//

import SwiftUI
import PDFKit
import UIKit
import Combine

@MainActor
class ProModePDFExporter: ObservableObject {

    // MARK: - Published Properties

    @Published var isExporting = false
    @Published var exportProgress: Double = 0.0

    // MARK: - PDF Export

    /// Export Pro Mode homework to PDF
    /// - Parameters:
    ///   - questions: Array of graded questions
    ///   - subject: Subject name
    ///   - totalQuestions: Total question count
    ///   - croppedImages: Dictionary of cropped question images
    /// - Returns: PDF document or nil if failed
    func exportToPDF(
        questions: [ProgressiveQuestionWithGrade],
        subject: String,
        totalQuestions: Int,
        croppedImages: [String: UIImage]  // Changed from [Int: UIImage] to [String: UIImage]
    ) async -> PDFDocument? {
        isExporting = true
        exportProgress = 0.0

        defer {
            isExporting = false
            exportProgress = 0.0
        }

        // Create PDF metadata
        let pdfMetadata: [String: Any] = [
            kCGPDFContextTitle as String: "StudyAI - \(subject) Homework",
            kCGPDFContextCreator as String: "StudyAI Pro Mode",
            kCGPDFContextSubject as String: subject
        ]

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let margin: CGFloat = 60
        let contentWidth = pageRect.width - (margin * 2)
        let maxContentHeight = pageRect.height - (margin * 2)  // Maximum usable height per page

        let pdfData = NSMutableData()

        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: pdfData)!, mediaBox: nil, pdfMetadata as CFDictionary) else {
            print("❌ [PDF Export] Failed to create PDF context")
            return nil
        }

        print("📄 [PDF Export] Starting PDF generation...")
        print("   Subject: \(subject)")
        print("   Total questions: \(totalQuestions)")
        print("   Questions array count: \(questions.count)")

        // Filter out archived questions (only export non-archived)
        let questionsToExport = questions.filter { !$0.isArchived }

        print("   Questions to export (non-archived): \(questionsToExport.count)")

        // If no non-archived questions, export ALL questions instead
        let finalQuestionsToExport = questionsToExport.isEmpty ? questions : questionsToExport

        print("   Final questions to export: \(finalQuestionsToExport.count)")

        exportProgress = 0.1

        // Render cover page
        renderCoverPage(context: pdfContext, pageRect: pageRect, subject: subject, questionCount: finalQuestionsToExport.count)

        exportProgress = 0.2

        // ✅ Start first content page (page 2) immediately after cover
        pdfContext.beginPDFPage(nil)
        drawWhiteBackground(context: pdfContext, rect: pageRect)

        // ✅ UPDATED: Dynamic page management - add questions until page is full
        var currentY: CGFloat = margin  // Start with top margin
        var pageNumber = 2  // Page 2 (after cover)
        var isFirstQuestionOnPage = true

        for (index, questionWithGrade) in finalQuestionsToExport.enumerated() {
            let progress = 0.2 + (Double(index) / Double(finalQuestionsToExport.count)) * 0.7
            exportProgress = progress

            // Calculate how much space this question needs
            let questionHeight = calculateQuestionHeight(
                questionWithGrade: questionWithGrade,
                croppedImage: croppedImages[questionWithGrade.question.id],
                contentWidth: contentWidth
            )

            // ✅ Check if question fits on current page (with spacing)
            let questionSpacing: CGFloat = 24  // Space between questions
            let totalQuestionHeight = questionHeight + (isFirstQuestionOnPage ? 0 : questionSpacing)

            if currentY + totalQuestionHeight > maxContentHeight + margin {
                // Question doesn't fit - start new page
                pdfContext.endPDFPage()
                pdfContext.beginPDFPage(nil)
                drawWhiteBackground(context: pdfContext, rect: pageRect)
                currentY = margin
                pageNumber += 1
                isFirstQuestionOnPage = true
            } else if !isFirstQuestionOnPage {
                // Add spacing before question (not first on page)
                currentY += questionSpacing
            }

            // Render question
            currentY = renderQuestion(
                context: pdfContext,
                pageRect: pageRect,
                questionWithGrade: questionWithGrade,
                croppedImage: croppedImages[questionWithGrade.question.id],
                startY: currentY,
                pageNumber: pageNumber,
                margin: margin,
                contentWidth: contentWidth
            )

            isFirstQuestionOnPage = false
        }

        // ✅ Close the last page
        pdfContext.endPDFPage()

        pdfContext.closePDF()

        exportProgress = 0.95

        // Create PDFDocument from data
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else {
            print("❌ [PDF Export] Failed to create PDFDocument from data")
            return nil
        }

        exportProgress = 1.0

        print("✅ [PDF Export] PDF generated successfully")
        print("   Total pages: \(pdfDocument.pageCount)")
        print("   File size: \(pdfData.length) bytes")

        return pdfDocument
    }

    // MARK: - Cover Page Rendering

    /// Draw white background for PDF pages
    private func drawWhiteBackground(context: CGContext, rect: CGRect) {
        context.setFillColor(UIColor.white.cgColor)
        context.fill(rect)
    }

    private func renderCoverPage(context: CGContext, pageRect: CGRect, subject: String, questionCount: Int) {
        context.beginPDFPage(nil)

        // Draw white background
        drawWhiteBackground(context: context, rect: pageRect)

        // ✅ FIX: Save graphics state to prevent coordinate transformation accumulation
        context.saveGState()
        defer { context.restoreGState() }

        // Push context for UIKit drawing
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        // Flip coordinate system for UIKit (PDF uses bottom-left origin, UIKit uses top-left)
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1.0, y: -1.0)

        let centerX = pageRect.width / 2
        var y: CGFloat = 200

        // App title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .bold),
            .foregroundColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) // Explicit blue
        ]
        let titleString = NSAttributedString(string: "StudyMates", attributes: titleAttributes)
        let titleSize = titleString.size()
        titleString.draw(at: CGPoint(x: centerX - titleSize.width / 2, y: y))

        y += titleSize.height + 20

        // Subtitle
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: UIColor.black // Explicit black
        ]
        let subtitleString = NSAttributedString(string: "Digital Homework Export", attributes: subtitleAttributes)
        let subtitleSize = subtitleString.size()
        subtitleString.draw(at: CGPoint(x: centerX - subtitleSize.width / 2, y: y))

        y += subtitleSize.height + 60

        // Subject
        let subjectAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: UIColor.black // Explicit black
        ]
        let subjectString = NSAttributedString(string: "Subject: \(subject)", attributes: subjectAttributes)
        let subjectSize = subjectString.size()
        subjectString.draw(at: CGPoint(x: centerX - subjectSize.width / 2, y: y))

        y += subjectSize.height + 20

        // Question count
        let countAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.darkGray // Explicit dark gray
        ]
        let countString = NSAttributedString(string: "Total Questions: \(questionCount)", attributes: countAttributes)
        let countSize = countString.size()
        countString.draw(at: CGPoint(x: centerX - countSize.width / 2, y: y))

        y += countSize.height + 20

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .none
        let dateString = dateFormatter.string(from: Date())

        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .regular),
            .foregroundColor: UIColor.gray // Explicit gray
        ]
        let dateAttrString = NSAttributedString(string: dateString, attributes: dateAttributes)
        let dateSize = dateAttrString.size()
        dateAttrString.draw(at: CGPoint(x: centerX - dateSize.width / 2, y: y))

        context.endPDFPage()
    }

    // MARK: - Height Calculation

    /// Calculate the total height required for a question (for page break logic)
    /// - Parameters:
    ///   - questionWithGrade: Question with grading data
    ///   - croppedImage: Optional cropped image
    ///   - contentWidth: Available content width
    /// - Returns: Total height in points
    private func calculateQuestionHeight(
        questionWithGrade: ProgressiveQuestionWithGrade,
        croppedImage: UIImage?,
        contentWidth: CGFloat
    ) -> CGFloat {
        var totalHeight: CGFloat = 0

        // Question header
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0) // Explicit blue
        ]
        let headerString = NSAttributedString(
            string: "Question \(questionWithGrade.question.questionNumber ?? "?")",
            attributes: headerAttributes
        )
        totalHeight += headerString.size().height + 15

        // Cropped image (if available) - ✅ TRUE PROPORTIONAL SIZING (same as rendering)
        if let image = croppedImage {
            let maxImageWidth: CGFloat = contentWidth
            let maxImageHeight: CGFloat = 300
            let imageAspect = image.size.width / image.size.height

            var imageHeight: CGFloat
            if imageAspect > 1 {
                // Wide image
                imageHeight = maxImageWidth / imageAspect
                if imageHeight > maxImageHeight {
                    imageHeight = maxImageHeight
                }
            } else {
                // Tall image
                imageHeight = min(maxImageWidth / imageAspect, maxImageHeight)
            }

            totalHeight += imageHeight + 15
        }

        // Question text
        let questionTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor.black
        ]
        let questionText = questionWithGrade.question.displayText

        if !questionText.isEmpty {
            let questionTextSize = (questionText as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: questionTextAttributes,
                context: nil
            ).size
            totalHeight += questionTextSize.height + 15
        } else {
            // Placeholder text height
            totalHeight += 30
        }

        // ✅ NEW: Add subquestions height
        if let subquestions = questionWithGrade.question.subquestions, !subquestions.isEmpty {
            let subquestionIndent: CGFloat = 20
            let subquestionHeaderAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            ]

            for subquestion in subquestions {
                totalHeight += 10  // Space before subquestion

                // Subquestion header height
                let subHeaderString = NSAttributedString(
                    string: "  (\(subquestion.id)) ",
                    attributes: subquestionHeaderAttributes
                )
                totalHeight += subHeaderString.size().height + 5

                // Subquestion text height
                if !subquestion.questionText.isEmpty {
                    let subTextSize = (subquestion.questionText as NSString).boundingRect(
                        with: CGSize(width: contentWidth - subquestionIndent - 20, height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: questionTextAttributes,
                        context: nil
                    ).size
                    totalHeight += subTextSize.height + 10
                }
            }
        }

        return totalHeight
    }

    // MARK: - Question Rendering

    private func renderQuestion(
        context: CGContext,
        pageRect: CGRect,
        questionWithGrade: ProgressiveQuestionWithGrade,
        croppedImage: UIImage?,
        startY: CGFloat,
        pageNumber: Int,
        margin: CGFloat,
        contentWidth: CGFloat
    ) -> CGFloat {
        var y = startY

        print("   [PDF] Rendering question: \(questionWithGrade.question.questionNumber ?? "?")")
        print("   [PDF] Question text: \(questionWithGrade.question.displayText.prefix(50))...")
        print("   [PDF] Has cropped image: \(croppedImage != nil)")
        print("   [PDF] Has subquestions: \(questionWithGrade.question.isParentQuestion)")

        // ✅ FIX: Save graphics state to prevent coordinate transformation accumulation
        context.saveGState()
        defer { context.restoreGState() }

        // Push context for UIKit drawing
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }

        // Flip coordinate system for UIKit (PDF uses bottom-left origin, UIKit uses top-left)
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1.0, y: -1.0)

        // Question number header
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        ]
        let questionNumberText = questionWithGrade.question.questionNumber ?? "\(questionWithGrade.id)"
        let headerString = NSAttributedString(
            string: "Question \(questionNumberText)",
            attributes: headerAttributes
        )
        headerString.draw(at: CGPoint(x: margin, y: y))
        y += headerString.size().height + 15

        // Cropped image (if available) - ✅ TRUE PROPORTIONAL SIZING
        if let image = croppedImage {
            let maxImageWidth: CGFloat = contentWidth
            let maxImageHeight: CGFloat = 300
            let imageAspect = image.size.width / image.size.height

            // Calculate dimensions that fit within max bounds while maintaining aspect ratio
            var imageWidth: CGFloat
            var imageHeight: CGFloat

            if imageAspect > 1 {
                // Wide image: fit to width
                imageWidth = maxImageWidth
                imageHeight = imageWidth / imageAspect

                // If height exceeds max, scale down proportionally
                if imageHeight > maxImageHeight {
                    imageHeight = maxImageHeight
                    imageWidth = imageHeight * imageAspect
                }
            } else {
                // Tall image: fit to height
                imageHeight = min(maxImageWidth / imageAspect, maxImageHeight)
                imageWidth = imageHeight * imageAspect
            }

            let imageRect = CGRect(x: margin, y: y, width: imageWidth, height: imageHeight)
            image.draw(in: imageRect)
            y += imageHeight + 15

            print("   [PDF] Image rendered: \(imageWidth)x\(imageHeight) (aspect: \(imageAspect))")
        }

        // Question text (for parent questions, this is the main question text)
        let questionTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor.black
        ]

        let questionText = questionWithGrade.question.displayText

        print("   [PDF] Question text length: \(questionText.count)")

        if !questionText.isEmpty {
            let questionTextSize = (questionText as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: questionTextAttributes,
                context: nil
            ).size

            (questionText as NSString).draw(
                in: CGRect(x: margin, y: y, width: contentWidth, height: questionTextSize.height),
                withAttributes: questionTextAttributes
            )
            y += questionTextSize.height + 15
        } else {
            // If no question text, show a placeholder
            let placeholderText = "[Question text not available]"
            let placeholderFont = UIFont.italicSystemFont(ofSize: 14)
            let placeholderAttributes: [NSAttributedString.Key: Any] = [
                .font: placeholderFont,
                .foregroundColor: UIColor.gray
            ]
            (placeholderText as NSString).draw(
                at: CGPoint(x: margin, y: y),
                withAttributes: placeholderAttributes
            )
            y += 30
        }

        // ✅ NEW: Render subquestions if this is a parent question
        if let subquestions = questionWithGrade.question.subquestions, !subquestions.isEmpty {
            print("   [PDF] Rendering \(subquestions.count) subquestions")

            let subquestionIndent: CGFloat = 20
            let subquestionHeaderAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            ]

            for (_, subquestion) in subquestions.enumerated() {
                y += 10  // Space before subquestion

                // Subquestion header (e.g., "(a)" or "(1)")
                let subHeaderString = NSAttributedString(
                    string: "  (\(subquestion.id)) ",
                    attributes: subquestionHeaderAttributes
                )
                subHeaderString.draw(at: CGPoint(x: margin + subquestionIndent, y: y))
                y += subHeaderString.size().height + 5

                // Subquestion text
                if !subquestion.questionText.isEmpty {
                    let subTextSize = (subquestion.questionText as NSString).boundingRect(
                        with: CGSize(width: contentWidth - subquestionIndent - 20, height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: questionTextAttributes,
                        context: nil
                    ).size

                    (subquestion.questionText as NSString).draw(
                        in: CGRect(x: margin + subquestionIndent + 20, y: y, width: contentWidth - subquestionIndent - 20, height: subTextSize.height),
                        withAttributes: questionTextAttributes
                    )
                    y += subTextSize.height + 10
                }
            }
        }

        return y
    }
}
