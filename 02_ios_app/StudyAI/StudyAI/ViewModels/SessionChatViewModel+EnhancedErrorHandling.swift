//
//  SessionChatViewModel+EnhancedErrorHandling.swift
//  StudyAI
//
//  Extension to SessionChatViewModel with automatic retry and enhanced error handling
//

import Foundation
import SwiftUI

extension SessionChatViewModel {
    // MARK: - Enhanced Send Message with Automatic Retry

    /// Send message with automatic retry and exponential backoff
    func sendMessageWithRetry() {
        print("🔄 === SEND MESSAGE WITH RETRY ===")
        print("🔄 Message: \(messageText)")
        print("🔄 Session ID: \(networkService.currentSessionId ?? "nil")")

        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("🔄 ⚠️ Message is empty, returning early")
            return
        }

        let message = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        messageText = ""
        isSubmitting = true
        errorMessage = ""

        // Clear AI suggestions
        aiGeneratedSuggestions = []
        isStreamingComplete = false
        streamingService.resetChunking()

        Task {
            do {
                // Execute with automatic retry
                let result = try await NetworkErrorHandler.shared.executeWithRetry(
                    operation: { [weak self] () async throws -> Bool in
                        guard let self = self else { throw MessageError.unknown(details: "ViewModel deallocated") }

                        // Attempt to send message
                        if let sessionId = self.networkService.currentSessionId {
                            return try await self.attemptSendToSession(sessionId: sessionId, message: message)
                        } else {
                            return try await self.attemptCreateSessionAndSend(message: message)
                        }
                    },
                    onRetry: { [weak self] attempt, error in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }

                            // Show retry notification to user
                            let retryMessage = String(
                                format: NSLocalizedString("chat.retry.attempting", comment: ""),
                                attempt
                            )
                            print("🔄 Retry attempt \(attempt): \(error.errorDescription ?? "Unknown error")")
                            self.errorMessage = retryMessage

                            // Hide after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                if self.errorMessage == retryMessage {
                                    self.errorMessage = ""
                                }
                            }
                        }
                    }
                )

                await MainActor.run {
                    if result {
                        print("✅ Message sent successfully (with or without retry)")
                        isSubmitting = false
                    } else {
                        handleSendFailure(message: message, error: .unknown(details: "Send returned false"))
                    }
                }

            } catch let error as MessageError {
                await MainActor.run {
                    handleSendFailure(message: message, error: error)
                }
            } catch {
                await MainActor.run {
                    handleSendFailure(message: message, error: .unknown(details: error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Attempt Send Operations

    private func attemptSendToSession(sessionId: String, message: String) async throws -> Bool {
        let homeworkContext = appState.pendingHomeworkContext

        // Persist user message
        if let questionImage = homeworkContext?.questionImage {
            let messageId = UUID().uuidString
            if let imageData = questionImage.jpegData(compressionQuality: 0.8) {
                await MainActor.run {
                    imageMessages[messageId] = imageData
                }
                networkService.conversationHistory.append([
                    "role": "user",
                    "content": message,
                    "hasImage": "true",
                    "messageId": messageId
                ])
            }
        } else {
            persistMessage(role: "user", content: message)
        }

        // Show typing indicator
        await MainActor.run {
            showTypingIndicator = true
        }

        // Send message
        let result = await networkService.sendSessionMessage(
            sessionId: sessionId,
            message: message,
            questionContext: homeworkContext?.toDictionary()
        )

        await MainActor.run {
            showTypingIndicator = false
        }

        if result.success, let aiResponse = result.aiResponse {
            // Success - persist AI response
            persistMessage(role: "assistant", content: aiResponse, addToHistory: false)

            // Store suggestions
            if let suggestions = result.suggestions {
                await MainActor.run {
                    aiGeneratedSuggestions = suggestions
                    isStreamingComplete = true
                }
            }

            // Clear homework context
            if homeworkContext != nil {
                await MainActor.run {
                    appState.clearPendingChatMessage()
                }
            }

            return true
        } else {
            // Parse error and throw appropriate MessageError
            if let errorMessage = result.aiResponse {
                throw categorizeErrorFromMessage(errorMessage)
            } else {
                throw MessageError.unknown(details: "No response from server")
            }
        }
    }

    private func attemptCreateSessionAndSend(message: String) async throws -> Bool {
        // Create session first
        let sessionResult = await networkService.startNewSession(subject: selectedSubject.lowercased())

        guard sessionResult.success,
              let sessionId = networkService.currentSessionId else {
            throw MessageError.sessionExpired(canRecover: true)
        }

        // Now send message to new session
        return try await attemptSendToSession(sessionId: sessionId, message: message)
    }

    // MARK: - Error Handling

    private func handleSendFailure(message: String, error: MessageError) {
        isSubmitting = false
        showTypingIndicator = false

        // Remove optimistically added user message
        if let lastMessage = networkService.conversationHistory.last,
           lastMessage["role"] == "user",
           lastMessage["content"] == message {
            networkService.removeLastMessageFromHistory()
        }

        // Add to failed messages queue
        let failedMessage = FailedMessage(
            message: message,
            timestamp: Date(),
            errorReason: error.errorDescription ?? "Unknown error",
            homeworkContext: appState.pendingHomeworkContext
        )
        failedMessages.append(failedMessage)
        showRetryBanner = true

        // Set error message
        errorMessage = error.errorDescription ?? NSLocalizedString("error.message.send", comment: "")

        // Special handling for specific error types
        switch error {
        case .authentication:
            // Trigger re-authentication flow
            NotificationCenter.default.post(name: NSNotification.Name("AuthenticationRequired"), object: nil)

        case .sessionExpired(let canRecover):
            if canRecover {
                Task {
                    let recovered = await NetworkErrorHandler.shared.recoverSession()
                    if recovered {
                        await MainActor.run {
                            errorMessage = NSLocalizedString("chat.session.recovered", comment: "")
                            // Auto-retry the failed message
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                self.retryFailedMessage(failedMessage)
                            }
                        }
                    }
                }
            }

        default:
            break
        }

        print("❌ Message send failed: \(error.errorDescription ?? "Unknown"), added to retry queue (\(failedMessages.count) total)")
    }

    private func categorizeErrorFromMessage(_ errorMessage: String) -> MessageError {
        let lowercased = errorMessage.lowercased()

        if lowercased.contains("session") || lowercased.contains("expired") {
            return .sessionExpired(canRecover: true)
        } else if lowercased.contains("authentication") || lowercased.contains("unauthorized") {
            return .authentication(action: .refreshToken)
        } else if lowercased.contains("network") || lowercased.contains("connection") {
            return .network(retryable: true, details: errorMessage)
        } else if lowercased.contains("rate limit") {
            return .rateLimit(retryAfter: 60)
        } else if lowercased.contains("timeout") {
            return .timeout(attempt: 1)
        } else {
            return .unknown(details: errorMessage)
        }
    }
}
