//
//  ErrorBoundary.swift
//  StudyAI
//
//  Error handling and boundary wrapper for views
//

import SwiftUI

/// User-friendly error types with actionable messages
enum UserFacingError: LocalizedError {
    case networkOffline
    case serverError(message: String)
    case rateLimitExceeded(resetTime: Date?)
    case invalidImage
    case aiProcessingFailed
    case authenticationFailed
    case unknown(error: Error)

    var errorDescription: String? {
        switch self {
        case .networkOffline:
            return NSLocalizedString("error.offline", value: "No internet connection", comment: "")
        case .serverError(let message):
            return message
        case .rateLimitExceeded(let resetTime):
            if let resetTime = resetTime {
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute]
                formatter.unitsStyle = .abbreviated
                if let timeRemaining = formatter.string(from: Date(), to: resetTime) {
                    return NSLocalizedString("error.rateLimit", value: "Too many requests. Try again in \(timeRemaining)", comment: "")
                }
            }
            return NSLocalizedString("error.rateLimitGeneric", value: "Too many requests. Please try again later", comment: "")
        case .invalidImage:
            return NSLocalizedString("error.invalidImage", value: "Image format not supported or corrupted", comment: "")
        case .aiProcessingFailed:
            return NSLocalizedString("error.aiProcessing", value: "AI analysis failed. Please try again", comment: "")
        case .authenticationFailed:
            return NSLocalizedString("error.auth", value: "Authentication failed. Please sign in again", comment: "")
        case .unknown(let error):
            return error.localizedDescription
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkOffline:
            return "Check your internet connection and try again"
        case .serverError:
            return "Our servers are experiencing issues. Please try again shortly"
        case .rateLimitExceeded:
            return "You've reached your usage limit. Wait a bit or upgrade to premium"
        case .invalidImage:
            return "Try taking a clearer photo with good lighting"
        case .aiProcessingFailed:
            return "Make sure the image contains clear text or equations"
        case .authenticationFailed:
            return "Sign out and sign in again with your account"
        case .unknown:
            return "If this persists, contact support"
        }
    }

    var icon: String {
        switch self {
        case .networkOffline:
            return "wifi.slash"
        case .serverError, .unknown:
            return "exclamationmark.triangle.fill"
        case .rateLimitExceeded:
            return "clock.fill"
        case .invalidImage:
            return "photo.fill.on.rectangle.fill"
        case .aiProcessingFailed:
            return "brain.head.profile"
        case .authenticationFailed:
            return "person.fill.xmark"
        }
    }

    var color: Color {
        switch self {
        case .networkOffline:
            return .orange
        case .serverError, .aiProcessingFailed, .authenticationFailed, .unknown:
            return .red
        case .rateLimitExceeded:
            return .yellow
        case .invalidImage:
            return .blue
        }
    }
}

/// Error boundary wrapper for SwiftUI views
struct ErrorBoundary<Content: View>: View {
    @State private var error: UserFacingError?
    @State private var showingError = false
    let content: Content
    let onRetry: (() -> Void)?

    init(@ViewBuilder content: () -> Content, onRetry: (() -> Void)? = nil) {
        self.content = content()
        self.onRetry = onRetry
    }

    var body: some View {
        content
            .alert(isPresented: $showingError) {
                Alert(
                    title: Text(error?.errorDescription ?? "Error"),
                    message: Text(error?.recoverySuggestion ?? ""),
                    primaryButton: .default(Text("Retry")) {
                        onRetry?()
                        error = nil
                    },
                    secondaryButton: .cancel {
                        error = nil
                    }
                )
            }
    }

    /// Call this to show an error
    func showError(_ error: Error) {
        if let userError = error as? UserFacingError {
            self.error = userError
        } else {
            self.error = .unknown(error: error)
        }
        showingError = true
    }
}

/// Error banner for inline error display
struct ErrorBanner: View {
    let error: UserFacingError
    let onDismiss: () -> Void
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: error.icon)
                    .font(.title2)
                    .foregroundColor(error.color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(error.errorDescription ?? "Error occurred")
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let suggestion = error.recoverySuggestion {
                        Text(suggestion)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            if let retry = onRetry {
                Button(action: retry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(error.color)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(error.color.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(error.color.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - NetworkError Extension

extension URLError {
    var userFacingError: UserFacingError {
        switch self.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkOffline
        case .timedOut:
            return .serverError(message: "Request timed out")
        case .cannotFindHost, .cannotConnectToHost:
            return .serverError(message: "Cannot reach server")
        default:
            return .unknown(error: self)
        }
    }
}

// MARK: - HTTP Status Code Helper

extension Int {
    var isRateLimited: Bool {
        return self == 429
    }

    var isServerError: Bool {
        return self >= 500
    }

    var isClientError: Bool {
        return self >= 400 && self < 500
    }
}

// MARK: - Usage Examples
/*
 // Wrap a view with error boundary
 ErrorBoundary {
     HomeworkProcessingView()
 } onRetry: {
     // Retry logic
 }

 // Show error banner inline
 if let error = viewModel.error {
     ErrorBanner(error: error, onDismiss: {
         viewModel.clearError()
     }, onRetry: {
         viewModel.retryLastAction()
     })
     .padding()
 }

 // Convert network errors
 catch let error as URLError {
     self.error = error.userFacingError
 }
 */
