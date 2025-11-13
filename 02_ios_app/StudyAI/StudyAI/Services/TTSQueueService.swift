//
//  TTSQueueService.swift
//  StudyAI
//
//  Created by Claude Code on 11/5/25.
//  Extracted from SessionChatView.swift for Phase 1 refactoring
//  Phase 3.4: Optimized for performance - efficient queue operations
//

import Foundation
import Combine

/// Service responsible for managing sequential TTS playback queue
/// Handles enqueueing, sequential playback, and session-based cleanup
/// **Phase 3.4 Optimizations**: Circular buffer queue, memory limits, efficient operations
@MainActor
class TTSQueueService: ObservableObject {

    // MARK: - Singleton

    static let shared = TTSQueueService()

    // MARK: - Phase 3.4: Optimized Queue Structure

    /// TTS queue item with metadata
    private struct TTSQueueItem {
        let text: String
        let messageId: String
        let enqueuedAt: Date

        var estimatedMemoryBytes: Int {
            return text.utf8.count
        }
    }

    /// Internal queue storage (circular buffer for O(1) operations)
    private var queueStorage: [TTSQueueItem] = []

    /// Head index for efficient dequeue (avoids array shifting)
    private var headIndex: Int = 0

    // MARK: - Published Properties

    /// Flag indicating if TTS is currently active
    @Published var isPlayingTTS = false

    /// Track which session's TTS is currently playing
    @Published var currentSessionIdForTTS: String?

    /// Current queue size (for UI observation)
    @Published var queueSize: Int = 0

    // MARK: - Phase 3.4: Configuration

    /// Maximum queue size to prevent memory issues
    private let maxQueueSize: Int = 50

    /// Maximum total memory (in bytes) for TTS queue
    private let maxQueueMemoryBytes: Int = 1_000_000 // ~1MB

    /// Cleanup threshold - compact queue when head reaches this index
    private let cleanupThreshold: Int = 20

    // MARK: - Dependencies

    /// Voice service for actual TTS playback
    private let voiceService = VoiceInteractionService.shared

    /// Network service for session validation
    private let networkService = NetworkService.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Add chunk to TTS queue and start playing if not already playing
    ///
    /// **Phase 3.4 Optimizations**:
    /// - Enforces memory limits
    /// - Drops old items if queue too large
    /// - O(1) enqueue operation
    ///
    /// - Parameters:
    ///   - text: Text content to be spoken
    ///   - messageId: Unique identifier for the message
    ///   - sessionId: Session ID for validation
    func enqueueTTSChunk(text: String, messageId: String, sessionId: String) {
        // Update current session for TTS
        currentSessionIdForTTS = sessionId

        // Phase 3.4: Check memory limits before adding
        let newItem = TTSQueueItem(text: text, messageId: messageId, enqueuedAt: Date())

        if effectiveQueueSize >= maxQueueSize {
            print("⚠️ [TTSQueueService] Queue full, dropping oldest item")
            _ = dequeueItem() // Drop oldest
        }

        // Check total memory usage
        let currentMemory = getTotalQueueMemory()
        if currentMemory + newItem.estimatedMemoryBytes > maxQueueMemoryBytes {
            print("⚠️ [TTSQueueService] Memory limit reached (\(currentMemory/1024)KB), dropping oldest items")
            while getTotalQueueMemory() + newItem.estimatedMemoryBytes > maxQueueMemoryBytes && effectiveQueueSize > 0 {
                _ = dequeueItem()
            }
        }

        // Add to queue (O(1) operation)
        queueStorage.append(newItem)
        updateQueueSize()

        print("🎵 [TTSQueueService] Enqueued TTS chunk: \(text.count) chars, queue size: \(effectiveQueueSize), memory: \(getTotalQueueMemory()/1024)KB")

        // Start playing if not already playing
        if !isPlayingTTS {
            playNextTTSChunk()
        }
    }

    /// Play the next chunk in the TTS queue
    /// Validates session and voice settings before playback
    ///
    /// **Phase 3.4**: Uses optimized dequeue operation
    func playNextTTSChunk() {
        guard effectiveQueueSize > 0 else {
            print("🎵 [TTSQueueService] TTS queue empty, stopping playback")
            isPlayingTTS = false
            currentSessionIdForTTS = nil
            compactQueueIfNeeded()
            return
        }

        // ✅ SAFETY CHECK: Ensure current session matches the TTS session
        guard let ttsSessionId = currentSessionIdForTTS,
              ttsSessionId == networkService.currentSessionId else {
            print("🎵 [TTSQueueService] Session mismatch - clearing TTS queue (TTS: \(currentSessionIdForTTS ?? "nil"), Current: \(networkService.currentSessionId ?? "nil"))")
            clearQueue()
            return
        }

        guard voiceService.isVoiceEnabled else {
            print("🎵 [TTSQueueService] Voice disabled, clearing TTS queue")
            clearQueue()
            return
        }

        // Phase 3.4: Efficient dequeue using head index (O(1))
        guard let nextItem = dequeueItem() else {
            isPlayingTTS = false
            return
        }

        isPlayingTTS = true

        print("🎵 [TTSQueueService] Playing TTS chunk: \(nextItem.text.count) chars, remaining in queue: \(effectiveQueueSize)")

        // Set as current speaking message
        voiceService.setCurrentSpeakingMessage(nextItem.messageId)

        // Speak the text
        voiceService.speakText(nextItem.text, autoSpeak: true)

        // Phase 3.4: Trigger cleanup if needed
        compactQueueIfNeeded()
    }

    /// Stop all TTS playback and clear queue
    func stopAllTTS() {
        print("🎵 [TTSQueueService] Stopping all TTS playback")
        voiceService.stopSpeech()
        clearQueue()
    }

    /// Clear TTS queue for a specific session
    ///
    /// - Parameter sessionId: Session ID to clear TTS for
    func clearTTSQueueForSession(_ sessionId: String) {
        if currentSessionIdForTTS == sessionId {
            print("🎵 [TTSQueueService] Clearing TTS queue for session: \(sessionId)")
            stopAllTTS()
        }
    }

    // MARK: - Phase 3.4: Optimized Private Methods

    /// Efficient queue size calculation (excludes dequeued items)
    private var effectiveQueueSize: Int {
        return max(0, queueStorage.count - headIndex)
    }

    /// Dequeue next item from queue (O(1) operation)
    /// Uses head index to avoid array shifting
    private func dequeueItem() -> TTSQueueItem? {
        guard headIndex < queueStorage.count else {
            return nil
        }

        let item = queueStorage[headIndex]
        headIndex += 1
        updateQueueSize()

        return item
    }

    /// Clear entire queue
    private func clearQueue() {
        queueStorage.removeAll(keepingCapacity: true)
        headIndex = 0
        isPlayingTTS = false
        currentSessionIdForTTS = nil
        updateQueueSize()
    }

    /// Compact queue storage when head index gets too large
    /// This prevents unbounded memory growth from dequeued items
    private func compactQueueIfNeeded() {
        guard headIndex >= cleanupThreshold else {
            return
        }

        print("🧹 [TTSQueueService] Compacting queue (head: \(headIndex), total: \(queueStorage.count))")

        // Remove dequeued items
        queueStorage.removeFirst(headIndex)
        headIndex = 0

        // Shrink capacity if queue is much smaller than capacity
        if queueStorage.capacity > queueStorage.count * 2 {
            queueStorage.reserveCapacity(queueStorage.count)
        }
    }

    /// Calculate total memory used by queue
    private func getTotalQueueMemory() -> Int {
        guard headIndex < queueStorage.count else {
            return 0
        }

        return queueStorage[headIndex...].reduce(0) { $0 + $1.estimatedMemoryBytes }
    }

    /// Update published queue size
    private func updateQueueSize() {
        queueSize = effectiveQueueSize
    }

    // MARK: - Phase 3.4: Performance Monitoring

    /// Get detailed queue statistics
    func getQueueStats() -> (size: Int, memoryKB: Int, headIndex: Int, capacity: Int) {
        return (
            size: effectiveQueueSize,
            memoryKB: getTotalQueueMemory() / 1024,
            headIndex: headIndex,
            capacity: queueStorage.capacity
        )
    }
}
