//
//  DigitalHomeworkViewModel.swift
//  StudyAI
//
//  ✅ REFACTORED: ViewModel now uses global state from DigitalHomeworkStateManager
//  Local state removed - all data comes from shared singleton
//

import Foundation
import SwiftUI
import UIKit
import Combine

@MainActor
class DigitalHomeworkViewModel: ObservableObject {

    // MARK: - Global State Manager

    // ✅ Use @ObservedObject to react to state changes
    @ObservedObject private var stateManager = DigitalHomeworkStateManager.shared

    // MARK: - Published Properties (UI-only state)

    @Published var selectedAnnotationId: UUID?

    @Published var isGrading = false
    @Published var gradedCount = 0

    @Published var showAnnotationMode = false
    @Published var showImageInFullScreen = false
    @Published var showImagePreview = true  // 控制图片预览显示

    // Archive selection mode
    @Published var isArchiveMode = false
    @Published var selectedQuestionIds: Set<Int> = []

    // Deep reasoning mode (深度批改模式)
    @Published var useDeepReasoning = false

    // AI model selection (NEW: OpenAI vs Gemini)
    @Published var selectedAIModel: String = "gemini"  // "openai" or "gemini"

    // ✅ NEW: Track if progress has been marked (prevent duplicate marking)
    @Published var hasMarkedProgress = false

    // ✅ NEW: Enhanced grading animations
    @Published var currentGradingStatus = ""  // Dynamic status message during grading
    @Published var gradingAnimation: GradingAnimation = .idle

    // ✅ OPTIMIZATION 4: Undo/Redo support for annotations
    private var annotationHistory: [[QuestionAnnotation]] = []
    private var historyIndex: Int = -1
    private let maxHistoryStates = 20  // Limit history to prevent memory bloat

    // ✅ NEW: Grading animation states
    enum GradingAnimation {
        case idle
        case analyzing  // Analyzing question
        case thinking   // AI thinking (Gemini deep reasoning)
        case grading    // Grading answer
        case complete   // Animation complete
    }

    // MARK: - Private Properties

    // Homework Album storage
    private let homeworkImageStorage = HomeworkImageStorageService.shared
    private var hasAlreadySavedToAlbum = false

    private let networkService = NetworkService.shared
    private let concurrentLimit = 5

    // MARK: - Computed Properties (from global state)

    var questions: [ProgressiveQuestionWithGrade] {
        return stateManager.currentHomework?.questions ?? []
    }

    var annotations: [QuestionAnnotation] {
        return stateManager.currentHomework?.annotations ?? []
    }

    /// Binding for annotations (needed for AnnotationOverlay which modifies annotations)
    var annotationsBinding: Binding<[QuestionAnnotation]> {
        Binding(
            get: { self.annotations },
            set: { newValue in
                self.stateManager.updateHomework(annotations: newValue)
            }
        )
    }

    var croppedImages: [Int: UIImage] {
        guard let homework = stateManager.currentHomework else { return [:] }
        var images: [Int: UIImage] = [:]
        for (questionId, _) in homework.croppedImages {
            if let image = homework.getCroppedImage(for: questionId) {
                images[questionId] = image
            }
        }
        return images
    }

    var parseResults: ParseHomeworkQuestionsResponse? {
        return stateManager.currentHomework?.parseResults
    }

    var originalImage: UIImage? {
        return stateManager.currentHomework?.originalImage
    }

    var subject: String {
        return stateManager.currentHomework?.parseResults.subject ?? ""
    }

    var totalQuestions: Int {
        return stateManager.currentHomework?.parseResults.totalQuestions ?? 0
    }

    var allQuestionsGraded: Bool {
        // ✅ SIMPLIFIED: Only check global state - this is the source of truth
        return stateManager.currentState == .graded
    }

    var hasValidAnnotations: Bool {
        let annotations = self.annotations
        return !annotations.isEmpty && annotations.allSatisfy { $0.questionNumber != nil }
    }

    var availableQuestionNumbers: [String] {
        guard let results = parseResults else { return [] }
        return results.questions.compactMap { $0.questionNumber }
    }

    // ✅ OPTIMIZATION 4: Undo/Redo availability
    var canUndo: Bool {
        return historyIndex > 0
    }

    var canRedo: Bool {
        return historyIndex < annotationHistory.count - 1
    }

    // MARK: - Accuracy Statistics (正确率统计)

    /// Calculate correct/partial/incorrect counts using improved logic
    var accuracyStats: (correct: Int, partial: Int, incorrect: Int, total: Int, accuracy: Double) {
        var correctCount = 0
        var partialCount = 0
        var incorrectCount = 0
        var totalCount = 0

        for questionWithGrade in questions {
            // Handle parent questions (questions with subquestions)
            if questionWithGrade.isParentQuestion {
                let subquestionGrades = Array(questionWithGrade.subquestionGrades.values)
                totalCount += subquestionGrades.count

                for subGrade in subquestionGrades {
                    if subGrade.isCorrect {
                        correctCount += 1
                    } else if subGrade.score >= 0.5 {
                        partialCount += 1
                    } else {
                        incorrectCount += 1
                    }
                }
            } else {
                // Handle regular questions
                totalCount += 1

                if let grade = questionWithGrade.grade {
                    if grade.isCorrect {
                        correctCount += 1
                    } else if grade.score >= 0.5 {
                        partialCount += 1
                    } else {
                        incorrectCount += 1
                    }
                } else {
                    // Ungraded: conservatively count as incorrect
                    incorrectCount += 1
                }
            }
        }

        let accuracy = totalCount > 0 ? Double(correctCount) / Double(totalCount) * 100 : 0
        return (correctCount, partialCount, incorrectCount, totalCount, accuracy)
    }

    // MARK: - Setup (No longer needed - state is global)

    /// ✅ DEPRECATED: Setup is now handled by StateManager.parseHomework()
    /// This method is kept for backward compatibility during migration
    func setup(parseResults: ParseHomeworkQuestionsResponse, originalImage: UIImage) {
        print("⚠️ [ViewModel] setup() called - redirecting to global state")
        print("   State should already be .parsed from HomeworkSummaryView")
        print("   Current state: \(stateManager.currentState)")

        // State should already be set by HomeworkSummaryView calling stateManager.parseHomework()
        // If not, set it now (fallback for migration)
        if stateManager.currentState == .nothing {
            print("   ⚠️ State is .nothing - calling parseHomework()")
            stateManager.parseHomework(parseResults: parseResults, image: originalImage)
        }
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

        // Update global state
        var updatedAnnotations = annotations
        updatedAnnotations.append(newAnnotation)
        stateManager.updateHomework(annotations: updatedAnnotations)

        selectedAnnotationId = newAnnotation.id

        print("📝 Created annotation at (\(Int(point.x)), \(Int(point.y)))")
    }

    func updateAnnotationQuestionNumber(annotationId: UUID, questionNumber: String) {
        // Save to history before modifying
        saveAnnotationHistory()

        var updatedAnnotations = annotations
        guard let index = updatedAnnotations.firstIndex(where: { $0.id == annotationId }) else { return }
        updatedAnnotations[index].questionNumber = questionNumber

        // Update global state
        stateManager.updateHomework(annotations: updatedAnnotations)

        print("✅ Updated annotation \(index) → Q\(questionNumber)")

        // Trigger image cropping for this annotation
        cropImageForAnnotation(updatedAnnotations[index])
    }

    func deleteAnnotation(id: UUID) {
        // Save to history before deleting
        saveAnnotationHistory()

        var updatedAnnotations = annotations
        var updatedImages = croppedImages

        // Find the annotation before deleting
        guard let annotation = updatedAnnotations.first(where: { $0.id == id }) else { return }

        // If this annotation has a question number assigned, remove the cropped image
        if let questionNumber = annotation.questionNumber,
           let questionId = parseResults?.questions.first(where: { $0.questionNumber == questionNumber })?.id {
            updatedImages.removeValue(forKey: questionId)
            print("🗑️ Removed cropped image for Q\(questionNumber) (id: \(questionId))")
        }

        // Remove the annotation
        updatedAnnotations.removeAll { $0.id == id }
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }

        // Update global state
        stateManager.updateHomework(annotations: updatedAnnotations, croppedImages: updatedImages)

        print("🗑️ Deleted annotation \(id)")
    }

    func resetAnnotations() {
        // Save to history before resetting
        saveAnnotationHistory()

        // Update global state
        stateManager.updateHomework(annotations: [], croppedImages: [:])
        selectedAnnotationId = nil

        print("🔄 Reset all annotations")
    }

    // ✅ OPTIMIZATION 4: Undo/Redo Functions

    /// Save current annotation state to history
    private func saveAnnotationHistory() {
        // Trim future history if user made changes after undo
        if historyIndex < annotationHistory.count - 1 {
            annotationHistory = Array(annotationHistory.prefix(historyIndex + 1))
        }

        // Add current state
        annotationHistory.append(annotations)
        historyIndex += 1

        // Limit history size to prevent memory bloat
        if annotationHistory.count > maxHistoryStates {
            annotationHistory.removeFirst()
            historyIndex -= 1
        }

        print("💾 Saved annotation history (state \(historyIndex + 1)/\(annotationHistory.count))")
    }

    /// Undo last annotation change
    func undoAnnotation() {
        guard canUndo else {
            print("⚠️ Cannot undo - at beginning of history")
            return
        }

        historyIndex -= 1
        let restoredAnnotations = annotationHistory[historyIndex]

        // Update global state without saving to history
        stateManager.updateHomework(annotations: restoredAnnotations)
        selectedAnnotationId = nil

        // Resync cropped images
        syncCroppedImages()

        print("↩️ Undo annotation (restored state \(historyIndex + 1)/\(annotationHistory.count))")

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Redo previously undone annotation change
    func redoAnnotation() {
        guard canRedo else {
            print("⚠️ Cannot redo - at end of history")
            return
        }

        historyIndex += 1
        let restoredAnnotations = annotationHistory[historyIndex]

        // Update global state without saving to history
        stateManager.updateHomework(annotations: restoredAnnotations)
        selectedAnnotationId = nil

        // Resync cropped images
        syncCroppedImages()

        print("↪️ Redo annotation (restored state \(historyIndex + 1)/\(annotationHistory.count))")

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// ✅ NEW: Revert grading - clear all grades and return to pre-grading state
    /// ⚠️ IMPORTANT: Does NOT reset hasMarkedProgress - progress marking remains permanent even after revert
    func revertGrading() {
        print("🔄 [Revert] Reverting all grading results...")

        // Call global state manager's revert method
        // This transitions state from .graded → .parsed while preserving homework data
        stateManager.revertGrading()

        // Reset UI-only state
        isGrading = false
        gradedCount = 0
        hasAlreadySavedToAlbum = false

        // Exit archive mode if active
        if isArchiveMode {
            isArchiveMode = false
            selectedQuestionIds.removeAll()
        }

        // ⚠️ NOTE: hasMarkedProgress is deliberately NOT reset here
        // Progress marking should persist even after reverting grades
        print("ℹ️ [Revert] hasMarkedProgress remains: \(hasMarkedProgress) (intentionally not reset)")
        print("✅ [Revert] Grading reverted successfully. State transitioned to .parsed")
    }

    // MARK: - Homework Album Storage

    /// Automatically save graded homework to Homework Album
    private func saveToHomeworkAlbum() {
        // Guard: Only save once per session
        guard !hasAlreadySavedToAlbum else {
            print("📸 [Album] Already saved to album for this session, skipping")
            return
        }

        // Only save if we have an image
        guard let image = originalImage else {
            print("📸 [Album] No original image to save")
            return
        }

        // Only save after grading is complete
        guard allQuestionsGraded else {
            print("📸 [Album] Grading not complete, skipping album save")
            return
        }

        // Mark as saved to prevent duplicate saves
        hasAlreadySavedToAlbum = true

        // Calculate statistics from graded questions
        let stats = accuracyStats
        let accuracy = Float(stats.accuracy / 100.0)  // Convert percentage to 0-1 range
        let questionCount = stats.total
        let correctCount = stats.correct
        let incorrectCount = stats.incorrect

        // Get raw question texts for reference
        let rawQuestions = questions.map { $0.question.displayText }

        print("📸 [Album] Saving graded homework:")
        print("   Subject: \(subject)")
        print("   Accuracy: \(accuracy)")
        print("   Questions: \(questionCount)")
        print("   Correct: \(correctCount)")
        print("   Incorrect: \(incorrectCount)")

        // Save to storage
        let record = homeworkImageStorage.saveHomeworkImage(
            image,
            subject: subject,
            accuracy: accuracy,
            questionCount: questionCount,
            correctCount: correctCount,
            incorrectCount: incorrectCount,
            totalPoints: nil,  // Digital Homework doesn't use points
            maxPoints: nil,
            rawQuestions: rawQuestions.isEmpty ? nil : rawQuestions
        )

        if record != nil {
            print("✅ [Album] Digital homework auto-saved to album: \(subject), \(questionCount) questions")
        } else {
            print("⚠️ [Album] Failed to auto-save digital homework (might be duplicate)")
        }
    }

    // MARK: - Image Cropping

    private func cropImageForAnnotation(_ annotation: QuestionAnnotation) {
        guard let originalImage = originalImage,
              let questionNumber = annotation.questionNumber,
              let questionId = parseResults?.questions.first(where: { $0.questionNumber == questionNumber })?.id else {
            return
        }

        // ✅ OPTIMIZATION 1: Normalize image orientation BEFORE cropping
        // This fixes rotation bugs where EXIF orientation causes wrong crops
        guard let normalizedImage = originalImage.normalizedOrientation() else {
            print("❌ Failed to normalize image orientation for Q\(questionNumber)")
            return
        }

        // Convert normalized coordinates to pixel coordinates
        let imageWidth = normalizedImage.size.width
        let imageHeight = normalizedImage.size.height

        let x = CGFloat(annotation.topLeft[0]) * imageWidth
        let y = CGFloat(annotation.topLeft[1]) * imageHeight
        let width = CGFloat(annotation.bottomRight[0] - annotation.topLeft[0]) * imageWidth
        let height = CGFloat(annotation.bottomRight[1] - annotation.topLeft[1]) * imageHeight

        let cropRect = CGRect(x: x, y: y, width: width, height: height)

        // Crop image
        if let croppedCGImage = normalizedImage.cgImage?.cropping(to: cropRect) {
            // ✅ OPTIMIZATION 2: Convert to JPEG data immediately (10x memory reduction)
            let croppedUIImage = UIImage(cgImage: croppedCGImage, scale: 1.0, orientation: .up)

            // Compress to JPEG (quality 0.85 = good balance between size and quality)
            if let jpegData = croppedUIImage.jpegData(compressionQuality: 0.85) {
                // Convert back to UIImage for immediate display
                if let compressedImage = UIImage(data: jpegData) {
                    // Update global state with compressed image
                    var updatedImages = croppedImages
                    updatedImages[questionId] = compressedImage
                    stateManager.updateHomework(croppedImages: updatedImages)

                    let originalSize = croppedUIImage.pngData()?.count ?? 0
                    let compressedSize = jpegData.count
                    let savings = originalSize > 0 ? (1.0 - Double(compressedSize) / Double(originalSize)) * 100 : 0
                    print("✂️ Cropped image for Q\(questionNumber) (id: \(questionId))")
                    print("   📦 Compressed: \(originalSize / 1024)KB → \(compressedSize / 1024)KB (saved \(Int(savings))%)")
                } else {
                    print("❌ Failed to create UIImage from JPEG data for Q\(questionNumber)")
                }
            } else {
                print("❌ Failed to compress image to JPEG for Q\(questionNumber)")
            }
        } else {
            print("❌ Failed to crop image for Q\(questionNumber)")
        }
    }

    func getCroppedImage(for questionId: Int) -> UIImage? {
        return croppedImages[questionId]
    }

    // MARK: - Sync Cropped Images

    /// Removes cropped images for questions that no longer have annotations
    func syncCroppedImages() {
        // Get all question numbers that have annotations
        let annotatedQuestionNumbers = Set(annotations.compactMap { $0.questionNumber })

        // Get all question IDs that should have images
        var validQuestionIds = Set<Int>()
        for questionNumber in annotatedQuestionNumbers {
            if let questionId = parseResults?.questions.first(where: { $0.questionNumber == questionNumber })?.id {
                validQuestionIds.insert(questionId)
            }
        }

        // Remove images for questions that no longer have annotations
        var updatedImages = croppedImages
        for questionId in croppedImages.keys {
            if !validQuestionIds.contains(questionId) {
                updatedImages.removeValue(forKey: questionId)
                print("🔄 Removed orphaned image for question ID \(questionId)")
            }
        }

        // Update global state if images changed
        if updatedImages.count != croppedImages.count {
            stateManager.updateHomework(croppedImages: updatedImages)
            print("🔄 Synced cropped images: \(updatedImages.count) images remain")
        }
    }

    // MARK: - AI Grading

    func startGrading() async {
        print("🚀 === STARTING AI GRADING ===")
        print("🤖 AI Model: \(selectedAIModel)")
        print("🧠 Deep Reasoning: \(useDeepReasoning ? "YES" : "NO")")
        print("📊 Total Questions: \(questions.count)")

        // 隐藏图片预览（触发向上飞走动画）
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showImagePreview = false
        }

        isGrading = true
        gradedCount = 0

        // ✅ NEW: Set initial grading animation state
        withAnimation(.easeInOut(duration: 0.3)) {
            gradingAnimation = .analyzing
            currentGradingStatus = useDeepReasoning ? "🧠 深度分析题目中..." : "📝 正在分析题目..."
        }

        // Get mutable copy of questions
        var updatedQuestions = questions

        // Use TaskGroup for parallel grading
        await withTaskGroup(of: GradingResult.self) { group in
            var activeTaskCount = 0
            var questionIndex = 0

            while questionIndex < updatedQuestions.count || activeTaskCount > 0 {

                // Launch new tasks (up to concurrentLimit)
                while activeTaskCount < concurrentLimit && questionIndex < updatedQuestions.count {
                    let question = updatedQuestions[questionIndex]

                    // Mark as grading
                    updatedQuestions[questionIndex].isGrading = true

                    // ✅ NEW: Push isGrading state to UI immediately
                    stateManager.updateHomework(questions: updatedQuestions)
                    print("📤 [Incremental] Marked Q\(question.question.id) as grading in UI")

                    // ✅ NEW: Update status message dynamically
                    let statusMessage: String
                    if useDeepReasoning && selectedAIModel == "gemini" {
                        statusMessage = "🧠 深度批改 Q\(question.question.questionNumber ?? "?")..."
                    } else if selectedAIModel == "gemini" {
                        statusMessage = "✨ Gemini 批改 Q\(question.question.questionNumber ?? "?")..."
                    } else {
                        statusMessage = "🤖 批改 Q\(question.question.questionNumber ?? "?")..."
                    }

                    withAnimation(.easeInOut(duration: 0.2)) {
                        gradingAnimation = useDeepReasoning ? .thinking : .grading
                        currentGradingStatus = statusMessage
                    }

                    group.addTask {
                        await self.gradeQuestion(question)
                    }

                    questionIndex += 1
                    activeTaskCount += 1
                }

                // Wait for one task to complete
                if let result = await group.next() {
                    activeTaskCount -= 1

                    // Update state with result
                    if let index = updatedQuestions.firstIndex(where: { $0.id == result.questionId }) {
                        updatedQuestions[index].grade = result.grade
                        updatedQuestions[index].gradingError = result.error
                        updatedQuestions[index].isGrading = false

                        // Update subquestion data if present
                        if !result.subquestionGrades.isEmpty {
                            print("🔥🔥🔥 STORING SUBQUESTION GRADES FOR Q\(result.questionId)")
                            print("🔥 Grades dict: \(result.subquestionGrades.keys.sorted())")
                            for (subId, grade) in result.subquestionGrades {
                                print("🔥   \(subId): score=\(grade.score), feedback=\(grade.feedback.prefix(50))...")
                            }
                            updatedQuestions[index].subquestionGrades = result.subquestionGrades
                        }
                        if !result.subquestionErrors.isEmpty {
                            updatedQuestions[index].subquestionErrors = result.subquestionErrors
                        }
                        for subId in result.subquestionGrades.keys {
                            updatedQuestions[index].subquestionGradingStatus[subId] = false
                        }

                        // ✅ NEW: INCREMENTAL UPDATE - Push grade to UI immediately
                        // This allows users to see grades appear dynamically as they complete
                        stateManager.updateHomework(questions: updatedQuestions)
                        print("📤 [Incremental] Pushed Q\(result.questionId) grade to UI")
                    }

                    gradedCount += 1

                    // ✅ NEW: Update progress status with animation
                    let progressPercent = Int((Float(gradedCount) / Float(totalQuestions)) * 100)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentGradingStatus = "✅ 已完成 \(gradedCount)/\(totalQuestions) (\(progressPercent)%)"
                    }

                    print("✅ Q\(result.questionId) graded (\(gradedCount)/\(totalQuestions))")
                }
            }
        }

        // ✅ NEW: Final completion animation
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            gradingAnimation = .complete
            currentGradingStatus = "🎉 批改完成！"
        }

        // Small delay to show completion message
        try? await Task.sleep(nanoseconds: 800_000_000)  // 0.8 seconds

        isGrading = false
        print("✅ === ALL QUESTIONS GRADED ===")

        // Reset animation state
        withAnimation(.easeOut(duration: 0.3)) {
            gradingAnimation = .idle
            currentGradingStatus = ""
        }

        // ✅ SINGLE state transition: .parsed → .graded
        stateManager.completeGrading(gradedQuestions: updatedQuestions)
        print("💾 State transitioned to .graded")

        // Auto-save to Homework Album after grading completes
        saveToHomeworkAlbum()
    }

    // ✅ NEW: Unified grading result type
    private struct GradingResult {
        let questionId: Int
        let grade: ProgressiveGradeResult?
        let error: String?
        let subquestionGrades: [String: ProgressiveGradeResult]
        let subquestionErrors: [String: String]
    }

    private func gradeQuestion(_ questionWithGrade: ProgressiveQuestionWithGrade) async -> GradingResult {
        let question = questionWithGrade.question

        // Check if this is a parent question with subquestions
        if question.isParentQuestion, let subquestions = question.subquestions {
            print("📋 Q\(question.id) is parent question with \(subquestions.count) subquestions")

            // Grade all subquestions in parallel
            var subquestionResults: [String: ProgressiveGradeResult] = [:]
            var subquestionErrors: [String: String] = [:]

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
                    if let grade = grade {
                        subquestionResults[subId] = grade
                    }
                    if let error = error {
                        subquestionErrors[subId] = error
                    }
                }
            }

            // ✅ SIMPLIFIED: Return all results in one batch
            print("📋 Q\(question.id) completed: \(subquestionResults.count) subquestions graded")

            return GradingResult(
                questionId: question.id,
                grade: nil,
                error: nil,
                subquestionGrades: subquestionResults,
                subquestionErrors: subquestionErrors
            )

        } else {
            // Regular question: grade normally
            do {
                // Get context image if available
                let contextImage = getCroppedImageBase64(for: question.id)

                // Call grading endpoint with deep reasoning flag
                let response = try await networkService.gradeSingleQuestion(
                    questionText: question.displayText,
                    studentAnswer: question.displayStudentAnswer,
                    subject: subject,
                    contextImageBase64: contextImage,
                    useDeepReasoning: useDeepReasoning,
                    modelProvider: selectedAIModel
                )

                if response.success, let grade = response.grade {
                    print("✅ Q\(question.id) graded: score=\(grade.score), correct=\(grade.isCorrect)")
                    return GradingResult(
                        questionId: question.id,
                        grade: grade,
                        error: nil,
                        subquestionGrades: [:],
                        subquestionErrors: [:]
                    )
                } else {
                    let error = response.error ?? "Grading failed"
                    print("❌ Q\(question.id) grading error: \(error)")
                    return GradingResult(
                        questionId: question.id,
                        grade: nil,
                        error: error,
                        subquestionGrades: [:],
                        subquestionErrors: [:]
                    )
                }

            } catch {
                print("❌ Q\(question.id) exception: \(error.localizedDescription)")
                return GradingResult(
                    questionId: question.id,
                    grade: nil,
                    error: error.localizedDescription,
                    subquestionGrades: [:],
                    subquestionErrors: [:]
                )
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

            // ✅ NEW: Get parent question content to provide context for subquestion grading
            let parentContent = questions.first(where: { $0.question.id == parentQuestionId })?.question.parentContent

            if let parent = parentContent {
                print("   📚 Including parent question context: \(parent.prefix(50))...")
            }

            // Call grading endpoint with deep reasoning flag and parent content
            let response = try await networkService.gradeSingleQuestion(
                questionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                subject: subject,
                contextImageBase64: contextImage,
                parentQuestionContent: parentContent,  // ✅ NEW: Pass parent question content
                useDeepReasoning: useDeepReasoning,  // Pass deep reasoning mode
                modelProvider: selectedAIModel  // NEW: Pass AI model selection
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

    func askAIForHelp(questionId: Int, appState: AppState, subquestion: ProgressiveSubquestion? = nil) {
        guard let questionWithGrade = questions.first(where: { $0.question.id == questionId }) else {
            print("❌ Question not found: \(questionId)")
            return
        }

        let question = questionWithGrade.question

        // ✅ NEW: Handle subquestion case separately
        if let subquestion = subquestion {
            // Subquestion case: Use subquestion-specific data
            let subGrade = questionWithGrade.subquestionGrades[subquestion.id]

            print("💬 Opening AI chat for subquestion \(subquestion.id) (parent Q\(questionId))")
            print("📝 Subquestion: \(subquestion.questionText)")
            print("📊 Grade: \(subGrade?.isCorrect == true ? "✅" : "❌") score: \(subGrade?.score ?? 0)")

            // Get cropped image from parent question if available
            let questionImage = croppedImages[questionId]
            if questionImage != nil {
                print("🖼️ Including cropped image from parent Q\(questionId)")
            }

            // Build context with subquestion data
            let context = HomeworkQuestionContext(
                questionText: subquestion.questionText,
                rawQuestionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                correctAnswer: nil,  // Pro Mode doesn't have correct answer
                currentGrade: subGrade.map {
                    $0.isCorrect ? "CORRECT" : ($0.score == 0 ? "INCORRECT" : "PARTIAL_CREDIT")
                },
                originalFeedback: subGrade?.feedback,
                pointsEarned: subGrade?.score,
                pointsPossible: 1.0,
                questionNumber: Int(question.questionNumber ?? "0"),  // Use parent question number
                subject: subject,
                questionImage: questionImage  // Use parent's cropped image
            )

            // Navigate to chat with subquestion context
            // Include parent question content for context
            let parentContext = question.parentContent ?? ""
            let message = """
            请帮我理解这道题（小题 \(subquestion.id)）：

            【母题背景】
            \(parentContext)

            【小题】
            \(subquestion.questionText)

            【我的答案】
            \(subquestion.studentAnswer)

            【老师反馈】
            \(subGrade?.feedback ?? "无反馈")
            """

            appState.navigateToChatWithHomeworkQuestion(message: message, context: context)

            print("✅ Navigated to chat with subquestion context (including parent background)")

        } else {
            // Regular question case: Use original logic
            let grade = questionWithGrade.grade

            print("💬 Opening AI chat for Q\(questionId)")
            print("📝 Question: \(question.displayText)")
            print("📊 Grade: \(grade?.isCorrect == true ? "✅" : "❌") score: \(grade?.score ?? 0)")

            // ✅ NEW: Get cropped image if available
            let questionImage = croppedImages[questionId]
            if questionImage != nil {
                print("🖼️ Including cropped image for Q\(questionId)")
            }

            // Build homework context
            let context = HomeworkQuestionContext(
                questionText: question.displayText,
                rawQuestionText: question.questionText,
                studentAnswer: question.displayStudentAnswer,
                correctAnswer: nil,  // Pro Mode doesn't have correct answer
                currentGrade: grade.map {
                    $0.isCorrect ? "CORRECT" : ($0.score == 0 ? "INCORRECT" : "PARTIAL_CREDIT")
                },
                originalFeedback: grade?.feedback,
                pointsEarned: grade?.score,
                pointsPossible: 1.0,
                questionNumber: Int(question.questionNumber ?? "0"),
                subject: subject,
                questionImage: questionImage  // ✅ NEW: Pass cropped image
            )

            // Navigate to chat with context
            appState.navigateToChatWithHomeworkQuestion(
                message: "请帮我理解这道题：\n\n\(question.displayText)\n\n我的答案：\(question.displayStudentAnswer)\n\n老师反馈：\(grade?.feedback ?? "无反馈")",
                context: context
            )

            print("✅ Navigated to chat with homework context")
        }
    }

    func archiveQuestion(questionId: Int) {
        Task {
            await archiveQuestions([questionId])

            // ✅ NEW: Mark question as archived instead of removing
            await MainActor.run {
                var updatedQuestions = questions
                if let index = updatedQuestions.firstIndex(where: { $0.question.id == questionId }) {
                    updatedQuestions[index].isArchived = true
                    stateManager.updateHomework(questions: updatedQuestions)
                    print("📦 [Archive] Marked Q\(questionId) as archived (remains visible)")
                }
            }
        }
    }

    /// Archive questions by their IDs
    private func archiveQuestions(_ questionIds: [Int]) async {
        guard let userId = AuthenticationService.shared.currentUser?.id else {
            print("❌ [Archive] User not authenticated")
            return
        }

        print("📦 [Archive] Archiving \(questionIds.count) Pro Mode questions...")

        let imageStorage = ProModeImageStorage.shared
        var questionsToArchive: [[String: Any]] = []

        for questionId in questionIds {
            guard let questionWithGrade = questions.first(where: { $0.question.id == questionId }) else {
                continue
            }

            let question = questionWithGrade.question

            // Save cropped image to file system if available
            var imagePath: String?
            print("   🔍 [Archive] Q\(questionId): Checking for cropped image...")
            print("   🔍 [Archive] croppedImages dictionary has \(croppedImages.count) entries")
            print("   🔍 [Archive] croppedImages keys: \(croppedImages.keys.sorted())")

            if let image = croppedImages[questionId] {
                print("   ✅ [Archive] Q\(questionId): Found cropped image in memory (size: \(image.size))")
                imagePath = imageStorage.saveImage(image)
                if let path = imagePath {
                    print("   ✅ [Archive] Q\(questionId): Saved image to: \(path)")
                    print("   ✅ [Archive] Q\(questionId): File exists: \(FileManager.default.fileExists(atPath: path))")
                } else {
                    print("   ❌ [Archive] Q\(questionId): Failed to save image to file system")
                }
            } else {
                print("   ⚠️ [Archive] Q\(questionId): No cropped image found in memory")
            }

            // Determine grade and isCorrect
            let (gradeString, isCorrect) = determineGradeAndCorrectness(for: questionWithGrade)

            // Build archived question data
            let questionData: [String: Any] = [
                "id": UUID().uuidString,
                "userId": userId,
                "subject": subject,
                "questionText": question.displayText,
                "rawQuestionText": question.displayText,  // Use same as questionText for Pro Mode
                "answerText": question.displayStudentAnswer,
                "confidence": 0.95,  // High confidence for Pro Mode
                "hasVisualElements": imagePath != nil,
                "questionImageUrl": imagePath ?? "",  // File path to cropped image
                "archivedAt": ISO8601DateFormatter().string(from: Date()),
                "reviewCount": 0,
                "tags": [],
                "notes": "",
                "studentAnswer": question.displayStudentAnswer,
                "grade": gradeString,
                "points": questionWithGrade.grade?.score ?? 0.0,
                "maxPoints": 1.0,
                "feedback": questionWithGrade.grade?.feedback ?? "",
                "correctAnswer": questionWithGrade.grade?.correctAnswer ?? "",  // ✅ NEW: Save correct answer
                "isGraded": questionWithGrade.grade != nil,
                "isCorrect": isCorrect,
                "questionType": question.questionType ?? "short_answer",
                "options": [],
                "proMode": true  // Mark as Pro Mode question
            ]

            questionsToArchive.append(questionData)
            print("   📝 [Archive] Prepared Q\(questionId): \(question.displayText.prefix(50))...")
            print("   📝 [Archive] Question data keys: \(questionData.keys.sorted())")
            print("   📝 [Archive] hasVisualElements: \(questionData["hasVisualElements"] ?? "nil")")
            print("   📝 [Archive] questionImageUrl: \(questionData["questionImageUrl"] ?? "nil")")
            print("   📝 [Archive] proMode: \(questionData["proMode"] ?? "nil")")
        }

        print("")
        print("📦 [Archive] === ARCHIVE SUMMARY ===")
        print("   Total questions to archive: \(questionsToArchive.count)")
        let withImages = questionsToArchive.filter { ($0["hasVisualElements"] as? Bool) == true }.count
        print("   Questions with images: \(withImages)")
        print("")

        // Save to local storage
        QuestionLocalStorage.shared.saveQuestions(questionsToArchive)

        print("✅ [Archive] Successfully archived \(questionsToArchive.count) Pro Mode questions")
    }

    /// Determine grade string and isCorrect status for a question
    private func determineGradeAndCorrectness(for questionWithGrade: ProgressiveQuestionWithGrade) -> (gradeString: String, isCorrect: Bool) {
        // For parent questions with subquestions
        if questionWithGrade.isParentQuestion {
            let totalSubquestions = questionWithGrade.totalSubquestionsCount
            let correctSubquestions = questionWithGrade.subquestionGrades.values.filter { $0.isCorrect }.count

            if correctSubquestions == totalSubquestions {
                return ("CORRECT", true)
            } else if correctSubquestions == 0 {
                return ("INCORRECT", false)
            } else {
                return ("PARTIAL_CREDIT", false)
            }
        }

        // For regular questions
        if let grade = questionWithGrade.grade {
            if grade.isCorrect {
                return ("CORRECT", true)
            } else if grade.score == 0 {
                return ("INCORRECT", false)
            } else {
                return ("PARTIAL_CREDIT", false)
            }
        }

        // Not graded
        return ("", false)
    }

    func markProgress() {
        Task {
            do {
                // ✅ IMPROVED: Calculate statistics correctly for Pro Mode
                // Handle parent questions with subquestions, partial credit, and ungraded questions

                var correctCount = 0
                var totalCount = 0

                print("📊 [Progress] Calculating accuracy for \(questions.count) questions...")

                for (index, questionWithGrade) in questions.enumerated() {
                    // Handle parent questions (questions with subquestions)
                    if questionWithGrade.isParentQuestion {
                        let subquestionGrades = Array(questionWithGrade.subquestionGrades.values)
                        totalCount += subquestionGrades.count
                        let subCorrect = subquestionGrades.filter { $0.isCorrect }.count
                        correctCount += subCorrect

                        print("   Q\(index+1) (Parent): \(subCorrect)/\(subquestionGrades.count) subquestions correct")

                    } else {
                        // Handle regular questions
                        totalCount += 1

                        if let grade = questionWithGrade.grade {
                            // Question has been graded
                            if grade.isCorrect {
                                correctCount += 1
                                print("   Q\(index+1): ✅ Correct (score: \(grade.score))")
                            } else if grade.score >= 0.5 {
                                // Partial credit: score >= 50%
                                // Conservative approach: don't count as correct (consistent with Detail/Fast mode)
                                print("   Q\(index+1): ⚡ Partial (score: \(grade.score)) - counted as incorrect")
                            } else {
                                print("   Q\(index+1): ❌ Incorrect (score: \(grade.score))")
                            }
                        } else {
                            // Ungraded question: conservatively count as incorrect
                            print("   Q\(index+1): 📝 Ungraded - counted as incorrect")
                        }
                    }
                }

                let totalQuestions = totalCount
                let totalCorrect = correctCount
                let accuracy = totalCount > 0 ? Float(correctCount) / Float(totalCount) : 0.0

                print("📊 [Progress] Final stats: \(totalCorrect)/\(totalQuestions) correct (\(String(format: "%.1f%%", accuracy * 100)))")

                // Update progress using PointsEarningManager
                await MainActor.run {
                    PointsEarningManager.shared.markHomeworkProgress(
                        subject: subject,
                        numberOfQuestions: totalQuestions,
                        numberOfCorrectQuestions: totalCorrect
                    )

                    // ✅ CRITICAL: Set flag to prevent duplicate marking (persists even after revert)
                    hasMarkedProgress = true
                }

                print("✅ Progress marked: \(totalCorrect)/\(totalQuestions) correct (\(String(format: "%.1f%%", accuracy * 100)))")
                print("🔒 [Progress] hasMarkedProgress flag set to true - button will be disabled")
            }
        }
    }

    // MARK: - Archive Selection Mode

    var isAllSelected: Bool {
        // Check if all graded questions are selected
        let gradedQuestionIds = questions.filter { $0.grade != nil }.map { $0.question.id }
        return !gradedQuestionIds.isEmpty && gradedQuestionIds.allSatisfy { selectedQuestionIds.contains($0) }
    }

    func toggleArchiveMode() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isArchiveMode.toggle()
            if !isArchiveMode {
                selectedQuestionIds.removeAll()
            }
        }
    }

    func toggleSelectAll() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            if isAllSelected {
                // Deselect all
                selectedQuestionIds.removeAll()
            } else {
                // Select all graded questions (only graded questions can be archived)
                let gradedQuestionIds = questions.filter { $0.grade != nil }.map { $0.question.id }
                selectedQuestionIds = Set(gradedQuestionIds)
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

        print("📦 [Archive] Batch archiving \(selectedQuestionIds.count) Pro Mode questions...")

        // Archive all selected questions
        await archiveQuestions(Array(selectedQuestionIds))

        // ✅ NEW: Mark questions as archived instead of removing them
        await MainActor.run {
            var updatedQuestions = questions
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                for questionId in selectedQuestionIds {
                    if let index = updatedQuestions.firstIndex(where: { $0.question.id == questionId }) {
                        updatedQuestions[index].isArchived = true
                    }
                }
                stateManager.updateHomework(questions: updatedQuestions)
                selectedQuestionIds.removeAll()
                isArchiveMode = false
            }
        }

        print("✅ [Archive] Batch archive completed - \(selectedQuestionIds.count) questions marked as archived")
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

// MARK: - UIImage Extension for Orientation Normalization

extension UIImage {
    /// Normalizes image orientation by redrawing to .up orientation
    /// This fixes cropping issues with EXIF-rotated images
    func normalizedOrientation() -> UIImage? {
        // Already in correct orientation
        if imageOrientation == .up {
            return self
        }

        // Create context with proper size for rotated image
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }

        // Draw image with correct orientation applied
        draw(in: CGRect(origin: .zero, size: size))

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
