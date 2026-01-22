//
//  ProgressiveHomeworkViewModel.swift
//  StudyAI
//
//  ⚠️ NOTE: This ViewModel is used by ProgressiveHomeworkView (alternative grading flow)
//  🔴 NOT USED in main homework flow (DirectAIHomeworkView → HomeworkSummaryView → DigitalHomeworkView)
//
//  Main flow uses: DigitalHomeworkViewModel + DigitalHomeworkView
//  This file exists for: Direct progressive grading sheet (showProgressiveGrading)
//
//  ViewModel for progressive homework grading system
//  Handles two-phase grading: Parse → Grade (parallel)
//

import Foundation
import SwiftUI
import UIKit
import Combine

// MARK: - Production Logging Safety
// Disable debug print statements in production builds to prevent homework data exposure
#if !DEBUG
private func print(_ items: Any...) { }
private func debugPrint(_ items: Any...) { }
#endif

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
    private var selectedModelProvider: String = "openai"  // Track which AI model is being used

    // IMPORTANT: Gemini has lower concurrent request limits than OpenAI
    // - OpenAI: Can handle 5-10 concurrent requests reliably
    // - Gemini: Should limit to 2 to avoid 503/rate limit errors (questions 4+ often skip)
    private var concurrentLimit: Int {
        return selectedModelProvider == "gemini" ? 2 : 5
    }

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
    ///   - modelProvider: AI model to use for grading ("openai" or "gemini")
    func processHomework(originalImage: UIImage, base64Image: String, preParsedQuestions: ParseHomeworkQuestionsResponse? = nil, modelProvider: String = "openai") async {
        print("🚀 === STARTING PROGRESSIVE HOMEWORK GRADING ===")
        print("🤖 AI Model: \(modelProvider)")

        // Store model provider for concurrentLimit calculation
        await MainActor.run {
            self.selectedModelProvider = modelProvider
        }

        do {
            // Phase 1: Parse questions (skip if Pro Mode already parsed)
            if let preParsed = preParsedQuestions {
                print("⚡ PRO MODE: Using pre-parsed questions, skipping Phase 1")
                await usePreParsedQuestions(preParsed, originalImage: originalImage)
            } else {
                print("📝 AUTO MODE: Parsing questions from scratch")
                try await parseQuestions(originalImage: originalImage, base64Image: base64Image, modelProvider: modelProvider)
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
        let backendDimensions = parseResponse.processedImageDimensions
        await cropImages(
            originalImage: originalImage,
            questions: parseResponse.questions,
            backendImageWidth: backendDimensions?.width,
            backendImageHeight: backendDimensions?.height
        )
    }

    // MARK: - Phase 1: Parse Questions

    private func parseQuestions(originalImage: UIImage, base64Image: String, modelProvider: String = "openai") async throws {
        print("📝 === PHASE 1: PARSING QUESTIONS ===")
        print("🤖 Using \(modelProvider) for parsing")

        await MainActor.run {
            self.currentPhase = .parsing
            self.isLoading = true
            self.loadingMessage = "Analyzing homework..."
        }

        // Call backend to parse questions with selected AI model
        let parseResponse = try await networkService.parseHomeworkQuestions(
            base64Image: base64Image,
            parsingMode: "standard",
            modelProvider: modelProvider
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

        // Phase 1.5: Crop images with backend dimensions for accurate scaling
        let backendDimensions = parseResponse.processedImageDimensions
        if let dims = backendDimensions {
            print("📏 Backend processed image dimensions: \(dims.width)x\(dims.height)")
        } else {
            print("⚠️  Backend did not return processed_image_dimensions (using legacy mode)")
        }
        await cropImages(
            originalImage: originalImage,
            questions: parseResponse.questions,
            backendImageWidth: backendDimensions?.width,
            backendImageHeight: backendDimensions?.height
        )
    }

    // MARK: - Image Cropping

    private func cropImages(
        originalImage: UIImage,
        questions: [ProgressiveQuestion],
        backendImageWidth: Int? = nil,
        backendImageHeight: Int? = nil
    ) async {
        print("\n✂️  === CROPPING IMAGE REGIONS ===")

        if let w = backendImageWidth, let h = backendImageHeight {
            print("🔧 Using backend image dimensions for coordinate scaling: \(w)x\(h)")
        } else {
            print("⚠️  Backend dimensions not available - cropping without scaling")
        }

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

        // Batch crop with backend dimensions for accurate coordinate scaling
        let croppedUIImages = ImageCropper.batchCrop(
            image: originalImage,
            regions: regions,
            backendImageWidth: backendImageWidth,
            backendImageHeight: backendImageHeight
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
        print("🤖 AI Model: \(selectedModelProvider)")
        print("⚡ Concurrent Limit: \(concurrentLimit) (optimized for \(selectedModelProvider.uppercased()))")

        self.currentPhase = .grading
        self.loadingMessage = "Grading questions..."
        self.gradedCount = 0

        let questions = state.questions

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

        print("🔥🔥🔥 === gradeQuestion() CALLED for Q\(question.id) ===")
        print("🔥 Has subquestions: \(question.subquestions != nil)")
        print("🔥 Subquestion count: \(question.subquestions?.count ?? 0)")
        print("🔥 isParent flag: \(question.isParent ?? false)")

        // Check if this question has subquestions (regardless of isParent flag)
        // Fix: AI may return subquestions without setting isParent=true
        if let subquestions = question.subquestions, !subquestions.isEmpty {
            print("📋 Q\(question.id) has \(subquestions.count) subquestions (isParent=\(question.isParent ?? false))")

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
                    // 🔍 DEBUG: Log what TaskGroup received
                    print("")
                    print("   " + String(repeating: "=", count: 70))
                    print("   🔍 === TASKGROUP RECEIVED RESULT (Subquestion '\(subId)') ===")
                    print("   " + String(repeating: "=", count: 70))
                    print("   🔑 Subquestion ID: '\(subId)'")
                    if let grade = grade {
                        print("   ✅ Grade: NOT NIL")
                        print("   📊 Score: \(grade.score)")
                        print("   ✓ Is Correct: \(grade.isCorrect)")
                        print("   💬 Feedback: '\(grade.feedback)'")
                        print("   🔍 Feedback length: \(grade.feedback.count) chars")
                        print("   🔍 Feedback empty: \(grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
                    } else {
                        print("   ❌ Grade: NIL")
                    }
                    if let error = error {
                        print("   ⚠️ Error: '\(error)'")
                    }
                    print("   🔄 About to run MainActor block to store in dictionary...")
                    print("   " + String(repeating: "=", count: 70))
                    print("")

                    await MainActor.run {
                        print("")
                        print("   " + String(repeating: "=", count: 70))
                        print("   🔍 === INSIDE MainActor.run (Storing Grade for '\(subId)') ===")
                        print("   " + String(repeating: "=", count: 70))

                        if let index = self.state.questions.firstIndex(where: { $0.id == question.id }) {
                            print("   ✅ Found parent question at index \(index)")

                            if let grade = grade {
                                // 🔍 DEBUG: Log dictionary storage
                                print("")
                                print("   " + String(repeating: "-", count: 70))
                                print("   🗄️ === STORING GRADE IN DICTIONARY ===")
                                print("   " + String(repeating: "-", count: 70))
                                print("   🔑 Dictionary Key (subId): '\(subId)'")
                                print("   📊 Score: \(grade.score)")
                                print("   ✓ Is Correct: \(grade.isCorrect)")
                                print("   💬 Feedback: '\(grade.feedback)'")
                                print("   🔍 Feedback length: \(grade.feedback.count) chars")
                                print("   🔍 Feedback is empty: \(grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
                                print("   🗄️ Storing to: state.questions[\(index)].subquestionGrades[\"\(subId)\"]")
                                print("   " + String(repeating: "-", count: 70))

                                // ACTUAL STORAGE
                                self.state.questions[index].subquestionGrades[subId] = grade

                                // ✅ FIX: Manually trigger SwiftUI update for nested dictionary mutation
                                // SwiftUI doesn't auto-detect changes to nested dictionaries in structs
                                self.objectWillChange.send()
                                print("   🔔 objectWillChange.send() called to trigger UI update")

                                // 🔍 DEBUG: Verify storage immediately
                                print("")
                                print("   🔍 === IMMEDIATE VERIFICATION AFTER STORAGE ===")
                                if let storedGrade = self.state.questions[index].subquestionGrades[subId] {
                                    print("   ✅ SUCCESS: Grade retrieved from dictionary")
                                    print("   📊 Retrieved score: \(storedGrade.score)")
                                    print("   💬 Retrieved feedback: '\(storedGrade.feedback)' (length: \(storedGrade.feedback.count))")
                                    print("   🔍 Feedback matches: \(storedGrade.feedback == grade.feedback)")
                                } else {
                                    print("   ❌ FAILURE: Could not retrieve stored grade!")
                                }

                                // 🔍 DEBUG: Show all keys in dictionary
                                print("\n   📚 All keys in subquestionGrades dictionary:")
                                print("   Keys: \(self.state.questions[index].subquestionGrades.keys.sorted())")
                                print("")
                            } else {
                                print("   ⚠️ Grade is NIL, not storing")
                            }

                            if let error = error {
                                print("   ⚠️ Storing error: '\(error)'")
                                self.state.questions[index].subquestionErrors[subId] = error
                                self.objectWillChange.send()  // ✅ Trigger UI update
                            }

                            print("   🔄 Setting subquestionGradingStatus[\"\(subId)\"] = false")
                            self.state.questions[index].subquestionGradingStatus[subId] = false
                            self.objectWillChange.send()  // ✅ Trigger UI update
                        } else {
                            print("   ❌ CRITICAL ERROR: Parent question not found in state.questions!")
                        }

                        print("   " + String(repeating: "=", count: 70))
                        print("")
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
                    subject: state.subject,
                    questionType: question.questionType,  // Pass question type for specialized grading
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

            // 🔍 DEBUG: Log request parameters
            print("")
            print("   " + String(repeating: "=", count: 70))
            print("   🔍 === CALLING gradeSingleQuestion API (Subquestion \(subquestion.id)) ===")
            print("   " + String(repeating: "=", count: 70))
            print("   🆔 Subquestion ID: '\(subquestion.id)'")
            print("   📝 Question Text: '\(subquestion.questionText.prefix(50))...'")
            print("   📝 Student Answer: '\(subquestion.studentAnswer)'")
            print("   📚 Subject: '\(state.subject ?? "nil")'")
            print("   🖼️ Context Image: \(contextImage != nil ? "YES (has parent image)" : "NO")")
            print("   " + String(repeating: "=", count: 70))
            print("")

            // Call grading endpoint
            let response = try await networkService.gradeSingleQuestion(
                questionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                subject: state.subject,
                questionType: subquestion.questionType,  // Pass question type for specialized grading
                contextImageBase64: contextImage
            )

            // 🔍 DEBUG: Log raw response object
            print("")
            print("   " + String(repeating: "=", count: 70))
            print("   🔍 === gradeSingleQuestion API RESPONSE (Subquestion \(subquestion.id)) ===")
            print("   " + String(repeating: "=", count: 70))
            print("   ✅ Response Success: \(response.success)")
            if let error = response.error {
                print("   ⚠️ Response Error: '\(error)'")
            }
            print("   " + String(repeating: "=", count: 70))
            print("")

            if response.success, let grade = response.grade {
                // 🔍 DEBUG: Log complete grade object received from API
                print("")
                print("   " + String(repeating: "=", count: 70))
                print("   🔍 === iOS RECEIVED GRADE OBJECT (Subquestion \(subquestion.id)) ===")
                print("   " + String(repeating: "=", count: 70))
                print("   📊 Score: \(grade.score)")
                print("   ✓ Is Correct: \(grade.isCorrect)")
                print("   💬 Feedback: '\(grade.feedback)'")
                print("   📈 Confidence: \(grade.confidence)")
                print("   🔍 Feedback length: \(grade.feedback.count) chars")
                print("   🔍 Feedback is empty: \(grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")

                // 🔍 DEBUG: Inspect grade object structure
                print("\n   🔬 Grade Object Inspection:")
                print("   - Type: \(type(of: grade))")
                print("   - Feedback type: \(type(of: grade.feedback))")
                print("   - Feedback bytes: \(grade.feedback.utf8.count) bytes")
                print("   - Feedback characters: \(grade.feedback.count) chars")

                // Check if feedback has any non-whitespace content
                let trimmedFeedback = grade.feedback.trimmingCharacters(in: .whitespacesAndNewlines)
                print("   - Trimmed feedback length: \(trimmedFeedback.count)")
                print("   - Has content: \(!trimmedFeedback.isEmpty)")

                print("   " + String(repeating: "=", count: 70))
                print("")

                print("   ✅ Subquestion \(subquestion.id): score \(grade.score), returning grade object to TaskGroup")

                // 🔍 DEBUG: Log what we're returning
                print("")
                print("   " + String(repeating: "=", count: 70))
                print("   🔍 === RETURNING FROM gradeSubquestion (Subquestion \(subquestion.id)) ===")
                print("   " + String(repeating: "=", count: 70))
                print("   🔑 Returning tuple: (id: '\(subquestion.id)', grade: NOT NIL, error: nil)")
                print("   📊 Grade being returned has feedback: '\(grade.feedback)'")
                print("   " + String(repeating: "=", count: 70))
                print("")

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
        guard let jpegData = state.croppedImages[questionId] else {
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
