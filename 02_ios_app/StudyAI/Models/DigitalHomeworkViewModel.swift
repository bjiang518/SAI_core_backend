//
//  DigitalHomeworkViewModel.swift
//  StudyAI
//
//  ViewModel for Digital Homework View
//  Manages annotations, image cropping, and AI grading
//

import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
class DigitalHomeworkViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var questions: [ProgressiveQuestionWithGrade] = []
    @Published var annotations: [QuestionAnnotation] = []
    @Published var selectedAnnotationId: UUID?
    @Published var croppedImages: [Int: UIImage] = [:]  // questionId -> cropped image

    @Published var isGrading = false
    @Published var gradedCount = 0
    @Published var totalQuestions = 0

    @Published var showAnnotationMode = false
    @Published var showImageInFullScreen = false
    @Published var showImagePreview = true  // 控制图片预览显示

    // Archive selection mode
    @Published var isArchiveMode = false
    @Published var selectedQuestionIds: Set<Int> = []

    // MARK: - Private Properties

    private var parseResults: ParseHomeworkQuestionsResponse?
    private var originalImage: UIImage?
    private var subject: String = ""

    private let networkService = NetworkService.shared
    private let concurrentLimit = 5

    // MARK: - Computed Properties

    var allQuestionsGraded: Bool {
        return !questions.isEmpty && questions.allSatisfy { $0.isComplete }
    }

    var hasValidAnnotations: Bool {
        return !annotations.isEmpty && annotations.allSatisfy { $0.questionNumber != nil }
    }

    var availableQuestionNumbers: [String] {
        guard let results = parseResults else { return [] }
        return results.questions.compactMap { $0.questionNumber }
    }

    // MARK: - Setup

    func setup(parseResults: ParseHomeworkQuestionsResponse, originalImage: UIImage) {
        self.parseResults = parseResults
        self.originalImage = originalImage
        self.subject = parseResults.subject
        self.totalQuestions = parseResults.totalQuestions

        // Convert parsed questions to ProgressiveQuestionWithGrade
        self.questions = parseResults.questions.map { question in
            ProgressiveQuestionWithGrade(
                id: question.id,
                question: question,
                grade: nil,
                isGrading: false,
                gradingError: nil
            )
        }

        print("✅ DigitalHomeworkView setup: \(totalQuestions) questions")
    }

    // MARK: - Annotation Management

    func addAnnotation(at point: CGPoint, imageSize: CGSize) {
        guard let originalImage = originalImage else { return }

        // Calculate normalized coordinates
        let normalizedTopLeft = [
            Double(point.x / imageSize.width),
            Double(point.y / imageSize.height)
        ]

        // Create square annotation (100x100 points initial size)
        let squareSize: CGFloat = 100
        let normalizedBottomRight = [
            Double((point.x + squareSize) / imageSize.width),
            Double((point.y + squareSize) / imageSize.height)
        ]

        let newAnnotation = QuestionAnnotation(
            topLeft: normalizedTopLeft,
            bottomRight: normalizedBottomRight,
            questionNumber: nil,
            color: annotationColor(for: annotations.count)
        )

        annotations.append(newAnnotation)
        selectedAnnotationId = newAnnotation.id

        print("📝 Created annotation at (\(Int(point.x)), \(Int(point.y)))")
    }

    func updateAnnotationQuestionNumber(annotationId: UUID, questionNumber: String) {
        guard let index = annotations.firstIndex(where: { $0.id == annotationId }) else { return }
        annotations[index].questionNumber = questionNumber

        print("✅ Updated annotation \(index) → Q\(questionNumber)")

        // Trigger image cropping for this annotation
        cropImageForAnnotation(annotations[index])
    }

    func deleteAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }

        print("🗑️ Deleted annotation \(id)")
    }

    func resetAnnotations() {
        annotations.removeAll()
        croppedImages.removeAll()
        selectedAnnotationId = nil

        print("🔄 Reset all annotations")
    }

    // MARK: - Image Cropping

    private func cropImageForAnnotation(_ annotation: QuestionAnnotation) {
        guard let originalImage = originalImage,
              let questionNumber = annotation.questionNumber,
              let questionId = parseResults?.questions.first(where: { $0.questionNumber == questionNumber })?.id else {
            return
        }

        // Convert normalized coordinates to pixel coordinates
        let imageWidth = originalImage.size.width
        let imageHeight = originalImage.size.height

        let x = CGFloat(annotation.topLeft[0]) * imageWidth
        let y = CGFloat(annotation.topLeft[1]) * imageHeight
        let width = CGFloat(annotation.bottomRight[0] - annotation.topLeft[0]) * imageWidth
        let height = CGFloat(annotation.bottomRight[1] - annotation.topLeft[1]) * imageHeight

        let cropRect = CGRect(x: x, y: y, width: width, height: height)

        // Crop image
        if let croppedCGImage = originalImage.cgImage?.cropping(to: cropRect) {
            let croppedUIImage = UIImage(cgImage: croppedCGImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
            croppedImages[questionId] = croppedUIImage

            print("✂️ Cropped image for Q\(questionNumber) (id: \(questionId))")
        } else {
            print("❌ Failed to crop image for Q\(questionNumber)")
        }
    }

    func getCroppedImage(for questionId: Int) -> UIImage? {
        return croppedImages[questionId]
    }

    // MARK: - AI Grading

    func startGrading() async {
        print("🚀 === STARTING AI GRADING ===")

        // 隐藏图片预览（触发向上飞走动画）
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showImagePreview = false
        }

        isGrading = true
        gradedCount = 0

        // Use TaskGroup for parallel grading
        await withTaskGroup(of: (Int, ProgressiveGradeResult?, String?).self) { group in
            var activeTaskCount = 0
            var questionIndex = 0

            while questionIndex < questions.count || activeTaskCount > 0 {

                // Launch new tasks (up to concurrentLimit)
                while activeTaskCount < concurrentLimit && questionIndex < questions.count {
                    let question = questions[questionIndex]

                    // Mark as grading
                    if let index = questions.firstIndex(where: { $0.id == question.id }) {
                        questions[index].isGrading = true
                    }

                    group.addTask {
                        await self.gradeQuestion(question)
                    }

                    questionIndex += 1
                    activeTaskCount += 1
                }

                // Wait for one task to complete
                if let (questionId, grade, error) = await group.next() {
                    activeTaskCount -= 1

                    // Update state with result
                    if let index = questions.firstIndex(where: { $0.id == questionId }) {
                        questions[index].grade = grade
                        questions[index].gradingError = error
                        questions[index].isGrading = false
                    }

                    gradedCount += 1

                    print("✅ Q\(questionId) graded (\(gradedCount)/\(totalQuestions))")
                }
            }
        }

        isGrading = false
        print("✅ === ALL QUESTIONS GRADED ===")
    }

    private func gradeQuestion(_ questionWithGrade: ProgressiveQuestionWithGrade) async -> (Int, ProgressiveGradeResult?, String?) {
        let question = questionWithGrade.question

        // Check if this is a parent question with subquestions
        if question.isParentQuestion, let subquestions = question.subquestions {
            print("📋 Q\(question.id) is parent question with \(subquestions.count) subquestions")

            // Grade all subquestions in parallel
            await withTaskGroup(of: (String, ProgressiveGradeResult?, String?).self) { group in
                for subquestion in subquestions {
                    group.addTask {
                        await self.gradeSubquestion(
                            subquestion: subquestion,
                            parentQuestionId: question.id
                        )
                    }
                }

                // Collect all subquestion grades
                for await (subId, grade, error) in group {
                    if let index = questions.firstIndex(where: { $0.id == question.id }) {
                        if let grade = grade {
                            questions[index].subquestionGrades[subId] = grade
                        }
                        if let error = error {
                            questions[index].subquestionErrors[subId] = error
                        }
                        questions[index].subquestionGradingStatus[subId] = false
                    }
                }
            }

            // Return success (individual subquestion grades are stored in subquestionGrades)
            return (question.id, nil, nil)

        } else {
            // Regular question: grade normally
            do {
                // Get context image if available
                let contextImage = getCroppedImageBase64(for: question.id)

                // Call grading endpoint
                let response = try await networkService.gradeSingleQuestion(
                    questionText: question.displayText,
                    studentAnswer: question.displayStudentAnswer,
                    subject: subject,
                    contextImageBase64: contextImage
                )

                if response.success, let grade = response.grade {
                    return (question.id, grade, nil)
                } else {
                    let error = response.error ?? "Grading failed"
                    print("❌ Q\(question.id) grading error: \(error)")
                    return (question.id, nil, error)
                }

            } catch {
                print("❌ Q\(question.id) exception: \(error.localizedDescription)")
                return (question.id, nil, error.localizedDescription)
            }
        }
    }

    private func gradeSubquestion(
        subquestion: ProgressiveSubquestion,
        parentQuestionId: Int
    ) async -> (String, ProgressiveGradeResult?, String?) {

        print("   📝 Grading subquestion \(subquestion.id)...")

        do {
            // Get context image from parent question if available
            let contextImage = getCroppedImageBase64(for: parentQuestionId)

            // Call grading endpoint
            let response = try await networkService.gradeSingleQuestion(
                questionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                subject: subject,
                contextImageBase64: contextImage
            )

            if response.success, let grade = response.grade {
                print("   ✅ Subquestion \(subquestion.id): score \(grade.score)")
                return (subquestion.id, grade, nil)
            } else {
                let error = response.error ?? "Grading failed"
                print("   ❌ Subquestion \(subquestion.id) error: \(error)")
                return (subquestion.id, nil, error)
            }

        } catch {
            print("   ❌ Subquestion \(subquestion.id) exception: \(error.localizedDescription)")
            return (subquestion.id, nil, error.localizedDescription)
        }
    }

    private func getCroppedImageBase64(for questionId: Int) -> String? {
        guard let image = croppedImages[questionId],
              let jpegData = image.jpegData(compressionQuality: 0.85) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    // MARK: - User Actions

    func askAIForHelp(questionId: Int) {
        print("💬 Opening AI chat for Q\(questionId)")
        // TODO: Navigate to SessionChatView with question context
        // This will be implemented when integrating with SessionChatView
    }

    func archiveQuestion(questionId: Int) {
        // TODO: Implement individual question archiving
        // This will require mapping ProgressiveQuestion to ParsedQuestion format
        // and using QuestionArchiveService.archiveQuestions()
        print("⚠️ Archive question feature not yet implemented for Q\(questionId)")
        print("💡 For now, questions are preserved in the session and can be archived as a whole")
    }

    func markProgress() {
        Task {
            do {
                // Calculate statistics
                let totalCorrect = questions.filter { $0.grade?.isCorrect == true }.count
                let totalQuestions = questions.count

                // TODO: Update progress using PointsEarningSystem when available
                print("✅ Progress marked: \(totalCorrect)/\(totalQuestions) correct")
            }
        }
    }

    // MARK: - Archive Selection Mode

    func toggleArchiveMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isArchiveMode.toggle()
            if !isArchiveMode {
                selectedQuestionIds.removeAll()
            }
        }
    }

    func toggleQuestionSelection(questionId: Int) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            if selectedQuestionIds.contains(questionId) {
                selectedQuestionIds.remove(questionId)
            } else {
                selectedQuestionIds.insert(questionId)
            }
        }
    }

    func batchArchiveSelected() async {
        guard !selectedQuestionIds.isEmpty else { return }

        print("📦 Archiving \(selectedQuestionIds.count) questions...")

        // TODO: Implement batch archiving via QuestionArchiveService
        // For now, remove selected questions from the list

        await MainActor.run {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                questions.removeAll { selectedQuestionIds.contains($0.question.id) }
                selectedQuestionIds.removeAll()
                isArchiveMode = false
            }
        }

        print("✅ Archived \(selectedQuestionIds.count) questions")
    }

    // MARK: - Helper Methods

    private func annotationColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        return colors[index % colors.count]
    }
}

// MARK: - Question Annotation Model

struct QuestionAnnotation: Identifiable {
    let id = UUID()
    var topLeft: [Double]       // Normalized [0-1] coordinates
    var bottomRight: [Double]   // Normalized [0-1] coordinates
    var questionNumber: String? // Maps to question number (not id)
    let color: Color
}
