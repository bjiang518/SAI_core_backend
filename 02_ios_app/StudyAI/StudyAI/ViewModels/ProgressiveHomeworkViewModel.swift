//
//  ProgressiveHomeworkViewModel.swift
//  StudyAI
//
//  ViewModel for progressive homework grading system
//  Handles two-phase grading: Parse → Grade (parallel)
//

import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
class ProgressiveHomeworkViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var state = HomeworkGradingState()
    @Published var isLoading = false
    @Published var loadingMessage = ""
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var isComplete = false

    // Progress tracking
    @Published var currentPhase: GradingPhase = .idle
    @Published var gradedCount = 0
    @Published var totalQuestions = 0

    // MARK: - Dependencies

    private let networkService = NetworkService.shared
    private let concurrentLimit = 5  // Maximum concurrent grading requests

    // MARK: - Phase Enum

    enum GradingPhase {
        case idle
        case parsing          // Phase 1: Parsing questions
        case cropping         // Cropping images
        case grading          // Phase 2: Grading questions
        case complete         // All done
        case error(String)    // Error occurred
    }

    // MARK: - Main Entry Point

    /// Process homework with progressive grading
    /// - Parameters:
    ///   - originalImage: Original UIImage captured from camera
    ///   - base64Image: Base64 encoded JPEG string
    ///   - preParsedQuestions: Optional pre-parsed questions from Pro Mode (skips Phase 1 if provided)
    func processHomework(originalImage: UIImage, base64Image: String, preParsedQuestions: ParseHomeworkQuestionsResponse? = nil) async {
        print("🚀 === STARTING PROGRESSIVE HOMEWORK GRADING ===")

        do {
            // Phase 1: Parse questions (skip if Pro Mode already parsed)
            if let preParsed = preParsedQuestions {
                print("⚡ PRO MODE: Using pre-parsed questions, skipping Phase 1")
                await usePreParsedQuestions(preParsed, originalImage: originalImage)
            } else {
                print("📝 AUTO MODE: Parsing questions from scratch")
                try await parseQuestions(originalImage: originalImage, base64Image: base64Image)
            }

            // Phase 2: Grade all questions in parallel
            await gradeAllQuestions()

            // Mark as complete
            await MainActor.run {
                self.currentPhase = .complete
                self.isComplete = true
                self.isLoading = false
                print("🎉 === ALL GRADING COMPLETE ===")
            }

        } catch {
            await MainActor.run {
                self.currentPhase = .error(error.localizedDescription)
                self.errorMessage = error.localizedDescription
                self.showError = true
                self.isLoading = false
                print("❌ Grading failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Use Pre-Parsed Questions (Pro Mode)

    private func usePreParsedQuestions(_ parseResponse: ParseHomeworkQuestionsResponse, originalImage: UIImage) async {
        print("📊 Using \(parseResponse.totalQuestions) pre-parsed questions from Pro Mode")

        await MainActor.run {
            self.currentPhase = .parsing
            self.isLoading = false  // Not loading since we already have data
        }

        // Store subject
        await MainActor.run {
            self.state.subject = parseResponse.subject
            self.state.subjectConfidence = parseResponse.subjectConfidence
            self.totalQuestions = parseResponse.totalQuestions
        }

        // Convert to ProgressiveQuestionWithGrade (parseResponse.questions are already ProgressiveQuestion type)
        await MainActor.run {
            self.state.questions = parseResponse.questions.map { question in
                ProgressiveQuestionWithGrade(
                    id: question.id,
                    question: question,
                    grade: nil,
                    isGrading: false,
                    gradingError: nil
                )
            }
            print("✅ Loaded \(self.state.questions.count) pre-parsed questions")
        }

        // Phase 1.5: Crop images (if needed)
        await cropImages(originalImage: originalImage, questions: parseResponse.questions)
    }

    // MARK: - Phase 1: Parse Questions

    private func parseQuestions(originalImage: UIImage, base64Image: String) async throws {
        print("📝 === PHASE 1: PARSING QUESTIONS ===")

        await MainActor.run {
            self.currentPhase = .parsing
            self.isLoading = true
            self.loadingMessage = "Analyzing homework..."
        }

        // Call backend to parse questions
        let parseResponse = try await networkService.parseHomeworkQuestions(
            base64Image: base64Image,
            parsingMode: "standard"
        )

        guard parseResponse.success else {
            throw ProgressiveGradingError.parsingFailed(parseResponse.error ?? "Unknown error")
        }

        print("✅ Parsed \(parseResponse.totalQuestions) questions")

        // DETAILED PHASE 1 LOGGING FOR DEBUGGING IMAGE SEGMENTATION
        print("\n" + String(repeating: "=", count: 80))
        print("📊 === PHASE 1 COMPLETE: DETAILED PARSING RESULTS ===")
        print(String(repeating: "=", count: 80))

        // Subject information
        print("\n📚 SUBJECT DETECTION:")
        print("   Subject: \(parseResponse.subject)")
        print("   Confidence: \(String(format: "%.2f", parseResponse.subjectConfidence))")

        // Overall statistics
        print("\n📈 STATISTICS:")
        print("   Total Questions: \(parseResponse.totalQuestions)")
        let questionsWithImages = parseResponse.questions.filter { $0.hasImage == true }
        print("   Questions with Images: \(questionsWithImages.count)")
        print("   Questions without Images: \(parseResponse.totalQuestions - questionsWithImages.count)")

        // Image dimensions for coordinate reference
        let imageWidth = originalImage.size.width
        let imageHeight = originalImage.size.height
        print("\n🖼️  ORIGINAL IMAGE DIMENSIONS:")
        print("   Width: \(Int(imageWidth))px")
        print("   Height: \(Int(imageHeight))px")

        // Detailed question-by-question breakdown
        print("\n" + String(repeating: "-", count: 80))
        print("📝 DETAILED QUESTION BREAKDOWN:")
        print(String(repeating: "-", count: 80))

        for (index, question) in parseResponse.questions.enumerated() {
            print("\n📌 Question \(index + 1) / \(parseResponse.totalQuestions)")
            print("   ID: \(question.id)")
            print("   Type: \(question.questionType ?? "Unknown")")
            print("   Has Image: \(question.hasImage == true ? "YES ✅" : "NO")")

            // Question text (truncated if too long)
            let questionText = question.questionText ?? ""
            let questionPreview = questionText.count > 100
                ? String(questionText.prefix(100)) + "..."
                : questionText
            print("   Question: \"\(questionPreview)\"")

            // Student answer (truncated if too long)
            let studentAnswer = question.studentAnswer ?? ""
            let answerPreview = studentAnswer.count > 100
                ? String(studentAnswer.prefix(100)) + "..."
                : studentAnswer
            print("   Student Answer: \"\(answerPreview.isEmpty ? "(empty)" : answerPreview)\"")

            // Image region details (if present)
            if let region = question.imageRegion {
                print("\n   📍 IMAGE REGION COORDINATES:")
                print("   Description: \(region.description ?? "N/A")")

                // Normalized coordinates [0-1]
                print("\n   ⚡ Normalized Coordinates (0.0 - 1.0):")
                print("      Top-Left:     [\(String(format: "%.4f", region.topLeft[0])), \(String(format: "%.4f", region.topLeft[1]))]")
                print("      Bottom-Right: [\(String(format: "%.4f", region.bottomRight[0])), \(String(format: "%.4f", region.bottomRight[1]))]")

                // Calculate pixel coordinates
                let pixelX1 = CGFloat(region.topLeft[0]) * imageWidth
                let pixelY1 = CGFloat(region.topLeft[1]) * imageHeight
                let pixelX2 = CGFloat(region.bottomRight[0]) * imageWidth
                let pixelY2 = CGFloat(region.bottomRight[1]) * imageHeight

                let cropWidth = pixelX2 - pixelX1
                let cropHeight = pixelY2 - pixelY1

                print("\n   📐 Pixel Coordinates (Absolute):")
                print("      Top-Left:     [\(Int(pixelX1))px, \(Int(pixelY1))px]")
                print("      Bottom-Right: [\(Int(pixelX2))px, \(Int(pixelY2))px]")
                print("      Crop Width:   \(Int(cropWidth))px")
                print("      Crop Height:  \(Int(cropHeight))px")
                print("      Crop Area:    \(Int(cropWidth * cropHeight))px² (\(String(format: "%.1f", (cropWidth * cropHeight) / (imageWidth * imageHeight) * 100))% of image)")

                // Validation warnings
                if region.topLeft[0] < 0 || region.topLeft[1] < 0 ||
                   region.bottomRight[0] > 1 || region.bottomRight[1] > 1 {
                    print("\n      ⚠️  WARNING: Coordinates out of [0-1] range!")
                }

                if region.topLeft[0] >= region.bottomRight[0] ||
                   region.topLeft[1] >= region.bottomRight[1] {
                    print("\n      ⚠️  WARNING: Invalid region (top-left should be < bottom-right)!")
                }

                if cropWidth < 50 || cropHeight < 50 {
                    print("\n      ⚠️  WARNING: Region very small (\(Int(cropWidth))x\(Int(cropHeight))px)")
                }
            }

            print(String(repeating: "-", count: 80))
        }

        print("\n" + String(repeating: "=", count: 80))
        print("✅ PHASE 1 LOGGING COMPLETE")
        print(String(repeating: "=", count: 80) + "\n")

        // Update state with parsed questions
        await MainActor.run {
            self.state.subject = parseResponse.subject
            self.state.subjectConfidence = parseResponse.subjectConfidence
            self.totalQuestions = parseResponse.totalQuestions

            // Convert to ProgressiveQuestionWithGrade
            self.state.questions = parseResponse.questions.map { question in
                ProgressiveQuestionWithGrade(
                    id: question.id,
                    question: question,
                    grade: nil,
                    isGrading: false,
                    gradingError: nil
                )
            }
        }

        // Phase 1.5: Crop images
        await cropImages(originalImage: originalImage, questions: parseResponse.questions)
    }

    // MARK: - Image Cropping

    private func cropImages(originalImage: UIImage, questions: [ProgressiveQuestion]) async {
        print("\n✂️  === CROPPING IMAGE REGIONS ===")

        await MainActor.run {
            self.currentPhase = .cropping
            self.loadingMessage = "Preparing diagrams..."
        }

        // Filter questions that need images
        let questionsWithImages = questions.filter { $0.hasImage == true && $0.imageRegion != nil }
        print("📊 Questions needing image context: \(questionsWithImages.count)")

        guard !questionsWithImages.isEmpty else {
            print("⏭️  No images to crop, skipping cropping phase\n")
            return
        }

        // Build image regions
        let regions = questionsWithImages.compactMap { question -> ImageCropper.ImageRegion? in
            guard let imageRegion = question.imageRegion else { return nil }

            return ImageCropper.ImageRegion(
                questionId: question.id,
                topLeft: imageRegion.topLeft,
                bottomRight: imageRegion.bottomRight,
                description: imageRegion.description ?? "Diagram"
            )
        }

        print("\n🔧 Starting batch crop operation for \(regions.count) regions...")

        // Batch crop
        let croppedUIImages = ImageCropper.batchCrop(
            image: originalImage,
            regions: regions
        )

        print("\n📸 CROPPING RESULTS:")
        print(String(repeating: "-", count: 60))

        // Convert UIImages to JPEG Data and store
        await MainActor.run {
            for (questionId, uiImage) in croppedUIImages {
                let imageSize = uiImage.size
                let scale = uiImage.scale

                print("\n   ✅ Q\(questionId) Cropped Successfully:")
                print("      Size: \(Int(imageSize.width))x\(Int(imageSize.height))px")
                print("      Scale: \(scale)x")

                if let jpegData = uiImage.jpegData(compressionQuality: 0.85) {
                    let jpegSizeKB = Double(jpegData.count) / 1024.0
                    self.state.croppedImages[questionId] = jpegData
                    print("      JPEG Size: \(String(format: "%.1f", jpegSizeKB))KB (0.85 quality)")
                } else {
                    print("      ⚠️  WARNING: Failed to convert to JPEG")
                }
            }

            // Check for missing crops
            let expectedQuestionIds = Set(questionsWithImages.map { $0.id })
            let actualQuestionIds = Set(croppedUIImages.keys)
            let missingIds = expectedQuestionIds.subtracting(actualQuestionIds)

            if !missingIds.isEmpty {
                print("\n   ⚠️  WARNING: Failed to crop \(missingIds.count) images:")
                for id in missingIds.sorted() {
                    print("      - Q\(id)")
                }
            }
        }

        print(String(repeating: "-", count: 60))
        print("✅ Cropping complete: \(croppedUIImages.count)/\(regions.count) successful\n")
    }

    // MARK: - Phase 2: Grade All Questions

    private func gradeAllQuestions() async {
        print("🚀 === PHASE 2: GRADING QUESTIONS ===")

        await MainActor.run {
            self.currentPhase = .grading
            self.loadingMessage = "Grading questions..."
            self.gradedCount = 0
        }

        let questions = await state.questions

        // Use TaskGroup for controlled concurrency
        await withTaskGroup(of: (Int, ProgressiveGradeResult?, String?).self) { group in
            var activeTaskCount = 0
            var questionIndex = 0

            while questionIndex < questions.count || activeTaskCount > 0 {

                // Launch new tasks (up to concurrentLimit)
                while activeTaskCount < concurrentLimit && questionIndex < questions.count {
                    let question = questions[questionIndex]

                    // Mark as grading
                    await MainActor.run {
                        if let index = self.state.questions.firstIndex(where: { $0.id == question.id }) {
                            self.state.questions[index].isGrading = true
                        }
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
                    await MainActor.run {
                        if let index = self.state.questions.firstIndex(where: { $0.id == questionId }) {
                            self.state.questions[index].grade = grade
                            self.state.questions[index].gradingError = error
                            self.state.questions[index].isGrading = false
                        }

                        self.gradedCount += 1

                        // Trigger animation
                        withAnimation(.spring()) {
                            self.state = self.state  // Trigger UI update
                        }

                        print("✅ Q\(questionId) graded (\(self.gradedCount)/\(self.totalQuestions))")
                    }
                }
            }
        }

        print("✅ === ALL QUESTIONS GRADED ===")
    }

    // MARK: - Single Question Grading

    /// Grade a single question (handles both regular and parent questions)
    /// For parent questions: grades all subquestions in parallel
    /// For regular questions: grades the single question
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
                    await MainActor.run {
                        if let index = self.state.questions.firstIndex(where: { $0.id == question.id }) {
                            if let grade = grade {
                                self.state.questions[index].subquestionGrades[subId] = grade
                            }
                            if let error = error {
                                self.state.questions[index].subquestionErrors[subId] = error
                            }
                            self.state.questions[index].subquestionGradingStatus[subId] = false
                        }
                    }
                }
            }

            // Return success (individual subquestion grades are stored in subquestionGrades)
            return (question.id, nil, nil)

        } else {
            // Regular question: grade normally
            do {
                // Get context image if available
                let contextImage = await getContextImageBase64(for: question.id)

                // Call grading endpoint
                let response = try await networkService.gradeSingleQuestion(
                    questionText: question.displayText,
                    studentAnswer: question.displayStudentAnswer,
                    subject: await state.subject,
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

    /// Grade a single subquestion within a parent question
    private func gradeSubquestion(
        subquestion: ProgressiveSubquestion,
        parentQuestionId: Int
    ) async -> (String, ProgressiveGradeResult?, String?) {

        print("   📝 Grading subquestion \(subquestion.id)...")

        do {
            // Get context image from parent question if available
            let contextImage = await getContextImageBase64(for: parentQuestionId)

            // Call grading endpoint
            let response = try await networkService.gradeSingleQuestion(
                questionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                subject: await state.subject,
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

    // MARK: - Helper Methods

    private func getContextImageBase64(for questionId: Int) async -> String? {
        guard let jpegData = await state.croppedImages[questionId] else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    // MARK: - User Actions

    /// Navigate to AI chat for help with this question
    func askAIForHelp(questionId: Int) {
        print("💬 Opening AI chat for Q\(questionId)")
        // TODO: Navigate to SessionChatView with question context
    }

    /// Save incorrect questions to collection (wrong answer book)
    func saveToCollection() {
        print("⭐ Saving to collection...")

        let incorrectQuestions = state.questions.filter { question in
            guard let grade = question.grade else { return false }
            return !grade.isCorrect  // Save incorrect or partial credit
        }

        print("📚 Saving \(incorrectQuestions.count) questions to collection")

        // TODO: Implement actual save logic
        // This would typically:
        // 1. Create archive entry in database
        // 2. Store questions with student answers
        // 3. Mark for review in wrong answer book
    }

    /// Retry grading for failed questions
    func retryFailedQuestions() async {
        print("🔄 Retrying failed questions...")

        let failedQuestions = state.questions.filter { $0.gradingError != nil }

        guard !failedQuestions.isEmpty else {
            print("No failed questions to retry")
            return
        }

        print("Retrying \(failedQuestions.count) failed questions")

        // Reset error state
        await MainActor.run {
            for i in 0..<self.state.questions.count {
                if self.state.questions[i].gradingError != nil {
                    self.state.questions[i].gradingError = nil
                    self.state.questions[i].grade = nil
                }
            }
        }

        // Re-grade
        await gradeAllQuestions()
    }

    // MARK: - Reset

    func reset() {
        state = HomeworkGradingState()
        isLoading = false
        loadingMessage = ""
        errorMessage = nil
        showError = false
        isComplete = false
        currentPhase = .idle
        gradedCount = 0
        totalQuestions = 0
    }
}
