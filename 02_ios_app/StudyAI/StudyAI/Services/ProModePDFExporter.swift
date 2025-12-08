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
        croppedImages: [Int: UIImage]
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

        // Filter out archived questions (only export non-archived)
        let questionsToExport = questions.filter { !$0.isArchived }

        exportProgress = 0.1

        // Render cover page
        renderCoverPage(context: pdfContext, pageRect: pageRect, subject: subject, questionCount: questionsToExport.count)

        exportProgress = 0.2

        // ✅ UPDATED: Dynamic page management - add questions until page is full
        var currentY: CGFloat = margin  // Start with top margin
        var pageNumber = 2  // Page 2 (after cover)
        var isFirstQuestionOnPage = true

        for (index, questionWithGrade) in questionsToExport.enumerated() {
            let progress = 0.2 + (Double(index) / Double(questionsToExport.count)) * 0.7
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

            // Start first page after cover if needed
            if index == 0 && currentY == margin {
                pdfContext.beginPDFPage(nil)
            }
        }

        // Close last page if it was started
        if !isFirstQuestionOnPage {
            pdfContext.endPDFPage()
        }

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

    private func renderCoverPage(context: CGContext, pageRect: CGRect, subject: String, questionCount: Int) {
        context.beginPDFPage(nil)

        let centerX = pageRect.width / 2
        var y: CGFloat = 200

        // App title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .bold),
            .foregroundColor: UIColor.systemBlue
        ]
        let titleString = NSAttributedString(string: "StudyAI", attributes: titleAttributes)
        let titleSize = titleString.size()
        titleString.draw(at: CGPoint(x: centerX - titleSize.width / 2, y: y))

        y += titleSize.height + 20

        // Subtitle
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .medium),
            .foregroundColor: UIColor.label
        ]
        let subtitleString = NSAttributedString(string: "Digital Homework Export", attributes: subtitleAttributes)
        let subtitleSize = subtitleString.size()
        subtitleString.draw(at: CGPoint(x: centerX - subtitleSize.width / 2, y: y))

        y += subtitleSize.height + 60

        // Subject
        let subjectAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        let subjectString = NSAttributedString(string: "Subject: \(subject)", attributes: subjectAttributes)
        let subjectSize = subjectString.size()
        subjectString.draw(at: CGPoint(x: centerX - subjectSize.width / 2, y: y))

        y += subjectSize.height + 20

        // Question count
        let countAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .regular),
            .foregroundColor: UIColor.secondaryLabel
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
            .foregroundColor: UIColor.tertiaryLabel
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
            .foregroundColor: UIColor.systemBlue
        ]
        let headerString = NSAttributedString(
            string: "Question \(questionWithGrade.question.questionNumber ?? "?")",
            attributes: headerAttributes
        )
        totalHeight += headerString.size().height + 15

        // Cropped image (if available) - ✅ PROPORTIONAL SIZING
        if let image = croppedImage {
            let maxImageHeight: CGFloat = 200
            let imageAspect = image.size.width / image.size.height
            let imageWidth = contentWidth
            let imageHeight = min(imageWidth / imageAspect, maxImageHeight)
            totalHeight += imageHeight + 15
        }

        // Question text
        let questionTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor.label
        ]
        let questionText = questionWithGrade.question.displayText
        let questionTextSize = (questionText as NSString).boundingRect(
            with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: questionTextAttributes,
            context: nil
        ).size
        totalHeight += questionTextSize.height + 15

        // Student answer (if available)
        let studentAnswer = questionWithGrade.question.displayStudentAnswer
        if !studentAnswer.isEmpty {
            let answerLabelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.systemBlue
            ]
            let answerLabel = NSAttributedString(string: "Student Answer:", attributes: answerLabelAttributes)
            totalHeight += answerLabel.size().height + 5

            let answerTextAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            let answerSize = (studentAnswer as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: answerTextAttributes,
                context: nil
            ).size
            totalHeight += answerSize.height + 15
        }

        // Grade badge and feedback (if graded)
        if let grade = questionWithGrade.grade {
            totalHeight += 10

            // Badge
            let badgeHeight: CGFloat = 30
            totalHeight += badgeHeight + 15

            // Correct answer (if available)
            if let correctAnswer = grade.correctAnswer, !correctAnswer.isEmpty {
                let correctLabelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.systemGreen
                ]
                let correctLabel = NSAttributedString(string: "Correct Answer:", attributes: correctLabelAttributes)
                totalHeight += correctLabel.size().height + 5

                let correctTextAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.label
                ]
                let correctSize = (correctAnswer as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: correctTextAttributes,
                    context: nil
                ).size
                totalHeight += correctSize.height + 15
            }

            // Feedback
            if !grade.feedback.isEmpty {
                let feedbackLabelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let feedbackLabel = NSAttributedString(string: "Feedback:", attributes: feedbackLabelAttributes)
                totalHeight += feedbackLabel.size().height + 5

                let feedbackTextAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let feedbackSize = (grade.feedback as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: feedbackTextAttributes,
                    context: nil
                ).size
                totalHeight += feedbackSize.height + 20
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

        // Question number header
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.systemBlue
        ]
        let headerString = NSAttributedString(
            string: "Question \(questionWithGrade.question.questionNumber ?? "?")",
            attributes: headerAttributes
        )
        headerString.draw(at: CGPoint(x: margin, y: y))
        y += headerString.size().height + 15

        // Cropped image (if available) - ✅ PROPORTIONAL SIZING
        if let image = croppedImage {
            let maxImageHeight: CGFloat = 200
            let imageAspect = image.size.width / image.size.height
            let imageWidth = contentWidth
            // ✅ Respect aspect ratio: calculate height based on width and aspect
            let imageHeight = min(imageWidth / imageAspect, maxImageHeight)

            let imageRect = CGRect(x: margin, y: y, width: imageWidth, height: imageHeight)
            image.draw(in: imageRect)
            y += imageHeight + 15
        }

        // Question text
        let questionTextAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: UIColor.label
        ]

        let questionText = questionWithGrade.question.displayText
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

        // Student answer (if available)
        let studentAnswer = questionWithGrade.question.displayStudentAnswer
        if !studentAnswer.isEmpty {
            let answerLabelAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.systemBlue
            ]
            let answerLabel = NSAttributedString(string: "Student Answer:", attributes: answerLabelAttributes)
            answerLabel.draw(at: CGPoint(x: margin, y: y))
            y += answerLabel.size().height + 5

            let answerTextAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.label
            ]
            let answerSize = (studentAnswer as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: answerTextAttributes,
                context: nil
            ).size

            (studentAnswer as NSString).draw(
                in: CGRect(x: margin, y: y, width: contentWidth, height: answerSize.height),
                withAttributes: answerTextAttributes
            )
            y += answerSize.height + 15
        }

        // Grade badge (if graded)
        if let grade = questionWithGrade.grade {
            y += 10

            // Draw colored background box
            let badgeWidth: CGFloat = 120
            let badgeHeight: CGFloat = 30
            let badgeRect = CGRect(x: margin, y: y, width: badgeWidth, height: badgeHeight)

            let gradeColor: UIColor = grade.isCorrect ? .systemGreen : (grade.score == 0 ? .systemRed : .systemOrange)
            context.setFillColor(gradeColor.withAlphaComponent(0.2).cgColor)
            context.fill(badgeRect)

            // Draw grade text
            let gradeText = String(format: "%.0f%%", grade.score * 100)
            let gradeAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: gradeColor
            ]
            let gradeString = NSAttributedString(string: gradeText, attributes: gradeAttributes)
            let gradeSize = gradeString.size()
            gradeString.draw(at: CGPoint(
                x: margin + (badgeWidth - gradeSize.width) / 2,
                y: y + (badgeHeight - gradeSize.height) / 2
            ))

            y += badgeHeight + 15

            // Correct answer (if available)
            if let correctAnswer = grade.correctAnswer, !correctAnswer.isEmpty {
                let correctLabelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.systemGreen
                ]
                let correctLabel = NSAttributedString(string: "Correct Answer:", attributes: correctLabelAttributes)
                correctLabel.draw(at: CGPoint(x: margin, y: y))
                y += correctLabel.size().height + 5

                let correctTextAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: UIColor.label
                ]
                let correctSize = (correctAnswer as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: correctTextAttributes,
                    context: nil
                ).size

                (correctAnswer as NSString).draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: correctSize.height),
                    withAttributes: correctTextAttributes
                )
                y += correctSize.height + 15
            }

            // Feedback
            if !grade.feedback.isEmpty {
                let feedbackLabelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let feedbackLabel = NSAttributedString(string: "Feedback:", attributes: feedbackLabelAttributes)
                feedbackLabel.draw(at: CGPoint(x: margin, y: y))
                y += feedbackLabel.size().height + 5

                let feedbackTextAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: UIColor.secondaryLabel
                ]
                let feedbackSize = (grade.feedback as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: feedbackTextAttributes,
                    context: nil
                ).size

                (grade.feedback as NSString).draw(
                    in: CGRect(x: margin, y: y, width: contentWidth, height: feedbackSize.height),
                    withAttributes: feedbackTextAttributes
                )
                y += feedbackSize.height + 20
            }
        }

        return y
    }
}
