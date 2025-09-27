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

    // MARK: - Private Methods

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

        // StudyAI branding
        let brandText = "Generated by StudyAI"
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
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
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
}