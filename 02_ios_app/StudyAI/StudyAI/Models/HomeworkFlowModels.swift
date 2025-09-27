//
//  HomeworkFlowModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/14/25.
//  Core models and state machine for homework scanning flow
//

import Foundation
import UIKit

// MARK: - State Machine

enum HomeworkFlowState: Equatable {
    case idle
    case selectingSource
    case capturingOrPicking
    case scanningAdjusting([ScannedPage])
    case readyToSubmit([ScannedPage])
    case submitting([ScannedPage])
    case showingResults(HomeworkResult)
    
    // Error sub-states with retry paths
    case pickFailed(String)
    case scanFailed(String, [ScannedPage])
    case submitFailed(String, [ScannedPage])
}

enum HomeworkFlowAction {
    case startFlow
    case selectSource(ImageSource)
    case imageSelected(UIImage, ImageSource)
    case imagePicked(UIImage)
    case scanCompleted([ScannedPage])
    case pageAdded(ScannedPage)
    case pageRemoved(Int)
    case pageReordered(from: Int, to: Int)
    case retryCapture
    case retrySubmit
    case submitPages([ScannedPage])
    case submissionCompleted(HomeworkResult)
    case submissionFailed(String)
    case resetFlow
    case cancel
}

// MARK: - Core Models

enum ImageSource: String, CaseIterable {
    case camera = "Camera"
    case photoLibrary = "Photo Library" 
    case files = "Files"
    
    var systemImage: String {
        switch self {
        case .camera: return "camera.fill"
        case .photoLibrary: return "photo.on.rectangle"
        case .files: return "doc.fill"
        }
    }
}

struct ScannedPage: Identifiable, Equatable {
    var id: UUID
    let originalImage: UIImage
    var processedImage: UIImage
    var cropRect: CGRect?
    var rotation: Double = 0
    var enhanceParams: EnhanceParams
    var filename: String
    var fileSize: Int

    init(id: UUID = UUID(), originalImage: UIImage, processedImage: UIImage? = nil, filename: String = "Document") {
        self.id = id
        self.originalImage = originalImage
        self.processedImage = processedImage ?? originalImage
        self.enhanceParams = EnhanceParams()
        self.filename = filename
        self.fileSize = originalImage.jpegData(compressionQuality: 0.8)?.count ?? 0
    }
}

struct EnhanceParams: Equatable {
    var brightness: Float = 0.0
    var contrast: Float = 1.0
    var saturation: Float = 1.0
    var perspectiveCorrected: Bool = false
    var autoEnhanced: Bool = false
}

struct HomeworkResult: Equatable {
    var id: UUID
    let overallScore: Float
    let questions: [QuestionResult]
    let processingTime: TimeInterval
    let submittedAt: Date
    let suggestedActions: [String]

    init(id: UUID = UUID(), overallScore: Float, questions: [QuestionResult], processingTime: TimeInterval) {
        self.id = id
        self.overallScore = overallScore
        self.questions = questions
        self.processingTime = processingTime
        self.submittedAt = Date()
        self.suggestedActions = generateSuggestedActions(score: overallScore)
    }
    
    private func generateSuggestedActions(score: Float) -> [String] {
        var actions: [String] = []
        
        if score < 0.5 {
            actions.append("Ask for a hint")
            actions.append("Review basic concepts")
        } else if score < 0.8 {
            actions.append("Generate similar practice")
            actions.append("Focus on weak areas")
        } else {
            actions.append("Try advanced problems")
            actions.append("Explore related topics")
        }
        
        actions.append("Rescan if quality was poor")
        return actions
    }
}

struct QuestionResult: Identifiable, Equatable {
    var id: UUID
    let questionNumber: Int
    let questionText: String
    let correctAnswer: String?
    let studentAnswer: String?
    let isCorrect: Bool
    let confidence: Float
    let feedback: String
    let hints: [String]

    init(id: UUID = UUID(), questionNumber: Int, questionText: String, correctAnswer: String?, studentAnswer: String?, isCorrect: Bool, confidence: Float, feedback: String, hints: [String]) {
        self.id = id
        self.questionNumber = questionNumber
        self.questionText = questionText
        self.correctAnswer = correctAnswer
        self.studentAnswer = studentAnswer
        self.isCorrect = isCorrect
        self.confidence = confidence
        self.feedback = feedback
        self.hints = hints
    }
}

// MARK: - Service Protocols

protocol ScanningService {
    func autoDetectDocument(_ image: UIImage) async -> ScannedPage
    func enhanceDocument(_ page: ScannedPage) async -> ScannedPage
    func applyPerspectiveCorrection(_ page: ScannedPage, rect: CGRect) async -> ScannedPage
    func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage
    func rotateImage(_ image: UIImage, by degrees: Double) -> UIImage
}

protocol AIClient {
    func submitHomework(_ pages: [ScannedPage]) async -> Result<HomeworkResult, AIError>
    func cancelSubmission()
}

protocol Analytics {
    func track(_ event: AnalyticsEvent)
}

protocol FileOptimizer {
    func optimizeForUpload(_ pages: [ScannedPage], targetSizeKB: Int) async -> [ScannedPage]
    func createPDF(from pages: [ScannedPage]) async -> Data?
}

// MARK: - Analytics Events

enum AnalyticsEvent {
    case sourceSelected(ImageSource)
    case scanAutoOK(timeSeconds: Double)
    case scanManualAdjust
    case submitClicked(pageCount: Int)
    case submitSucceeded(timeSeconds: Double)
    case submitFailed(error: String)
    case resultsViewed(score: Float)
}

// MARK: - Errors

enum AIError: Error, LocalizedError {
    case networkError(String)
    case processingError(String)
    case invalidImage(String)
    case serverError(Int, String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .processingError(let message):
            return "Processing error: \(message)"
        case .invalidImage(let message):
            return "Invalid image: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
    }
}

// MARK: - File Size Utilities

extension ScannedPage {
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(fileSize))
    }
    
    mutating func updateFileSize() {
        self.fileSize = processedImage.jpegData(compressionQuality: 0.8)?.count ?? 0
    }
}