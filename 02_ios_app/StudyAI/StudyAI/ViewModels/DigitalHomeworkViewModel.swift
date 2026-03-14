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
    @Published var isAnnotationSectionExpanded: Bool = false  // Fold/unfold annotation panel

    // Archive selection mode
    @Published var isArchiveMode = false
    @Published var selectedQuestionIds: Set<String> = []

    // deep → Gemini, normal → OpenAI
    @Published var useDeepReasoning = false

    // Diagram analysis state (Phase 1.5)
    @Published var isDiagramAnalysisPending = false
    @Published var diagramAnalysisFailed = false
    @Published var questionsUnderDiagramAnalysis: Set<String> = []
    @Published var questionsMissingDiagramImage: Set<String> = []

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

    // ✅ Archive result summary (for UI toast)
    struct ArchiveResultSummary: Equatable {
        let added: Int        // New questions added to library
        let skipped: Int      // Duplicates skipped
        let mistakeCount: Int // Wrong answers queued for mistake notebook
        let albumSaved: Bool  // Image saved to homework album (Smart Organize only)
        let isSmartOrganize: Bool
    }

    @Published var archiveResultSummary: ArchiveResultSummary? = nil

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

    var croppedImages: [String: UIImage] {
        guard let homework = stateManager.currentHomework else { return [:] }
        var images: [String: UIImage] = [:]
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

    /// Grade button is enabled only when diagram analysis is complete and not already grading
    var isGradingEnabled: Bool {
        !isDiagramAnalysisPending && !isGrading && !questions.isEmpty
    }

    var hasValidAnnotations: Bool {
        let annotations = self.annotations
        return !annotations.isEmpty && annotations.allSatisfy { $0.questionNumber != nil }
    }

    var availableQuestionNumbers: [String] {
        guard let results = parseResults else { return [] }
        return results.questions.compactMap { $0.questionNumber }
    }

    /// True when any question (or subquestion) in Pro Mode signals it needs a diagram image
    var anyQuestionNeedsImage: Bool {
        questions.contains { qwg in
            qwg.question.needImage == true ||
            qwg.question.subquestions?.contains { $0.needImage == true } == true
        }
    }

    /// Hierarchical list of annotation targets: parent/independent questions and their subquestions
    enum AnnotationTarget: Equatable {
        case parent(id: String, number: String, previewText: String)
        case subquestion(parentId: String, subId: String, subNumber: String, previewText: String)
        case independent(id: String, number: String, previewText: String)

        var questionId: String {
            switch self {
            case .parent(let id, _, _): return id
            case .subquestion(_, let subId, _, _): return subId
            case .independent(let id, _, _): return id
            }
        }

        var displayLabel: String {
            switch self {
            case .parent(_, let number, let preview):
                let questionPrefix = NSLocalizedString("proMode.questionPrefix", comment: "Q")
                return "\(questionPrefix) \(number): \(preview)"
            case .subquestion(_, _, let subNumber, let preview):
                return "  (\(subNumber)) \(preview)"
            case .independent(_, let number, let preview):
                let questionPrefix = NSLocalizedString("proMode.questionPrefix", comment: "Q")
                return "\(questionPrefix) \(number): \(preview)"
            }
        }

        /// Indentation level for display (0 = top-level, 1 = subquestion)
        var indentLevel: Int {
            switch self {
            case .parent, .independent: return 0
            case .subquestion: return 1
            }
        }

        /// The question number string used for annotation matching
        var annotationQuestionNumber: String {
            switch self {
            case .parent(_, let number, _): return number
            case .subquestion(_, let subId, _, _): return subId
            case .independent(_, let number, _): return number
            }
        }
    }

    var availableAnnotationTargets: [AnnotationTarget] {
        var targets: [AnnotationTarget] = []
        let sorted = questions.sorted {
            let a = Int($0.question.questionNumber ?? "") ?? 0
            let b = Int($1.question.questionNumber ?? "") ?? 0
            return a < b
        }
        for qwg in sorted {
            let q = qwg.question
            guard let number = q.questionNumber else { continue }
            let preview = String(q.displayText.prefix(30))
            if q.isParentQuestion, let subs = q.subquestions {
                targets.append(.parent(id: q.id, number: number, previewText: preview))
                for sub in subs {
                    let subPreview = String(sub.questionText.prefix(30))
                    targets.append(.subquestion(parentId: q.id, subId: sub.id, subNumber: sub.id, previewText: subPreview))
                }
            } else {
                targets.append(.independent(id: q.id, number: number, previewText: preview))
            }
        }
        return targets
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
        // ✅ FIX: Use the correct image based on annotation's pageIndex
        guard annotation.pageIndex < originalImages.count else {
            logger.error("Invalid pageIndex \(annotation.pageIndex) for annotation")
            return
        }

        let imageForThisPage = originalImages[annotation.pageIndex]

        guard let questionNumber = annotation.questionNumber else { return }

        // Resolve the storage key: check top-level questions first, then subquestions
        let imageKey: String
        if let topLevelId = parseResults?.questions.first(where: { $0.questionNumber == questionNumber })?.id {
            imageKey = topLevelId
        } else if let subId = parseResults?.questions
            .flatMap({ $0.subquestions ?? [] })
            .first(where: { $0.id == questionNumber })?.id {
            imageKey = subId
        } else {
            return
        }

        // ✅ OPTIMIZATION 1: Normalize image orientation BEFORE cropping
        // This fixes rotation bugs where EXIF orientation causes wrong crops
        guard let normalizedImage = imageForThisPage.normalizedOrientation() else {
            logger.error("Failed to normalize image orientation for Q\(questionNumber) on page \(annotation.pageIndex)")
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
                    updatedImages[imageKey] = compressedImage
                    objectWillChange.send()
                    stateManager.updateHomework(croppedImages: updatedImages)
                    questionsMissingDiagramImage.remove(imageKey)

                    let originalSize = croppedUIImage.pngData()?.count ?? 0
                    let compressedSize = jpegData.count
                    let savings = originalSize > 0 ? (1.0 - Double(compressedSize) / Double(originalSize)) * 100 : 0
                    if Self.isDebugMode {
                        logger.debug("Cropped image for Q\(questionNumber) from page \(annotation.pageIndex) (id: \(imageKey))")
                        logger.debug("Compressed: \(originalSize / 1024)KB → \(compressedSize / 1024)KB (saved \(Int(savings))%)")
                    }
                } else {
                    logger.error("Failed to create UIImage from JPEG data for Q\(questionNumber)")
                }
            } else {
                logger.error("Failed to compress image to JPEG for Q\(questionNumber)")
            }
        } else {
            logger.error("Failed to crop image for Q\(questionNumber) on page \(annotation.pageIndex)")
        }
    }

    func getCroppedImage(for questionId: String) -> UIImage? {
        return croppedImages[questionId]
    }

    // MARK: - Sync Cropped Images

    /// Removes cropped images for questions that no longer have annotations
    func syncCroppedImages() {
        // Get all question numbers that have annotations
        let annotatedQuestionNumbers = Set(annotations.compactMap { $0.questionNumber })

        // Get all question IDs that should have images (top-level AND subquestion IDs)
        var validQuestionIds = Set<String>()
        for questionNumber in annotatedQuestionNumbers {
            if let questionId = parseResults?.questions.first(where: { $0.questionNumber == questionNumber })?.id {
                // Top-level question match
                validQuestionIds.insert(questionId)
            } else if let subId = parseResults?.questions
                .flatMap({ $0.subquestions ?? [] })
                .first(where: { $0.id == questionNumber })?.id {
                // Subquestion match — store under subquestion's own id
                validQuestionIds.insert(subId)
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

    // MARK: - Diagram Analysis (Phase 1.5)

    /// Run after parse. Finds diagram bounding boxes for need_image=true questions,
    /// auto-crops them, and attaches to croppedImages. Blocks grade button until done.
    /// If no questions need images, or analysis already ran, returns immediately.
    func runDiagramAnalysisIfNeeded() async {
        // Skip if already running
        guard !isDiagramAnalysisPending else { return }

        let needImageQuestions = questions.filter {
            $0.question.needImage == true ||
            $0.question.subquestions?.contains { $0.needImage == true } == true
        }
        guard !needImageQuestions.isEmpty else {
            logger.info("No need_image questions — skipping diagram analysis")
            return
        }

        logger.info("Starting diagram analysis for \(needImageQuestions.count) questions")
        print("🔍 [DiagramAnalysis] STEP 1: Found \(needImageQuestions.count) need_image questions: \(needImageQuestions.map { $0.question.id })")
        print("🔍 [DiagramAnalysis] originalImages.count = \(originalImages.count)")

        // Collect all IDs that need an image (top-level + subquestions)
        var allNeedImageIds = Set<String>()
        for qwg in needImageQuestions {
            allNeedImageIds.insert(qwg.question.id)
            for sub in qwg.question.subquestions ?? [] where sub.needImage == true {
                allNeedImageIds.insert(sub.id)
            }
        }

        await MainActor.run {
            isDiagramAnalysisPending = true
            diagramAnalysisFailed = false
            questionsUnderDiagramAnalysis = allNeedImageIds
        }

        defer {
            Task { @MainActor in
                isDiagramAnalysisPending = false
            }
        }

        // Group questions by pageNumber (each page = one batch call)
        var byPage: [Int: [(question: ProgressiveQuestionWithGrade, image: UIImage)]] = [:]
        for qwg in needImageQuestions {
            let pageIndex = (qwg.question.pageNumber ?? 1) - 1
            guard pageIndex < originalImages.count else {
                print("🔍 [DiagramAnalysis] ⚠️ pageIndex \(pageIndex) out of bounds (count=\(originalImages.count)) for q=\(qwg.question.id)")
                continue
            }
            byPage[pageIndex, default: []].append((qwg, originalImages[pageIndex]))
        }

        print("🔍 [DiagramAnalysis] STEP 2: byPage keys = \(byPage.keys.sorted())")

        // Capture base state once — task children must not read ViewModel properties directly
        let baseAnnotations = annotations

        // Collect per-page results in parallel, then apply a single atomic write
        typealias PageResult = (crops: [String: UIImage], annotations: [QuestionAnnotation])
        var mergedCrops: [String: UIImage] = [:]
        var mergedAnnotations: [QuestionAnnotation] = baseAnnotations

        await withTaskGroup(of: PageResult?.self) { group in
            for (pageIndex, entries) in byPage {
                group.addTask {
                    await self.locateAndCropDiagrams(entries: entries, pageIndex: pageIndex)
                }
            }
            for await result in group {
                guard let result else { continue }
                mergedCrops.merge(result.crops) { _, new in new }
                for ann in result.annotations {
                    if !mergedAnnotations.contains(where: { $0.questionNumber == ann.questionNumber }) {
                        mergedAnnotations.append(ann)
                    }
                }
            }
        }

        let foundIds = Set(mergedCrops.keys)
        let notFoundIds = allNeedImageIds.subtracting(foundIds)
        await MainActor.run {
            questionsUnderDiagramAnalysis = []
            questionsMissingDiagramImage.formUnion(notFoundIds)
            for id in foundIds { questionsMissingDiagramImage.remove(id) }
            if !mergedCrops.isEmpty {
                stateManager.updateHomework(annotations: mergedAnnotations, croppedImages: mergedCrops)
                print("🔍 [DiagramAnalysis] STEP 6c: stateManager updated — croppedImages.count=\(stateManager.currentHomework?.croppedImages.count ?? -1)")
            }
        }

        print("🔍 [DiagramAnalysis] STEP 7: COMPLETE — crops=\(mergedCrops.count), keys=\(mergedCrops.keys.sorted())")
        logger.info("Diagram analysis complete. Cropped images: \(mergedCrops.count)")
    }

    // Returns per-page crops and annotations; never writes to stateManager directly.
    private func locateAndCropDiagrams(
        entries: [(question: ProgressiveQuestionWithGrade, image: UIImage)],
        pageIndex: Int
    ) async -> (crops: [String: UIImage], annotations: [QuestionAnnotation])? {
        guard let image = entries.first?.image else {
            print("🔍 [DiagramAnalysis] STEP 3 FAIL: could not get image for pageIndex=\(pageIndex)")
            return nil
        }

        // Compress to 1024px/0.7 for the API call (same as parse) to stay under 5MB body limit.
        // The original full-res image is kept for cropping — normalized coords are scale-independent.
        let apiImage = image.resizedForUpload(maxDimension: 1024)
        guard let jpegData = apiImage.jpegData(compressionQuality: 0.7) else {
            print("🔍 [DiagramAnalysis] STEP 3 FAIL: could not compress image for pageIndex=\(pageIndex)")
            return nil
        }

        print("🔍 [DiagramAnalysis] STEP 3: image size=\(image.size) → api size=\(apiImage.size) pageIndex=\(pageIndex) jpegData=\(jpegData.count) bytes")
        let base64Image = jpegData.base64EncodedString()

        // Build DiagramQuestion list (top-level + subquestions that need images)
        var diagramQuestions: [DiagramQuestion] = []
        for entry in entries {
            let q = entry.question.question
            diagramQuestions.append(DiagramQuestion(
                id: q.id,
                questionNumber: q.questionNumber,
                questionText: q.displayText.isEmpty ? nil : String(q.displayText.prefix(200))
            ))
            for sub in q.subquestions ?? [] where sub.needImage == true {
                diagramQuestions.append(DiagramQuestion(
                    id: sub.id,
                    questionNumber: sub.id,
                    questionText: String(sub.questionText.prefix(200))
                ))
            }
        }

        print("🔍 [DiagramAnalysis] STEP 4: sending \(diagramQuestions.count) questions to API: \(diagramQuestions.map { "\($0.id)=\($0.questionText?.prefix(30) ?? "nil")" })")

        do {
            let response = try await networkService.locateDiagramRegions(
                base64Image: base64Image,
                questions: diagramQuestions
            )

            print("🔍 [DiagramAnalysis] STEP 5: API response success=\(response.success) regions=\(response.regions.count) error=\(response.error ?? "nil")")
            for r in response.regions {
                print("🔍 [DiagramAnalysis]   region qid=\(r.questionId) topLeft=\(r.imageRegion.topLeft) bottomRight=\(r.imageRegion.bottomRight) confidence=\(r.confidence)")
            }

            guard response.success else {
                logger.warning("locate-diagram-regions returned success=false: \(response.error ?? "unknown")")
                await MainActor.run { diagramAnalysisFailed = true }
                return nil
            }

            // Build region lookup: questionId → ImageRegion
            var regionMap: [String: ImageRegion] = [:]
            for result in response.regions {
                regionMap[result.questionId] = result.imageRegion
            }

            // Crop from full-res orientation-normalized image
            guard let normalizedImage = image.normalizedOrientation() else {
                print("🔍 [DiagramAnalysis] STEP 6 FAIL: normalizedOrientation() returned nil for image size=\(image.size)")
                return nil
            }
            print("🔍 [DiagramAnalysis] STEP 6: normalizedImage size=\(normalizedImage.size) cgImage=\(normalizedImage.cgImage != nil)")

            var pageCrops: [String: UIImage] = [:]
            var pageAnnotations: [QuestionAnnotation] = []

            for entry in entries {
                let q = entry.question.question

                // Parent/independent question
                if let region = regionMap[q.id] {
                    if let cropped = cropRegion(region, from: normalizedImage) {
                        pageCrops[q.id] = cropped
                        print("🔍 [DiagramAnalysis] ✅ Cropped q.id=\(q.id) size=\(cropped.size)")
                        addAnnotationIfAbsent(
                            region: region,
                            questionNumber: q.questionNumber,
                            pageIndex: pageIndex,
                            into: &pageAnnotations
                        )
                    } else {
                        print("🔍 [DiagramAnalysis] ❌ cropRegion returned nil for q.id=\(q.id) tl=\(region.topLeft) br=\(region.bottomRight)")
                    }
                } else {
                    print("🔍 [DiagramAnalysis] ⚠️ no region in regionMap for q.id=\(q.id) — regionMap keys=\(regionMap.keys.sorted())")
                }

                // Subquestions — use their own region, fallback to parent's
                let parentRegion = regionMap[q.id]
                for sub in q.subquestions ?? [] {
                    let subRegion = regionMap[sub.id] ?? parentRegion
                    if let subRegion, let cropped = cropRegion(subRegion, from: normalizedImage) {
                        pageCrops[sub.id] = cropped
                        print("🔍 [DiagramAnalysis] ✅ Cropped sub.id=\(sub.id) size=\(cropped.size)")
                    }
                }
            }

            print("🔍 [DiagramAnalysis] STEP 6b: page \(pageIndex) produced crops=\(pageCrops.count) annotations=\(pageAnnotations.count)")
            return (crops: pageCrops, annotations: pageAnnotations)

        } catch {
            print("🔍 [DiagramAnalysis] ❌ CATCH: \(error)")
            logger.warning("locate-diagram-regions call failed (will grade without image context): \(error.localizedDescription)")
            await MainActor.run { diagramAnalysisFailed = true }
            return nil
        }
    }

    private func cropRegion(_ region: ImageRegion, from image: UIImage) -> UIImage? {
        let w = image.size.width
        let h = image.size.height
        let rect = CGRect(
            x: CGFloat(region.topLeft[0]) * w,
            y: CGFloat(region.topLeft[1]) * h,
            width: CGFloat(region.bottomRight[0] - region.topLeft[0]) * w,
            height: CGFloat(region.bottomRight[1] - region.topLeft[1]) * h
        )
        print("🔍 [DiagramAnalysis] cropRegion: imageSize=(\(w)x\(h)) rect=\(rect) cgImage=\(image.cgImage != nil)")
        guard rect.width > 10, rect.height > 10 else {
            print("🔍 [DiagramAnalysis] cropRegion FAIL: rect too small \(rect)")
            return nil
        }
        guard let cgCropped = image.cgImage?.cropping(to: rect) else {
            print("🔍 [DiagramAnalysis] cropRegion FAIL: cgImage?.cropping returned nil")
            return nil
        }
        return UIImage(cgImage: cgCropped)
    }

    private func addAnnotationIfAbsent(
        region: ImageRegion,
        questionNumber: String?,
        pageIndex: Int,
        into annotations: inout [QuestionAnnotation]
    ) {
        guard let questionNumber else { return }
        guard !annotations.contains(where: { $0.questionNumber == questionNumber }) else { return }
        annotations.append(QuestionAnnotation(
            topLeft: region.topLeft,
            bottomRight: region.bottomRight,
            questionNumber: questionNumber,
            color: annotationColor(for: annotations.count),
            pageIndex: pageIndex
        ))
    }

    // MARK: - AI Grading

    func startGrading() async {
        logger.info("Starting AI grading: mode=\(useDeepReasoning ? "deep/Gemini" : "normal/OpenAI"), questions=\(questions.count)")

        // Fold annotation panel when grading starts
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isAnnotationSectionExpanded = false
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
                    let statusMessage = useDeepReasoning
                        ? String(format: NSLocalizedString("proMode.grading.deepGrading", comment: "Deep grading question"), questionNum)
                        : String(format: NSLocalizedString("proMode.grading.grading", comment: "Grading question"), questionNum)

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
        let questionId: String  // Changed from Int to String
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
                    useDeepReasoning: useDeepReasoning
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

            } catch NetworkService.NetworkError.authenticationRequired {
                logger.error("Q\(question.id) auth expired — triggering sign-out")
                AuthenticationService.shared.handleExpiredSession()
                return GradingResult(
                    questionId: question.id,
                    grade: nil,
                    error: "Session expired",
                    subquestionGrades: [:],
                    subquestionErrors: [:]
                )
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
        parentQuestionId: String  // Changed from Int to String
    ) async -> (String, ProgressiveGradeResult?, String?) {

        logger.debug("Grading subquestion \(subquestion.id)...")

        do {
            // Prefer the subquestion's own cropped image; fall back to parent's image
            let contextImage = getCroppedImageBase64(for: subquestion.id)
                ?? getCroppedImageBase64(for: parentQuestionId)

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
                useDeepReasoning: useDeepReasoning  // Pass deep reasoning mode
            )

            if response.success, let grade = response.grade {
                logger.debug("Subquestion \(subquestion.id) graded successfully")
                return (subquestion.id, grade, nil)
            } else {
                let error = response.error ?? "Grading failed"
                logger.error("Subquestion \(subquestion.id) error: \(error)")
                return (subquestion.id, nil, error)
            }

        } catch NetworkService.NetworkError.authenticationRequired {
            logger.error("Subquestion \(subquestion.id) auth expired — triggering sign-out")
            AuthenticationService.shared.handleExpiredSession()
            return (subquestion.id, nil, "Session expired")
        } catch {
            logger.error("Subquestion \(subquestion.id) exception: \(error.localizedDescription)")
            return (subquestion.id, nil, error.localizedDescription)
        }
    }

    private func getCroppedImageBase64(for questionId: String) -> String? {  // Changed from Int to String
        guard let image = croppedImages[questionId],
              let jpegData = image.jpegData(compressionQuality: 0.85) else {
            return nil
        }
        return jpegData.base64EncodedString()
    }

    // MARK: - Per-Question Reparsing

    /// Re-extract a single question from its source page image using Gemini.
    /// Called when the user taps the reparse icon on an inaccurately parsed question card.
    /// On success: replaces question content and clears the stale grade.
    func reparseQuestion(questionId: String) async {
        guard let index = questions.firstIndex(where: { $0.question.id == questionId }) else {
            logger.error("Question \(questionId) not found for reparsing")
            return
        }

        let question = questions[index].question
        let pageIndex = (question.pageNumber ?? 1) - 1
        guard pageIndex < originalImages.count else {
            logger.error("Page index \(pageIndex) out of range (have \(originalImages.count) pages)")
            return
        }

        logger.info("🔄 [Reparse] Starting reparse for Q\(questionId) on page \(pageIndex + 1)...")

        // Mark as loading
        var updatedQuestions = questions
        updatedQuestions[index].isGrading = true
        await MainActor.run {
            objectWillChange.send()
            stateManager.updateHomework(questions: updatedQuestions)
        }

        // Compress the source page image
        guard let imageData = originalImages[pageIndex].jpegData(compressionQuality: 0.85) else {
            logger.error("Failed to compress page image for reparse")
            await MainActor.run {
                var fresh = self.questions
                guard let i = fresh.firstIndex(where: { $0.question.id == questionId }) else { return }
                fresh[i].gradingError = "Failed to prepare image"
                fresh[i].isGrading = false
                objectWillChange.send()
                stateManager.updateHomework(questions: fresh)
            }
            return
        }

        let base64Image = imageData.base64EncodedString()

        do {
            let response = try await networkService.reparseQuestion(
                base64Image: base64Image,
                questionNumber: question.questionNumber ?? questionId,
                questionHint: question.questionText
            )

            await MainActor.run {
                var fresh = self.questions
                guard let i = fresh.firstIndex(where: { $0.question.id == questionId }) else {
                    logger.error("Question \(questionId) disappeared during reparse")
                    return
                }

                if response.success, let newQuestion = response.question {
                    // Log AI reparsed content
                    logger.info("[Reparse] AI returned for Q\(questionId):")
                    logger.info("[Reparse]   questionNumber : \(newQuestion.questionNumber ?? "nil")")
                    logger.info("[Reparse]   questionText   : \(newQuestion.questionText ?? "nil")")
                    logger.info("[Reparse]   studentAnswer  : \(newQuestion.studentAnswer ?? "nil")")
                    logger.info("[Reparse]   isParent       : \(String(newQuestion.isParent ?? false))")
                    logger.info("[Reparse]   needImage      : \(String(newQuestion.needImage ?? false))")
                    if let subs = newQuestion.subquestions {
                        logger.info("[Reparse]   subquestions   : \(subs.count)")
                        for sub in subs {
                            logger.info("[Reparse]     sub \(sub.id): \(sub.questionText ?? "?")")
                        }
                    }

                    // Replace with reparsed question, clear stale grade
                    fresh[i] = ProgressiveQuestionWithGrade(id: fresh[i].id, question: newQuestion)

                    logger.info("[Reparse] iOS state updated — Q\(questionId) question replaced, grade cleared")
                    logger.info("✅ [Reparse] Q\(questionId) reparsed successfully")
                } else {
                    let error = response.error ?? "Reparse failed"
                    fresh[i].gradingError = error
                    fresh[i].isGrading = false
                    logger.error("❌ [Reparse] Q\(questionId) failed: \(error)")
                }

                objectWillChange.send()
                stateManager.updateHomework(questions: fresh)

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(response.success ? .success : .error)
            }

        } catch {
            logger.error("❌ [Reparse] Q\(questionId) exception: \(error.localizedDescription)")
            await MainActor.run {
                var fresh = self.questions
                guard let i = fresh.firstIndex(where: { $0.question.id == questionId }) else { return }
                fresh[i].gradingError = error.localizedDescription
                fresh[i].isGrading = false
                objectWillChange.send()
                stateManager.updateHomework(questions: fresh)
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - Per-Question Regrading

    /// Regrade a single question with Gemini's deep mode for enhanced accuracy
    func regradeQuestion(questionId: String) async {  // Changed from Int to String
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
                useDeepReasoning: true  // ✅ Force deep reasoning for regrade
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

        } catch NetworkService.NetworkError.authenticationRequired {
            logger.error("❌ [Regrade] Q\(questionId) auth expired — triggering sign-out")
            AuthenticationService.shared.handleExpiredSession()
            await MainActor.run {
                var freshQuestions = self.questions
                guard let currentIndex = freshQuestions.firstIndex(where: { $0.question.id == questionId }) else { return }
                freshQuestions[currentIndex].gradingError = "Session expired"
                freshQuestions[currentIndex].isGrading = false
                objectWillChange.send()
                stateManager.updateHomework(questions: freshQuestions)
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
    func regradeSubquestion(parentQuestionId: String, subquestionId: String) async {  // Changed Int to String
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
                useDeepReasoning: true  // ✅ Force deep reasoning for regrade
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

    func askAIForHelp(questionId: String, appState: AppState, subquestion: ProgressiveSubquestion? = nil) {  // Changed Int to String
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

    func archiveQuestion(questionId: String) {  // Changed Int to String
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
    func archiveSubquestion(parentQuestionId: String, subquestionId: String) {  // Changed Int to String
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
    private func archiveSubquestions(parentQuestionId: String, subquestionIds: [String]) async -> (added: Int, skipped: Int) {
        guard let userId = AuthenticationService.shared.currentUser?.id else {
            logger.error("User not authenticated")
            return (0, 0)
        }

        let log = AppLogger(category: "SmartOrganize")
        let pLabel = "Q\(questions.first(where: { $0.question.id == parentQuestionId })?.question.questionNumber ?? parentQuestionId.prefix(4).description)"

        guard let questionWithGrade = questions.first(where: { $0.question.id == parentQuestionId }) else {
            log.info("🗂️ [SMART ORGANIZE]   ⚠️ \(pLabel) — parent not found, cannot archive subquestions")
            return (0, 0)
        }

        let imageStorage = ProModeImageStorage.shared
        var questionsToArchive: [[String: Any]] = []
        let parentContent = questionWithGrade.question.parentContent ?? ""

        // Save parent cropped image (fallback shared by subquestions that have no own crop)
        var parentImagePath: String?
        if let image = croppedImages[parentQuestionId] {
            parentImagePath = imageStorage.saveImage(image)
            log.info("🗂️ [SMART ORGANIZE]   🖼️  \(pLabel) — shared cropped image saved: \(parentImagePath != nil ? "✅" : "❌ failed")")
        } else {
            log.info("🗂️ [SMART ORGANIZE]   🖼️  \(pLabel) — no cropped image for parent")
        }

        for subquestionId in subquestionIds {
            guard let subquestion = questionWithGrade.question.subquestions?.first(where: { $0.id == subquestionId }) else {
                log.info("🗂️ [SMART ORGANIZE]   ⚠️  \(pLabel)(\(subquestionId)) — subquestion not found, skipping")
                continue
            }

            // Prefer subquestion-specific crop; fall back to parent crop
            var effectiveImagePath: String? = parentImagePath
            if let subImage = croppedImages[subquestionId] {
                effectiveImagePath = imageStorage.saveImage(subImage)
                log.info("🗂️ [SMART ORGANIZE]   🖼️  \(pLabel)(\(subquestionId)) — subquestion-specific crop saved: \(effectiveImagePath != nil ? "✅" : "❌ failed")")
            }

            let grade = questionWithGrade.subquestionGrades[subquestionId]
            let (gradeString, isCorrect) = determineSubquestionGrade(grade: grade)
            let studentAns = (subquestion.studentAnswer ?? "").prefix(40)
            let correctAns = (grade?.correctAnswer ?? "").prefix(40)

            log.info("🗂️ [SMART ORGANIZE]   📝 \(pLabel)(\(subquestionId)) — grade: \(gradeString.isEmpty ? "(ungraded)" : gradeString) | correct: \(isCorrect)")
            log.info("🗂️ [SMART ORGANIZE]        student: \"\(studentAns)\"")
            log.info("🗂️ [SMART ORGANIZE]        answer:  \"\(correctAns)\"")

            let questionData: [String: Any] = [
                "id": "\(parentQuestionId)_\(subquestionId)",  // globally unique — parent+sub compound key
                "userId": userId,
                "subject": subject,
                "questionText": subquestion.questionText,
                "rawQuestionText": "\(parentContent)\n\nSubquestion (\(subquestionId)): \(subquestion.questionText)",
                "answerText": grade?.correctAnswer ?? "",
                "confidence": 0.95,
                "hasVisualElements": effectiveImagePath != nil,
                "questionImageUrl": effectiveImagePath ?? "",
                "archivedAt": ISO8601DateFormatter().string(from: Date()),
                "reviewCount": 0,
                "tags": [],
                "notes": "",
                "studentAnswer": subquestion.studentAnswer ?? "",
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
                "parentQuestionId": parentQuestionId,
                "subquestionId": subquestionId,
                "source": "homework"
            ]
            questionsToArchive.append(questionData)
        }

        let idMappings = currentUserQuestionStorage().saveQuestions(questionsToArchive)
        let skipped = idMappings.filter { $0.originalId != $0.savedId }.count
        let added   = idMappings.count - skipped
        log.info("🗂️ [SMART ORGANIZE]   💾 \(pLabel) subquestions — added: \(added), skipped (duplicate): \(skipped)")

        print("🔬 [EA-DBG] ── archiveSubquestions \(pLabel): \(questionsToArchive.count) subqs, idMappings (\(idMappings.count)):")
        for m in idMappings {
            if m.originalId != m.savedId {
                print("🔬 [EA-DBG]   REMAP \(m.originalId.prefix(20)) → \(m.savedId.prefix(12))  ⚠️ duplicate")
            } else {
                print("🔬 [EA-DBG]   OK    \(m.originalId.prefix(20))")
            }
        }

        // Pass 2: error analysis
        var wrongSubquestions = questionsToArchive.filter { ($0["isCorrect"] as? Bool) == false }
        print("🔬 [EA-DBG] subq wrong filter: \(wrongSubquestions.count)/\(questionsToArchive.count)")
        if wrongSubquestions.isEmpty {
            log.info("🗂️ [SMART ORGANIZE]   🧠 \(pLabel) — no wrong subquestions for error analysis")
        } else {
            for index in 0..<wrongSubquestions.count {
                if let originalId = wrongSubquestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    if mapping.originalId != mapping.savedId {
                        print("🔬 [EA-DBG]   remap subq wrong[\(index)] \(originalId.prefix(20)) → \(mapping.savedId.prefix(12))")
                    }
                    wrongSubquestions[index]["id"] = mapping.savedId
                } else if let originalId = wrongSubquestions[index]["id"] as? String {
                    print("🔬 [EA-DBG]   ⚠️ subq wrong[\(index)] id=\(originalId.prefix(20)) NOT FOUND in idMappings!")
                }
            }
            let sessionId = UUID().uuidString
            print("🔬 [EA-DBG] → subq queueErrorAnalysis sessionId=\(sessionId.prefix(8)) count=\(wrongSubquestions.count) ids=\(wrongSubquestions.compactMap { ($0["id"] as? String)?.prefix(20) })")
            ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(sessionId: sessionId, wrongQuestions: wrongSubquestions)
            log.info("🗂️ [SMART ORGANIZE]   🧠 \(pLabel) — queued \(wrongSubquestions.count) wrong subquestion(s) for error analysis")
        }

        // Pass 2: concept extraction
        var correctSubquestions = questionsToArchive.filter { ($0["isCorrect"] as? Bool) == true }
        if correctSubquestions.isEmpty {
            log.info("🗂️ [SMART ORGANIZE]   ✅ \(pLabel) — no correct subquestions for concept extraction")
        } else {
            for index in 0..<correctSubquestions.count {
                if let originalId = correctSubquestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    correctSubquestions[index]["id"] = mapping.savedId
                }
            }
            let sessionId = UUID().uuidString
            ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(sessionId: sessionId, correctQuestions: correctSubquestions)
            log.info("🗂️ [SMART ORGANIZE]   ✅ \(pLabel) — queued \(correctSubquestions.count) correct subquestion(s) for concept extraction")
        }

        return (added: added, skipped: skipped)
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

    /// Archive questions by their IDs. Returns (added, skipped, mistakeCount).
    @discardableResult
    private func archiveQuestions(_ questionIds: [String]) async -> (added: Int, skipped: Int, mistakeCount: Int) {
        guard let userId = AuthenticationService.shared.currentUser?.id else {
            logger.error("User not authenticated")
            return (0, 0, 0)
        }

        let log = AppLogger(category: "SmartOrganize")
        log.info("🗂️ [SMART ORGANIZE] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        log.info("🗂️ [SMART ORGANIZE] ARCHIVE START — \(questionIds.count) question(s) requested")
        log.info("🗂️ [SMART ORGANIZE] Subject: \(subject)")

        let imageStorage = ProModeImageStorage.shared
        var questionsToArchive: [[String: Any]] = []
        var subquestionsToArchive: [(parentId: String, subquestionIds: [String])] = []

        for questionId in questionIds {
            guard let questionWithGrade = questions.first(where: { $0.question.id == questionId }) else {
                log.info("🗂️ [SMART ORGANIZE]   ⚠️ Q[\(questionId.prefix(8))] — not found in session, skipping")
                continue
            }

            let question = questionWithGrade.question
            let qLabel = "Q\(question.questionNumber ?? questionId.prefix(4).description)"

            // Parent question — delegate to subquestion archiving
            if question.isParentQuestion, let subquestions = question.subquestions, !subquestions.isEmpty {
                log.info("🗂️ [SMART ORGANIZE]   🔀 \(qLabel) — parent with \(subquestions.count) subquestion(s), delegating")
                let subquestionIds = subquestions.map { $0.id }
                subquestionsToArchive.append((parentId: questionId, subquestionIds: subquestionIds))
                continue
            }

            // Save cropped image
            var imagePath: String?
            if let image = croppedImages[questionId] {
                imagePath = imageStorage.saveImage(image)
                log.info("🗂️ [SMART ORGANIZE]   🖼️  \(qLabel) — cropped image saved: \(imagePath != nil ? "✅" : "❌ failed")")
            } else {
                log.info("🗂️ [SMART ORGANIZE]   🖼️  \(qLabel) — no cropped image")
            }

            let (gradeString, isCorrect) = determineGradeAndCorrectness(for: questionWithGrade)
            let studentAns = question.displayStudentAnswer.prefix(40)
            let correctAns = (questionWithGrade.grade?.correctAnswer ?? "").prefix(40)
            log.info("🗂️ [SMART ORGANIZE]   📝 \(qLabel) — grade: \(gradeString.isEmpty ? "(ungraded)" : gradeString) | correct: \(isCorrect)")
            log.info("🗂️ [SMART ORGANIZE]        student: \"\(studentAns)\"")
            log.info("🗂️ [SMART ORGANIZE]        answer:  \"\(correctAns)\"")

            let questionData: [String: Any] = [
                "id": questionId,
                "userId": userId,
                "subject": subject,
                "questionText": question.displayText,
                "rawQuestionText": question.displayText,
                "answerText": questionWithGrade.grade?.correctAnswer ?? "",
                "confidence": 0.95,
                "hasVisualElements": imagePath != nil,
                "questionImageUrl": imagePath ?? "",
                "archivedAt": ISO8601DateFormatter().string(from: Date()),
                "reviewCount": 0,
                "tags": [],
                "notes": "",
                "studentAnswer": question.displayStudentAnswer,
                "grade": gradeString,
                "points": questionWithGrade.grade?.score ?? 0.0,
                "maxPoints": 1.0,
                "feedback": questionWithGrade.grade?.feedback ?? "",
                "correctAnswer": questionWithGrade.grade?.correctAnswer ?? "",
                "isGraded": questionWithGrade.grade != nil,
                "isCorrect": isCorrect,
                "questionType": question.questionType ?? "short_answer",
                "options": [],
                "proMode": true,
                "source": "homework"
            ]
            questionsToArchive.append(questionData)
        }

        log.info("🗂️ [SMART ORGANIZE]   ─────────────────────────────────────────")
        log.info("🗂️ [SMART ORGANIZE]   Prepared \(questionsToArchive.count) regular + \(subquestionsToArchive.count) parent(s) for storage")

        // Debug: dump each question going into storage
        print("🔬 [EA-DBG] ── archiveQuestions: \(questionsToArchive.count) questions to save ──")
        for q in questionsToArchive {
            let qid     = (q["id"]            as? String) ?? "nil"
            let correct = (q["isCorrect"]     as? Bool)   ?? false
            let graded  = (q["isGraded"]      as? Bool)   ?? false
            let student = (q["studentAnswer"] as? String) ?? ""
            let answer  = (q["answerText"]    as? String) ?? ""
            print("🔬 [EA-DBG]   id=\(qid.prefix(12)) isCorrect=\(correct) isGraded=\(graded) student='\(student.prefix(30))' answerText='\(answer.prefix(30))'")
        }

        // Pass 1: save to local storage
        let idMappings = currentUserQuestionStorage().saveQuestions(questionsToArchive)

        let skipped = idMappings.filter { $0.originalId != $0.savedId }.count
        let added   = idMappings.count - skipped
        log.info("🗂️ [SMART ORGANIZE]   💾 Storage result — added: \(added), skipped (duplicate): \(skipped)")
        print("🔬 [EA-DBG] saveQuestions idMappings (\(idMappings.count) total, \(skipped) remapped):")
        for m in idMappings {
            if m.originalId != m.savedId {
                log.info("🗂️ [SMART ORGANIZE]      ⏭️  duplicate remapped \(m.originalId.prefix(8))… → \(m.savedId.prefix(8))…")
                print("🔬 [EA-DBG]   REMAP \(m.originalId.prefix(12)) → \(m.savedId.prefix(12))  ⚠️ duplicate — error analysis will use savedId")
            } else {
                print("🔬 [EA-DBG]   OK    \(m.originalId.prefix(12)) → \(m.savedId.prefix(12))")
            }
        }

        // Pass 2: error analysis for wrong answers
        var wrongQuestions = questionsToArchive.filter { ($0["isCorrect"] as? Bool) == false }
        print("🔬 [EA-DBG] wrong filter: \(wrongQuestions.count)/\(questionsToArchive.count) questions are isCorrect=false")
        for q in wrongQuestions {
            let qid    = (q["id"]        as? String) ?? "nil"
            let graded = (q["isGraded"]  as? Bool)   ?? false
            print("🔬 [EA-DBG]   wrong id=\(qid.prefix(12)) isGraded=\(graded)")
        }
        if wrongQuestions.isEmpty {
            log.info("🗂️ [SMART ORGANIZE]   🧠 Pass 2 (error analysis) — no wrong answers, skipped")
        } else {
            for index in 0..<wrongQuestions.count {
                if let originalId = wrongQuestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    if mapping.originalId != mapping.savedId {
                        print("🔬 [EA-DBG]   remap wrong[\(index)] \(originalId.prefix(12)) → \(mapping.savedId.prefix(12))")
                    }
                    wrongQuestions[index]["id"] = mapping.savedId
                } else if let originalId = wrongQuestions[index]["id"] as? String {
                    print("🔬 [EA-DBG]   ⚠️ wrong[\(index)] id=\(originalId.prefix(12)) NOT FOUND in idMappings — id mismatch!")
                }
            }
            let sessionId = UUID().uuidString
            print("🔬 [EA-DBG] → queueErrorAnalysis sessionId=\(sessionId.prefix(8)) count=\(wrongQuestions.count) ids=\(wrongQuestions.compactMap { ($0["id"] as? String)?.prefix(12) })")
            ErrorAnalysisQueueService.shared.queueErrorAnalysisAfterGrading(
                sessionId: sessionId,
                wrongQuestions: wrongQuestions
            )
            log.info("🗂️ [SMART ORGANIZE]   🧠 Pass 2 (error analysis) — queued \(wrongQuestions.count) wrong answer(s), session: \(sessionId.prefix(8))…")
        }

        // Pass 2: concept extraction for correct answers
        var correctQuestions = questionsToArchive.filter { ($0["isCorrect"] as? Bool) == true }
        if correctQuestions.isEmpty {
            log.info("🗂️ [SMART ORGANIZE]   ✅ Pass 2 (concept extraction) — no correct answers, skipped")
        } else {
            for index in 0..<correctQuestions.count {
                if let originalId = correctQuestions[index]["id"] as? String,
                   let mapping = idMappings.first(where: { $0.originalId == originalId }) {
                    correctQuestions[index]["id"] = mapping.savedId
                }
            }
            let sessionId = UUID().uuidString
            ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                sessionId: sessionId,
                correctQuestions: correctQuestions
            )
            log.info("🗂️ [SMART ORGANIZE]   ✅ Pass 2 (concept extraction) — queued \(correctQuestions.count) correct answer(s), session: \(sessionId.prefix(8))…")
        }

        // Archive subquestions for parent questions
        var subAdded = 0
        var subSkipped = 0
        if !subquestionsToArchive.isEmpty {
            for (parentId, subquestionIds) in subquestionsToArchive {
                let pLabel = "Q\(questions.first(where: { $0.question.id == parentId })?.question.questionNumber ?? parentId.prefix(4).description)"
                log.info("🗂️ [SMART ORGANIZE]   🔀 Archiving \(subquestionIds.count) subquestion(s) for \(pLabel)")
                let subResult = await archiveSubquestions(parentQuestionId: parentId, subquestionIds: subquestionIds)
                subAdded += subResult.added
                subSkipped += subResult.skipped
            }
        }

        log.info("🗂️ [SMART ORGANIZE] ARCHIVE END ✅")
        log.info("🗂️ [SMART ORGANIZE] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        return (added: added + subAdded, skipped: skipped + subSkipped, mistakeCount: wrongQuestions.count)
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
            let log = AppLogger(category: "SmartOrganize")
            log.info("🗂️ [SMART ORGANIZE] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            log.info("🗂️ [SMART ORGANIZE] SMART ORGANIZE START — subject: \(subject)")

            // Calculate statistics
            var correctCount = 0
            var totalCount = 0

            for (index, questionWithGrade) in questions.enumerated() {
                if questionWithGrade.isParentQuestion {
                    let subquestionGrades = Array(questionWithGrade.subquestionGrades.values)
                    let subCorrect = subquestionGrades.filter { $0.isCorrect }.count
                    totalCount += subquestionGrades.count
                    correctCount += subCorrect
                    log.info("🗂️ [SMART ORGANIZE]   Q\(index+1) (parent) — \(subCorrect)/\(subquestionGrades.count) subquestions correct")
                } else {
                    totalCount += 1
                    if let grade = questionWithGrade.grade, grade.isCorrect {
                        correctCount += 1
                        log.info("🗂️ [SMART ORGANIZE]   Q\(index+1) — ✅ correct (score: \(grade.score))")
                    } else if let grade = questionWithGrade.grade {
                        log.info("🗂️ [SMART ORGANIZE]   Q\(index+1) — ❌ incorrect (score: \(grade.score))")
                    } else {
                        log.info("🗂️ [SMART ORGANIZE]   Q\(index+1) — ⚪ ungraded")
                    }
                }
            }

            log.info("🗂️ [SMART ORGANIZE]   Score: \(correctCount)/\(totalCount)")

            await MainActor.run {
                PointsEarningManager.shared.markHomeworkProgress(
                    subject: subject,
                    numberOfQuestions: totalCount,
                    numberOfCorrectQuestions: correctCount
                )
                stateManager.currentHomework?.hasMarkedProgress = true
            }
            log.info("🗂️ [SMART ORGANIZE]   📊 PointsEarningManager updated")

            // Record handwriting score if available
            if let handwriting = stateManager.currentHomework?.parseResults.handwritingEvaluation,
               handwriting.hasHandwriting,
               let score = handwriting.score {
                ShortTermStatusService.shared.recordHandwritingScore(
                    score: score,
                    feedback: handwriting.feedback,
                    subject: subject,
                    questionCount: totalCount
                )
                log.info("🗂️ [SMART ORGANIZE]   ✍️  Handwriting score recorded: \(score)/10")
            } else {
                log.info("🗂️ [SMART ORGANIZE]   ✍️  No handwriting evaluation to record")
            }

            saveToHomeworkAlbum()
            log.info("🗂️ [SMART ORGANIZE]   📸 Homework album saved")

            // Archive all wrong/ungraded questions
            let wrongQuestionIds = questions.compactMap { qwg -> String? in
                if qwg.isParentQuestion {
                    let hasWrong = qwg.subquestionGrades.values.contains { !$0.isCorrect }
                    return hasWrong ? qwg.question.id : nil
                } else {
                    let isWrong = qwg.grade.map { !$0.isCorrect } ?? true
                    return isWrong ? qwg.question.id : nil
                }
            }

            if wrongQuestionIds.isEmpty {
                log.info("🗂️ [SMART ORGANIZE]   🗂️  No wrong/ungraded questions — archive skipped")
                await MainActor.run {
                    archiveResultSummary = ArchiveResultSummary(
                        added: 0, skipped: 0, mistakeCount: 0,
                        albumSaved: true, isSmartOrganize: true
                    )
                }
            } else {
                log.info("🗂️ [SMART ORGANIZE]   🗂️  Archiving \(wrongQuestionIds.count) wrong/ungraded question(s) (dedup via hash)")
                let result = await archiveQuestions(wrongQuestionIds)
                await MainActor.run {
                    var updatedQuestions = questions
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        for id in wrongQuestionIds {
                            if let idx = updatedQuestions.firstIndex(where: { $0.question.id == id }) {
                                updatedQuestions[idx].isArchived = true
                            }
                        }
                        stateManager.updateHomework(questions: updatedQuestions)
                    }
                    archiveResultSummary = ArchiveResultSummary(
                        added: result.added,
                        skipped: result.skipped,
                        mistakeCount: result.mistakeCount,
                        albumSaved: true,
                        isSmartOrganize: true
                    )
                }
            }

            // Save correct questions to local storage so LocalProgressService can compute accurate accuracy
            // getMistakeQuestions() filters isCorrect==false, so this won't pollute mistake review
            let userId = AuthenticationService.shared.currentUser?.id ?? "anonymous"
            let nowISO = ISO8601DateFormatter().string(from: Date())
            let correctPayload: [[String: Any]] = questions.compactMap { qwg -> [String: Any]? in
                let question = qwg.question
                let isCorrect: Bool
                if qwg.isParentQuestion {
                    guard !qwg.subquestionGrades.isEmpty else { return nil }
                    isCorrect = qwg.subquestionGrades.values.allSatisfy { $0.isCorrect }
                } else {
                    isCorrect = qwg.grade?.isCorrect == true
                }
                guard isCorrect else { return nil }
                return [
                    "id": question.id,
                    "userId": userId,
                    "subject": subject,
                    "questionText": question.displayText,
                    "answerText": qwg.grade?.correctAnswer ?? "",
                    "studentAnswer": question.displayStudentAnswer,
                    "grade": "CORRECT",
                    "isCorrect": true,
                    "isGraded": true,
                    "archivedAt": nowISO,
                    "confidence": 0.95,
                    "reviewCount": 0,
                    "tags": [],
                    "points": 1.0,
                    "maxPoints": 1.0,
                    "questionType": question.questionType ?? "short_answer",
                    "proMode": true,
                    "source": "homework"
                ]
            }
            if !correctPayload.isEmpty {
                currentUserQuestionStorage().saveQuestions(correctPayload)
                log.info("🗂️ [SMART ORGANIZE]   ✅ Saved \(correctPayload.count) correct answer(s) to local storage for progress tracking")
                let correctSessionId = UUID().uuidString
                ErrorAnalysisQueueService.shared.queueConceptExtractionForCorrectAnswers(
                    sessionId: correctSessionId,
                    correctQuestions: correctPayload
                )
                log.info("🗂️ [SMART ORGANIZE]   ✅ Queued concept extraction for \(correctPayload.count) correct answer(s)")
            } else {
                log.info("🗂️ [SMART ORGANIZE]   ✅ No correct answers to save or extract")
            }

            log.info("🗂️ [SMART ORGANIZE] SMART ORGANIZE END ✅")
            log.info("🗂️ [SMART ORGANIZE] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
    }

    // MARK: - Archive Selection Mode

    var isAllSelected: Bool {
        // Check if all graded, non-archived questions are selected
        let selectableIds = questions.filter { q in
            !q.isArchived && (q.question.isParentQuestion ? !q.subquestionGrades.isEmpty : q.grade != nil)
        }.map { $0.question.id }
        return !selectableIds.isEmpty && selectableIds.allSatisfy { selectedQuestionIds.contains($0) }
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
                // Select all graded, non-archived questions
                let selectableIds = questions.filter { questionWithGrade in
                    guard !questionWithGrade.isArchived else { return false }
                    if questionWithGrade.question.isParentQuestion {
                        return !questionWithGrade.subquestionGrades.isEmpty
                    } else {
                        return questionWithGrade.grade != nil
                    }
                }.map { $0.question.id }
                selectedQuestionIds = Set(selectableIds)
            }
        }
    }

    func toggleQuestionSelection(questionId: String) {
        // Don't allow selecting already-archived questions
        guard let q = questions.first(where: { $0.question.id == questionId }), !q.isArchived else { return }
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
        let result = await archiveQuestions(Array(selectedQuestionIds))

        // Mark questions as archived instead of removing them
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
            archiveResultSummary = ArchiveResultSummary(
                added: result.added,
                skipped: result.skipped,
                mistakeCount: result.mistakeCount,
                albumSaved: false,
                isSmartOrganize: false
            )
        }

        logger.info("Batch archive completed — added: \(result.added), skipped: \(result.skipped), mistakes: \(result.mistakeCount)")
    }

    // MARK: - Question Deletion

    /// Delete selected questions from the homework session
    /// Unlike archiving, this permanently removes questions from the session
    func deleteQuestions(questionIds: [String]) {  // Changed from [Int] to [String]
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

    /// Set to true to present DigitalHomeworkPDFPreviewView via fullScreenCover.
    /// Generation and options customisation are handled inside the preview view.
    @Published var showPDFPreview = false

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
        let colors: [Color] = [DesignTokens.Colors.Cute.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
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

    /// Resize to fit within maxDimension (preserving aspect ratio) for API uploads.
    /// Returns self unchanged if already within bounds.
    func resizedForUpload(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let ratio = maxDimension / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
