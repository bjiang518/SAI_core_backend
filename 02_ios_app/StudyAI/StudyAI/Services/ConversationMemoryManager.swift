//
//  ConversationMemoryManager.swift
//  StudyAI
//
//  Created by Claude Code on 11/6/25.
//  Phase 3.3: Advanced conversation memory management
//

import Foundation
import Combine

/// Advanced memory manager for conversation history
/// **Phase 3.3**: Implements windowing, compression, and smart memory limits
@MainActor
class ConversationMemoryManager: ObservableObject {

    // MARK: - Singleton

    static let shared = ConversationMemoryManager()

    // MARK: - Configuration

    /// Maximum messages to keep in active memory (recent window)
    private let activeWindowSize: Int = 30

    /// Maximum messages to keep in compressed storage (archive)
    private let archiveWindowSize: Int = 70

    /// Threshold for compressing old messages (character count)
    private let compressionThreshold: Int = 500

    /// Maximum total memory for conversation history (bytes)
    private let maxTotalMemoryBytes: Int = 5_000_000 // ~5MB

    // MARK: - Storage

    /// Active conversation window (recent messages, full content)
    private var activeMessages: [ConversationMessage] = []

    /// Archived messages (compressed summaries)
    private var archivedMessages: [CompressedMessage] = []

    /// Session metadata
    private var sessionId: String?

    // MARK: - Published Properties

    /// Total message count (active + archived)
    @Published var totalMessageCount: Int = 0

    /// Current memory usage estimate (KB)
    @Published var estimatedMemoryKB: Int = 0

    // MARK: - Models

    /// Full conversation message
    struct ConversationMessage {
        let role: String
        let content: String
        let timestamp: Date
        var messageId: String?

        var estimatedMemoryBytes: Int {
            return content.utf8.count + role.utf8.count + 64 // +64 for metadata
        }
    }

    /// Compressed message for archive
    struct CompressedMessage {
        let role: String
        let summary: String // Truncated/summarized content
        let timestamp: Date
        let originalLength: Int

        var estimatedMemoryBytes: Int {
            return summary.utf8.count + role.utf8.count + 32
        }
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Add new message to conversation history
    /// Automatically manages memory by archiving old messages
    ///
    /// - Parameters:
    ///   - role: Message role (user/assistant)
    ///   - content: Message content
    ///   - sessionId: Current session ID
    func addMessage(role: String, content: String, sessionId: String) {
        let message = ConversationMessage(
            role: role,
            content: content,
            timestamp: Date()
        )

        // Check if session changed (clear if different)
        if self.sessionId != sessionId {
            clearHistory()
            self.sessionId = sessionId
        }

        activeMessages.append(message)
        totalMessageCount += 1

        // Phase 3.3: Smart memory management
        manageMemory()
        updateMemoryStats()
    }

    /// Get recent messages for API context (most relevant for current conversation)
    ///
    /// - Parameter count: Number of recent messages to retrieve
    /// - Returns: Array of messages in dictionary format
    func getRecentMessages(count: Int = 30) -> [[String: String]] {
        let recentCount = min(count, activeMessages.count)
        let startIndex = max(0, activeMessages.count - recentCount)

        return activeMessages[startIndex...].map { msg in
            var dict: [String: String] = [
                "role": msg.role,
                "content": msg.content
            ]
            if let messageId = msg.messageId {
                dict["messageId"] = messageId
            }
            return dict
        }
    }

    /// Get all active messages (for UI display)
    func getAllActiveMessages() -> [[String: String]] {
        return activeMessages.map { msg in
            var dict: [String: String] = [
                "role": msg.role,
                "content": msg.content
            ]
            if let messageId = msg.messageId {
                dict["messageId"] = messageId
            }
            return dict
        }
    }

    /// Clear conversation history
    func clearHistory() {
        activeMessages.removeAll()
        archivedMessages.removeAll()
        sessionId = nil
        totalMessageCount = 0
        updateMemoryStats()
    }

    /// Remove last message (for error handling)
    func removeLastMessage() {
        guard !activeMessages.isEmpty else { return }
        activeMessages.removeLast()
        totalMessageCount = max(0, totalMessageCount - 1)
        updateMemoryStats()
    }

    // MARK: - Phase 3.3: Memory Management

    /// Manage conversation memory by archiving old messages
    private func manageMemory() {
        // Check if active window exceeded
        if activeMessages.count > activeWindowSize {
            archiveOldMessages()
        }

        // Check if total memory exceeded
        let currentMemory = calculateTotalMemory()
        if currentMemory > maxTotalMemoryBytes {
            compressOldestArchived()
        }
    }

    /// Archive oldest messages from active window to compressed storage
    private func archiveOldMessages() {
        let excessCount = activeMessages.count - activeWindowSize

        guard excessCount > 0 else { return }

        print("💾 [MemoryManager] Archiving \(excessCount) old messages")

        // Compress and move to archive
        for i in 0..<excessCount {
            let message = activeMessages[i]
            let compressed = compressMessage(message)
            archivedMessages.append(compressed)
        }

        // Remove from active
        activeMessages.removeFirst(excessCount)

        // Limit archive size
        if archivedMessages.count > archiveWindowSize {
            let removeCount = archivedMessages.count - archiveWindowSize
            archivedMessages.removeFirst(removeCount)
            totalMessageCount -= removeCount
            print("⚠️ [MemoryManager] Dropped \(removeCount) oldest archived messages")
        }
    }

    /// Compress a message for archival
    private func compressMessage(_ message: ConversationMessage) -> CompressedMessage {
        let summary: String
        if message.content.count > compressionThreshold {
            // Truncate long messages
            let endIndex = message.content.index(message.content.startIndex, offsetBy: compressionThreshold)
            summary = String(message.content[..<endIndex]) + "..."
        } else {
            summary = message.content
        }

        return CompressedMessage(
            role: message.role,
            summary: summary,
            timestamp: message.timestamp,
            originalLength: message.content.count
        )
    }

    /// Remove oldest archived messages to free memory
    private func compressOldestArchived() {
        guard !archivedMessages.isEmpty else { return }

        let removeCount = min(10, archivedMessages.count)
        archivedMessages.removeFirst(removeCount)
        totalMessageCount -= removeCount

        print("⚠️ [MemoryManager] Removed \(removeCount) oldest archived messages due to memory pressure")
    }

    /// Calculate total memory usage
    private func calculateTotalMemory() -> Int {
        let activeMemory = activeMessages.reduce(0) { $0 + $1.estimatedMemoryBytes }
        let archivedMemory = archivedMessages.reduce(0) { $0 + $1.estimatedMemoryBytes }
        return activeMemory + archivedMemory
    }

    /// Update published memory statistics
    private func updateMemoryStats() {
        estimatedMemoryKB = calculateTotalMemory() / 1024
    }

    // MARK: - Performance Monitoring

    /// Get detailed memory statistics
    func getMemoryStats() -> (activeCount: Int, archivedCount: Int, totalKB: Int, activeKB: Int, archivedKB: Int) {
        let activeMemory = activeMessages.reduce(0) { $0 + $1.estimatedMemoryBytes }
        let archivedMemory = archivedMessages.reduce(0) { $0 + $1.estimatedMemoryBytes }

        return (
            activeCount: activeMessages.count,
            archivedCount: archivedMessages.count,
            totalKB: (activeMemory + archivedMemory) / 1024,
            activeKB: activeMemory / 1024,
            archivedKB: archivedMemory / 1024
        )
    }
}
