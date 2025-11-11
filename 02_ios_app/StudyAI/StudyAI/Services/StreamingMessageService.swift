//
//  StreamingMessageService.swift
//  StudyAI
//
//  Created by Claude Code on 11/5/25.
//  Extracted from SessionChatView.swift for Phase 1 refactoring
//  Phase 3.2: Optimized for performance - zero-copy operations
//

import Foundation
import Combine

/// Service responsible for managing streaming message chunking and processing
/// Handles smart chunking of long streaming responses at sentence boundaries
/// **Phase 3.2 Optimizations**: Zero-copy string operations, cached boundaries
@MainActor
class StreamingMessageService: ObservableObject {

    // MARK: - Singleton

    static let shared = StreamingMessageService()

    // MARK: - Published Properties

    /// All completed chunks for the current streaming response
    @Published var streamingChunks: [String] = []

    /// Total length of text that has been processed into chunks
    @Published var totalProcessedLength: Int = 0

    /// Flag to track if this is the first chunk of the response (uses smaller target)
    @Published var isFirstChunkOfResponse: Bool = true

    // MARK: - Configuration

    /// Target size for first chunk (characters) - smaller for faster initial response
    private let firstChunkSizeTarget: Int = 150

    /// Target size for subsequent chunks (characters) - larger for optimal TTS performance
    private let chunkSizeTarget: Int = 800

    // MARK: - Phase 3.2: Performance Optimizations

    /// Maximum number of chunks to keep in memory (prevents unbounded growth)
    private let maxChunksInMemory: Int = 100

    /// Sentence ending characters for fast lookup
    private let sentenceEnders: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]

    /// Fallback word boundary characters for fast lookup
    private let wordBoundaries: Set<Character> = [" ", ",", "，", ";", "；"]

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Process streaming text and split into chunks at sentence boundaries
    /// Returns completed chunks that are ready for display and TTS
    ///
    /// **Phase 3.2 Optimizations**:
    /// - Uses String.Index for zero-copy substring operations
    /// - Pre-computed character sets for O(1) boundary detection
    /// - Eliminates intermediate string allocations
    ///
    /// - Parameter accumulatedText: Full text received from server so far
    /// - Returns: Array of newly completed chunks
    func processStreamingChunk(_ accumulatedText: String) -> [String] {
        var completedChunks: [String] = []

        // Phase 3.2: Use String.Index for zero-copy operations
        let startIndex = accumulatedText.index(accumulatedText.startIndex, offsetBy: totalProcessedLength, limitedBy: accumulatedText.endIndex) ?? accumulatedText.endIndex

        guard startIndex < accumulatedText.endIndex else {
            return completedChunks
        }

        // Get unprocessed text using indices (zero-copy)
        let unprocessedStartIndex = startIndex
        var currentIndex = unprocessedStartIndex

        // Process the unprocessed text to find chunk boundaries
        while currentIndex < accumulatedText.endIndex {
            let targetSize = isFirstChunkOfResponse ? firstChunkSizeTarget : chunkSizeTarget
            let remainingDistance = accumulatedText.distance(from: currentIndex, to: accumulatedText.endIndex)

            guard remainingDistance >= targetSize else {
                break
            }

            // Find sentence boundary using optimized search
            if let boundary = findSentenceBoundaryOptimized(in: accumulatedText, from: currentIndex, targetSize: targetSize) {
                // Extract completed chunk (zero-copy substring)
                let chunkSubstring = accumulatedText[currentIndex..<boundary]
                let chunk = String(chunkSubstring)
                completedChunks.append(chunk)

                // Track that we've processed this chunk
                totalProcessedLength += chunk.count

                // Mark that we've created the first chunk
                if isFirstChunkOfResponse {
                    isFirstChunkOfResponse = false
                    print("📦 [StreamingService] First chunk created: \(chunk.count) chars (target: \(targetSize))")
                }

                // Update current index
                currentIndex = boundary

                print("📦 [StreamingService] Smart chunk created: \(chunk.count) chars (target: \(targetSize)), total processed: \(totalProcessedLength)")
            } else {
                // No good boundary found, stop chunking for now
                break
            }
        }

        // Add completed chunks to our tracking array
        streamingChunks.append(contentsOf: completedChunks)

        // Phase 3.2: Memory management - limit chunks in memory
        if streamingChunks.count > maxChunksInMemory {
            let excessCount = streamingChunks.count - maxChunksInMemory
            streamingChunks.removeFirst(excessCount)
            print("⚠️ [StreamingService] Memory limit reached, removed \(excessCount) old chunks")
        }

        return completedChunks
    }

    /// Get the current incomplete chunk being streamed (for UI display)
    /// This is simply the text we haven't chunked yet
    ///
    /// **Phase 3.2**: Optimized with String.Index (zero-copy)
    ///
    /// - Parameter accumulatedText: Full text received from server
    /// - Returns: The incomplete portion still being streamed
    func getCurrentStreamingChunk(_ accumulatedText: String) -> String {
        guard totalProcessedLength < accumulatedText.count else {
            return ""
        }

        // Phase 3.2: Use String.Index for zero-copy operation
        let startIndex = accumulatedText.index(accumulatedText.startIndex, offsetBy: totalProcessedLength, limitedBy: accumulatedText.endIndex) ?? accumulatedText.endIndex

        return String(accumulatedText[startIndex...])
    }

    /// Reset chunking state for new streaming session
    /// Call this when starting a new message to clear previous state
    func resetChunking() {
        streamingChunks.removeAll(keepingCapacity: true) // Phase 3.2: Keep capacity to avoid reallocation
        totalProcessedLength = 0
        isFirstChunkOfResponse = true
        print("🔄 [StreamingService] Chunking reset - ready for new response")
    }

    // MARK: - Phase 3.2: Optimized Private Helpers

    /// Find the last sentence boundary in text before targetSize (optimized version)
    ///
    /// **Phase 3.2 Optimizations**:
    /// - Uses String.Index directly (no intermediate strings)
    /// - Pre-computed character sets for O(1) lookups
    /// - Single reverse scan (no array creation)
    ///
    /// - Parameters:
    ///   - text: Full text to search in
    ///   - startIndex: Starting index for search
    ///   - targetSize: Target size for chunk
    /// - Returns: Index of the boundary, or nil if none found
    private func findSentenceBoundaryOptimized(in text: String, from startIndex: String.Index, targetSize: Int) -> String.Index? {
        // Calculate search end index
        guard let searchEndIndex = text.index(startIndex, offsetBy: targetSize, limitedBy: text.endIndex) else {
            return nil
        }

        // Search backwards from searchEndIndex to startIndex
        var currentIndex = searchEndIndex
        var lastBoundary: String.Index?

        // Phase 3.2: Single reverse scan with pre-computed sets
        while currentIndex > startIndex {
            let prevIndex = text.index(before: currentIndex)
            let char = text[prevIndex]

            if sentenceEnders.contains(char) {
                lastBoundary = currentIndex // Include the punctuation
                break
            }

            currentIndex = prevIndex
        }

        // If no sentence boundary found, try to split at last word boundary
        if lastBoundary == nil {
            currentIndex = searchEndIndex
            while currentIndex > startIndex {
                let prevIndex = text.index(before: currentIndex)
                let char = text[prevIndex]

                if wordBoundaries.contains(char) {
                    lastBoundary = currentIndex
                    break
                }

                currentIndex = prevIndex
            }
        }

        return lastBoundary
    }

    // MARK: - Phase 3.2: Performance Monitoring

    /// Get current memory usage statistics
    func getMemoryStats() -> (chunkCount: Int, totalProcessedLength: Int, estimatedMemoryKB: Int) {
        let estimatedMemory = streamingChunks.reduce(0) { $0 + $1.utf8.count } / 1024
        return (streamingChunks.count, totalProcessedLength, estimatedMemory)
    }
}
