//
//  HomeworkFlowController.swift
//  StudyAI
//
//  Created by Claude Code on 9/14/25.
//  State machine controller for homework scanning flow
//

import Foundation
import SwiftUI
import Combine

@MainActor
class HomeworkFlowController: ObservableObject {
    @Published var state: HomeworkFlowState = .idle
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Services
    private let scanningService: ScanningService
    private let aiClient: AIClient
    private let analytics: Analytics
    private let fileOptimizer: FileOptimizer
    
    // Internal state
    private var cancellables = Set<AnyCancellable>()
    private var currentSubmissionTask: Task<Void, Never>?
    private var selectedImageSource: ImageSource = .camera
    
    init(
        scanningService: ScanningService = DefaultScanningService(),
        aiClient: AIClient = DefaultAIClient(),
        analytics: Analytics = DefaultAnalytics(),
        fileOptimizer: FileOptimizer = DefaultFileOptimizer()
    ) {
        self.scanningService = scanningService
        self.aiClient = aiClient
        self.analytics = analytics
        self.fileOptimizer = fileOptimizer
    }
    
    // MARK: - Public Interface
    
    func handle(_ action: HomeworkFlowAction) {
        print("🔄 HomeworkFlow: \(state) + \(action)")
        
        Task { @MainActor in
            await processAction(action)
        }
    }
    
    func startFlow() {
        handle(.startFlow)
    }
    
    func cancel() {
        currentSubmissionTask?.cancel()
        handle(.cancel)
    }
    
    // MARK: - State Machine Processing
    
    private func processAction(_ action: HomeworkFlowAction) async {
        let oldState = state
        
        switch (state, action) {
        
        // MARK: - Starting Flow
        case (.idle, .startFlow):
            state = .selectingSource
            analytics.track(.sourceSelected(.camera)) // Default tracking
            
        // MARK: - Source Selection
        case (.selectingSource, .selectSource(let source)):
            analytics.track(.sourceSelected(source))
            selectedImageSource = source
            state = .capturingOrPicking
            
        case (.capturingOrPicking, .imageSelected(let image, let source)):
            await handleImageSelected(image, from: source)
            
        case (.capturingOrPicking, .imagePicked(let image)):
            await handleImagePicked(image)
            
        // MARK: - Scanning & Adjusting
        case (.scanningAdjusting(var pages), .pageAdded(let page)):
            pages.append(page)
            state = .scanningAdjusting(pages)
            
        case (.scanningAdjusting(var pages), .pageRemoved(let index)):
            guard index >= 0 && index < pages.count else { break }
            pages.remove(at: index)
            if pages.isEmpty {
                state = .selectingSource
            } else {
                state = .scanningAdjusting(pages)
            }
            
        case (.scanningAdjusting(var pages), .pageReordered(let from, let to)):
            guard from >= 0 && from < pages.count && to >= 0 && to < pages.count else { break }
            let page = pages.remove(at: from)
            pages.insert(page, at: to)
            state = .scanningAdjusting(pages)
            
        case (.scanningAdjusting(let pages), .scanCompleted(let updatedPages)):
            let finalPages = updatedPages.isEmpty ? pages : updatedPages
            state = .readyToSubmit(finalPages)
            
        // MARK: - Ready to Submit
        case (.readyToSubmit(let pages), .submitPages(_)):
            await handleSubmission(pages)
            
        // MARK: - Error Handling
        case (.pickFailed(_), .retryCapture):
            state = .capturingOrPicking
            
        case (.scanFailed(_, let pages), .retryCapture):
            if pages.isEmpty {
                state = .capturingOrPicking
            } else {
                state = .scanningAdjusting(pages)
            }
            
        case (.submitFailed(_, let pages), .retrySubmit):
            await handleSubmission(pages)
            
        // MARK: - Cancel & Reset
        case (_, .cancel), (_, .resetFlow):
            currentSubmissionTask?.cancel()
            state = .idle
            errorMessage = nil
            isLoading = false
            
        default:
            print("⚠️ HomeworkFlow: Unhandled transition from \(oldState) with \(action)")
        }
        
        print("🎯 HomeworkFlow: \(oldState) → \(state)")
    }
    
    // MARK: - Action Handlers
    
    private func handleImageSelected(_ image: UIImage, from source: ImageSource) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let startTime = Date()
            let scannedPage = await scanningService.autoDetectDocument(image)
            let processingTime = Date().timeIntervalSince(startTime)
            
            analytics.track(.scanAutoOK(timeSeconds: processingTime))
            state = .scanningAdjusting([scannedPage])
            
        } catch {
            errorMessage = "Failed to process image: \(error.localizedDescription)"
            state = .pickFailed(error.localizedDescription)
        }
        
        isLoading = false
    }
    
    private func handleImagePicked(_ image: UIImage) async {
        await handleImageSelected(image, from: .photoLibrary)
    }
    
    private func handleSubmission(_ pages: [ScannedPage]) async {
        guard !pages.isEmpty else {
            errorMessage = "No pages to submit"
            return
        }
        
        isLoading = true
        errorMessage = nil
        state = .submitting(pages)
        
        analytics.track(.submitClicked(pageCount: pages.count))
        
        currentSubmissionTask = Task {
            do {
                let startTime = Date()
                
                // Optimize pages for upload
                let optimizedPages = await fileOptimizer.optimizeForUpload(pages, targetSizeKB: 2048)
                
                // Submit to AI
                let result = try await aiClient.submitHomework(optimizedPages)
                
                let processingTime = Date().timeIntervalSince(startTime)
                
                await MainActor.run {
                    switch result {
                    case .success(let homeworkResult):
                        analytics.track(.submitSucceeded(timeSeconds: processingTime))
                        state = .showingResults(homeworkResult)
                        
                    case .failure(let error):
                        analytics.track(.submitFailed(error: error.localizedDescription))
                        errorMessage = error.localizedDescription
                        state = .submitFailed(error.localizedDescription, pages)
                    }
                    
                    isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        analytics.track(.submitFailed(error: error.localizedDescription))
                        errorMessage = error.localizedDescription
                        state = .submitFailed(error.localizedDescription, pages)
                    }
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Convenience State Accessors

extension HomeworkFlowController {
    var isInProgress: Bool {
        switch state {
        case .idle, .showingResults: return false
        default: return true
        }
    }
    
    var canGoBack: Bool {
        switch state {
        case .idle, .selectingSource: return false
        case .capturingOrPicking: return true
        case .scanningAdjusting: return true
        case .readyToSubmit: return true
        case .submitting: return false
        case .showingResults: return false
        case .pickFailed, .scanFailed, .submitFailed: return true
        }
    }
    
    var currentPages: [ScannedPage] {
        switch state {
        case .scanningAdjusting(let pages): return pages
        case .readyToSubmit(let pages): return pages
        case .submitting(let pages): return pages
        case .scanFailed(_, let pages): return pages
        case .submitFailed(_, let pages): return pages
        default: return []
        }
    }
    
    var currentResult: HomeworkResult? {
        if case .showingResults(let result) = state {
            return result
        }
        return nil
    }
    
    var currentImageSource: ImageSource {
        return selectedImageSource
    }
}

// MARK: - Default Implementations

class DefaultAIClient: AIClient {
    func submitHomework(_ pages: [ScannedPage]) async -> Result<HomeworkResult, AIError> {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Mock result
        let questions = [
            QuestionResult(
                questionNumber: 1,
                questionText: "Solve: 2x + 5 = 13",
                correctAnswer: "x = 4",
                studentAnswer: "x = 4",
                isCorrect: true,
                confidence: 0.95,
                feedback: "Correct! Good job solving this linear equation.",
                hints: []
            )
        ]
        
        let result = HomeworkResult(
            overallScore: 0.85,
            questions: questions,
            processingTime: 2.0
        )
        
        return .success(result)
    }
    
    func cancelSubmission() {
        // Placeholder implementation
    }
}

class DefaultAnalytics: Analytics {
    func track(_ event: AnalyticsEvent) {
        print("📊 Analytics: \(event)")
    }
}

class DefaultFileOptimizer: FileOptimizer {
    func optimizeForUpload(_ pages: [ScannedPage], targetSizeKB: Int) async -> [ScannedPage] {
        // Placeholder implementation
        return pages
    }
    
    func createPDF(from pages: [ScannedPage]) async -> Data? {
        // Placeholder implementation
        return nil
    }
}