//
//  NetworkErrorHandler.swift
//  StudyAI
//
//  Enhanced error handling with automatic retry and exponential backoff
//

import Foundation

// MARK: - Message Error Types

enum MessageError: Error, LocalizedError {
    case network(retryable: Bool, details: String)
    case rateLimit(retryAfter: TimeInterval)
    case sessionExpired(canRecover: Bool)
    case authentication(action: AuthAction)
    case serverError(code: Int, retryable: Bool, message: String)
    case invalidResponse(details: String)
    case timeout(attempt: Int)
    case unknown(details: String)

    var errorDescription: String? {
        switch self {
        case .network(_, let details):
            return NSLocalizedString("error.network", comment: "") + ": \(details)"
        case .rateLimit(let retryAfter):
            return String(format: NSLocalizedString("error.rateLimit", comment: ""), Int(retryAfter))
        case .sessionExpired:
            return NSLocalizedString("error.sessionExpired", comment: "")
        case .authentication:
            return NSLocalizedString("error.authentication", comment: "")
        case .serverError(let code, _, let message):
            return String(format: NSLocalizedString("error.server", comment: ""), code, message)
        case .invalidResponse(let details):
            return NSLocalizedString("error.invalidResponse", comment: "") + ": \(details)"
        case .timeout(let attempt):
            return String(format: NSLocalizedString("error.timeout", comment: ""), attempt)
        case .unknown(let details):
            return NSLocalizedString("error.unknown", comment: "") + ": \(details)"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network(let retryable, _),
             .serverError(_, let retryable, _):
            return retryable
        case .rateLimit, .timeout:
            return true
        case .sessionExpired(let canRecover):
            return canRecover
        case .authentication, .invalidResponse, .unknown:
            return false
        }
    }

    var retryDelay: TimeInterval {
        switch self {
        case .rateLimit(let retryAfter):
            return retryAfter
        case .network:
            return 0 // Will use exponential backoff
        case .serverError:
            return 0 // Will use exponential backoff
        case .timeout:
            return 0 // Will use exponential backoff
        default:
            return 0
        }
    }
}

enum AuthAction {
    case relogin
    case refreshToken
    case clearSession
}

// MARK: - Network Error Handler

@MainActor
class NetworkErrorHandler {
    static let shared = NetworkErrorHandler()

    private let maxRetries = 3
    private let baseBackoffDelay: TimeInterval = 1.0 // 1 second
    private let maxBackoffDelay: TimeInterval = 16.0 // 16 seconds

    private init() {}

    // MARK: - Retry Logic with Exponential Backoff

    func executeWithRetry<T>(
        operation: @escaping () async throws -> T,
        onRetry: ((Int, MessageError) -> Void)? = nil
    ) async throws -> T {
        var lastError: MessageError?
        var attempt = 0

        while attempt < maxRetries {
            do {
                let result = try await operation()
                return result
            } catch let error as MessageError {
                lastError = error
                attempt += 1

                // Don't retry if error is not retryable
                guard error.isRetryable && attempt < maxRetries else {
                    throw error
                }

                // Calculate backoff delay
                let backoffDelay = calculateBackoffDelay(
                    attempt: attempt,
                    baseDelay: error.retryDelay > 0 ? error.retryDelay : baseBackoffDelay
                )

                // Notify about retry
                onRetry?(attempt, error)

                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))

            } catch {
                // Convert unknown errors to MessageError
                lastError = .unknown(details: error.localizedDescription)
                throw lastError!
            }
        }

        // All retries exhausted
        throw lastError ?? .unknown(details: "Max retries exceeded")
    }

    // MARK: - Session Recovery

    func recoverSession() async -> Bool {
        // Attempt to create a new session
        let networkService = NetworkService.shared
        let result = await networkService.startNewSession(subject: "general")
        return result.success
    }

    // MARK: - Error Categorization

    func categorizeError(from httpStatusCode: Int, responseData: Data?) -> MessageError {
        switch httpStatusCode {
        case 400:
            return .invalidResponse(details: "Bad request")
        case 401:
            return .authentication(action: .refreshToken)
        case 403:
            return .authentication(action: .relogin)
        case 404:
            return .sessionExpired(canRecover: true)
        case 408:
            return .timeout(attempt: 1)
        case 429:
            // Try to parse retry-after header
            let retryAfter: TimeInterval = 60 // Default to 60 seconds
            return .rateLimit(retryAfter: retryAfter)
        case 500...599:
            let isRetryable = httpStatusCode != 501 && httpStatusCode != 505
            return .serverError(
                code: httpStatusCode,
                retryable: isRetryable,
                message: "Server error occurred"
            )
        default:
            return .unknown(details: "HTTP \(httpStatusCode)")
        }
    }

    func categorizeError(from error: Error) -> MessageError {
        let nsError = error as NSError

        // Network connectivity errors
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet,
                 NSURLErrorNetworkConnectionLost:
                return .network(retryable: true, details: "No internet connection")

            case NSURLErrorTimedOut:
                return .timeout(attempt: 1)

            case NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost:
                return .network(retryable: true, details: "Cannot reach server")

            case NSURLErrorBadServerResponse:
                return .invalidResponse(details: "Bad server response")

            default:
                return .network(retryable: false, details: error.localizedDescription)
            }
        }

        return .unknown(details: error.localizedDescription)
    }

    // MARK: - Private Helpers

    private func calculateBackoffDelay(attempt: Int, baseDelay: TimeInterval) -> TimeInterval {
        // Exponential backoff: delay = baseDelay * (2 ^ (attempt - 1))
        // With jitter to avoid thundering herd
        let exponentialDelay = baseDelay * pow(2.0, Double(attempt - 1))
        let cappedDelay = min(exponentialDelay, maxBackoffDelay)

        // Add jitter (±25%)
        let jitterRange = cappedDelay * 0.25
        let jitter = Double.random(in: -jitterRange...jitterRange)

        return max(0, cappedDelay + jitter)
    }
}
