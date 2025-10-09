//
//  MessageActionsView.swift
//  StudyAI
//
//  Created by Claude Code on 10/7/25.
//  Message action menu and handlers
//

import SwiftUI
import Combine

// MARK: - Message Actions Menu

struct MessageActionsMenu: View {
    let message: [String: String]
    let messageIndex: Int
    let isUserMessage: Bool
    let onCopy: () -> Void
    let onRegenerate: (() -> Void)?
    let onEdit: (() -> Void)?
    let onShare: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        Menu {
            // Copy
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }

            // Share
            Button(action: onShare) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            // Regenerate (AI messages only)
            if !isUserMessage, let regenerate = onRegenerate {
                Button(action: regenerate) {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }

            // Edit (User messages only)
            if isUserMessage, let edit = onEdit {
                Button(action: edit) {
                    Label("Edit", systemImage: "pencil")
                }
            }

            Divider()

            // Delete
            Button(role: .destructive, action: {
                showingDeleteConfirmation = true
            }) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Message Feedback Buttons

struct MessageFeedbackButtons: View {
    let messageIndex: Int
    @Binding var feedbackState: MessageFeedback?

    enum MessageFeedback: String {
        case thumbsUp = "👍"
        case thumbsDown = "👎"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbs Up
            Button(action: {
                if feedbackState == .thumbsUp {
                    feedbackState = nil
                } else {
                    feedbackState = .thumbsUp
                    // TODO: Send feedback to backend
                    print("👍 Positive feedback for message \(messageIndex)")
                }
            }) {
                Image(systemName: feedbackState == .thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.caption)
                    .foregroundColor(feedbackState == .thumbsUp ? .green : .secondary)
            }

            // Thumbs Down
            Button(action: {
                if feedbackState == .thumbsDown {
                    feedbackState = nil
                } else {
                    feedbackState = .thumbsDown
                    // TODO: Send feedback to backend
                    print("👎 Negative feedback for message \(messageIndex)")
                }
            }) {
                Image(systemName: feedbackState == .thumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.caption)
                    .foregroundColor(feedbackState == .thumbsDown ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Message Actions Handler
// Note: ShareSheet is defined in PDFPreviewView.swift

@MainActor
class MessageActionsHandler: ObservableObject {
    @Published var showingShareSheet = false
    @Published var shareText = ""
    @Published var showingEditSheet = false
    @Published var editText = ""
    @Published var editingMessageIndex: Int?

    // Message feedback tracking
    @Published var messageFeedback: [Int: MessageFeedbackButtons.MessageFeedback] = [:]

    // MARK: - Copy Message

    func copyMessage(content: String) {
        UIPasteboard.general.string = content
        print("📋 Copied message to clipboard")

        // Show haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - Share Message

    func shareMessage(content: String) {
        shareText = content
        showingShareSheet = true
        print("📤 Sharing message")
    }

    // MARK: - Edit Message

    func editMessage(content: String, at index: Int) {
        editText = content
        editingMessageIndex = index
        showingEditSheet = true
        print("✏️ Editing message at index \(index)")
    }

    // MARK: - Regenerate Response

    func regenerateResponse(
        at index: Int,
        networkService: NetworkService,
        onComplete: @escaping () -> Void
    ) {
        print("🔄 Regenerating response at index \(index)")

        // Find the user message that triggered this AI response
        guard index > 0 else {
            print("❌ Cannot regenerate first message")
            return
        }

        let previousMessage = networkService.conversationHistory[index - 1]
        guard previousMessage["role"] == "user",
              let userMessage = previousMessage["content"] else {
            print("❌ Previous message is not a user message")
            return
        }

        // Remove the AI response we want to regenerate
        networkService.conversationHistory.remove(at: index)

        // TODO: Implement regenerate with proper API
        // The NetworkService API needs to be updated to support regeneration
        print("⚠️ TODO: Regenerate message: \(userMessage)")
        onComplete()

        // Future implementation:
        // Task {
        //     await networkService.sendSessionMessage(
        //         sessionId: currentSessionId,
        //         message: userMessage
        //     )
        //     onComplete()
        // }
    }

    // MARK: - Delete Message

    func deleteMessage(
        at index: Int,
        networkService: NetworkService,
        messageManager: ChatMessageManager
    ) {
        print("🗑️ Deleting message at index \(index)")

        // Delete from conversation history
        guard index < networkService.conversationHistory.count else {
            print("❌ Invalid message index")
            return
        }

        networkService.conversationHistory.remove(at: index)

        // TODO: Delete from persistent storage
        // If we have message ID, delete from SwiftData as well
    }

    // MARK: - Toggle Feedback

    func toggleFeedback(for messageIndex: Int, feedback: MessageFeedbackButtons.MessageFeedback) {
        if messageFeedback[messageIndex] == feedback {
            messageFeedback[messageIndex] = nil
        } else {
            messageFeedback[messageIndex] = feedback
        }

        // TODO: Send feedback to backend analytics
        print("📊 Feedback for message \(messageIndex): \(messageFeedback[messageIndex]?.rawValue ?? "none")")
    }
}