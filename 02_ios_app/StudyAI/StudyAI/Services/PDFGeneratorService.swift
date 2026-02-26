//
//  PDFGeneratorService.swift
//  StudyAI
//
//  Unified PDF generation engine for all four export paths.
//  Uses CGContext vector rendering (not UIGraphicsImageRenderer) so the
//  output is a true vector PDF: text is selectable, prints crisply at any
//  resolution, and file sizes are smaller than bitmap alternatives.
//
//  All four paths share one rendering pipeline driven by PDFExportOptions,
//  so font size, question gap, and image size are consistently honoured
//  everywhere and dynamic page-break calculation always agrees with rendering.
//

import Foundation
import PDFKit
import UIKit
import SwiftUI
import Combine

// MARK: - Export Options

/// Centralised configuration for every PDF export path.
/// All properties have sensible defaults so existing callers need no changes.
struct PDFExportOptions {
    // Font sizes (points)
    var titleFontSize: CGFloat     = 18   // Page header title ("Practice Questions" etc.)
    var subjectFontSize: CGFloat   = 12   // "Subject: …" line in header
    var metaFontSize: CGFloat      = 10   // Date / generation-type / instruction lines
    var questionFontSize: CGFloat  = 14   // Question body text
    var labelFontSize: CGFloat     = 12   // "Question N:" label
    var hintFontSize: CGFloat      = 9    // Mistake hint / answer-box label

    // Spacing
    var questionGap: CGFloat       = 32   // Vertical gap between consecutive questions

    // Images (Pro Mode / homework paths only)
    var maxImageHeight: CGFloat    = 300  // Cap for main question image
    var maxSubImageHeight: CGFloat = 200  // Cap for sub-question image
    // Image width always fills the available content width — no separate param needed.
}

// MARK: - Service

@MainActor
class PDFGeneratorService: ObservableObject {

    @Published var isGenerating = false
    @Published var generationProgress: Double = 0.0

    // MARK: - Constants

    private let pageSize   = CGSize(width: 612, height: 792) // US Letter at 72 DPI
    private let margin: CGFloat = 54                          // 0.75 inch

    private var contentWidth: CGFloat { pageSize.width - margin * 2 }
    private var contentHeight: CGFloat { pageSize.height - margin * 2 }

    // MARK: - Public API

    /// Path 1 — Generated practice questions
    func generatePracticePDF(
        questions: [QuestionGenerationService.GeneratedQuestion],
        subject: String,
        generationType: String,
        options: PDFExportOptions = PDFExportOptions()
    ) async -> PDFDocument? {
        guard !questions.isEmpty else { return nil }
        isGenerating = true
        generationProgress = 0.0
        defer { isGenerating = false; generationProgress = 0.0 }

        let renderWidth = contentWidth - 20
        return buildVectorPDF(options: options, totalItems: questions.count) { ctx, pageRect, addPage in
            var y: CGFloat = margin
            y = drawPageHeader(
                ctx: ctx, pageRect: pageRect,
                title: "Practice Questions", subject: subject,
                subtitle: "Generated on \(formattedDate()) • \(generationType)",
                instruction: "Answer each question in the space provided. Show your work where applicable.",
                options: options, startY: y)
            y += options.questionGap

            for (index, question) in questions.enumerated() {
                let imgH = multilineHeight(plainText(question.question), width: renderWidth, fontSize: options.questionFontSize)
                let blockH = options.metaFontSize + 6 + options.labelFontSize + 8 + imgH + 12
                    + (question.options.map { CGFloat($0.count) * (options.questionFontSize + 11) + 16 } ?? 0)
                    + options.hintFontSize + 4 + 60

                if y + blockH > pageSize.height - margin { addPage(); y = margin }

                y = drawPracticeQuestion(ctx: ctx, pageRect: pageRect, question: question,
                    number: index + 1, startY: y, options: options)
                y += options.questionGap
                generationProgress = Double(index + 1) / Double(questions.count)
            }
        }
    }

    /// Path 2 — Mistake review
    func generateMistakesPDF(
        questions: [MistakeQuestion],
        subject: String,
        timeRange: MistakeTimeRange,
        options: PDFExportOptions = PDFExportOptions()
    ) async -> PDFDocument? {
        guard !questions.isEmpty else { return nil }
        isGenerating = true
        generationProgress = 0.0
        defer { isGenerating = false; generationProgress = 0.0 }

        let renderWidth = contentWidth - 20
        return buildVectorPDF(options: options, totalItems: questions.count) { ctx, pageRect, addPage in
            var y: CGFloat = margin
            y = drawPageHeader(
                ctx: ctx, pageRect: pageRect,
                title: "Mistake Review", subject: subject,
                subtitle: "Generated on \(formattedDate()) • \(timeRange.rawValue)",
                instruction: "Review these questions and write your answers in the space provided below each question.",
                options: options, startY: y)
            y += options.questionGap

            for (index, question) in questions.enumerated() {
                let imgH = multilineHeight(plainText(question.question), width: renderWidth, fontSize: options.questionFontSize)
                let blockH = options.labelFontSize + 8 + imgH + 12 + options.hintFontSize + 4 + 40 + 10 + options.hintFontSize + 4

                if y + blockH > pageSize.height - margin { addPage(); y = margin }

                y = drawMistakeQuestion(ctx: ctx, pageRect: pageRect, question: question,
                    number: index + 1, startY: y, options: options)
                y += options.questionGap
                generationProgress = Double(index + 1) / Double(questions.count)
            }
        }
    }

    /// Path 4 fallback — Raw homework questions (text only, no images)
    func generateRawQuestionsPDF(
        rawQuestions: [String],
        pageImages: [UIImage] = [],
        subject: String,
        date: Date,
        accuracy: Float,
        questionCount: Int,
        options: PDFExportOptions = PDFExportOptions()
    ) async -> PDFDocument? {
        guard !rawQuestions.isEmpty else { return nil }
        isGenerating = true
        generationProgress = 0.0
        defer { isGenerating = false; generationProgress = 0.0 }

        let renderWidth = contentWidth - 20
        return buildVectorPDF(options: options, totalItems: rawQuestions.count) { ctx, pageRect, addPage in
            var y: CGFloat = margin
            y = drawPageHeader(
                ctx: ctx, pageRect: pageRect,
                title: "Homework Questions", subject: subject,
                subtitle: "\(questionCount) Questions",
                instruction: "These are the questions from your homework assignment.",
                options: options, startY: y)
            y += options.questionGap

            for (index, text) in rawQuestions.enumerated() {
                // Use the page image that corresponds to this question if available
                // If there are fewer images than questions, the last image is reused for remaining questions
                let pageImage: UIImage? = pageImages.isEmpty ? nil
                    : pageImages[min(index, pageImages.count - 1)]

                let textH = multilineHeight(plainText(text), width: renderWidth, fontSize: options.questionFontSize)
                let imgH: CGFloat = pageImage.map {
                    scaledImageHeight($0, maxWidth: renderWidth, maxHeight: options.maxImageHeight)
                } ?? 0
                let blockH = options.labelFontSize + 8 + imgH + (imgH > 0 ? 10 : 0) + textH + 8

                if y + blockH > pageSize.height - margin { addPage(); y = margin }

                y = drawRawQuestion(ctx: ctx, pageRect: pageRect, pageImage: pageImage,
                    fallbackText: text, number: index + 1, startY: y, options: options)
                y += options.questionGap
                generationProgress = Double(index + 1) / Double(rawQuestions.count)
            }
        }
    }

    /// Path 5 — Library questions (QuestionSummary array, text-only)
    func generateLibraryPDF(
        questions: [QuestionSummary],
        subject: String,
        options: PDFExportOptions = PDFExportOptions()
    ) async -> PDFDocument? {
        guard !questions.isEmpty else { return nil }
        isGenerating = true
        generationProgress = 0.0
        defer { isGenerating = false; generationProgress = 0.0 }

        let renderWidth = contentWidth - 20
        return buildVectorPDF(options: options, totalItems: questions.count) { ctx, pageRect, addPage in
            var y: CGFloat = margin
            y = drawPageHeader(
                ctx: ctx, pageRect: pageRect,
                title: "Library Questions", subject: subject,
                subtitle: "Generated on \(formattedDate()) • \(questions.count) questions",
                instruction: "Review each question and write your answers in the space provided.",
                options: options, startY: y)
            y += options.questionGap

            for (index, question) in questions.enumerated() {
                let qImage: UIImage? = question.questionImageUrl.flatMap { UIImage(contentsOfFile: $0) }
                let qImgH: CGFloat = qImage.map { scaledImageHeight($0, maxWidth: renderWidth, maxHeight: options.maxImageHeight) + 10 } ?? 0
                let textH = multilineHeight(plainText(question.questionText), width: renderWidth, fontSize: options.questionFontSize)
                let optH = question.options.map { CGFloat($0.count) * (options.questionFontSize + 11) + 8 } ?? 0
                let blockH = options.labelFontSize + 8 + qImgH + textH + 10 + optH

                if y + blockH > pageSize.height - margin { addPage(); y = margin }

                y = drawLibraryQuestion(ctx: ctx, pageRect: pageRect, question: question,
                    qImage: qImage, number: index + 1, startY: y, options: options)
                y += options.questionGap
                generationProgress = Double(index + 1) / Double(questions.count)
            }
        }
    }

    // MARK: - Library Question (QuestionSummary)

    @discardableResult
    private func drawLibraryQuestion(
        ctx: CGContext,
        pageRect: CGRect,
        question: QuestionSummary,
        qImage: UIImage?,
        number: Int,
        startY: CGFloat,
        options: PDFExportOptions
    ) -> CGFloat {
        var y = startY
        withUIKitContext(ctx: ctx, pageRect: pageRect) {
            let w = contentWidth
            let labelFont = UIFont.systemFont(ofSize: options.labelFontSize, weight: .semibold)
            let bodyFont  = UIFont.systemFont(ofSize: options.questionFontSize, weight: .regular)

            // Label
            y += drawString("Question \(number):", font: labelFont, color: .black, alignment: .left,
                            x: margin, y: y, width: w) + 6

            // Question image (Pro Mode cropped image)
            if let img = qImage {
                let iw = w - 20
                let ih = scaledImageHeight(img, maxWidth: iw, maxHeight: options.maxImageHeight)
                img.draw(in: CGRect(x: margin + 20, y: y, width: iw, height: ih))
                y += ih + 10
            }

            // Question body
            y += drawMultiline(plainText(question.questionText), font: bodyFont, x: margin + 20, y: y, width: w - 20) + 10

            // MCQ options
            if let opts = question.options, !opts.isEmpty {
                for (i, opt) in opts.enumerated() {
                    let label = "\(String(UnicodeScalar(65 + i)!))) \(plainText(opt))"
                    y += drawMultiline(label, font: bodyFont, x: margin + 30, y: y, width: w - 30) + 5
                }
                y += 6
            }
        }
        return y
    }


    func generateProModePDF(
        questions: [ProgressiveQuestionWithGrade],
        subject: String,
        croppedImages: [String: UIImage],
        includeArchived: Bool = false,
        options: PDFExportOptions = PDFExportOptions()
    ) async -> PDFDocument? {
        AppLogger.forFeature("PDFGen").info("▶︎ generateProModePDF(UIImages) called — questions=\(questions.count) croppedImages=\(croppedImages.count) subject='\(subject)' includeArchived=\(includeArchived)")

        isGenerating = true
        generationProgress = 0.0
        defer { isGenerating = false; generationProgress = 0.0 }

        let toExport: [ProgressiveQuestionWithGrade]
        if includeArchived {
            toExport = questions
        } else {
            let filtered = questions.filter { !$0.isArchived }
            toExport = filtered.isEmpty ? questions : filtered
        }

        AppLogger.forFeature("PDFGen").info("  toExport count=\(toExport.count) (after archive filter)")

        guard !toExport.isEmpty else {
            AppLogger.forFeature("PDFGen").error("  ✗ toExport is EMPTY — returning nil")
            return nil
        }

        let doc = buildVectorPDF(options: options, totalItems: toExport.count) { ctx, pageRect, addPage in
            AppLogger.forFeature("PDFGen").info("  buildVectorPDF body called — drawing cover page")
            drawCoverPage(ctx: ctx, pageRect: pageRect, subject: subject, questionCount: toExport.count, options: options)
            addPage()
            var y: CGFloat = margin
            for (index, q) in toExport.enumerated() {
                let img = croppedImages[q.question.id]
                AppLogger.forFeature("PDFGen").info("  Q\(index+1) id=\(q.question.id) hasImage=\(img != nil)")
                let blockHeight = proModeQuestionHeight(q: q, image: img, croppedImages: croppedImages, options: options)
                if y + blockHeight > pageSize.height - margin { addPage(); y = margin }
                y = drawProModeQuestion(ctx: ctx, pageRect: pageRect, q: q, image: img,
                                        croppedImages: croppedImages, startY: y, options: options)
                y += options.questionGap
                generationProgress = Double(index + 1) / Double(toExport.count)
            }
        }

        AppLogger.forFeature("PDFGen").info("  buildVectorPDF returned doc=\(doc != nil ? "✓ \(doc!.pageCount) pages" : "nil")")
        return doc
    }

    /// Path 4 Pro Mode (HomeworkQuestionsPDFPreviewView) — decodes images from DigitalHomeworkData
    func generateProModePDF(
        digitalHomework: DigitalHomeworkData,
        subject: String,
        date: Date,
        options: PDFExportOptions = PDFExportOptions()
    ) async -> PDFDocument? {
        AppLogger.forFeature("PDFGen").info("▶︎ generateProModePDF(DigitalHomeworkData) called — questions=\(digitalHomework.questions.count) rawImages=\(digitalHomework.croppedImages.count) subject='\(subject)'")
        var croppedImages: [String: UIImage] = [:]
        for (id, data) in digitalHomework.croppedImages {
            if let img = UIImage(data: data) { croppedImages[id] = img }
        }
        AppLogger.forFeature("PDFGen").info("  decoded \(croppedImages.count)/\(digitalHomework.croppedImages.count) images successfully")
        return await generateProModePDF(
            questions: digitalHomework.questions,
            subject: subject,
            croppedImages: croppedImages,
            options: options
        )
    }

    // MARK: - Core Vector PDF Builder

    /// Creates a CGContext-backed PDF and calls `body` to fill its pages.
    /// `addPage()` closes the current page and opens a fresh one with a white background.
    /// Returns a `PDFDocument` built from the raw data.
    private func buildVectorPDF(
        options: PDFExportOptions,
        totalItems: Int,
        body: (_ ctx: CGContext, _ pageRect: CGRect, _ addPage: () -> Void) -> Void
    ) -> PDFDocument? {
        let log = AppLogger.forFeature("PDFGen")
        log.info("  buildVectorPDF: pageSize=\(pageSize) totalItems=\(totalItems)")

        let metadata: [String: Any] = [
            kCGPDFContextCreator as String: "StudyMates"
        ]

        let pdfData = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            log.error("  ✗ CGDataConsumer creation failed")
            return nil
        }
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, metadata as CFDictionary) else {
            log.error("  ✗ CGContext creation failed")
            return nil
        }

        log.info("  CGContext created OK — beginning first page")

        // Open first page
        ctx.beginPDFPage(nil)
        fillWhite(ctx: ctx)

        var pageCount = 1
        // Caller fills content; can request new pages via addPage()
        body(ctx, CGRect(origin: .zero, size: pageSize)) {
            log.info("  addPage() called — ending page \(pageCount), starting page \(pageCount + 1)")
            ctx.endPDFPage()
            ctx.beginPDFPage(nil)
            fillWhite(ctx: ctx)
            pageCount += 1
        }

        ctx.endPDFPage()
        ctx.closePDF()

        let dataSize = pdfData.length
        log.info("  PDF closed — raw data size=\(dataSize) bytes, pages=\(pageCount)")

        guard dataSize > 0 else {
            log.error("  ✗ PDF data is empty after closePDF")
            return nil
        }

        let doc = PDFDocument(data: pdfData as Data)
        log.info("  PDFDocument created: \(doc != nil ? "\(doc!.pageCount) pages" : "nil — PDFDocument init failed")")
        return doc
    }

    // MARK: - Cover Page (Pro Mode)

    private func drawCoverPage(
        ctx: CGContext,
        pageRect: CGRect,
        subject: String,
        questionCount: Int,
        options: PDFExportOptions
    ) {
        withUIKitContext(ctx: ctx, pageRect: pageRect) {
            let cx = pageRect.width / 2
            var y: CGFloat = 220

            // App title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            ]
            let titleStr = NSAttributedString(string: "StudyMates", attributes: titleAttrs)
            titleStr.draw(at: CGPoint(x: cx - titleStr.size().width / 2, y: y))
            y += titleStr.size().height + 16

            // Subtitle
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            let subStr = NSAttributedString(string: "Digital Homework Export", attributes: subAttrs)
            subStr.draw(at: CGPoint(x: cx - subStr.size().width / 2, y: y))
            y += subStr.size().height + 48

            // Subject
            let sAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: options.subjectFontSize + 6, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            let sStr = NSAttributedString(string: "Subject: \(subject)", attributes: sAttrs)
            sStr.draw(at: CGPoint(x: cx - sStr.size().width / 2, y: y))
            y += sStr.size().height + 14

            // Question count
            let cAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: options.subjectFontSize, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            let cStr = NSAttributedString(string: "Total Questions: \(questionCount)", attributes: cAttrs)
            cStr.draw(at: CGPoint(x: cx - cStr.size().width / 2, y: y))
            y += cStr.size().height + 14

            // Date
            let dAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: options.metaFontSize, weight: .regular),
                .foregroundColor: UIColor.gray
            ]
            let dStr = NSAttributedString(string: formattedDateLong(), attributes: dAttrs)
            dStr.draw(at: CGPoint(x: cx - dStr.size().width / 2, y: y))
        }
    }

    // MARK: - Shared Page Header

    @discardableResult
    private func drawPageHeader(
        ctx: CGContext,
        pageRect: CGRect,
        title: String,
        subject: String,
        subtitle: String,
        instruction: String,
        options: PDFExportOptions,
        startY: CGFloat
    ) -> CGFloat {
        var y = startY
        withUIKitContext(ctx: ctx, pageRect: pageRect) {
            let w = contentWidth

            // Title
            let titleFont = UIFont.systemFont(ofSize: options.titleFontSize, weight: .bold)
            y += drawString(title, font: titleFont, color: .black, alignment: .center,
                            x: margin, y: y, width: w)
            y += 6

            // Subject
            let subjectFont = UIFont.systemFont(ofSize: options.subjectFontSize, weight: .medium)
            y += drawString("Subject: \(subject)", font: subjectFont, color: .darkGray, alignment: .left,
                            x: margin, y: y, width: w)
            y += 4

            // Subtitle (date + type / count)
            let metaFont = UIFont.systemFont(ofSize: options.metaFontSize, weight: .regular)
            y += drawString(subtitle, font: metaFont, color: .gray, alignment: .left,
                            x: margin, y: y, width: w)
            y += 4

            // Instruction
            y += drawString(instruction, font: metaFont, color: .gray, alignment: .left,
                            x: margin, y: y, width: w)
            y += 10

            // Divider
            ctx.saveGState()
            ctx.translateBy(x: 0, y: pageRect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.setStrokeColor(UIColor.lightGray.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: pageRect.height - y))
            ctx.addLine(to: CGPoint(x: margin + w, y: pageRect.height - y))
            ctx.strokePath()
            ctx.restoreGState()
            y += 1
        }
        return y
    }

    // MARK: - Practice Question

    @discardableResult
    private func drawPracticeQuestion(
        ctx: CGContext,
        pageRect: CGRect,
        question: QuestionGenerationService.GeneratedQuestion,
        number: Int,
        startY: CGFloat,
        options: PDFExportOptions
    ) -> CGFloat {
        var y = startY
        withUIKitContext(ctx: ctx, pageRect: pageRect) {
            let w = contentWidth
            let labelFont  = UIFont.systemFont(ofSize: options.labelFontSize, weight: .semibold)
            let bodyFont   = UIFont.systemFont(ofSize: options.questionFontSize, weight: .regular)

            // Label
            y += drawString("Question \(number):", font: labelFont, color: .black, alignment: .left,
                            x: margin, y: y, width: w) + 6

            // Question body
            y += drawMultiline(plainText(question.question), font: bodyFont, x: margin + 20, y: y, width: w - 20) + 10

            // Options
            if let opts = question.options, !opts.isEmpty {
                y += 6
                for (i, opt) in opts.enumerated() {
                    let label = "\(String(UnicodeScalar(65 + i)!))) \(plainText(opt))"
                    y += drawMultiline(label, font: bodyFont, x: margin + 30, y: y, width: w - 30) + 5
                }
                y += 6
            }
        }
        return y
    }

    // MARK: - Mistake Question

    @discardableResult
    private func drawMistakeQuestion(
        ctx: CGContext,
        pageRect: CGRect,
        question: MistakeQuestion,
        number: Int,
        startY: CGFloat,
        options: PDFExportOptions
    ) -> CGFloat {
        var y = startY
        withUIKitContext(ctx: ctx, pageRect: pageRect) {
            let w = contentWidth
            let labelFont = UIFont.systemFont(ofSize: options.labelFontSize, weight: .semibold)
            let bodyFont  = UIFont.systemFont(ofSize: options.questionFontSize, weight: .regular)
            let hintFont  = UIFont.systemFont(ofSize: options.hintFontSize, weight: .regular)

            y += drawString("Question \(number):", font: labelFont, color: .black, alignment: .left,
                            x: margin, y: y, width: w) + 6

            y += drawMultiline(plainText(question.question), font: bodyFont, x: margin + 20, y: y, width: w - 20) + 10

            let hintText = "💡 You originally answered: \"\(question.studentAnswer.isEmpty ? "No answer" : question.studentAnswer)\""
            y += drawString(hintText, font: hintFont, color: .gray, alignment: .left,
                            x: margin + 20, y: y, width: w - 20) + 2
        }
        return y
    }

    // MARK: - Raw Question

    @discardableResult
    private func drawRawQuestion(
        ctx: CGContext,
        pageRect: CGRect,
        pageImage: UIImage?,
        fallbackText: String,
        number: Int,
        startY: CGFloat,
        options: PDFExportOptions
    ) -> CGFloat {
        var y = startY
        withUIKitContext(ctx: ctx, pageRect: pageRect) {
            let labelFont = UIFont.systemFont(ofSize: options.labelFontSize, weight: .semibold)
            let bodyFont  = UIFont.systemFont(ofSize: options.questionFontSize, weight: .regular)
            let w = contentWidth

            y += drawString("Question \(number):", font: labelFont, color: .black, alignment: .left,
                            x: margin, y: y, width: w) + 6

            // Draw homework page image if available
            if let img = pageImage {
                let ih = scaledImageHeight(img, maxWidth: w - 20, maxHeight: options.maxImageHeight)
                let iw = w - 20
                img.draw(in: CGRect(x: margin + 20, y: y, width: iw, height: ih))
                y += ih + 10
            }

            // Always draw the question text below the image
            y += drawMultiline(plainText(fallbackText), font: bodyFont, x: margin + 20, y: y, width: w - 20) + 6
        }
        return y
    }

    // MARK: - Pro Mode Question

    private func proModeQuestionHeight(
        q: ProgressiveQuestionWithGrade,
        image: UIImage?,
        croppedImages: [String: UIImage],
        options: PDFExportOptions
    ) -> CGFloat {
        var h: CGFloat = 0
        // Header label
        h += options.labelFontSize + 4 + 12

        // Main image
        if let img = image {
            h += scaledImageHeight(img, maxWidth: contentWidth, maxHeight: options.maxImageHeight) + 12
        }

        // Question text
        let qt = q.question.displayText
        if !qt.isEmpty {
            h += multilineHeight(qt, width: contentWidth, fontSize: options.questionFontSize) + 12
        } else {
            h += 28
        }

        // Subquestions
        if let subs = q.question.subquestions, !subs.isEmpty {
            let subW = contentWidth - 40
            for sub in subs {
                h += 8
                h += options.labelFontSize + 4 + 6
                let subImg = croppedImages[sub.id] ?? image
                if let img = subImg {
                    h += scaledImageHeight(img, maxWidth: subW, maxHeight: options.maxSubImageHeight) + 8
                }
                if !sub.questionText.isEmpty {
                    h += multilineHeight(sub.questionText, width: subW, fontSize: options.questionFontSize) + 8
                }
            }
        }
        return h
    }

    @discardableResult
    private func drawProModeQuestion(
        ctx: CGContext,
        pageRect: CGRect,
        q: ProgressiveQuestionWithGrade,
        image: UIImage?,
        croppedImages: [String: UIImage],
        startY: CGFloat,
        options: PDFExportOptions
    ) -> CGFloat {
        var y = startY
        withUIKitContext(ctx: ctx, pageRect: pageRect) {
            let w = contentWidth
            let headerFont = UIFont.systemFont(ofSize: options.labelFontSize + 4, weight: .bold)
            let bodyFont   = UIFont.systemFont(ofSize: options.questionFontSize, weight: .regular)
            let subFont    = UIFont.systemFont(ofSize: options.questionFontSize, weight: .semibold)
            let blue = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)

            let qNum = q.question.questionNumber ?? "\(q.id)"
            y += drawString("Question \(qNum)", font: headerFont, color: blue, alignment: .left,
                            x: margin, y: y, width: w) + 12

            // Main image
            if let img = image {
                let ih = scaledImageHeight(img, maxWidth: w, maxHeight: options.maxImageHeight)
                let iw = ih * (img.size.width / img.size.height)
                img.draw(in: CGRect(x: margin, y: y, width: iw, height: ih))
                y += ih + 12
            }

            // Question text
            let qt = q.question.displayText
            if !qt.isEmpty {
                y += drawMultiline(qt, font: bodyFont, x: margin, y: y, width: w) + 12
            } else {
                y += drawString("[Question text not available]",
                                font: UIFont.italicSystemFont(ofSize: options.questionFontSize),
                                color: .gray, alignment: .left,
                                x: margin, y: y, width: w) + 12
            }

            // Subquestions
            if let subs = q.question.subquestions, !subs.isEmpty {
                let indent: CGFloat = 20
                let subW = w - indent - 20
                for sub in subs {
                    y += 8
                    y += drawString("  (\(sub.id))", font: subFont, color: blue, alignment: .left,
                                    x: margin + indent, y: y, width: subW) + 6

                    let subImg = croppedImages[sub.id] ?? image
                    if let img = subImg {
                        let ih = scaledImageHeight(img, maxWidth: subW, maxHeight: options.maxSubImageHeight)
                        let iw = ih * (img.size.width / img.size.height)
                        img.draw(in: CGRect(x: margin + indent + 20, y: y, width: iw, height: ih))
                        y += ih + 8
                    }

                    if !sub.questionText.isEmpty {
                        y += drawMultiline(sub.questionText, font: bodyFont,
                                           x: margin + indent + 20, y: y, width: subW) + 8
                    }
                }
            }
        }
        return y
    }

    // MARK: - UIKit Drawing Helpers

    /// Converts LaTeX-formatted text to plain text suitable for PDF drawing.
    /// Uses the project's existing LaTeXToHTMLConverter.extractPlainText() to strip
    /// \command{text} patterns, then removes math delimiters (\( \) \[ \] $$ $).
    private func plainText(_ input: String) -> String {
        // Step 1: use existing converter to unwrap \command{content} → content
        var s = LaTeXToHTMLConverter.shared.extractPlainText(input)

        // Step 2: strip display/inline math delimiters
        s = s.replacingOccurrences(of: "\\[", with: "").replacingOccurrences(of: "\\]", with: "")
        s = s.replacingOccurrences(of: "\\(", with: "").replacingOccurrences(of: "\\)", with: "")
        s = s.replacingOccurrences(of: "$$", with: "")

        // Step 3: strip lone $ signs (single-dollar inline math delimiters)
        s = s.replacingOccurrences(of: "$", with: "")

        // Step 4: strip remaining bare LaTeX command tokens (no braces)
        let bareCommands = ["\\frac", "\\times", "\\div", "\\cdot", "\\sqrt",
                            "\\pi", "\\alpha", "\\beta", "\\theta", "\\gamma",
                            "\\delta", "\\lambda", "\\mu", "\\sigma", "\\omega",
                            "\\sum", "\\int", "\\infty", "\\leq", "\\geq",
                            "\\neq", "\\approx", "\\pm", "\\rightarrow",
                            "\\leftarrow", "\\Rightarrow", "\\left", "\\right",
                            "\\begin", "\\end", "\\quad", "\\qquad",
                            "\\,", "\\;", "\\:", "\\!", "\\\\"]
        for cmd in bareCommands { s = s.replacingOccurrences(of: cmd, with: " ") }

        // Collapse multiple spaces
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Draws a rectangle border in UIKit-flipped coordinate space (inside withUIKitContext).
    private func strokeRect(_ rect: CGRect, color: UIColor, lineWidth: CGFloat) {
        let path = UIBezierPath(rect: rect)
        color.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    /// Executes a drawing block with the coordinate system
    /// flipped to top-left origin (PDF native is bottom-left).
    /// Graphics state is saved/restored around the whole block so no transformations leak.
    private func withUIKitContext(ctx: CGContext, pageRect: CGRect, block: () -> Void) {
        ctx.saveGState()
        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: pageRect.height)
        ctx.scaleBy(x: 1, y: -1)
        block()
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    /// Draws a single-line string and returns its rendered height.
    @discardableResult
    private func drawString(
        _ text: String,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        str.draw(in: CGRect(x: x, y: y, width: width, height: font.lineHeight * 2))
        return font.lineHeight
    }

    /// Draws word-wrapped text, returns rendered height.
    @discardableResult
    private func drawMultiline(
        _ text: String,
        font: UIFont,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        style.lineBreakMode = .byWordWrapping

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.black,
            .paragraphStyle: style
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let h = str.boundingRect(
            with: CGSize(width: width, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height
        str.draw(in: CGRect(x: x, y: y, width: width, height: h))
        return h
    }

    /// Calculates the height multiline text would occupy — used for page-break prediction.
    private func multilineHeight(_ text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).boundingRect(
            with: CGSize(width: width, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        ).height
    }

    /// Scales image height to fit within maxWidth × maxHeight while preserving aspect ratio.
    private func scaledImageHeight(_ image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let aspect = image.size.width / image.size.height
        if aspect > 1 {
            let h = maxWidth / aspect
            return min(h, maxHeight)
        } else {
            return min(maxWidth / aspect, maxHeight)
        }
    }

    private func fillWhite(ctx: CGContext) {
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: pageSize))
    }

    // MARK: - Date Helpers

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: Date())
    }

    private func formattedDateLong() -> String {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: Date())
    }
}
