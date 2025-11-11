//
//  AppError.swift
//  StudyAI
//
//  Created by Claude Code on 11/6/25.
//  Comprehensive error handling system for StudyAI
//

import Foundation

/// Comprehensive error types for the StudyAI application
/// Provides structured error handling with user-friendly messages and recovery suggestions
enum AppError: Error, LocalizedError, Identifiable {

    // MARK: - Network Errors

    case noInternetConnection
    case requestTimeout
    case serverUnavailable
    case rateLimitExceeded
    case invalidResponse

    // MARK: - API Errors

    case apiError(statusCode: Int, message: String)
    case sessionExpired
    case sessionNotFound
    case invalidSessionState
    case messageDeliveryFailed

    // MARK: - Authentication Errors

    case authenticationRequired
    case authenticationFailed
    case tokenExpired
    case insufficientPermissions

    // MARK: - Validation Errors

    case emptyMessage
    case messageTooLong(maxLength: Int)
    case invalidImageFormat
    case imageTooLarge(maxSize: Int)
    case invalidInput(field: String, reason: String)

    // MARK: - Data Errors

    case dataCorrupted
    case saveFailed
    case loadFailed
    case deleteFailed
    case exportFailed

    // MARK: - Service Errors

    case ttsServiceUnavailable
    case speechRecognitionFailed
    case imageProcessingFailed
    case streamingInterrupted

    // MARK: - Configuration Errors

    case missingConfiguration(key: String)
    case invalidConfiguration(key: String, reason: String)

    // MARK: - Unknown Errors

    case unknown(Error)
    case unexpectedState(description: String)

    // MARK: - Identifiable

    var id: String {
        switch self {
        case .noInternetConnection: return "noInternet"
        case .requestTimeout: return "timeout"
        case .serverUnavailable: return "serverUnavailable"
        case .rateLimitExceeded: return "rateLimit"
        case .invalidResponse: return "invalidResponse"
        case .apiError(let code, _): return "apiError_\(code)"
        case .sessionExpired: return "sessionExpired"
        case .sessionNotFound: return "sessionNotFound"
        case .invalidSessionState: return "invalidSessionState"
        case .messageDeliveryFailed: return "messageDeliveryFailed"
        case .authenticationRequired: return "authRequired"
        case .authenticationFailed: return "authFailed"
        case .tokenExpired: return "tokenExpired"
        case .insufficientPermissions: return "insufficientPermissions"
        case .emptyMessage: return "emptyMessage"
        case .messageTooLong: return "messageTooLong"
        case .invalidImageFormat: return "invalidImageFormat"
        case .imageTooLarge: return "imageTooLarge"
        case .invalidInput(let field, _): return "invalidInput_\(field)"
        case .dataCorrupted: return "dataCorrupted"
        case .saveFailed: return "saveFailed"
        case .loadFailed: return "loadFailed"
        case .deleteFailed: return "deleteFailed"
        case .exportFailed: return "exportFailed"
        case .ttsServiceUnavailable: return "ttsUnavailable"
        case .speechRecognitionFailed: return "speechRecognitionFailed"
        case .imageProcessingFailed: return "imageProcessingFailed"
        case .streamingInterrupted: return "streamingInterrupted"
        case .missingConfiguration(let key): return "missingConfig_\(key)"
        case .invalidConfiguration(let key, _): return "invalidConfig_\(key)"
        case .unknown: return "unknown"
        case .unexpectedState: return "unexpectedState"
        }
    }

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        // Network Errors
        case .noInternetConnection:
            return NSLocalizedString("error.noInternet.description",
                                   value: "No internet connection available",
                                   comment: "")
        case .requestTimeout:
            return NSLocalizedString("error.timeout.description",
                                   value: "The request took too long to complete",
                                   comment: "")
        case .serverUnavailable:
            return NSLocalizedString("error.serverUnavailable.description",
                                   value: "The server is currently unavailable",
                                   comment: "")
        case .rateLimitExceeded:
            return NSLocalizedString("error.rateLimit.description",
                                   value: "Too many requests. Please wait a moment",
                                   comment: "")
        case .invalidResponse:
            return NSLocalizedString("error.invalidResponse.description",
                                   value: "Received invalid response from server",
                                   comment: "")

        // API Errors
        case .apiError(let statusCode, let message):
            return String(format: NSLocalizedString("error.api.description",
                                                   value: "Server error (%d): %@",
                                                   comment: ""), statusCode, message)
        case .sessionExpired:
            return NSLocalizedString("error.sessionExpired.description",
                                   value: "Your session has expired",
                                   comment: "")
        case .sessionNotFound:
            return NSLocalizedString("error.sessionNotFound.description",
                                   value: "Session not found",
                                   comment: "")
        case .invalidSessionState:
            return NSLocalizedString("error.invalidSessionState.description",
                                   value: "Session is in an invalid state",
                                   comment: "")
        case .messageDeliveryFailed:
            return NSLocalizedString("error.messageDeliveryFailed.description",
                                   value: "Failed to deliver message",
                                   comment: "")

        // Authentication Errors
        case .authenticationRequired:
            return NSLocalizedString("error.authRequired.description",
                                   value: "Authentication required",
                                   comment: "")
        case .authenticationFailed:
            return NSLocalizedString("error.authFailed.description",
                                   value: "Authentication failed",
                                   comment: "")
        case .tokenExpired:
            return NSLocalizedString("error.tokenExpired.description",
                                   value: "Authentication token expired",
                                   comment: "")
        case .insufficientPermissions:
            return NSLocalizedString("error.insufficientPermissions.description",
                                   value: "You don't have permission to perform this action",
                                   comment: "")

        // Validation Errors
        case .emptyMessage:
            return NSLocalizedString("error.emptyMessage.description",
                                   value: "Message cannot be empty",
                                   comment: "")
        case .messageTooLong(let maxLength):
            return String(format: NSLocalizedString("error.messageTooLong.description",
                                                   value: "Message exceeds maximum length of %d characters",
                                                   comment: ""), maxLength)
        case .invalidImageFormat:
            return NSLocalizedString("error.invalidImageFormat.description",
                                   value: "Invalid image format",
                                   comment: "")
        case .imageTooLarge(let maxSize):
            return String(format: NSLocalizedString("error.imageTooLarge.description",
                                                   value: "Image exceeds maximum size of %d MB",
                                                   comment: ""), maxSize)
        case .invalidInput(let field, let reason):
            return String(format: NSLocalizedString("error.invalidInput.description",
                                                   value: "Invalid %@: %@",
                                                   comment: ""), field, reason)

        // Data Errors
        case .dataCorrupted:
            return NSLocalizedString("error.dataCorrupted.description",
                                   value: "Data is corrupted",
                                   comment: "")
        case .saveFailed:
            return NSLocalizedString("error.saveFailed.description",
                                   value: "Failed to save data",
                                   comment: "")
        case .loadFailed:
            return NSLocalizedString("error.loadFailed.description",
                                   value: "Failed to load data",
                                   comment: "")
        case .deleteFailed:
            return NSLocalizedString("error.deleteFailed.description",
                                   value: "Failed to delete data",
                                   comment: "")
        case .exportFailed:
            return NSLocalizedString("error.exportFailed.description",
                                   value: "Failed to export data",
                                   comment: "")

        // Service Errors
        case .ttsServiceUnavailable:
            return NSLocalizedString("error.ttsUnavailable.description",
                                   value: "Text-to-speech service is unavailable",
                                   comment: "")
        case .speechRecognitionFailed:
            return NSLocalizedString("error.speechRecognitionFailed.description",
                                   value: "Speech recognition failed",
                                   comment: "")
        case .imageProcessingFailed:
            return NSLocalizedString("error.imageProcessingFailed.description",
                                   value: "Failed to process image",
                                   comment: "")
        case .streamingInterrupted:
            return NSLocalizedString("error.streamingInterrupted.description",
                                   value: "Streaming was interrupted",
                                   comment: "")

        // Configuration Errors
        case .missingConfiguration(let key):
            return String(format: NSLocalizedString("error.missingConfiguration.description",
                                                   value: "Missing configuration: %@",
                                                   comment: ""), key)
        case .invalidConfiguration(let key, let reason):
            return String(format: NSLocalizedString("error.invalidConfiguration.description",
                                                   value: "Invalid configuration '%@': %@",
                                                   comment: ""), key, reason)

        // Unknown Errors
        case .unknown(let error):
            return error.localizedDescription
        case .unexpectedState(let description):
            return String(format: NSLocalizedString("error.unexpectedState.description",
                                                   value: "Unexpected state: %@",
                                                   comment: ""), description)
        }
    }

    var recoverySuggestion: String? {
        switch self {
        // Network Errors
        case .noInternetConnection:
            return NSLocalizedString("error.noInternet.recovery",
                                   value: "Check your internet connection and try again",
                                   comment: "")
        case .requestTimeout:
            return NSLocalizedString("error.timeout.recovery",
                                   value: "Check your connection and try again",
                                   comment: "")
        case .serverUnavailable:
            return NSLocalizedString("error.serverUnavailable.recovery",
                                   value: "Please try again in a few moments",
                                   comment: "")
        case .rateLimitExceeded:
            return NSLocalizedString("error.rateLimit.recovery",
                                   value: "Please wait a minute before trying again",
                                   comment: "")
        case .invalidResponse:
            return NSLocalizedString("error.invalidResponse.recovery",
                                   value: "Please try again or contact support",
                                   comment: "")

        // API Errors
        case .apiError:
            return NSLocalizedString("error.api.recovery",
                                   value: "Please try again. If the problem persists, contact support",
                                   comment: "")
        case .sessionExpired, .sessionNotFound, .invalidSessionState:
            return NSLocalizedString("error.session.recovery",
                                   value: "A new session will be created automatically",
                                   comment: "")
        case .messageDeliveryFailed:
            return NSLocalizedString("error.messageDeliveryFailed.recovery",
                                   value: "Tap to retry sending the message",
                                   comment: "")

        // Authentication Errors
        case .authenticationRequired, .authenticationFailed, .tokenExpired:
            return NSLocalizedString("error.auth.recovery",
                                   value: "Please sign in again",
                                   comment: "")
        case .insufficientPermissions:
            return NSLocalizedString("error.insufficientPermissions.recovery",
                                   value: "Contact your administrator for access",
                                   comment: "")

        // Validation Errors
        case .emptyMessage:
            return NSLocalizedString("error.emptyMessage.recovery",
                                   value: "Type a message before sending",
                                   comment: "")
        case .messageTooLong:
            return NSLocalizedString("error.messageTooLong.recovery",
                                   value: "Shorten your message and try again",
                                   comment: "")
        case .invalidImageFormat:
            return NSLocalizedString("error.invalidImageFormat.recovery",
                                   value: "Use a JPEG or PNG image",
                                   comment: "")
        case .imageTooLarge:
            return NSLocalizedString("error.imageTooLarge.recovery",
                                   value: "Choose a smaller image",
                                   comment: "")
        case .invalidInput:
            return NSLocalizedString("error.invalidInput.recovery",
                                   value: "Check your input and try again",
                                   comment: "")

        // Data Errors
        case .dataCorrupted:
            return NSLocalizedString("error.dataCorrupted.recovery",
                                   value: "Try restarting the app",
                                   comment: "")
        case .saveFailed, .loadFailed, .deleteFailed, .exportFailed:
            return NSLocalizedString("error.data.recovery",
                                   value: "Check available storage and try again",
                                   comment: "")

        // Service Errors
        case .ttsServiceUnavailable:
            return NSLocalizedString("error.ttsUnavailable.recovery",
                                   value: "Voice features will be disabled temporarily",
                                   comment: "")
        case .speechRecognitionFailed:
            return NSLocalizedString("error.speechRecognitionFailed.recovery",
                                   value: "Try speaking again or use text input",
                                   comment: "")
        case .imageProcessingFailed:
            return NSLocalizedString("error.imageProcessingFailed.recovery",
                                   value: "Try a different image or describe it in text",
                                   comment: "")
        case .streamingInterrupted:
            return NSLocalizedString("error.streamingInterrupted.recovery",
                                   value: "The message will be resent automatically",
                                   comment: "")

        // Configuration Errors
        case .missingConfiguration, .invalidConfiguration:
            return NSLocalizedString("error.configuration.recovery",
                                   value: "Please reinstall the app or contact support",
                                   comment: "")

        // Unknown Errors
        case .unknown, .unexpectedState:
            return NSLocalizedString("error.unknown.recovery",
                                   value: "Try restarting the app. If the problem persists, contact support",
                                   comment: "")
        }
    }

    // MARK: - Error Severity

    var severity: ErrorSeverity {
        switch self {
        case .noInternetConnection, .requestTimeout, .rateLimitExceeded:
            return .warning
        case .emptyMessage, .messageTooLong, .invalidImageFormat, .imageTooLarge, .invalidInput:
            return .info
        case .sessionExpired, .sessionNotFound, .invalidSessionState:
            return .warning
        case .ttsServiceUnavailable, .speechRecognitionFailed:
            return .warning
        case .serverUnavailable, .invalidResponse, .apiError, .messageDeliveryFailed:
            return .error
        case .authenticationRequired, .authenticationFailed, .tokenExpired, .insufficientPermissions:
            return .error
        case .dataCorrupted, .saveFailed, .loadFailed, .deleteFailed, .exportFailed:
            return .error
        case .imageProcessingFailed, .streamingInterrupted:
            return .error
        case .missingConfiguration, .invalidConfiguration:
            return .critical
        case .unknown, .unexpectedState:
            return .error
        }
    }

    // MARK: - Is Retryable

    var isRetryable: Bool {
        switch self {
        case .noInternetConnection, .requestTimeout, .serverUnavailable, .rateLimitExceeded:
            return true
        case .invalidResponse, .apiError, .messageDeliveryFailed:
            return true
        case .sessionExpired, .sessionNotFound, .invalidSessionState:
            return true
        case .imageProcessingFailed, .streamingInterrupted:
            return true
        case .emptyMessage, .messageTooLong, .invalidImageFormat, .imageTooLarge, .invalidInput:
            return false
        case .authenticationRequired, .authenticationFailed, .tokenExpired, .insufficientPermissions:
            return false
        case .dataCorrupted, .saveFailed, .loadFailed, .deleteFailed, .exportFailed:
            return true
        case .ttsServiceUnavailable, .speechRecognitionFailed:
            return true
        case .missingConfiguration, .invalidConfiguration:
            return false
        case .unknown, .unexpectedState:
            return false
        }
    }
}

// MARK: - Error Severity

enum ErrorSeverity {
    case info      // Informational, user can continue
    case warning   // Something went wrong but app can recover
    case error     // Significant error, may need user action
    case critical  // Critical error, app may not function correctly

    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    var color: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        case .critical: return "red"
        }
    }
}

// MARK: - Error Logger

class ErrorLogger {
    static let shared = ErrorLogger()

    private init() {}

    func log(_ error: AppError, context: String? = nil) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let contextInfo = context.map { " [Context: \($0)]" } ?? ""

        print("❌ [\(timestamp)] [\(error.severity)] \(error.errorDescription ?? "Unknown error")\(contextInfo)")

        if let recovery = error.recoverySuggestion {
            print("   💡 Recovery: \(recovery)")
        }

        // In production, send to analytics/crash reporting
        // Analytics.logError(error, context: context)
    }
}
