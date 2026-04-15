//
//  DigitalHomeworkStateManager.swift
//  StudyAI
//
//  ✅ NEW: Global state manager for Digital Homework (State-based architecture)
//  Manages three states: Nothing → Parsed → Graded
//  State persists across tab switches, only resets on new homework parse
//

import Foundation
import SwiftUI
import Combine

// MARK: - Digital Homework State Enum

enum DigitalHomeworkState: String, Codable {
    case nothing    // No homework parsed
    case parsed     // Homework parsed, not graded yet
    case graded     // Homework graded
}

// MARK: - Digital Homework Data Model
// ✅ Codable for persistence in Homework Album
struct DigitalHomeworkData: Codable {
    let homeworkHash: String  // Unique identifier for this homework
    var parseResults: ParseHomeworkQuestionsResponse
    let originalImageDataArray: [Data]  // ✅ UPDATED: Store multiple images as Data array
    var questions: [ProgressiveQuestionWithGrade]
    var annotations: [QuestionAnnotation]
    var croppedImages: [String: Data]  // Changed from Int to String - questionId -> image data (for in-memory storage)

    // Metadata
    let createdAt: Date
    var lastModified: Date

    // Progress tracking
    var hasMarkedProgress: Bool = false

    // ✅ Custom initializer
    init(
        homeworkHash: String,
        parseResults: ParseHomeworkQuestionsResponse,
        originalImageDataArray: [Data],
        questions: [ProgressiveQuestionWithGrade],
        annotations: [QuestionAnnotation],
        croppedImages: [String: Data],  // Changed from Int to String
        createdAt: Date,
        lastModified: Date,
        hasMarkedProgress: Bool = false
    ) {
        self.homeworkHash = homeworkHash
        self.parseResults = parseResults
        self.originalImageDataArray = originalImageDataArray
        self.questions = questions
        self.annotations = annotations
        self.croppedImages = croppedImages
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.hasMarkedProgress = hasMarkedProgress
    }

    // ✅ Backward compatibility: return first image
    var originalImage: UIImage? {
        guard let firstImageData = originalImageDataArray.first else { return nil }
        return UIImage(data: firstImageData)
    }

    // ✅ NEW: Get all original images
    var originalImages: [UIImage] {
        return originalImageDataArray.compactMap { UIImage(data: $0) }
    }

    func getCroppedImage(for questionId: String) -> UIImage? {  // Changed from Int to String
        guard let imageData = croppedImages[questionId] else { return nil }
        return UIImage(data: imageData)
    }

    mutating func setCroppedImage(_ image: UIImage, for questionId: String) {  // Changed from Int to String
        if let imageData = image.jpegData(compressionQuality: 0.85) {
            croppedImages[questionId] = imageData
        }
    }

    /// Clear all grades but keep homework data (for revert)
    mutating func clearGrades() {
        for i in 0..<questions.count {
            questions[i].grade = nil
            questions[i].isGrading = false
            questions[i].gradingError = nil

            if questions[i].isParentQuestion {
                questions[i].subquestionGrades.removeAll()
                questions[i].subquestionGradingStatus.removeAll()
                questions[i].subquestionErrors.removeAll()
            }

            // Keep isArchived flag (archived questions persist)
        }

        // ✅ CRITICAL FIX: Reset progress tracking when reverting grades
        // This prevents double-counting when user reverts and regrades
        hasMarkedProgress = false
    }

    // ✅ Custom Codable implementation for backward compatibility
    enum CodingKeys: String, CodingKey {
        case homeworkHash
        case parseResults
        case originalImageDataArray
        case originalImageData  // Old key for backward compatibility
        case questions
        case annotations
        case croppedImages
        case createdAt
        case lastModified
        case hasMarkedProgress
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        homeworkHash = try container.decode(String.self, forKey: .homeworkHash)
        parseResults = try container.decode(ParseHomeworkQuestionsResponse.self, forKey: .parseResults)
        questions = try container.decode([ProgressiveQuestionWithGrade].self, forKey: .questions)
        annotations = try container.decode([QuestionAnnotation].self, forKey: .annotations)
        croppedImages = try container.decode([String: Data].self, forKey: .croppedImages)  // Changed from Int to String
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        hasMarkedProgress = try container.decodeIfPresent(Bool.self, forKey: .hasMarkedProgress) ?? false

        // ✅ Backward compatibility: try new format first, fallback to old format
        if let imageDataArray = try? container.decode([Data].self, forKey: .originalImageDataArray) {
            originalImageDataArray = imageDataArray
        } else if let singleImageData = try? container.decode(Data.self, forKey: .originalImageData) {
            // Old format: single image
            originalImageDataArray = [singleImageData]
        } else {
            throw DecodingError.dataCorruptedError(forKey: .originalImageDataArray, in: container, debugDescription: "Missing image data")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(homeworkHash, forKey: .homeworkHash)
        try container.encode(parseResults, forKey: .parseResults)
        try container.encode(originalImageDataArray, forKey: .originalImageDataArray)
        try container.encode(questions, forKey: .questions)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(croppedImages, forKey: .croppedImages)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(hasMarkedProgress, forKey: .hasMarkedProgress)
    }
}

// MARK: - Global State Manager

@MainActor
class DigitalHomeworkStateManager: ObservableObject {
    static let shared = DigitalHomeworkStateManager()

    // MARK: - Published Properties (Global State)

    /// Current state of Digital Homework
    @Published var currentState: DigitalHomeworkState = .nothing

    /// Current homework data (nil when state is .nothing)
    @Published var currentHomework: DigitalHomeworkData?

    /// Show resume prompt when user returns to Pro Mode with existing homework
    @Published var showResumePrompt: Bool = false

    // MARK: - Background Diagram Analysis State (Phase 1.5)

    /// True while the background diagram analysis is running
    @Published var isBackgroundDiagramAnalysisPending: Bool = false

    /// True if the background analysis completed but found zero crops
    @Published var backgroundDiagramAnalysisFailed: Bool = false

    /// Increments after each completed background analysis run (0 = not run yet)
    @Published var backgroundDiagramAttemptCount: Int = 0

    /// IDs of questions currently being cropped in the background pass
    @Published var questionsUnderBackgroundAnalysis: Set<String> = []

    // MARK: - Private Properties

    private var currentHomeworkHash: String?
    private var autosaveWorkItem: DispatchWorkItem?

    private init() {
        // In-memory only (no UserDefaults persistence)
    }

    // MARK: - Pipeline State

    /// Derives the current pipeline state from in-memory homework data.
    var pipelineState: HomeworkPipelineState {
        guard let hw = currentHomework else { return .parsed }
        let gradedCount = hw.questions.filter { $0.allSubquestionsGraded }.count
        let total = hw.questions.count
        let hasCrops = !hw.croppedImages.isEmpty || !hw.annotations.isEmpty
        if gradedCount == total && total > 0 { return .graded }
        if gradedCount > 0 { return .partiallyGraded }
        if hasCrops { return .cropped }
        return .parsed
    }

    // MARK: - Autosave Helpers

    private func saveNow() {
        guard let hw = currentHomework else { return }
        HomeworkSessionPersistenceService.shared.save(data: hw, state: pipelineState)
    }

    private func scheduleDebouncedSave() {
        autosaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, let hw = self.currentHomework else { return }
            HomeworkSessionPersistenceService.shared.save(data: hw, state: self.pipelineState)
        }
        autosaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    // MARK: - State Management Methods

    /// Generate unique hash for homework based on image content ONLY (no timestamp)
    /// This allows us to detect if the same image is being parsed again vs a new image
    private func generateHomeworkHash(image: UIImage) -> String {
        // Use ONLY image data hash for comparison (no timestamp)
        // This makes hash stable - same image = same hash
        let imageData = image.jpegData(compressionQuality: 0.1)
        let hashString = "\(imageData?.hashValue ?? 0)"
        return hashString
    }

    /// Parse new homework - State transition: Any → Nothing → Parsed
    func parseHomework(parseResults: ParseHomeworkQuestionsResponse, images: [UIImage]) {
        // ✅ Generate hash from first image for consistency
        guard let firstImage = images.first else { return }

        let newHash = generateHomeworkHash(image: firstImage)

        // Check if this is a NEW homework (different image from current)
        if let existingHash = currentHomeworkHash, existingHash != newHash {
            // Reset to .nothing first
            currentState = .nothing
            currentHomework = nil
            currentHomeworkHash = nil
        } else if currentHomeworkHash == newHash {
            // Same homework - ignore redundant parse call
            return
        }

        // Convert all images to data
        let imageDataArray = images.compactMap { $0.jpegData(compressionQuality: 0.8) }
        guard !imageDataArray.isEmpty else { return }

        // Create ungraded questions
        let ungradedQuestions = parseResults.questions.map { question in
            ProgressiveQuestionWithGrade(
                id: question.id,
                question: question.sanitized(),
                grade: nil,
                isGrading: false,
                gradingError: nil
            )
        }

        // Create new homework data
        let homeworkData = DigitalHomeworkData(
            homeworkHash: newHash,
            parseResults: parseResults,
            originalImageDataArray: imageDataArray,  // ✅ UPDATED: Use array
            questions: ungradedQuestions,
            annotations: [],
            croppedImages: [:],
            createdAt: Date(),
            lastModified: Date()
        )

        // Update global state
        currentHomeworkHash = newHash
        currentHomework = homeworkData
        currentState = .parsed

        // Reset background analysis flags for new homework
        isBackgroundDiagramAnalysisPending = false
        backgroundDiagramAnalysisFailed = false
        backgroundDiagramAttemptCount = 0
        questionsUnderBackgroundAnalysis = []

        // Persist new session immediately
        saveNow()
    }

    /// Complete grading - State transition: Parsed → Graded
    func completeGrading(gradedQuestions: [ProgressiveQuestionWithGrade]) {
        guard var homework = currentHomework else {
            return
        }

        homework.questions = gradedQuestions
        homework.lastModified = Date()
        currentHomework = homework
        currentState = .graded

        // Persist graded state immediately
        saveNow()
    }

    /// Update homework data (during grading, annotation, etc.)
    func updateHomework(questions: [ProgressiveQuestionWithGrade]? = nil,
                       annotations: [QuestionAnnotation]? = nil,
                       croppedImages: [String: UIImage]? = nil) {  // Changed from Int to String
        guard var homework = currentHomework else {
            return
        }

        if let questions = questions {
            homework.questions = questions
        }

        if let annotations = annotations {
            homework.annotations = annotations
        }

        if let croppedImages = croppedImages {
            // ✅ FIX: Replace entire croppedImages dictionary (not just update entries)
            // This ensures deleted images are actually removed from the dictionary
            homework.croppedImages.removeAll()

            // Convert UIImages to Data and set all images
            for (questionId, image) in croppedImages {
                homework.setCroppedImage(image, for: questionId)
            }
        }

        homework.lastModified = Date()

        // ✅ FIX: Explicitly notify SwiftUI of changes before updating
        objectWillChange.send()
        currentHomework = homework

        // Debounced save (2s) — covers partial grading, annotation, crop changes
        scheduleDebouncedSave()
    }

    /// Patch handwriting evaluation into the current homework's parseResults.
    /// Called after the concurrent handwriting eval API call completes.
    func patchHandwritingEvaluation(_ evaluation: HandwritingEvaluation?) {
        guard evaluation != nil, var homework = currentHomework else { return }
        homework.parseResults = homework.parseResults.withHandwritingEvaluation(evaluation)
        objectWillChange.send()
        currentHomework = homework
    }

    // MARK: - Background Diagram Analysis (Phase 1.5)

    /// Starts background diagram analysis as soon as `need_image=true` is detected.
    /// Called from HomeworkSummaryView immediately after parseHomework().
    /// Idempotent — exits early if already running or already done.
    func startBackgroundDiagramAnalysis(images: [UIImage]) async {
        guard let homework = currentHomework else { return }
        guard backgroundDiagramAttemptCount == 0, !isBackgroundDiagramAnalysisPending else { return }

        let needImageQuestions = homework.questions.filter {
            $0.question.needImage == true ||
            $0.question.subquestions?.contains { $0.needImage == true } == true
        }
        guard !needImageQuestions.isEmpty else { return }

        // Collect all IDs that need an image
        var allNeedImageIds = Set<String>()
        for qwg in needImageQuestions {
            if qwg.question.needImage == true { allNeedImageIds.insert(qwg.question.id) }
            for sub in qwg.question.subquestions ?? [] where sub.needImage == true {
                allNeedImageIds.insert(sub.id)
            }
        }

        isBackgroundDiagramAnalysisPending = true
        backgroundDiagramAnalysisFailed = false
        questionsUnderBackgroundAnalysis = allNeedImageIds
        debugPrint("🔍 [BGDiagram] Starting for \(needImageQuestions.count) questions: \(allNeedImageIds)")

        // Group by page, then call the shared per-page helper
        var byPage: [Int: [(question: ProgressiveQuestionWithGrade, image: UIImage)]] = [:]
        for qwg in needImageQuestions {
            let pageIndex = (qwg.question.pageNumber ?? 1) - 1
            guard pageIndex < images.count else { continue }
            byPage[pageIndex, default: []].append((qwg, images[pageIndex]))
        }

        typealias PageResult = (crops: [String: UIImage], annotations: [QuestionAnnotation])
        var mergedCrops: [String: UIImage] = [:]
        var mergedAnnotations: [QuestionAnnotation] = homework.annotations

        await withTaskGroup(of: PageResult?.self) { group in
            for (pageIndex, entries) in byPage {
                group.addTask { [weak self] in
                    await self?.backgroundLocateAndCrop(entries: entries, pageIndex: pageIndex)
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

        debugPrint("🔍 [BGDiagram] Complete — crops=\(mergedCrops.count), keys=\(mergedCrops.keys.sorted())")

        if !mergedCrops.isEmpty {
            updateHomework(annotations: mergedAnnotations, croppedImages: mergedCrops)
        }
        isBackgroundDiagramAnalysisPending = false
        backgroundDiagramAttemptCount += 1
        backgroundDiagramAnalysisFailed = mergedCrops.isEmpty
        questionsUnderBackgroundAnalysis = []
    }

    /// Per-page locate+crop helper (background pass). Mirrors DigitalHomeworkViewModel.locateAndCropDiagrams().
    private func backgroundLocateAndCrop(
        entries: [(question: ProgressiveQuestionWithGrade, image: UIImage)],
        pageIndex: Int
    ) async -> (crops: [String: UIImage], annotations: [QuestionAnnotation])? {
        guard let image = entries.first?.image else { return nil }

        let apiImage = image.resizedForUpload(maxDimension: 1024)
        guard let jpegData = apiImage.jpegData(compressionQuality: 0.7) else { return nil }
        let base64Image = jpegData.base64EncodedString()

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

        do {
            let response = try await NetworkService.shared.locateDiagramRegions(
                base64Image: base64Image,
                questions: diagramQuestions
            )
            guard response.success else { return nil }

            var regionMap: [String: ImageRegion] = [:]
            for result in response.regions { regionMap[result.questionId] = result.imageRegion }

            guard let normalizedImage = image.normalizedOrientation() else { return nil }

            var pageCrops: [String: UIImage] = [:]
            var pageAnnotations: [QuestionAnnotation] = []

            for entry in entries {
                let q = entry.question.question
                if let region = regionMap[q.id] {
                    if let cropped = cropRegionFromImage(region, from: normalizedImage) {
                        pageCrops[q.id] = cropped
                        addAnnotationIfAbsent(region: region, questionNumber: q.questionNumber,
                                              pageIndex: pageIndex, into: &pageAnnotations)
                    }
                }
                let parentRegion = regionMap[q.id]
                for sub in q.subquestions ?? [] {
                    let subRegion = regionMap[sub.id] ?? parentRegion
                    if let subRegion, let cropped = cropRegionFromImage(subRegion, from: normalizedImage) {
                        pageCrops[sub.id] = cropped
                        addAnnotationIfAbsent(region: subRegion, questionNumber: sub.id,
                                              pageIndex: pageIndex, into: &pageAnnotations)
                    }
                }
            }
            return (crops: pageCrops, annotations: pageAnnotations)
        } catch {
            debugPrint("🔍 [BGDiagram] Page \(pageIndex) failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func cropRegionFromImage(_ region: ImageRegion, from image: UIImage) -> UIImage? {
        guard let cgImg = image.cgImage else { return nil }
        let w = CGFloat(cgImg.width)
        let h = CGFloat(cgImg.height)
        let rect = CGRect(
            x: CGFloat(region.topLeft[0]) * w,
            y: CGFloat(region.topLeft[1]) * h,
            width: CGFloat(region.bottomRight[0] - region.topLeft[0]) * w,
            height: CGFloat(region.bottomRight[1] - region.topLeft[1]) * h
        )
        guard rect.width > 10, rect.height > 10,
              let cgImage = cgImg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cgImage)
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
            colorIndex: annotations.count,
            pageIndex: pageIndex
        ))
    }

    /// Revert grading - State transition: Graded → Parsed
    func revertGrading() {
        guard var homework = currentHomework else {
            return
        }

        guard currentState == .graded else {
            return
        }

        // Clear all grades but keep homework data
        homework.clearGrades()
        homework.lastModified = Date()
        currentHomework = homework
        currentState = .parsed
    }

    /// Clear all state - State transition: Any → Nothing
    func clearAll() {
        // Delete from persistence before clearing
        if let hash = currentHomeworkHash {
            HomeworkSessionPersistenceService.shared.delete(hash: hash)
        }
        autosaveWorkItem?.cancel()
        currentState = .nothing
        currentHomework = nil
        currentHomeworkHash = nil
        showResumePrompt = false
        isBackgroundDiagramAnalysisPending = false
        backgroundDiagramAnalysisFailed = false
        backgroundDiagramAttemptCount = 0
        questionsUnderBackgroundAnalysis = []
    }

    /// Restore a persisted session. Called by HomeworkSessionPersistenceService.restore().
    func restoreSession(from data: DigitalHomeworkData) {
        currentHomeworkHash = data.homeworkHash
        currentHomework = data
        let gradedCount = data.questions.filter { $0.allSubquestionsGraded }.count
        currentState = (gradedCount == data.questions.count && !data.questions.isEmpty) ? .graded : .parsed

        // Reset background analysis state for restored session
        isBackgroundDiagramAnalysisPending = false
        backgroundDiagramAnalysisFailed = false
        backgroundDiagramAttemptCount = 0
        questionsUnderBackgroundAnalysis = []

        // Ensure this session is in the persistence store (covers album-recovered sessions)
        HomeworkSessionPersistenceService.shared.save(data: data, state: pipelineState)
    }

    /// Check if user should see resume prompt
    func checkResumePrompt() {
        // Show resume prompt if there's existing homework in parsed or graded state
        if currentState != .nothing && currentHomework != nil {
            showResumePrompt = true
            debugPrint("💡 [StateManager] Resume prompt enabled (existing homework found)")
        } else {
            showResumePrompt = false
        }
    }

    /// Resume existing homework (dismiss prompt and continue)
    func resumeHomework() {
        showResumePrompt = false
        debugPrint("▶️ [StateManager] Resuming existing homework (state: \(currentState))")
    }

    /// Start fresh (dismiss prompt and clear state)
    func startFresh() {
        showResumePrompt = false
        clearAll()
        debugPrint("🆕 [StateManager] Starting fresh (state cleared)")
    }
}
