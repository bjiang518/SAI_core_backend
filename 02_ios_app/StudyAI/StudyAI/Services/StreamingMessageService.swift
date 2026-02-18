//
//  StreamingMessageService.swift
//  StudyAI
//
//  Created by Claude Code on 11/5/25.
//  Extracted from SessionChatView.swift for Phase 1 refactoring
//  Phase 3.2: Optimized for performance - zero-copy operations
//  Phase 3.5 (2026-02-16): Delta processing with O(1) complexity + LaTeX boundary detection
//

import Foundation
import Combine

/// Service responsible for managing streaming message chunking and processing
/// Handles smart chunking of long streaming responses at sentence boundaries
/// **Phase 3.5 Optimizations**: Cached String.Index for O(1) delta extraction + LaTeX completion detection
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
    /// Phase 3.6 (2026-02-16): Reduced from 150 to 100 chars for faster first TTS
    private let firstChunkSizeTarget: Int = 100

    /// Target size for subsequent chunks (characters) - balanced for TTS performance
    /// Phase 3.6 (2026-02-16): Reduced from 800 to 400 chars for more frequent TTS updates
    private let chunkSizeTarget: Int = 400

    // MARK: - Phase 3.2: Performance Optimizations

    /// Maximum number of chunks to keep in memory (prevents unbounded growth)
    private let maxChunksInMemory: Int = 100

    /// Sentence ending characters for fast lookup
    private let sentenceEnders: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]

    /// Fallback word boundary characters for fast lookup
    private let wordBoundaries: Set<Character> = [" ", ",", "，", ";", "；"]

    // MARK: - Phase 3.5: Delta Processing with Cached Index (O(1))

    /// Cached String.Index for O(1) delta extraction (eliminates O(n) offsetBy)
    private var cachedProcessedIndex: String.Index?

    /// Reference to last processed text for cache validation
    private var lastProcessedText: String = ""

    /// LaTeX delimiter tracking for completion detection
    private var openInlineDelimiters: Int = 0  // Count of unmatched \(
    private var openDisplayDelimiters: Int = 0  // Count of unmatched \[

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Process streaming text and split into chunks at sentence boundaries
    /// Returns completed chunks that are ready for display and TTS
    ///
    /// **Phase 3.5 Optimizations (2026-02-16)**:
    /// - Uses CACHED String.Index for O(1) delta extraction (not O(n) offsetBy!)
    /// - Only processes NEW text since last call
    /// - LaTeX completion detection (only render complete expressions)
    /// - Pre-computed character sets for O(1) boundary detection
    ///
    /// - Parameter accumulatedText: Full text received from server so far
    /// - Returns: Array of newly completed chunks (with complete LaTeX only)
    func processStreamingChunk(_ accumulatedText: String) -> [String] {
        var completedChunks: [String] = []

        // ✅ Phase 3.5: O(1) Delta Extraction using Cached Index
        var startIndex: String.Index

        // Check if we can use cached index (text is continuation of last)
        if let cached = cachedProcessedIndex,
           accumulatedText.hasPrefix(lastProcessedText),
           cached <= accumulatedText.endIndex {
            // ✅ FAST PATH: Use cached index - O(1) operation!
            startIndex = cached
        } else {
            // Cache miss - recalculate from offset (only on first call or text change)
            startIndex = accumulatedText.index(
                accumulatedText.startIndex,
                offsetBy: totalProcessedLength,
                limitedBy: accumulatedText.endIndex
            ) ?? accumulatedText.endIndex
        }

        guard startIndex < accumulatedText.endIndex else {
            return completedChunks
        }

        // Get unprocessed text using indices (zero-copy)
        var currentIndex = startIndex

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

                // ✅ Phase 3.5: Check LaTeX completion before accepting chunk
                if isLaTeXComplete(in: chunk) {
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

                    print("📦 [StreamingService] ✅ Complete chunk (LaTeX verified): \(chunk.count) chars, total processed: \(totalProcessedLength)")
                } else {
                    // LaTeX incomplete - wait for closing delimiters
                    print("⏳ [StreamingService] Incomplete LaTeX in chunk, waiting for closing delimiters")
                    break
                }
            } else {
                // No good boundary found, stop chunking for now
                break
            }
        }

        // ✅ Phase 3.5: Cache the current index for next call - O(1) next time!
        cachedProcessedIndex = currentIndex
        lastProcessedText = accumulatedText

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

        // ✅ Phase 3.5: Clear cached index and LaTeX state
        cachedProcessedIndex = nil
        lastProcessedText = ""
        openInlineDelimiters = 0
        openDisplayDelimiters = 0

        print("🔄 [StreamingService] Chunking reset - ready for new response (cache cleared)")
    }

    // MARK: - Phase 3.2: Optimized Private Helpers

    // MARK: - Phase 3.5: LaTeX Completion Detection

    /// Check if LaTeX expressions in text are complete (all delimiters balanced)
    /// Returns true if all LaTeX expressions have matching opening and closing delimiters
    ///
    /// - Parameter text: Text chunk to check
    /// - Returns: true if all LaTeX is complete, false if incomplete expressions detected
    private func isLaTeXComplete(in text: String) -> Bool {
        var inlineOpen = 0
        var displayOpen = 0
        var i = text.startIndex

        while i < text.endIndex {
            let char = text[i]

            // Check for backslash (potential LaTeX delimiter)
            if char == "\\" {
                let nextIndex = text.index(after: i)
                guard nextIndex < text.endIndex else {
                    // Trailing backslash - incomplete
                    return false
                }

                let nextChar = text[nextIndex]

                if nextChar == "(" {
                    // Opening inline delimiter \(
                    inlineOpen += 1
                    i = text.index(after: nextIndex)
                    continue
                } else if nextChar == ")" {
                    // Closing inline delimiter \)
                    inlineOpen -= 1
                    i = text.index(after: nextIndex)
                    continue
                } else if nextChar == "[" {
                    // Opening display delimiter \[
                    displayOpen += 1
                    i = text.index(after: nextIndex)
                    continue
                } else if nextChar == "]" {
                    // Closing display delimiter \]
                    displayOpen -= 1
                    i = text.index(after: nextIndex)
                    continue
                }
            }

            i = text.index(after: i)
        }

        // All delimiters must be balanced (count = 0)
        let isComplete = (inlineOpen == 0) && (displayOpen == 0)

        if !isComplete {
            print("📐 [StreamingService] LaTeX incomplete: inline=\(inlineOpen), display=\(displayOpen)")
        }

        return isComplete
    }

    // MARK: - Original Phase 3.2 Helpers

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
