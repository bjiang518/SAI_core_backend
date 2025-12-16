//
//  PDFGeneratorService.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import Foundation
import PDFKit
import UIKit
import SwiftUI
import Combine

@MainActor
class PDFGeneratorService: ObservableObject {
    @Published var isGenerating = false
    @Published var generationProgress: Double = 0.0

    // MARK: - Public Methods

    /// Generate PDF for generated practice questions
    func generatePracticePDF(
        questions: [QuestionGenerationService.GeneratedQuestion],
        subject: String,
        generationType: String
    ) async -> PDFDocument? {
        isGenerating = true
        generationProgress = 0.0

        defer {
            isGenerating = false
            generationProgress = 0.0
        }

        let pdfDocument = PDFDocument()
        let questionsPerPage = 2
        let totalPages = Int(ceil(Double(questions.count) / Double(questionsPerPage)))

        for pageIndex in 0..<totalPages {
            let startIndex = pageIndex * questionsPerPage
            let endIndex = min(startIndex + questionsPerPage, questions.count)
            let pageQuestions = Array(questions[startIndex..<endIndex])

            if let pdfPage = await createPracticePDFPage(
                questions: pageQuestions,
                pageNumber: pageIndex + 1,
                totalPages: totalPages,
                subject: subject,
                generationType: generationType
            ) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }

            // Update progress
            generationProgress = Double(pageIndex + 1) / Double(totalPages)
        }

        return pdfDocument.pageCount > 0 ? pdfDocument : nil
    }

    func generateMistakesPDF(
        questions: [MistakeQuestion],
        subject: String,
        timeRange: MistakeTimeRange
    ) async -> PDFDocument? {
        isGenerating = true
        generationProgress = 0.0

        defer {
            isGenerating = false
            generationProgress = 0.0
        }

        let pdfDocument = PDFDocument()
        let questionsPerPage = 2
        let totalPages = Int(ceil(Double(questions.count) / Double(questionsPerPage)))

        for pageIndex in 0..<totalPages {
            let startIndex = pageIndex * questionsPerPage
            let endIndex = min(startIndex + questionsPerPage, questions.count)
            let pageQuestions = Array(questions[startIndex..<endIndex])

            if let pdfPage = await createPDFPage(
                questions: pageQuestions,
                pageNumber: pageIndex + 1,
                totalPages: totalPages,
                subject: subject,
                timeRange: timeRange
            ) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }

            // Update progress
            generationProgress = Double(pageIndex + 1) / Double(totalPages)
        }

        return pdfDocument.pageCount > 0 ? pdfDocument : nil
    }

    /// Generate PDF for raw homework questions (from homework album)
    func generateRawQuestionsPDF(
        rawQuestions: [String],
        subject: String,
        date: Date,
        accuracy: Float,
        questionCount: Int
    ) async -> PDFDocument? {
        isGenerating = true
        generationProgress = 0.0

        defer {
            isGenerating = false
            generationProgress = 0.0
        }

        let pdfDocument = PDFDocument()
        let questionsPerPage = 3 // 3 questions per page for readability
        let totalPages = Int(ceil(Double(rawQuestions.count) / Double(questionsPerPage)))

        for pageIndex in 0..<totalPages {
            let startIndex = pageIndex * questionsPerPage
            let endIndex = min(startIndex + questionsPerPage, rawQuestions.count)
            let pageQuestions = Array(rawQuestions[startIndex..<endIndex])

            if let pdfPage = await createRawQuestionsPDFPage(
                questions: pageQuestions,
                pageNumber: pageIndex + 1,
                totalPages: totalPages,
                subject: subject,
                date: date,
                accuracy: accuracy,
                questionCount: questionCount,
                startQuestionNumber: startIndex + 1
            ) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }

            // Update progress
            generationProgress = Double(pageIndex + 1) / Double(totalPages)
        }

        return pdfDocument.pageCount > 0 ? pdfDocument : nil
    }

    // MARK: - Private Methods

    private func createPracticePDFPage(
        questions: [QuestionGenerationService.GeneratedQuestion],
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        generationType: String
    ) async -> PDFPage? {
        let pageSize = CGSize(width: 612, height: 792) // US Letter: 8.5" x 11" at 72 DPI
        let renderer = UIGraphicsImageRenderer(size: pageSize)

        let image = renderer.image { context in
            let cgContext = context.cgContext

            // Set up drawing context
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: pageSize))

            // Draw the page content
            drawPracticePageContent(
                in: cgContext,
                pageSize: pageSize,
                questions: questions,
                pageNumber: pageNumber,
                totalPages: totalPages,
                subject: subject,
                generationType: generationType
            )
        }

        // Convert UIImage to PDFPage
        let pdfPage = PDFPage(image: image)
        return pdfPage
    }

    private func drawPracticePageContent(
        in context: CGContext,
        pageSize: CGSize,
        questions: [QuestionGenerationService.GeneratedQuestion],
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        generationType: String
    ) {
        let margin: CGFloat = 54 // 0.75 inch margins at 72 DPI
        let contentWidth = pageSize.width - (2 * margin)
        var currentY: CGFloat = margin

        // Header
        currentY = drawPracticeHeader(
            in: context,
            x: margin,
            y: currentY,
            width: contentWidth,
            subject: subject,
            generationType: generationType
        )

        currentY += 30 // Space after header

        // Questions
        for (index, question) in questions.enumerated() {
            let questionHeight = drawPracticeQuestion(
                in: context,
                x: margin,
                y: currentY,
                width: contentWidth,
                question: question,
                questionNumber: ((pageNumber - 1) * 2) + index + 1
            )
            currentY += questionHeight + 40 // Space between questions
        }

        // Footer
        drawFooter(
            in: context,
            pageSize: pageSize,
            pageNumber: pageNumber,
            totalPages: totalPages
        )
    }

    private func drawPracticeHeader(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        subject: String,
        generationType: String
    ) -> CGFloat {
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        let dateFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        var currentY = y

        // Title
        let title = "Practice Questions"
        drawText(
            title,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: titleFont,
            color: UIColor.black,
            alignment: .center
        )
        currentY += 25

        // Subject
        let subjectText = "Subject: \(subject)"
        drawText(
            subjectText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: subtitleFont,
            color: UIColor.darkGray,
            alignment: .left
        )
        currentY += 18

        // Generation type and date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let dateText = "Generated on \(dateFormatter.string(from: Date())) • \(generationType)"

        drawText(
            dateText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: dateFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 18

        // Instruction line
        let instruction = "Answer each question in the space provided. Show your work where applicable."
        drawText(
            instruction,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: dateFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 20

        // Divider line
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: currentY))
        context.addLine(to: CGPoint(x: x + width, y: currentY))
        context.strokePath()

        return currentY
    }

    private func drawPracticeQuestion(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        question: QuestionGenerationService.GeneratedQuestion,
        questionNumber: Int
    ) -> CGFloat {
        let questionFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let metaFont = UIFont.systemFont(ofSize: 8, weight: .regular)

        var currentY = y
        let answerSpaceHeight: CGFloat = 60

        // Question number and metadata
        let metadata = "Difficulty: \(question.difficulty) | Topic: \(question.topic)"
        drawText(
            metadata,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: metaFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 18

        // Question header
        let questionHeader = "Question \(questionNumber):"
        drawText(
            questionHeader,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: questionFont,
            color: UIColor.black,
            alignment: .left
        )
        currentY += 25

        // Question content
        let questionHeight = drawMultilineText(
            question.question,
            in: context,
            at: CGPoint(x: x + 20, y: currentY),
            width: width - 20,
            font: bodyFont
        )
        currentY += questionHeight + 15

        // For multiple choice, show options
        if let options = question.options, !options.isEmpty {
            currentY += 10
            for (index, option) in options.enumerated() {
                let optionLabel = "\(String(UnicodeScalar(65 + index)!))) \(option)"
                let optionHeight = drawMultilineText(
                    optionLabel,
                    in: context,
                    at: CGPoint(x: x + 30, y: currentY),
                    width: width - 30,
                    font: bodyFont
                )
                currentY += optionHeight + 8
            }
            currentY += 10
        }

        // Answer space
        drawText(
            "Your Answer:",
            in: context,
            at: CGPoint(x: x + 20, y: currentY),
            width: width - 20,
            font: bodyFont,
            color: UIColor.darkGray,
            alignment: .left
        )
        currentY += 20

        // Answer box
        let answerBox = CGRect(x: x + 20, y: currentY, width: width - 20, height: answerSpaceHeight)
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(1)
        context.stroke(answerBox)
        currentY += answerSpaceHeight + 5

        return currentY - y
    }

    private func createPDFPage(
        questions: [MistakeQuestion],
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        timeRange: MistakeTimeRange
    ) async -> PDFPage? {
        let pageSize = CGSize(width: 612, height: 792) // US Letter: 8.5" x 11" at 72 DPI
        let renderer = UIGraphicsImageRenderer(size: pageSize)

        let image = renderer.image { context in
            let cgContext = context.cgContext

            // Set up drawing context
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: pageSize))

            // Draw the page content
            drawPageContent(
                in: cgContext,
                pageSize: pageSize,
                questions: questions,
                pageNumber: pageNumber,
                totalPages: totalPages,
                subject: subject,
                timeRange: timeRange
            )
        }

        // Convert UIImage to PDFPage
        let pdfPage = PDFPage(image: image)
        return pdfPage
    }

    private func drawPageContent(
        in context: CGContext,
        pageSize: CGSize,
        questions: [MistakeQuestion],
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        timeRange: MistakeTimeRange
    ) {
        let margin: CGFloat = 54 // 0.75 inch margins at 72 DPI
        let contentWidth = pageSize.width - (2 * margin)
        var currentY: CGFloat = margin

        // Header
        currentY = drawHeader(
            in: context,
            x: margin,
            y: currentY,
            width: contentWidth,
            subject: subject,
            timeRange: timeRange
        )

        currentY += 30 // Space after header

        // Questions
        for (index, question) in questions.enumerated() {
            let questionHeight = drawQuestion(
                in: context,
                x: margin,
                y: currentY,
                width: contentWidth,
                question: question,
                questionNumber: ((pageNumber - 1) * 2) + index + 1
            )
            currentY += questionHeight + 40 // Space between questions
        }

        // Footer
        drawFooter(
            in: context,
            pageSize: pageSize,
            pageNumber: pageNumber,
            totalPages: totalPages
        )
    }

    private func drawHeader(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        subject: String,
        timeRange: MistakeTimeRange
    ) -> CGFloat {
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        let dateFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        var currentY = y

        // Title
        let title = "Practice Questions"
        drawText(
            title,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: titleFont,
            color: UIColor.black,
            alignment: .center
        )
        currentY += 25

        // Subject
        let subjectText = "Subject: \(subject)"
        drawText(
            subjectText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: subtitleFont,
            color: UIColor.darkGray,
            alignment: .left
        )
        currentY += 18

        // Time range and date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let dateText = "Generated on \(dateFormatter.string(from: Date())) • \(timeRange.rawValue)"

        drawText(
            dateText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: dateFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 18

        // Instruction line
        let instruction = "Review these questions and write your answers in the space provided below each question."
        drawText(
            instruction,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: dateFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 20

        // Divider line
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: currentY))
        context.addLine(to: CGPoint(x: x + width, y: currentY))
        context.strokePath()

        return currentY
    }

    private func drawQuestion(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        question: MistakeQuestion,
        questionNumber: Int
    ) -> CGFloat {
        let questionFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
        let hintFont = UIFont.systemFont(ofSize: 8, weight: .regular)

        var currentY = y
        let answerSpaceHeight: CGFloat = 40

        // Question number and text
        let questionHeader = "Question \(questionNumber):"
        drawText(
            questionHeader,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: questionFont,
            color: UIColor.black,
            alignment: .left
        )
        currentY += 25

        // Question content
        let questionHeight = drawMultilineText(
            question.question,
            in: context,
            at: CGPoint(x: x + 20, y: currentY),
            width: width - 20,
            font: bodyFont
        )
        currentY += questionHeight + 15

        // Answer space
        drawText(
            "Your Answer:",
            in: context,
            at: CGPoint(x: x + 20, y: currentY),
            width: width - 20,
            font: bodyFont,
            color: UIColor.darkGray,
            alignment: .left
        )
        currentY += 20

        // Answer box
        let answerBox = CGRect(x: x + 20, y: currentY, width: width - 20, height: answerSpaceHeight)
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(1)
        context.stroke(answerBox)
        currentY += answerSpaceHeight + 10

        // Small hint about original mistake
        let hintText = "💡 You originally answered: \"\(question.studentAnswer.isEmpty ? "No answer" : question.studentAnswer)\""
        drawText(
            hintText,
            in: context,
            at: CGPoint(x: x + 20, y: currentY),
            width: width - 20,
            font: hintFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 15

        return currentY - y
    }

    // MARK: - Raw Questions PDF Methods

    private func createRawQuestionsPDFPage(
        questions: [String],
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        date: Date,
        accuracy: Float,
        questionCount: Int,
        startQuestionNumber: Int
    ) async -> PDFPage? {
        let pageSize = CGSize(width: 612, height: 792) // US Letter: 8.5" x 11" at 72 DPI
        let renderer = UIGraphicsImageRenderer(size: pageSize)

        let image = renderer.image { context in
            let cgContext = context.cgContext

            // Set up drawing context
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: pageSize))

            // Draw the page content
            drawRawQuestionsPageContent(
                in: cgContext,
                pageSize: pageSize,
                questions: questions,
                pageNumber: pageNumber,
                totalPages: totalPages,
                subject: subject,
                date: date,
                accuracy: accuracy,
                questionCount: questionCount,
                startQuestionNumber: startQuestionNumber
            )
        }

        // Convert UIImage to PDFPage
        let pdfPage = PDFPage(image: image)
        return pdfPage
    }

    private func drawRawQuestionsPageContent(
        in context: CGContext,
        pageSize: CGSize,
        questions: [String],
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        date: Date,
        accuracy: Float,
        questionCount: Int,
        startQuestionNumber: Int
    ) {
        let margin: CGFloat = 54 // 0.75 inch margins at 72 DPI
        let contentWidth = pageSize.width - (2 * margin)
        var currentY: CGFloat = margin

        // Header (only on first page)
        if pageNumber == 1 {
            currentY = drawRawQuestionsHeader(
                in: context,
                x: margin,
                y: currentY,
                width: contentWidth,
                subject: subject,
                date: date,
                accuracy: accuracy,
                questionCount: questionCount
            )
            currentY += 30 // Space after header
        }

        // Questions
        for (index, question) in questions.enumerated() {
            let questionNumber = startQuestionNumber + index
            let questionHeight = drawRawQuestion(
                in: context,
                x: margin,
                y: currentY,
                width: contentWidth,
                question: question,
                questionNumber: questionNumber
            )
            currentY += questionHeight + 35 // Space between questions
        }

        // Footer
        drawFooter(
            in: context,
            pageSize: pageSize,
            pageNumber: pageNumber,
            totalPages: totalPages
        )
    }

    private func drawRawQuestionsHeader(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        subject: String,
        date: Date,
        accuracy: Float,
        questionCount: Int
    ) -> CGFloat {
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        let metadataFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        var currentY = y

        // Title
        let title = "Homework Questions"
        drawText(
            title,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: titleFont,
            color: UIColor.black,
            alignment: .center
        )
        currentY += 25

        // Subject
        let subjectText = "Subject: \(subject)"
        drawText(
            subjectText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: subtitleFont,
            color: UIColor.darkGray,
            alignment: .left
        )
        currentY += 18

        // Question count only (simplified subtitle as requested)
        let metadataText = "\(questionCount) Questions"

        drawText(
            metadataText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: metadataFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 18

        // Instruction line
        let instruction = "These are the questions from your homework assignment."
        drawText(
            instruction,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: metadataFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 20

        // Divider line
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: currentY))
        context.addLine(to: CGPoint(x: x + width, y: currentY))
        context.strokePath()

        return currentY
    }

    private func drawRawQuestion(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        question: String,
        questionNumber: Int
    ) -> CGFloat {
        let questionHeaderFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        var currentY = y

        // Question number
        let questionHeader = "Question \(questionNumber):"
        drawText(
            questionHeader,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: questionHeaderFont,
            color: UIColor.black,
            alignment: .left
        )
        currentY += 25

        // Question content
        let questionHeight = drawMultilineText(
            question,
            in: context,
            at: CGPoint(x: x + 20, y: currentY),
            width: width - 20,
            font: bodyFont
        )
        currentY += questionHeight + 10

        return currentY - y
    }

    private func drawFooter(
        in context: CGContext,
        pageSize: CGSize,
        pageNumber: Int,
        totalPages: Int
    ) {
        let footerFont = UIFont.systemFont(ofSize: 9, weight: .regular)
        let footerY = pageSize.height - 30
        let margin: CGFloat = 54

        // Page number
        let pageText = "Page \(pageNumber) of \(totalPages)"
        drawText(
            pageText,
            in: context,
            at: CGPoint(x: margin, y: footerY),
            width: pageSize.width - (2 * margin),
            font: footerFont,
            color: UIColor.gray,
            alignment: .center
        )

        // Study Mates branding
        let brandText = "Generated by Study Mates"
        drawText(
            brandText,
            in: context,
            at: CGPoint(x: margin, y: footerY - 15),
            width: pageSize.width - (2 * margin),
            font: footerFont,
            color: UIColor.lightGray,
            alignment: .center
        )
    }

    // MARK: - Text Drawing Helpers

    private func drawText(
        _ text: String,
        in context: CGContext,
        at point: CGPoint,
        width: CGFloat,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let drawRect = CGRect(x: point.x, y: point.y, width: width, height: font.lineHeight)

        attributedString.draw(in: drawRect)
    }

    private func drawMultilineText(
        _ text: String,
        in context: CGContext,
        at point: CGPoint,
        width: CGFloat,
        font: UIFont
    ) -> CGFloat {
        // ✅ Convert LaTeX math to Unicode symbols before rendering
        let renderedText = SimpleMathRenderer.renderMathText(text)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: renderedText, attributes: attributes)
        _ = CGRect(x: point.x, y: point.y, width: width, height: 1000) // Large height for calculation

        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: width, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let drawRect = CGRect(x: point.x, y: point.y, width: width, height: boundingRect.height)
        attributedString.draw(in: drawRect)

        return boundingRect.height
    }

    // MARK: - Pro Mode PDF Generation (NEW)

    /// Generate PDF for Pro Mode homework with full grading data
    /// Includes: question text, student answer, grade, feedback, and cropped images
    /// Implements intelligent multi-column layout based on content length
    func generateProModePDF(
        digitalHomework: DigitalHomeworkData,
        subject: String,
        date: Date
    ) async -> PDFDocument? {
        isGenerating = true
        generationProgress = 0.0

        defer {
            isGenerating = false
            generationProgress = 0.0
        }

        let pdfDocument = PDFDocument()

        // Analyze questions and group by layout type
        let layoutGroups = categorizeQuestionsForLayout(digitalHomework.questions)

        // Generate pages with intelligent layout
        for (groupIndex, group) in layoutGroups.enumerated() {
            if let pdfPage = await createProModePDFPage(
                questions: group.questions,
                columns: group.columns,
                pageNumber: groupIndex + 1,
                totalPages: layoutGroups.count,
                subject: subject,
                date: date,
                digitalHomework: digitalHomework
            ) {
                pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
            }

            // Update progress
            generationProgress = Double(groupIndex + 1) / Double(layoutGroups.count)
        }

        return pdfDocument.pageCount > 0 ? pdfDocument : nil
    }

    // MARK: - Layout Intelligence

    /// Categorize questions into layout groups based on content length
    /// Returns groups with column count (1, 2, or 3 columns)
    private func categorizeQuestionsForLayout(_ questions: [ProgressiveQuestionWithGrade]) -> [LayoutGroup] {
        var groups: [LayoutGroup] = []
        var currentGroup: [ProgressiveQuestionWithGrade] = []
        var currentColumns = 0

        for question in questions {
            let contentLength = question.question.displayText.count
            let hasImage = question.question.hasImage == true

            // Determine column count for this question
            let columns: Int
            if hasImage || contentLength > 200 {
                // Long questions or questions with images: single column
                columns = 1
            } else if contentLength > 80 {
                // Medium questions: two columns
                columns = 2
            } else {
                // Short questions: three columns
                columns = 3
            }

            // If column count changes, start a new group
            if currentColumns != 0 && currentColumns != columns {
                groups.append(LayoutGroup(questions: currentGroup, columns: currentColumns))
                currentGroup = []
            }

            currentGroup.append(question)
            currentColumns = columns

            // Limit questions per page based on column count
            let maxQuestionsPerPage = columns == 3 ? 6 : (columns == 2 ? 4 : 2)
            if currentGroup.count >= maxQuestionsPerPage {
                groups.append(LayoutGroup(questions: currentGroup, columns: columns))
                currentGroup = []
                currentColumns = 0
            }
        }

        // Add remaining questions
        if !currentGroup.isEmpty {
            groups.append(LayoutGroup(questions: currentGroup, columns: currentColumns))
        }

        return groups
    }

    struct LayoutGroup {
        let questions: [ProgressiveQuestionWithGrade]
        let columns: Int
    }

    // MARK: - Pro Mode Page Creation

    private func createProModePDFPage(
        questions: [ProgressiveQuestionWithGrade],
        columns: Int,
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        date: Date,
        digitalHomework: DigitalHomeworkData
    ) async -> PDFPage? {
        let pageSize = CGSize(width: 612, height: 792) // US Letter: 8.5" x 11" at 72 DPI
        let renderer = UIGraphicsImageRenderer(size: pageSize)

        let image = renderer.image { context in
            let cgContext = context.cgContext

            // Set up drawing context
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: pageSize))

            // Draw the page content
            drawProModePageContent(
                in: cgContext,
                pageSize: pageSize,
                questions: questions,
                columns: columns,
                pageNumber: pageNumber,
                totalPages: totalPages,
                subject: subject,
                date: date,
                digitalHomework: digitalHomework
            )
        }

        // Convert UIImage to PDFPage
        let pdfPage = PDFPage(image: image)
        return pdfPage
    }

    private func drawProModePageContent(
        in context: CGContext,
        pageSize: CGSize,
        questions: [ProgressiveQuestionWithGrade],
        columns: Int,
        pageNumber: Int,
        totalPages: Int,
        subject: String,
        date: Date,
        digitalHomework: DigitalHomeworkData
    ) {
        let margin: CGFloat = 54 // 0.75 inch margins at 72 DPI
        let contentWidth = pageSize.width - (2 * margin)
        var currentY: CGFloat = margin

        // Header (only on first page)
        if pageNumber == 1 {
            currentY = drawProModeHeader(
                in: context,
                x: margin,
                y: currentY,
                width: contentWidth,
                subject: subject,
                date: date,
                totalQuestions: digitalHomework.questions.count
            )
            currentY += 30 // Space after header
        }

        // Draw questions in multi-column layout
        if columns == 1 {
            // Single column layout (default)
            for question in questions {
                let questionHeight = drawProModeQuestion(
                    in: context,
                    x: margin,
                    y: currentY,
                    width: contentWidth,
                    question: question,
                    digitalHomework: digitalHomework
                )
                currentY += questionHeight + 30
            }
        } else {
            // Multi-column layout (2 or 3 columns)
            let columnGap: CGFloat = 20
            let columnWidth = (contentWidth - CGFloat(columns - 1) * columnGap) / CGFloat(columns)

            var columnY: [CGFloat] = Array(repeating: currentY, count: columns)
            var currentColumn = 0

            for question in questions {
                let x = margin + CGFloat(currentColumn) * (columnWidth + columnGap)
                let questionHeight = drawProModeQuestionCompact(
                    in: context,
                    x: x,
                    y: columnY[currentColumn],
                    width: columnWidth,
                    question: question,
                    digitalHomework: digitalHomework
                )

                columnY[currentColumn] += questionHeight + 20
                currentColumn = (currentColumn + 1) % columns
            }
        }

        // Footer
        drawFooter(
            in: context,
            pageSize: pageSize,
            pageNumber: pageNumber,
            totalPages: totalPages
        )
    }

    private func drawProModeHeader(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        subject: String,
        date: Date,
        totalQuestions: Int
    ) -> CGFloat {
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
        let metadataFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        var currentY = y

        // Title
        let title = "Digital Homework - \(subject)"
        drawText(
            title,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: titleFont,
            color: UIColor.black,
            alignment: .center
        )
        currentY += 25

        // Subtitle (simplified - only question count)
        let metadataText = "\(totalQuestions) Questions"
        drawText(
            metadataText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: metadataFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 18

        // Instruction line
        let instruction = "Review your work with AI feedback and grades"
        drawText(
            instruction,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: metadataFont,
            color: UIColor.gray,
            alignment: .left
        )
        currentY += 20

        // Divider line
        context.setStrokeColor(UIColor.lightGray.cgColor)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: x, y: currentY))
        context.addLine(to: CGPoint(x: x + width, y: currentY))
        context.strokePath()

        return currentY
    }

    // Full question layout (single column)
    // ✅ IMPROVED: Removed grading information for Pro Mode (only show question + student answer)
    // ✅ IMPROVED: Reduced spacing to optimize page usage
    private func drawProModeQuestion(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        question: ProgressiveQuestionWithGrade,
        digitalHomework: DigitalHomeworkData
    ) -> CGFloat {
        let questionFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        var currentY = y

        // Question number
        let questionNumber = question.question.questionNumber ?? "\(question.id)"
        let questionHeader = "Question \(questionNumber)"
        drawText(
            questionHeader,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: questionFont,
            color: UIColor.black,
            alignment: .left
        )
        currentY += 18  // ✅ Reduced from 25

        // Question text
        let questionHeight = drawMultilineText(
            question.question.displayText,
            in: context,
            at: CGPoint(x: x + 10, y: currentY),
            width: width - 10,
            font: bodyFont
        )
        currentY += questionHeight + 8  // ✅ Reduced from 10

        // Student answer (if available)
        if !question.question.displayStudentAnswer.isEmpty {
            drawText(
                "Your Answer:",
                in: context,
                at: CGPoint(x: x + 10, y: currentY),
                width: width - 10,
                font: bodyFont,
                color: UIColor.darkGray,
                alignment: .left
            )
            currentY += 12  // ✅ Reduced from 15

            let answerHeight = drawMultilineText(
                question.question.displayStudentAnswer,
                in: context,
                at: CGPoint(x: x + 20, y: currentY),
                width: width - 20,
                font: bodyFont
            )
            currentY += answerHeight + 8  // ✅ Reduced from 10
        }

        // ✅ REMOVED: All grading information (grade, feedback, correct answer)
        // Pro Mode PDFs should not contain original grading - user can review digital version for grades

        return currentY - y
    }

    // Compact question layout (multi-column)
    private func drawProModeQuestionCompact(
        in context: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        question: ProgressiveQuestionWithGrade,
        digitalHomework: DigitalHomeworkData
    ) -> CGFloat {
        let questionFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 9, weight: .regular)

        var currentY = y

        // Question number and text (compact)
        let questionNumber = question.question.questionNumber ?? "\(question.id)"
        let questionText = "Q\(questionNumber): \(question.question.displayText.prefix(100))"

        let questionHeight = drawMultilineText(
            questionText,
            in: context,
            at: CGPoint(x: x, y: currentY),
            width: width,
            font: bodyFont
        )
        currentY += questionHeight + 8

        // Grade indicator (compact)
        if let grade = question.grade {
            let gradeColor = grade.isCorrect ? UIColor.systemGreen : UIColor.systemRed
            let gradeText = grade.isCorrect ? "✓" : "✗ \(Int(grade.score * 100))%"

            drawText(
                gradeText,
                in: context,
                at: CGPoint(x: x, y: currentY),
                width: width,
                font: questionFont,
                color: gradeColor,
                alignment: .left
            )
            currentY += 15
        }

        return currentY - y
    }
}