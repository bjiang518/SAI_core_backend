//
//  TTSQueueService.swift
//  StudyAI
//
//  Created by Claude Code on 11/5/25.
//  Extracted from SessionChatView.swift for Phase 1 refactoring
//  Phase 3.4: Optimized for performance - efficient queue operations
//  Phase 3.6 (2026-02-16): Watchdog timers + direct callbacks + incremental memory tracking
//

import Foundation
import Combine

/// Service responsible for managing sequential TTS playback queue
/// Handles enqueueing, sequential playback, and session-based cleanup
/// **Phase 3.6 Enhancements**: Watchdog for stuck detection, direct callbacks, O(1) memory tracking
@MainActor
class TTSQueueService: ObservableObject {

    // MARK: - Debug Mode

    /// Enable verbose logging for debugging (default: false)
    private static let debugMode = false

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

    // MARK: - Phase 3.7: Race Condition Prevention

    /// Re-entrance guard to prevent observer from firing multiple times
    private var isProcessingNextChunk = false

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

    // MARK: - Phase 3.6: Watchdog and Reliability

    /// Watchdog timer to detect stuck TTS (20s timeout)
    private var watchdogTimer: Timer?

    /// Timeout for watchdog (20 seconds - reduced from 30s to match 15s network timeout)
    /// Gives 5s buffer for processing after network request completes
    private let watchdogTimeout: TimeInterval = 20.0

    /// Track current memory incrementally - O(1) instead of O(n)
    private var totalQueueMemoryBytes: Int = 0

    /// Direct completion callback for next chunk (replaces observer pattern)
    private var completionCallback: (() -> Void)?

    // MARK: - Dependencies

    /// Voice service for actual TTS playback
    private let voiceService = VoiceInteractionService.shared

    /// Network service for session validation
    private let networkService = NetworkService.shared

    // MARK: - Initialization

    private init() {
        // ✅ Phase 3.6: Setup completion observation from voice service
        setupCompletionObserver()
    }

    // MARK: - Public API

    // MARK: - Phase 3.6: Setup Completion Observer

    /// Setup observer for voice service completion to trigger next chunk
    /// This replaces the SessionChatView observer pattern with direct callback
    private var cancellables = Set<AnyCancellable>()

    private func setupCompletionObserver() {
        // Observe voice service state changes
        voiceService.$interactionState
            .sink { [weak self] state in
                guard let self = self else { return }

                // ✅ Phase 3.7 (2026-02-18): CRITICAL FIX - Observer must trigger even when queue is empty
                // When voice becomes idle AND we're playing TTS, always call playNextTTSChunk()
                // playNextTTSChunk() will handle both cases:
                //   - Queue has items → play next chunk
                //   - Queue is empty → clean up and stop
                if state == .idle
                    && !self.voiceService.isProcessingTTS  // Not loading audio from network
                    && self.isPlayingTTS
                    && !self.isProcessingNextChunk {  // ✅ Prevent double-trigger race condition

                    // ✅ Lock to prevent re-entrance
                    self.isProcessingNextChunk = true

                    print("🎵 [TTSQueue] Observer triggered (queue: \(self.effectiveQueueSize) items)")

                    // Reset watchdog since we're making progress
                    self.resetWatchdog()

                    // Play next chunk or clean up if queue is empty
                    self.playNextTTSChunk()

                    // ✅ Release lock after chunk starts (500ms delay allows audio to start)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.isProcessingNextChunk = false
                        print("🎵 [TTSQueue] Re-entrance guard released")
                    }
                }
            }
            .store(in: &cancellables)
    }

    /// Add chunk to TTS queue and start playing if not already playing
    ///
    /// **Phase 3.6 Enhancements**:
    /// - Incremental memory tracking (O(1) instead of O(n))
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

        // Phase 3.6: Create new item
        let newItem = TTSQueueItem(text: text, messageId: messageId, enqueuedAt: Date())

        // ✅ Phase 3.6: Check memory limits with INCREMENTAL tracking (O(1)!)
        if effectiveQueueSize >= maxQueueSize {
            print("⚠️ [TTSQueue] Queue full (\(maxQueueSize)), dropping oldest item")
            if let removed = dequeueItem() {
                // Decrement memory counter
                totalQueueMemoryBytes -= removed.estimatedMemoryBytes
            }
        }

        // Check total memory using cached value - O(1) instead of O(n)!
        if totalQueueMemoryBytes + newItem.estimatedMemoryBytes > maxQueueMemoryBytes {
            print("⚠️ [TTSQueue] Memory limit reached (\(totalQueueMemoryBytes/1024)KB), dropping oldest items")
            while totalQueueMemoryBytes + newItem.estimatedMemoryBytes > maxQueueMemoryBytes && effectiveQueueSize > 0 {
                if let removed = dequeueItem() {
                    totalQueueMemoryBytes -= removed.estimatedMemoryBytes
                }
            }
        }

        // Add to queue (O(1) operation)
        queueStorage.append(newItem)
        // ✅ Increment memory counter (O(1))
        totalQueueMemoryBytes += newItem.estimatedMemoryBytes
        updateQueueSize()

        // ✅ Phase 3.7: Enhanced logging with text preview
        let textPreview = text.prefix(80).replacingOccurrences(of: "\n", with: " ")
        print("📥 [TTSQueue] Enqueued chunk #\(effectiveQueueSize): \(text.count) chars")
        print("   └─ Preview: \"\(textPreview)...\"")
        print("   └─ Queue: \(effectiveQueueSize) items, \(totalQueueMemoryBytes/1024)KB")

        // Start playing if not already playing
        if !isPlayingTTS {
            print("▶️ [TTSQueue] Starting playback (queue was idle)")
            playNextTTSChunk()
        }
    }

    /// Play the next chunk in the TTS queue
    /// Validates session and voice settings before playback
    ///
    /// **Phase 3.6**: Adds watchdog timer to detect stuck states
    func playNextTTSChunk() {
        print("🎬 [TTSQueue] playNextTTSChunk() called")
        print("   └─ Queue size: \(effectiveQueueSize)")
        print("   └─ isPlayingTTS: \(isPlayingTTS)")
        print("   └─ voiceEnabled: \(voiceService.isVoiceEnabled)")

        guard effectiveQueueSize > 0 else {
            print("⏹️ [TTSQueue] Queue empty - stopping playback")
            isPlayingTTS = false
            currentSessionIdForTTS = nil
            cancelWatchdog() // ✅ Cancel watchdog when done

            // ✅ Phase 3.7 (2026-02-18): Deactivate audio session when queue is truly empty
            // This ensures battery optimization and allows other apps to play audio
            print("⏹️ [TTSQueue] Deactivating audio session (queue empty)")
            voiceService.stopSpeech()  // This will deactivate the audio session

            compactQueueIfNeeded()
            return
        }

        // ✅ SAFETY CHECK: Ensure current session matches the TTS session
        guard let ttsSessionId = currentSessionIdForTTS,
              ttsSessionId == networkService.currentSessionId else {
            print("⚠️ [TTSQueue] Session mismatch - clearing queue")
            print("   └─ TTS session: \(currentSessionIdForTTS ?? "nil")")
            print("   └─ Current session: \(networkService.currentSessionId ?? "nil")")
            clearQueue()
            return
        }

        guard voiceService.isVoiceEnabled else {
            print("⚠️ [TTSQueue] Voice disabled - clearing queue")
            clearQueue()
            return
        }

        // Phase 3.4: Efficient dequeue using head index (O(1))
        guard let nextItem = dequeueItem() else {
            print("⚠️ [TTSQueue] Failed to dequeue item (unexpected)")
            isPlayingTTS = false
            cancelWatchdog() // ✅ Cancel watchdog
            return
        }

        isPlayingTTS = true

        // ✅ Phase 3.6: Start watchdog timer to detect stuck TTS
        startWatchdog()

        let textPreview = nextItem.text.prefix(80).replacingOccurrences(of: "\n", with: " ")
        print("▶️ [TTSQueue] Playing chunk: \(nextItem.text.count) chars")
        print("   └─ Preview: \"\(textPreview)...\"")
        print("   └─ Remaining in queue: \(effectiveQueueSize)")
        print("   └─ Watchdog: started (\(watchdogTimeout)s timeout)")

        // Set as current speaking message
        voiceService.setCurrentSpeakingMessage(nextItem.messageId)

        // Speak the text
        voiceService.speakText(nextItem.text, autoSpeak: true)

        // Phase 3.4: Trigger cleanup if needed
        compactQueueIfNeeded()
    }

    /// Stop all TTS playback and clear queue
    func stopAllTTS() {
        if Self.debugMode {
        print("🎵 [TTSQueueService] Stopping all TTS playback")
        }
        voiceService.stopSpeech()
        clearQueue()
    }

    /// Clear TTS queue for a specific session
    ///
    /// - Parameter sessionId: Session ID to clear TTS for
    func clearTTSQueueForSession(_ sessionId: String) {
        if currentSessionIdForTTS == sessionId {
            if Self.debugMode {
            print("🎵 [TTSQueueService] Clearing TTS queue for session: \(sessionId)")
            }
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
        totalQueueMemoryBytes = 0  // ✅ Phase 3.6: Reset memory counter
        cancelWatchdog()  // ✅ Cancel watchdog when clearing
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
    /// ⚠️ DEPRECATED in Phase 3.6: Use totalQueueMemoryBytes (O(1)) instead
    /// Kept for backward compatibility and debugging
    private func getTotalQueueMemory() -> Int {
        // ✅ Phase 3.6: Return cached value instead of recalculating
        return totalQueueMemoryBytes
    }

    /// Update published queue size
    private func updateQueueSize() {
        queueSize = effectiveQueueSize
    }

    // MARK: - Phase 3.6: Watchdog Methods

    /// Start watchdog timer to detect stuck TTS (60s timeout)
    private func startWatchdog() {
        cancelWatchdog() // Cancel existing timer first

        watchdogTimer = Timer.scheduledTimer(withTimeInterval: watchdogTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.handleWatchdogTimeout()
            }
        }

        if Self.debugMode {
        print("🐕 [TTSQueueService] Watchdog started (\(watchdogTimeout)s timeout)")
        }
    }

    /// Reset watchdog timer (called when progress is made)
    private func resetWatchdog() {
        if watchdogTimer != nil {
            if Self.debugMode {
            print("🐕 [TTSQueueService] Watchdog reset - progress detected")
            }
            startWatchdog()
        }
    }

    /// Cancel watchdog timer
    private func cancelWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    /// Handle watchdog timeout - TTS is stuck!
    private func handleWatchdogTimeout() {
        // ✅ Phase 3.6 (2026-02-16): Cancel watchdog FIRST to prevent double timers
        cancelWatchdog()

        print("⚠️⚠️⚠️ [TTSQueue] WATCHDOG TIMEOUT - TTS STUCK FOR \(watchdogTimeout)s!")
        print("   └─ Queue size: \(effectiveQueueSize)")
        print("   └─ isPlayingTTS: \(isPlayingTTS)")
        print("   └─ Voice state: \(voiceService.interactionState)")
        print("   └─ isProcessingTTS: \(voiceService.isProcessingTTS)")
        print("   └─ isProcessingNextChunk: \(isProcessingNextChunk)")
        print("   └─ currentSessionId: \(currentSessionIdForTTS ?? "nil")")

        // Force recovery - stop current playback and try next
        voiceService.stopSpeech()

        // If queue has more items, try playing next
        if effectiveQueueSize > 0 {
            print("🔄 [TTSQueue] Recovery attempt - playing next chunk (\(effectiveQueueSize) remaining)")
            // playNextTTSChunk will start a new watchdog
            playNextTTSChunk()
        } else {
            // Queue empty - just stop
            isPlayingTTS = false
            print("🛑 [TTSQueue] Queue empty after timeout - stopping TTS")
        }
    }

    // MARK: - Phase 3.4: Performance Monitoring

    /// Get detailed queue statistics
    func getQueueStats() -> (size: Int, memoryKB: Int, headIndex: Int, capacity: Int) {
        return (
            size: effectiveQueueSize,
            memoryKB: totalQueueMemoryBytes / 1024,  // ✅ Phase 3.6: Use cached value (O(1))
            headIndex: headIndex,
            capacity: queueStorage.capacity
        )
    }
}
