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
import PDFKit

@MainActor
class DigitalHomeworkViewModel: ObservableObject {

    // MARK: - Logger

    private let logger = AppLogger.forFeature("ProMode")

    // ✅ Debug mode flag - set to false to disable verbose logs
    private static let isDebugMode = false  // Set to true for verbose debugging

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

    // ✅ NEW: Get all original images (for multi-page homework)
    var originalImages: [UIImage] {
        return stateManager.currentHomework?.originalImages ?? []
    }

    var subject: String {
        return stateManager.currentHomework?.parseResults.subject ?? ""
    }

    var totalQuestions: Int {
        return stateManager.currentHomework?.parseResults.totalQuestions ?? 0
    }

    // ✅ Track if progress has been marked (prevent duplicate marking)
    // Read from StateManager to persist across navigation
    var hasMarkedProgress: Bool {
        return stateManager.currentHomework?.hasMarkedProgress ?? false
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
        if Self.isDebugMode {
            logger.debug("[ViewModel] setup() called - redirecting to global state")
            logger.debug("State should already be .parsed from HomeworkSummaryView")
            logger.debug("Current state: \(stateManager.currentState)")
        }

        // State should already be set by HomeworkSummaryView calling stateManager.parseHomework()
        // If not, set it now (fallback for migration)
        if stateManager.currentState == .nothing {
            logger.warning("State is .nothing - calling parseHomework()")
            stateManager.parseHomework(parseResults: parseResults, images: originalImages)  // ✅ UPDATED: Pass array
        }
    }

    // MARK: - Annotation Management

    func addAnnotation(at point: CGPoint, imageSize: CGSize, pageIndex: Int = 0) {
        guard originalImage != nil else { return }

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
            color: annotationColor(for: annotations.count),
            pageIndex: pageIndex  // ✅ NEW: Include page index
        )

        // Update global state
        var updatedAnnotations = annotations
        updatedAnnotations.append(newAnnotation)
        stateManager.updateHomework(annotations: updatedAnnotations)

        selectedAnnotationId = newAnnotation.id

        if Self.isDebugMode {
            logger.debug("Created annotation at (\(Int(point.x)), \(Int(point.y))) on page \(pageIndex)")
        }
    }

    func updateAnnotationQuestionNumber(annotationId: UUID, questionNumber: String) {
        // Save to history before modifying
        saveAnnotationHistory()

        var updatedAnnotations = annotations
        guard let index = updatedAnnotations.firstIndex(where: { $0.id == annotationId }) else { return }
        updatedAnnotations[index].questionNumber = questionNumber

        // ✅ FIX: Explicitly notify observers before updating
        objectWillChange.send()

        // Update global state
        stateManager.updateHomework(annotations: updatedAnnotations)

        logger.debug("Updated annotation \(index) → Q\(questionNumber)")

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
            logger.debug("Removed cropped image for Q\(questionNumber) (id: \(questionId))")
        }

        // Remove the annotation
        updatedAnnotations.removeAll { $0.id == id }
        if selectedAnnotationId == id {
            selectedAnnotationId = nil
        }

        // ✅ FIX: Explicitly notify observers before updating (ensures UI sees the change immediately)
        objectWillChange.send()

        // Update global state
        stateManager.updateHomework(annotations: updatedAnnotations, croppedImages: updatedImages)

        logger.debug("Deleted annotation \(id)")
    }

    func resetAnnotations() {
        // Save to history before resetting
        saveAnnotationHistory()

        // Update global state
        stateManager.updateHomework(annotations: [], croppedImages: [:])
        selectedAnnotationId = nil

        logger.debug("Reset all annotations")
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

        logger.debug("Saved annotation history (state \(historyIndex + 1)/\(annotationHistory.count))")
    }

    /// Undo last annotation change
    func undoAnnotation() {
        guard canUndo else {
            logger.debug("Cannot undo - at beginning of history")
            return
        }

        historyIndex -= 1
        let restoredAnnotations = annotationHistory[historyIndex]

        // Update global state without saving to history
        stateManager.updateHomework(annotations: restoredAnnotations)
        selectedAnnotationId = nil

        // Resync cropped images
        syncCroppedImages()

        logger.debug("Undo annotation (restored state \(historyIndex + 1)/\(annotationHistory.count))")

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Redo previously undone annotation change
    func redoAnnotation() {
        guard canRedo else {
            logger.debug("Cannot redo - at end of history")
            return
        }

        historyIndex += 1
        let restoredAnnotations = annotationHistory[historyIndex]

        // Update global state without saving to history
        stateManager.updateHomework(annotations: restoredAnnotations)
        selectedAnnotationId = nil

        // Resync cropped images
        syncCroppedImages()

        logger.debug("Redo annotation (restored state \(historyIndex + 1)/\(annotationHistory.count))")

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// ✅ NEW: Revert grading - clear all grades and return to pre-grading state
    /// ✅ CRITICAL FIX: Now RESETS hasMarkedProgress to prevent double-counting on regrade
    func revertGrading() {
        logger.info("Reverting all grading results...")

        // Call global state manager's revert method
        // This transitions state from .graded → .parsed while preserving homework data
        // ✅ clearGrades() now also resets hasMarkedProgress to false
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

        // ✅ CRITICAL FIX: hasMarkedProgress is now reset in clearGrades()
        // This prevents double-counting when user reverts and regrades the same homework
        logger.debug("hasMarkedProgress reset to: \(hasMarkedProgress)")
        logger.info("Grading reverted successfully. State transitioned to .parsed")
    }

    // MARK: - Homework Album Storage

    /// Automatically save graded homework to Homework Album
    private func saveToHomeworkAlbum() {
        // Guard: Only save once per session
        guard !hasAlreadySavedToAlbum else {
            logger.debug("Already saved to album for this session")
            return
        }

        // ✅ UPDATED: Only save if we have images (plural for multi-page)
        guard !originalImages.isEmpty else {
            logger.debug("No original images to save")
            return
        }

        // Only save after grading is complete
        guard allQuestionsGraded else {
            logger.debug("Grading not complete, skipping album save")
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

        // ✅ NEW: Serialize Pro Mode digital homework data for later viewing
        var proModeData: Data? = nil
        if let currentHomework = stateManager.currentHomework {
            do {
                let encoder = JSONEncoder()
                proModeData = try encoder.encode(currentHomework)
                logger.debug("Serialized Pro Mode data (\(proModeData?.count ?? 0) bytes)")
            } catch {
                logger.error("Failed to serialize Pro Mode data: \(error.localizedDescription)")
            }
        }

        logger.info("Saving \(originalImages.count) page(s) of graded homework to album: \(subject), \(questionCount) questions")

        // ✅ UPDATED: Save all pages as a homework deck
        let record = homeworkImageStorage.saveHomeworkImages(
            originalImages,  // ✅ Pass entire array of images
            subject: subject,
            accuracy: accuracy,
            questionCount: questionCount,
            correctCount: correctCount,
            incorrectCount: incorrectCount,
            totalPoints: nil,  // Digital Homework doesn't use points
            maxPoints: nil,
            rawQuestions: rawQuestions.isEmpty ? nil : rawQuestions,
            proModeData: proModeData
        )

        if record != nil {
            logger.info("Digital homework auto-saved to album as \(originalImages.count)-page deck: \(subject), \(questionCount) questions")
        } else {
            logger.error("Failed to auto-save digital homework (might be duplicate)")
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
            logger.error("Failed to normalize image orientation for Q\(questionNumber)")
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
                    if Self.isDebugMode {
                        logger.debug("Cropped image for Q\(questionNumber) (id: \(questionId))")
                        logger.debug("Compressed: \(originalSize / 1024)KB → \(compressedSize / 1024)KB (saved \(Int(savings))%)")
                    }
                } else {
                    logger.error("Failed to create UIImage from JPEG data for Q\(questionNumber)")
                }
            } else {
                logger.error("Failed to compress image to JPEG for Q\(questionNumber)")
            }
        } else {
            logger.error("Failed to crop image for Q\(questionNumber)")
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
                logger.debug("Removed orphaned image for question ID \(questionId)")
            }
        }

        // Update global state if images changed
        if updatedImages.count != croppedImages.count {
            stateManager.updateHomework(croppedImages: updatedImages)
            logger.debug("Synced cropped images: \(updatedImages.count) images remain")
        }
    }

    // MARK: - AI Grading

    func startGrading() async {
        logger.info("Starting AI grading: model=\(selectedAIModel), deepReasoning=\(useDeepReasoning), questions=\(questions.count)")

        // 隐藏图片预览（触发向上飞走动画）
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showImagePreview = false
        }

        isGrading = true
        gradedCount = 0

        // ✅ NEW: Set initial grading animation state
        withAnimation(.easeInOut(duration: 0.3)) {
            gradingAnimation = .analyzing
            currentGradingStatus = useDeepReasoning ?
                NSLocalizedString("proMode.grading.deepAnalyzing", comment: "Deep analyzing questions...") :
                NSLocalizedString("proMode.grading.analyzing", comment: "Analyzing questions...")
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
                    logger.debug("Marked Q\(question.question.id) as grading in UI")

                    // ✅ NEW: Update status message dynamically
                    let questionNum = question.question.questionNumber ?? "?"
                    let statusMessage: String
                    if useDeepReasoning && selectedAIModel == "gemini" {
                        statusMessage = String(format: NSLocalizedString("proMode.grading.deepGrading", comment: "Deep grading question"), questionNum)
                    } else if selectedAIModel == "gemini" {
                        statusMessage = String(format: NSLocalizedString("proMode.grading.geminiGrading", comment: "Gemini grading question"), questionNum)
                    } else {
                        statusMessage = String(format: NSLocalizedString("proMode.grading.grading", comment: "Grading question"), questionNum)
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
                            logger.debug("Storing subquestion grades for Q\(result.questionId): \(result.subquestionGrades.count) subquestions")
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
                        logger.debug("Pushed Q\(result.questionId) grade to UI")
                    }

                    gradedCount += 1

                    // ✅ NEW: Update progress status with animation
                    let progressPercent = Int((Float(gradedCount) / Float(totalQuestions)) * 100)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentGradingStatus = String(format: NSLocalizedString("proMode.grading.progress", comment: "Grading progress"), gradedCount, totalQuestions, progressPercent)
                    }

                    logger.debug("Q\(result.questionId) graded (\(gradedCount)/\(totalQuestions))")
                }
            }
        }

        // ✅ NEW: Final completion animation
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            gradingAnimation = .complete
            currentGradingStatus = NSLocalizedString("proMode.grading.complete", comment: "Grading complete!")
        }

        // Small delay to show completion message
        try? await Task.sleep(nanoseconds: 800_000_000)  // 0.8 seconds

        isGrading = false
        logger.info("All questions graded successfully")

        // Reset animation state
        withAnimation(.easeOut(duration: 0.3)) {
            gradingAnimation = .idle
            currentGradingStatus = ""
        }

        // ✅ SINGLE state transition: .parsed → .graded
        stateManager.completeGrading(gradedQuestions: updatedQuestions)
        logger.debug("State transitioned to .graded")
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
            logger.debug("Q\(question.id) is parent question with \(subquestions.count) subquestions")

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
            logger.debug("Q\(question.id) completed: \(subquestionResults.count) subquestions graded")

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
                    questionType: question.questionType,  // Pass question type for specialized grading
                    contextImageBase64: contextImage,
                    useDeepReasoning: useDeepReasoning,
                    modelProvider: selectedAIModel
                )

                if response.success, let grade = response.grade {
                    if Self.isDebugMode {
                        logger.debug("Q\(question.id) graded: score=\(grade.score), correct=\(grade.isCorrect)")
                    }
                    return GradingResult(
                        questionId: question.id,
                        grade: grade,
                        error: nil,
                        subquestionGrades: [:],
                        subquestionErrors: [:]
                    )
                } else {
                    let error = response.error ?? "Grading failed"
                    logger.error("Q\(question.id) grading error: \(error)")
                    return GradingResult(
                        questionId: question.id,
                        grade: nil,
                        error: error,
                        subquestionGrades: [:],
                        subquestionErrors: [:]
                    )
                }

            } catch {
                logger.error("Q\(question.id) exception: \(error.localizedDescription)")
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

        logger.debug("Grading subquestion \(subquestion.id)...")

        do {
            // Get context image from parent question if available
            let contextImage = getCroppedImageBase64(for: parentQuestionId)

            // ✅ NEW: Get parent question content to provide context for subquestion grading
            let parentContent = questions.first(where: { $0.question.id == parentQuestionId })?.question.parentContent

            if let parent = parentContent {
                logger.debug("Including parent question context: \(parent.prefix(50))...")
            }

            // Call grading endpoint with deep reasoning flag and parent content
            let response = try await networkService.gradeSingleQuestion(
                questionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                subject: subject,
                questionType: subquestion.questionType,  // Pass question type for specialized grading
                contextImageBase64: contextImage,
                parentQuestionContent: parentContent,  // ✅ NEW: Pass parent question content
                useDeepReasoning: useDeepReasoning,  // Pass deep reasoning mode
                modelProvider: selectedAIModel  // NEW: Pass AI model selection
            )

            if response.success, let grade = response.grade {
                logger.debug("Subquestion \(subquestion.id) graded successfully")
                return (subquestion.id, grade, nil)
            } else {
                let error = response.error ?? "Grading failed"
                logger.error("Subquestion \(subquestion.id) error: \(error)")
                return (subquestion.id, nil, error)
            }

        } catch {
            logger.error("Subquestion \(subquestion.id) exception: \(error.localizedDescription)")
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

    // MARK: - Per-Question Regrading

    /// Regrade a single question with Gemini's deep mode for enhanced accuracy
    func regradeQuestion(questionId: Int) async {
        guard let index = questions.firstIndex(where: { $0.question.id == questionId }) else {
            logger.error("Question \(questionId) not found for regrading")
            return
        }

        logger.info("🔄 [Regrade] Starting regrade for Q\(questionId) with Gemini deep mode...")

        // Get local copy and mark as grading
        var updatedQuestions = questions
        updatedQuestions[index].isGrading = true

        await MainActor.run {
            // ✅ FIX: Notify observers so UI sees the isGrading = true change and shows animations
            objectWillChange.send()
            stateManager.updateHomework(questions: updatedQuestions)
        }

        let question = updatedQuestions[index].question

        do {
            // Get context image if available
            let contextImage = getCroppedImageBase64(for: questionId)

            // Call grading endpoint with deep reasoning enabled (Gemini)
            let response = try await networkService.gradeSingleQuestion(
                questionText: question.displayText,
                studentAnswer: question.displayStudentAnswer,
                subject: subject,
                questionType: question.questionType,
                contextImageBase64: contextImage,
                useDeepReasoning: true,  // ✅ Force deep reasoning for regrade
                modelProvider: "gemini"  // ✅ Force Gemini for deep mode
            )

            await MainActor.run {
                // ✅ FIX: Get FRESH copy from state manager to avoid stale data
                var freshQuestions = self.questions
                guard let currentIndex = freshQuestions.firstIndex(where: { $0.question.id == questionId }) else {
                    logger.error("Question \(questionId) disappeared during regrade")
                    return
                }

                if response.success, let grade = response.grade {
                    // Update grade
                    freshQuestions[currentIndex].grade = grade
                    freshQuestions[currentIndex].gradingError = nil
                    logger.info("✅ [Regrade] Q\(questionId) regraded: score=\(grade.score), correct=\(grade.isCorrect)")
                    logger.debug("  - feedback: '\(grade.feedback.prefix(100))...'")
                    logger.debug("  - correctAnswer: '\(grade.correctAnswer?.prefix(50) ?? "nil")...'")
                } else {
                    let error = response.error ?? "Regrade failed"
                    freshQuestions[currentIndex].gradingError = error
                    logger.error("❌ [Regrade] Q\(questionId) failed: \(error)")
                }

                // Mark as not grading anymore
                freshQuestions[currentIndex].isGrading = false

                // ✅ FIX: Explicitly notify observers before updating (ensures UI sees the change)
                objectWillChange.send()

                // Update state
                stateManager.updateHomework(questions: freshQuestions)

                logger.debug("State updated - UI should refresh now")

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(response.success ? .success : .error)
            }

        } catch {
            logger.error("❌ [Regrade] Q\(questionId) exception: \(error.localizedDescription)")
            await MainActor.run {
                var freshQuestions = self.questions
                guard let currentIndex = freshQuestions.firstIndex(where: { $0.question.id == questionId }) else {
                    return
                }

                freshQuestions[currentIndex].gradingError = error.localizedDescription
                freshQuestions[currentIndex].isGrading = false

                objectWillChange.send()
                stateManager.updateHomework(questions: freshQuestions)

                // Error feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }

    /// Regrade a specific subquestion with Gemini's deep mode
    func regradeSubquestion(parentQuestionId: Int, subquestionId: String) async {
        guard let index = questions.firstIndex(where: { $0.question.id == parentQuestionId }) else {
            logger.error("Parent question \(parentQuestionId) not found for subquestion regrade")
            return
        }

        guard let subquestion = questions[index].question.subquestions?.first(where: { $0.id == subquestionId }) else {
            logger.error("Subquestion \(subquestionId) not found in Q\(parentQuestionId)")
            return
        }

        logger.info("🔄 [Regrade] Starting regrade for subquestion \(subquestionId) of Q\(parentQuestionId) with Gemini deep mode...")

        // Mark subquestion as grading
        var updatedQuestions = questions
        updatedQuestions[index].subquestionGradingStatus[subquestionId] = true

        await MainActor.run {
            // ✅ FIX: Notify observers so UI sees the grading status change and shows animations
            objectWillChange.send()
            stateManager.updateHomework(questions: updatedQuestions)
        }

        do {
            // Get context image from parent question if available
            let contextImage = getCroppedImageBase64(for: parentQuestionId)

            // Get parent question content for context
            let parentContent = updatedQuestions[index].question.parentContent

            // Call grading endpoint with deep reasoning enabled (Gemini)
            let response = try await networkService.gradeSingleQuestion(
                questionText: subquestion.questionText,
                studentAnswer: subquestion.studentAnswer,
                subject: subject,
                questionType: subquestion.questionType,
                contextImageBase64: contextImage,
                parentQuestionContent: parentContent,
                useDeepReasoning: true,  // ✅ Force deep reasoning for regrade
                modelProvider: "gemini"  // ✅ Force Gemini for deep mode
            )

            await MainActor.run {
                // ✅ FIX: Get FRESH copy from state manager to avoid stale data
                var freshQuestions = self.questions
                guard let currentIndex = freshQuestions.firstIndex(where: { $0.question.id == parentQuestionId }) else {
                    logger.error("Parent question \(parentQuestionId) disappeared during regrade")
                    return
                }

                if response.success, let grade = response.grade {
                    // Update subquestion grade
                    freshQuestions[currentIndex].subquestionGrades[subquestionId] = grade
                    freshQuestions[currentIndex].subquestionErrors.removeValue(forKey: subquestionId)
                    logger.info("✅ [Regrade] Subquestion \(subquestionId) regraded: score=\(grade.score), correct=\(grade.isCorrect)")
                    logger.debug("  - feedback: '\(grade.feedback.prefix(100))...'")
                    logger.debug("  - correctAnswer: '\(grade.correctAnswer?.prefix(50) ?? "nil")...'")
                } else {
                    let error = response.error ?? "Regrade failed"
                    freshQuestions[currentIndex].subquestionErrors[subquestionId] = error
                    logger.error("❌ [Regrade] Subquestion \(subquestionId) failed: \(error)")
                }

                // Mark subquestion as not grading
                freshQuestions[currentIndex].subquestionGradingStatus[subquestionId] = false

                // ✅ FIX: Explicitly notify observers before updating
                objectWillChange.send()

                // Update state
                stateManager.updateHomework(questions: freshQuestions)

                logger.debug("State updated - UI should refresh now")

                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(response.success ? .success : .error)
            }

        } catch {
            logger.error("❌ [Regrade] Subquestion \(subquestionId) exception: \(error.localizedDescription)")
            await MainActor.run {
                var freshQuestions = self.questions
                guard let currentIndex = freshQuestions.firstIndex(where: { $0.question.id == parentQuestionId }) else {
                    return
                }

                freshQuestions[currentIndex].subquestionErrors[subquestionId] = error.localizedDescription
                freshQuestions[currentIndex].subquestionGradingStatus[subquestionId] = false

                objectWillChange.send()
                stateManager.updateHomework(questions: freshQuestions)

                // Error feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.error)
            }
        }
    }

    // MARK: - User Actions

    func askAIForHelp(questionId: Int, appState: AppState, subquestion: ProgressiveSubquestion? = nil) {
        guard let questionWithGrade = questions.first(where: { $0.question.id == questionId }) else {
            logger.error("Question not found: \(questionId)")
            return
        }

        let question = questionWithGrade.question

        // ✅ NEW: Handle subquestion case separately
        if let subquestion = subquestion {
            // Subquestion case: Use subquestion-specific data
            let subGrade = questionWithGrade.subquestionGrades[subquestion.id]

            logger.debug("Opening AI chat for subquestion \(subquestion.id) of Q\(questionId)")

            // Get cropped image from parent question if available
            let questionImage = croppedImages[questionId]
            if questionImage != nil {
                logger.debug("Including cropped image from parent Q\(questionId)")
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
            let message = String(
                format: NSLocalizedString("proMode.askAIPromptWithSubquestion", comment: ""),
                subquestion.id
            ) + """

            \(NSLocalizedString("proMode.parentQuestionContext", comment: ""))
            \(parentContext)

            \(NSLocalizedString("proMode.subquestion", comment: ""))
            \(subquestion.questionText)

            \(NSLocalizedString("proMode.myAnswer", comment: ""))
            \(subquestion.studentAnswer)

            \(NSLocalizedString("proMode.teacherFeedback", comment: ""))
            \(subGrade?.feedback ?? NSLocalizedString("proMode.noFeedback", comment: ""))
            """

            appState.navigateToChatWithHomeworkQuestion(message: message, context: context)

            logger.debug("Navigated to chat with subquestion context")

        } else {
            // Regular question case: Use original logic
            let grade = questionWithGrade.grade

            logger.debug("Opening AI chat for Q\(questionId)")

            // ✅ NEW: Get cropped image if available
            let questionImage = croppedImages[questionId]
            if questionImage != nil {
                logger.debug("Including cropped image for Q\(questionId)")
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
            let message = "\(NSLocalizedString("proMode.askAIPrompt", comment: "")):\n\n\(question.displayText)\n\n\(NSLocalizedString("proMode.myAnswer", comment: "")):\(question.displayStudentAnswer)\n\n\(NSLocalizedString("proMode.teacherFeedback", comment: "")):\(grade?.feedback ?? NSLocalizedString("proMode.noFeedback", comment: ""))"

            appState.navigateToChatWithHomeworkQuestion(
                message: message,
                context: context
            )

            logger.debug("Navigated to chat with homework context")
        }
    }

    func archiveQuestion(questionId: Int) {
        Task {
            await archiveQuestions([questionId])

            // ✅ NEW: Mark question as archived instead of removing
            await MainActor.run {
                var updatedQuestions = questions
                if let index = updatedQuestions.firstIndex(where: { $0.question.id == questionId }) {
                    // ✅ FIX: Explicitly notify observers before updating (ensures UI sees the change)
                    objectWillChange.send()

                    // ✅ FIX: Wrap in animation for smooth green border appearance
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        updatedQuestions[index].isArchived = true
                        stateManager.updateHomework(questions: updatedQuestions)
                    }
                    logger.debug("Marked Q\(questionId) as archived (remains visible)")
                }
            }
        }
    }

    // ✅ NEW: Archive a specific subquestion only
    func archiveSubquestion(parentQuestionId: Int, subquestionId: String) {
        Task {
            await archiveSubquestions(parentQuestionId: parentQuestionId, subquestionIds: [subquestionId])

            // ✅ Mark the subquestion as archived (visual feedback with green border)
            await MainActor.run {
                var updatedQuestions = questions
                if let index = updatedQuestions.firstIndex(where: { $0.question.id == parentQuestionId }) {
                    // ✅ FIX: Explicitly notify observers before updating
                    objectWillChange.send()

                    // ✅ FIX: Add subquestion ID to archived set with animation
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        updatedQuestions[index].archivedSubquestions.insert(subquestionId)
                        stateManager.updateHomework(questions: updatedQuestions)
                    }
                    logger.debug("Marked subquestion \(subquestionId) of Q\(parentQuestionId) as archived (green border applied)")
                }
            }
        }
    }

    /// Archive specific subquestions from a parent question
    private func archiveSubquestions(parentQuestionId: Int, subquestionIds: [String]) async {
        guard let userId = AuthenticationService.shared.currentUser?.id else {
            logger.error("User not authenticated")
            return
        }

        logger.debug("Archiving \(subquestionIds.count) subquestions from parent Q\(parentQuestionId)...")

        guard let questionWithGrade = questions.first(where: { $0.question.id == parentQuestionId }) else {
            logger.error("Parent question \(parentQuestionId) not found")
            return
        }

        let imageStorage = ProModeImageStorage.shared
        var questionsToArchive: [[String: Any]] = []

        // Get parent question content for context
        let parentContent = questionWithGrade.question.parentContent ?? ""

        // Save cropped image from parent question (shared by all subquestions)
        var imagePath: String?
        if let image = croppedImages[parentQuestionId] {
            logger.debug("Found cropped image for parent Q\(parentQuestionId)")
            imagePath = imageStorage.saveImage(image)
            if let path = imagePath {
                logger.debug("Saved parent image: \(path)")
            }
        }

        // Archive each subquestion individually
        for subquestionId in subquestionIds {
            guard let subquestion = questionWithGrade.question.subquestions?.first(where: { $0.id == subquestionId }) else {
                logger.error("Subquestion \(subquestionId) not found in parent")
                continue
            }

            // Get grade for this specific subquestion
            let grade = questionWithGrade.subquestionGrades[subquestionId]

            // Determine grade string and isCorrect
            let (gradeString, isCorrect) = determineSubquestionGrade(grade: grade)

            // Build archived subquestion data (similar format to regular questions)
            let questionData: [String: Any] = [
                "id": UUID().uuidString,
                "userId": userId,
                "subject": subject,
                "questionText": subquestion.questionText,  // ✅ FIX: Use just subquestion text for library card preview
                "rawQuestionText": "\(parentContent)\n\nSubquestion (\(subquestionId)): \(subquestion.questionText)",  // Full context with parent
                "answerText": grade?.correctAnswer ?? "",  // ✅ FIX: Use correct answer, not student answer
                "confidence": 0.95,
                "hasVisualElements": imagePath != nil,
                "questionImageUrl": imagePath ?? "",  // Share parent's cropped image
                "archivedAt": ISO8601DateFormatter().string(from: Date()),
                "reviewCount": 0,
                "tags": [],
                "notes": "",
                "studentAnswer": subquestion.studentAnswer,
                "grade": gradeString,
                "points": grade?.score ?? 0.0,
                "maxPoints": 1.0,
                "feedback": grade?.feedback ?? "",
                "correctAnswer": grade?.correctAnswer ?? "",
                "isGraded": grade != nil,
                "isCorrect": isCorrect,
                "questionType": subquestion.questionType ?? "short_answer",
                "options": [],
                "proMode": true,
                "parentQuestionId": parentQuestionId,  // Link back to parent
                "subquestionId": subquestionId  // Track subquestion ID
            ]

            questionsToArchive.append(questionData)
            logger.debug("Prepared subquestion \(subquestionId) for archiving")
        }

        let withImages = questionsToArchive.filter { ($0["hasVisualElements"] as? Bool) == true }.count
        logger.info("Subquestion archive summary: parent Q\(parentQuestionId), \(questionsToArchive.count) subquestions, \(withImages) with images")

        // Save to local storage and get ID mappings
        let idMappings = QuestionLocalStorage.shared.saveQuestions(questionsToArchive)

        logger.info("Successfully archived \(questionsToArchive.count) subquestions from parent Q\(parentQuestionId)")

        // ✅ NEW: Queue error analysis for wrong subquestions (Pass 2 - Two-Pass Grading)
        var wrongSubquestions = questionsToArchive.filter {
            ($0["isCorrect"] as? Bool) == false
        }

        // ✅ CRITICAL: Remap IDs to actual saved IDs (handles duplicate detection)
        if !wrongSubquestions.isEmpty {
            for index in 0..<wrongSubquestions.count {
                if let originalId = wrongSubquestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    wrongSubquestions[index]["id"] = mapping.savedId
                    if Self.isDebugMode {
                        logger.debug("Remapped subquestion error analysis ID: \(originalId.prefix(8))... → \(mapping.savedId.prefix(8))...")
                    }
                }
            }

            let sessionId = UUID().uuidString // Generate session ID for this grading batch
            ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                sessionId: sessionId,
                wrongQuestions: wrongSubquestions
            )
            logger.info("Queued \(wrongSubquestions.count) wrong SUBQUESTIONS for Pass 2 error analysis")
        }

        // ✅ NEW: Queue concept extraction for correct subquestions (Bidirectional Status Tracking)
        var correctSubquestions = questionsToArchive.filter {
            ($0["isCorrect"] as? Bool) == true
        }

        // ✅ CRITICAL: Remap IDs to actual saved IDs (handles duplicate detection)
        if !correctSubquestions.isEmpty {
            for index in 0..<correctSubquestions.count {
                if let originalId = correctSubquestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    correctSubquestions[index]["id"] = mapping.savedId
                    if Self.isDebugMode {
                        logger.debug("Remapped subquestion concept extraction ID: \(originalId.prefix(8))... → \(mapping.savedId.prefix(8))...")
                    }
                }
            }

            let sessionId = UUID().uuidString // Generate session ID for this grading batch
            ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                sessionId: sessionId,
                correctQuestions: correctSubquestions
            )
            logger.info("✅ Queued \(correctSubquestions.count) correct SUBQUESTIONS for concept extraction (mastery tracking)")
        }
    }

    /// Determine grade string and isCorrect status for a subquestion
    private func determineSubquestionGrade(grade: ProgressiveGradeResult?) -> (gradeString: String, isCorrect: Bool) {
        if let grade = grade {
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

    /// Archive questions by their IDs
    private func archiveQuestions(_ questionIds: [Int]) async {
        guard let userId = AuthenticationService.shared.currentUser?.id else {
            logger.error("User not authenticated")
            return
        }

        logger.debug("Archiving \(questionIds.count) Pro Mode questions...")

        let imageStorage = ProModeImageStorage.shared
        var questionsToArchive: [[String: Any]] = []
        var subquestionsToArchive: [(parentId: Int, subquestionIds: [String])] = []

        for questionId in questionIds {
            guard let questionWithGrade = questions.first(where: { $0.question.id == questionId }) else {
                continue
            }

            let question = questionWithGrade.question

            // ✅ FIX: Check if this is a parent question with subquestions
            if question.isParentQuestion, let subquestions = question.subquestions, !subquestions.isEmpty {
                logger.debug("Q\(questionId): Detected parent question with \(subquestions.count) subquestions")
                let subquestionIds = subquestions.map { $0.id }
                subquestionsToArchive.append((parentId: questionId, subquestionIds: subquestionIds))

                // ✅ FIX: Skip archiving parent question itself - only archive subquestions
                // Parent content is already included in each subquestion's rawQuestionText (see archiveSubquestions)
                logger.debug("Q\(questionId): Skipping parent question archive (will archive \(subquestions.count) subquestions separately)")
                continue  // Skip to next question
            }

            // Save cropped image to file system if available
            var imagePath: String?
            if Self.isDebugMode {
                logger.debug("Q\(questionId): Checking for cropped image...")
                logger.debug("croppedImages has \(croppedImages.count) entries, keys: \(croppedImages.keys.sorted())")
            }

            if let image = croppedImages[questionId] {
                if Self.isDebugMode {
                    logger.debug("Q\(questionId): Found cropped image (size: \(image.size))")
                }
                imagePath = imageStorage.saveImage(image)
                if let path = imagePath {
                    if Self.isDebugMode {
                        let fileExists = FileManager.default.fileExists(atPath: path)
                        logger.debug("Q\(questionId): Saved image to: \(path), exists: \(fileExists)")
                    }
                } else {
                    logger.error("Q\(questionId): Failed to save image to file system")
                }
            } else if Self.isDebugMode {
                logger.debug("Q\(questionId): No cropped image found in memory")
            }

            // Determine grade and isCorrect
            let (gradeString, isCorrect) = determineGradeAndCorrectness(for: questionWithGrade)

            // 🔍 CRITICAL DEBUG: Log grading data before archiving (debug mode only)
            if Self.isDebugMode {
                logger.debug("=== ARCHIVE DEBUG Q\(questionId) ===")
                logger.debug("Grade object present: \(questionWithGrade.grade != nil)")
                if let grade = questionWithGrade.grade {
                    logger.debug("  - score: \(grade.score)")
                    logger.debug("  - isCorrect: \(grade.isCorrect)")
                    logger.debug("  - feedback: '\(grade.feedback.prefix(50))'...")
                    logger.debug("  - correctAnswer: '\(grade.correctAnswer ?? "NIL")'")
                    logger.debug("  - correctAnswer length: \(grade.correctAnswer?.count ?? 0)")
                }
                logger.debug("Student answer: '\(question.displayStudentAnswer.prefix(50))'...")
                logger.debug("===")
            }

            // Build archived question data
            let questionData: [String: Any] = [
                "id": UUID().uuidString,
                "userId": userId,
                "subject": subject,
                "questionText": question.displayText,
                "rawQuestionText": question.displayText,  // Use same as questionText for Pro Mode
                "answerText": questionWithGrade.grade?.correctAnswer ?? "",  // ✅ FIX: Use correct answer, not student answer
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
                "correctAnswer": questionWithGrade.grade?.correctAnswer ?? "",  // ✅ CRITICAL: Save correct answer
                "isGraded": questionWithGrade.grade != nil,
                "isCorrect": isCorrect,
                "questionType": question.questionType ?? "short_answer",
                "options": [],
                "proMode": true  // Mark as Pro Mode question
            ]

            // 🔍 CRITICAL DEBUG: Log what's actually being archived (debug mode only)
            if Self.isDebugMode {
                logger.debug("ARCHIVED Q\(questionId): studentAnswer='\(question.displayStudentAnswer.prefix(30))', correctAnswer='\((questionWithGrade.grade?.correctAnswer ?? "NIL").prefix(30))'")
            }
            questionsToArchive.append(questionData)
            if Self.isDebugMode {
                logger.debug("Prepared Q\(questionId) for archiving (hasImage: \(imagePath != nil), isCorrect: \(isCorrect))")
            }
        }

        let withImages = questionsToArchive.filter { ($0["hasVisualElements"] as? Bool) == true }.count
        logger.info("Archive summary: \(questionsToArchive.count) questions, \(withImages) with images")

        // Save to local storage and get ID mappings
        let idMappings = QuestionLocalStorage.shared.saveQuestions(questionsToArchive)

        logger.info("Successfully archived \(questionsToArchive.count) Pro Mode questions")

        // ✅ NEW: Queue error analysis for wrong answers (Pass 2 - Two-Pass Grading)
        var wrongQuestions = questionsToArchive.filter {
            ($0["isCorrect"] as? Bool) == false
        }

        // ✅ CRITICAL: Remap IDs to actual saved IDs (handles duplicate detection)
        if !wrongQuestions.isEmpty {
            for index in 0..<wrongQuestions.count {
                if let originalId = wrongQuestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    wrongQuestions[index]["id"] = mapping.savedId
                    if Self.isDebugMode {
                        logger.debug("Remapped error analysis ID: \(originalId.prefix(8))... → \(mapping.savedId.prefix(8))...")
                    }
                }
            }

            let sessionId = UUID().uuidString // Generate session ID for this grading batch
            ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                sessionId: sessionId,
                wrongQuestions: wrongQuestions
            )
            logger.info("Queued \(wrongQuestions.count) wrong answers for Pass 2 error analysis")
        }

        // ✅ NEW: Queue concept extraction for CORRECT answers (Bidirectional Status Tracking)
        var correctQuestions = questionsToArchive.filter {
            ($0["isCorrect"] as? Bool) == true
        }

        // ✅ CRITICAL: Remap IDs to actual saved IDs (handles duplicate detection)
        if !correctQuestions.isEmpty {
            for index in 0..<correctQuestions.count {
                if let originalId = correctQuestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    correctQuestions[index]["id"] = mapping.savedId
                    if Self.isDebugMode {
                        logger.debug("Remapped concept extraction ID: \(originalId.prefix(8))... → \(mapping.savedId.prefix(8))...")
                    }
                }
            }

            let sessionId = UUID().uuidString // Generate session ID for this grading batch
            ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                sessionId: sessionId,
                correctQuestions: correctQuestions
            )
            logger.info("✅ Queued \(correctQuestions.count) CORRECT answers for concept extraction (mastery tracking)")
        }

        // ✅ NEW: Archive all subquestions for parent questions
        if !subquestionsToArchive.isEmpty {
            logger.debug("Archiving subquestions for \(subquestionsToArchive.count) parent questions...")
            for (parentId, subquestionIds) in subquestionsToArchive {
                logger.debug("Archiving \(subquestionIds.count) subquestions for parent Q\(parentId)")
                await archiveSubquestions(parentQuestionId: parentId, subquestionIds: subquestionIds)
            }
            let totalSubquestions = subquestionsToArchive.reduce(0) { $0 + $1.subquestionIds.count }
            logger.info("Successfully archived \(totalSubquestions) subquestions across \(subquestionsToArchive.count) parent questions")
        }
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

                logger.debug("Calculating accuracy for \(questions.count) questions...")

                for (index, questionWithGrade) in questions.enumerated() {
                    // Handle parent questions (questions with subquestions)
                    if questionWithGrade.isParentQuestion {
                        let subquestionGrades = Array(questionWithGrade.subquestionGrades.values)
                        totalCount += subquestionGrades.count
                        let subCorrect = subquestionGrades.filter { $0.isCorrect }.count
                        correctCount += subCorrect

                        logger.debug("Q\(index+1) (Parent): \(subCorrect)/\(subquestionGrades.count) subquestions correct")

                    } else {
                        // Handle regular questions
                        totalCount += 1

                        if let grade = questionWithGrade.grade {
                            // Question has been graded
                            if grade.isCorrect {
                                correctCount += 1
                                logger.debug("Q\(index+1): Correct")
                            } else if grade.score >= 0.5 {
                                // Partial credit: score >= 50%
                                // Conservative approach: don't count as correct (consistent with Detail/Fast mode)
                                logger.debug("Q\(index+1): Partial - counted as incorrect")
                            } else {
                                logger.debug("Q\(index+1): Incorrect")
                            }
                        } else {
                            // Ungraded question: conservatively count as incorrect
                            logger.debug("Q\(index+1): Ungraded - counted as incorrect")
                        }
                    }
                }

                let totalQuestions = totalCount
                let totalCorrect = correctCount

                logger.info("Progress marking: \(totalCorrect)/\(totalQuestions) correct")

                // Update progress using PointsEarningManager
                await MainActor.run {
                    PointsEarningManager.shared.markHomeworkProgress(
                        subject: subject,
                        numberOfQuestions: totalQuestions,
                        numberOfCorrectQuestions: totalCorrect
                    )

                    // ✅ CRITICAL: Set flag in BOTH ViewModel and StateManager to persist across navigation
                    stateManager.currentHomework?.hasMarkedProgress = true
                }

                logger.info("Progress marked successfully")
                logger.debug("hasMarkedProgress flag set in StateManager")

                // ✅ NEW: Record handwriting score if available
                if let handwriting = stateManager.currentHomework?.parseResults.handwritingEvaluation,
                   handwriting.hasHandwriting,
                   let score = handwriting.score {

                    ShortTermStatusService.shared.recordHandwritingScore(
                        score: score,
                        feedback: handwriting.feedback,
                        subject: subject,
                        questionCount: totalQuestions
                    )

                    logger.info("✅ Recorded handwriting score: \(score)/10")
                }

                // ✅ NEW: Save to Homework Album when marking progress
                saveToHomeworkAlbum()
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
                // Select all graded questions (including parent questions with graded subquestions)
                let gradedQuestionIds = questions.filter { questionWithGrade in
                    if questionWithGrade.question.isParentQuestion {
                        // Parent question: select if ANY subquestion is graded
                        return !questionWithGrade.subquestionGrades.isEmpty
                    } else {
                        // Regular question: select if graded
                        return questionWithGrade.grade != nil
                    }
                }.map { $0.question.id }
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

        logger.debug("Batch archiving \(selectedQuestionIds.count) Pro Mode questions...")

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

        logger.info("Batch archive completed - \(selectedQuestionIds.count) questions marked as archived")
    }

    // MARK: - Question Deletion

    /// Delete selected questions from the homework session
    /// Unlike archiving, this permanently removes questions from the session
    func deleteQuestions(questionIds: [Int]) {
        guard !questionIds.isEmpty else {
            logger.warning("deleteQuestions called with empty array")
            return
        }

        logger.info("Deleting \(questionIds.count) questions from homework session...")

        // Get current state
        var updatedQuestions = questions
        var updatedCroppedImages = croppedImages
        var updatedAnnotations = annotations

        // Remove questions and their associated data
        updatedQuestions.removeAll { questionIds.contains($0.question.id) }

        // Remove cropped images for deleted questions
        for questionId in questionIds {
            updatedCroppedImages.removeValue(forKey: questionId)
            logger.debug("Removed cropped image for Q\(questionId)")
        }

        // Remove annotations for deleted questions
        // Find question numbers for deleted questions
        let deletedQuestionNumbers = Set(
            parseResults?.questions
                .filter { questionIds.contains($0.id) }
                .compactMap { $0.questionNumber } ?? []
        )

        if !deletedQuestionNumbers.isEmpty {
            updatedAnnotations.removeAll { annotation in
                if let questionNumber = annotation.questionNumber {
                    return deletedQuestionNumbers.contains(questionNumber)
                }
                return false
            }
            logger.debug("Removed \(annotations.count - updatedAnnotations.count) annotations for deleted questions")
        }

        // Update global state
        stateManager.updateHomework(
            questions: updatedQuestions,
            annotations: updatedAnnotations,
            croppedImages: updatedCroppedImages
        )

        logger.info("✅ Successfully deleted \(questionIds.count) questions from session")
    }

    // MARK: - PDF Export

    @Published var isExportingPDF = false
    @Published var pdfExportProgress: Double = 0.0
    @Published var exportedPDFDocument: PDFDocument?
    @Published var showPDFPreview = false

    private let pdfExporter = ProModePDFExporter()

    /// Export homework to PDF (local rendering, no AI/backend)
    func exportToPDF() async {
        logger.info("📄 [PDF Export] Starting PDF export...")

        // Reset state
        await MainActor.run {
            isExportingPDF = true
            pdfExportProgress = 0.0
            exportedPDFDocument = nil
            showPDFPreview = false
        }

        // Update progress from exporter
        let cancellable = pdfExporter.$exportProgress.sink { [weak self] progress in
            Task { @MainActor in
                self?.pdfExportProgress = progress
            }
        }

        // Export PDF
        let pdfDocument = await pdfExporter.exportToPDF(
            questions: questions,
            subject: parseResults?.subject ?? "Homework",
            totalQuestions: parseResults?.totalQuestions ?? questions.count,
            croppedImages: croppedImages
        )

        cancellable.cancel()

        await MainActor.run {
            isExportingPDF = false
        }

        if let pdfDocument = pdfDocument {
            logger.info("✅ [PDF Export] PDF export succeeded - \(pdfDocument.pageCount) pages")
            await MainActor.run {
                exportedPDFDocument = pdfDocument
                // Show preview with a small delay to ensure state is updated
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                    showPDFPreview = true
                }
            }
        } else {
            logger.error("❌ [PDF Export] PDF export failed - nil document returned")
        }
    }

    // MARK: - Helper Methods

    private func annotationColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        return colors[index % colors.count]
    }
}

// MARK: - Question Annotation Model

struct QuestionAnnotation: Identifiable, Codable {
    let id: UUID
    var topLeft: [Double]       // Normalized [0-1] coordinates
    var bottomRight: [Double]   // Normalized [0-1] coordinates
    var questionNumber: String? // Maps to question number (not id)
    let colorIndex: Int         // Store color index instead of Color
    var pageIndex: Int = 0      // ✅ NEW: Track which page this annotation belongs to

    // ✅ NEW: Computed property to get Color from index
    var color: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        return colors[colorIndex % colors.count]
    }

    // ✅ NEW: Custom initializer to support old API
    init(id: UUID = UUID(), topLeft: [Double], bottomRight: [Double], questionNumber: String?, colorIndex: Int, pageIndex: Int = 0) {
        self.id = id
        self.topLeft = topLeft
        self.bottomRight = bottomRight
        self.questionNumber = questionNumber
        self.colorIndex = colorIndex
        self.pageIndex = pageIndex
    }

    // ✅ NEW: Convenience initializer with Color (for backward compatibility)
    init(topLeft: [Double], bottomRight: [Double], questionNumber: String?, color: Color, pageIndex: Int = 0) {
        // Map color to index (approximate - just use sequential index)
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        let colorIndex = colors.firstIndex(of: color) ?? 0

        self.init(
            id: UUID(),
            topLeft: topLeft,
            bottomRight: bottomRight,
            questionNumber: questionNumber,
            colorIndex: colorIndex,
            pageIndex: pageIndex
        )
    }
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
