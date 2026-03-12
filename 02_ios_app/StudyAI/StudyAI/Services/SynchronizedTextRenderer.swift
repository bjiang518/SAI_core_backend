//
//  SynchronizedTextRenderer.swift
//  StudyAI
//
//  Phase 3: Interactive Mode - Synchronized Text Rendering
//  Renders text progressively synchronized with audio playback
//
//  Flow:
//  1. Receive alignment data from ElevenLabs (character timings)
//  2. Hold back full text rendering
//  3. Reveal text word-by-word or character-by-character matching audio
//  4. Create illusion of AI "speaking" the text in real-time
//

import Foundation
import Combine
import SwiftUI

/// Alignment data from ElevenLabs for a single audio chunk
struct AudioAlignment: Codable {
    let characters: [String]?
    let characterStartTimesMs: [Double]?
    let characterEndTimesMs: [Double]?

    enum CodingKeys: String, CodingKey {
        case characters
        case characterStartTimesMs = "character_start_times_ms"
        case characterEndTimesMs = "character_end_times_ms"
    }
}

/// Service to synchronize text rendering with audio playback
@MainActor
class SynchronizedTextRenderer: ObservableObject {

    // MARK: - Published State

    /// Currently visible portion of the text
    @Published var visibleText: String = ""

    /// Full text that will be revealed
    @Published var fullText: String = ""

    /// Whether synchronization is active
    @Published var isSynchronizing: Bool = false

    // MARK: - Public Computed Properties

    /// Total audio duration in seconds (for completion scheduling)
    var estimatedAudioDuration: TimeInterval {
        // Calculate time for characters with alignment data
        let alignmentDuration = totalAudioDurationMs / 1000.0

        // Calculate time for remaining characters (if incomplete alignment)
        let charsWithAlignment = characterTimings.count
        let totalChars = fullText.count
        let remainingChars = max(0, totalChars - charsWithAlignment)

        // Remaining characters use fast fallback speed
        let fallbackDuration = Double(remainingChars) / fastFallbackCharsPerSecond

        // Total duration = alignment + fallback + small buffer
        let total = alignmentDuration + fallbackDuration + 1.0

        return total
    }

    // MARK: - Private Properties

    private let logger = AppLogger.forFeature("SyncTextRenderer")

    /// Queue of alignment data chunks to process
    private var alignmentQueue: [(text: String, alignment: AudioAlignment?)] = []

    /// Timer for character-by-character reveal
    private var revealTimer: Timer?

    /// Current character index being revealed
    private var currentCharIndex: Int = 0

    /// Start time of current audio chunk playback
    private var audioStartTime: Date?

    /// Accumulated character timings across all chunks
    private var characterTimings: [(char: String, startMs: Double, endMs: Double)] = []

    /// Total audio duration accumulated so far (ms)
    private var totalAudioDurationMs: Double = 0

    // MARK: - Configuration

    /// Fallback: Characters per second when no alignment data available
    private let fallbackCharsPerSecond: Double = 15.0

    /// Faster fallback for continuation after alignment data exhausted
    /// This ensures remaining text reveals quickly to catch up with audio completion
    private let fastFallbackCharsPerSecond: Double = 50.0  // Much faster to catch up

    /// Whether to use word-based reveal (vs character-based)
    private let useWordBasedReveal: Bool = true

    // MARK: - Public API

    /// Start a new synchronized rendering session
    func startSession() {
        logger.info("🎬 Starting synchronized rendering")
        reset()
        isSynchronizing = true
    }

    /// Add full text that needs to be revealed
    /// - Parameter text: Complete accumulated text received so far
    func setFullText(_ text: String) {
        logger.debug("📥 setFullText: received \(text.count) chars (currentCharIndex=\(currentCharIndex), hasAudio=\(audioStartTime != nil))")
        fullText = text
        // Do NOT reset currentCharIndex or visibleText here.
        // This is called on every text_delta with the full accumulated AI text.
        // Resetting currentCharIndex would restart the fallback timer from 0 on every
        // chunk, causing non-aligned content (e.g. Chinese) to never stably accumulate.

        // If audio arrived before the first text_delta, or the timer stopped after
        // catching up to shorter text, restart the reveal for newly arrived content.
        if audioStartTime != nil && revealTimer == nil && currentCharIndex < fullText.count {
            startRevealingText()
        }
    }

    /// Process an audio chunk with alignment data
    /// - Parameters:
    ///   - text: Text corresponding to this audio chunk
    ///   - alignmentData: Optional alignment timing data from ElevenLabs
    func processAudioChunk(text: String, alignmentData: Data?) {
        let timestamp = Date()
        let timestampStr = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)

        logger.info("[\(timestampStr)] 📥 processAudioChunk - text: \(text.count) chars, hasAlignmentData: \(alignmentData != nil)")

        // Parse alignment data if available
        var alignment: AudioAlignment?
        if let data = alignmentData {
            do {
                alignment = try JSONDecoder().decode(AudioAlignment.self, from: data)
                logger.info("[\(timestampStr)] ✅ Alignment data parsed - chars: \(alignment?.characters?.count ?? 0)")
            } catch {
                logger.warning("[\(timestampStr)] ⚠️ Failed to parse alignment: \(error)")
            }
        } else {
            logger.warning("[\(timestampStr)] ⚠️ No alignment data provided")
        }

        // Add to processing queue
        alignmentQueue.append((text: text, alignment: alignment))

        // Build timing information
        if let alignment = alignment,
           let chars = alignment.characters,
           let startTimes = alignment.characterStartTimesMs,
           let endTimes = alignment.characterEndTimesMs,
           chars.count == startTimes.count,
           chars.count == endTimes.count {

            let beforeCount = characterTimings.count

            // Append timing data with offset for accumulated audio duration
            for i in 0..<chars.count {
                let timing = (
                    char: chars[i],
                    startMs: startTimes[i] + totalAudioDurationMs,
                    endMs: endTimes[i] + totalAudioDurationMs
                )
                characterTimings.append(timing)
            }

            logger.info("[\(timestampStr)] ✅ Added \(chars.count) character timings (total: \(beforeCount) → \(characterTimings.count))")

            // Update total duration
            if let lastEndTime = endTimes.last {
                let oldDuration = totalAudioDurationMs
                totalAudioDurationMs = lastEndTime + totalAudioDurationMs
                logger.info("[\(timestampStr)] ⏱️ Audio duration: \(Int(oldDuration))ms → \(Int(totalAudioDurationMs))ms")
            }
        } else {
            logger.warning("[\(timestampStr)] ⚠️ Cannot build timings - alignment validation failed")
        }

        // Record when audio started and kick off the text reveal timer.
        if audioStartTime == nil {
            audioStartTime = Date()
            logger.info("[\(timestampStr)] ▶️ First audio chunk - starting text reveal")
            startRevealingText()
        }
    }

    /// Signal that audio playback has started
    func audioPlaybackStarted() {
        if audioStartTime == nil {
            audioStartTime = Date()
            logger.info("▶️ Audio started - revealing text")
            startRevealingText()
        }
    }

    /// Stop synchronization and show all text immediately
    func complete() {
        let timestamp = Date()
        let timestampStr = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)
        logger.info("[\(timestampStr)] 🏁 Text reveal complete - revealed \(visibleText.count)/\(fullText.count) chars")
        stopRevealTimer()
        visibleText = fullText
        isSynchronizing = false
    }

    /// Reset state for new session
    func reset() {
        stopRevealTimer()
        visibleText = ""
        fullText = ""
        alignmentQueue.removeAll()
        characterTimings.removeAll()
        currentCharIndex = 0
        audioStartTime = nil
        totalAudioDurationMs = 0
        isSynchronizing = false
    }

    // MARK: - Private Methods

    /// Start progressive text reveal synchronized with audio timing
    private func startRevealingText() {
        let timestamp = Date()
        let timestampStr = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)

        guard !fullText.isEmpty else {
            logger.warning("[\(timestampStr)] ⚠️ No full text set, cannot start reveal")
            return
        }

        logger.info("[\(timestampStr)] 🎬 Starting text reveal - fullText: \(fullText.count) chars, currentCharIndex: \(currentCharIndex), timings: \(characterTimings.count)")

        // If currentCharIndex has already passed the alignment window (e.g. resumed
        // after fallback exhausted alignment, then more text_delta arrived), skip
        // straight to fallback continuation instead of re-entering alignment mode.
        if !characterTimings.isEmpty && currentCharIndex < characterTimings.count {
            logger.info("[\(timestampStr)] ✅ Using alignment-based reveal (\(characterTimings.count) timings, resuming from char \(currentCharIndex))")
            startAlignmentBasedReveal()
        } else if currentCharIndex < fullText.count {
            logger.info("[\(timestampStr)] 🔄 Past alignment window or no timings — using fallback continuation from char \(currentCharIndex)")
            startFallbackRevealContinuation()
        }
    }

    /// Reveal text using ElevenLabs character timing data
    /// HYBRID MODE: Uses alignment data when available, falls back to timer for remaining chars
    private func startAlignmentBasedReveal() {
        logger.info("⏱️ Using alignment-based reveal with \(characterTimings.count) timings")

        // Check every 50ms to see which characters should be visible
        let updateInterval: TimeInterval = 0.05 // 50ms

        revealTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.audioStartTime else { return }

                // Calculate elapsed time since audio started
                let elapsedMs = Date().timeIntervalSince(startTime) * 1000

                // Find all characters that should be visible by now
                let visibleChars = self.characterTimings.filter { timing in
                    timing.startMs <= elapsedMs
                }

                // Reveal text up to the last visible character
                if !visibleChars.isEmpty {
                    let revealCount = visibleChars.count
                    if revealCount > self.currentCharIndex {
                        self.currentCharIndex = revealCount

                        // Extract visible portion from full text
                        let endIndex = min(self.currentCharIndex, self.fullText.count)
                        self.visibleText = String(self.fullText.prefix(endIndex))
                        self.logger.debug("🖥️ [align] rendered \(endIndex)/\(self.fullText.count) | tail: \"\(self.visibleText.suffix(30))\"")

                        // ✅ CRITICAL FIX: Check if we've exhausted alignment data but still have text
                        // If we've revealed all characters with timing data, switch to fallback mode
                        // to reveal the remaining text
                        if self.currentCharIndex >= self.characterTimings.count &&
                           self.currentCharIndex < self.fullText.count {
                            self.logger.warning("⚠️ Exhausted alignment data at char \(self.currentCharIndex)/\(self.fullText.count)")
                            self.logger.warning("🔄 Switching to fallback timer for remaining \(self.fullText.count - self.currentCharIndex) chars")

                            // Stop alignment-based timer
                            self.stopRevealTimer()

                            // Continue with fallback mode for remaining characters
                            self.startFallbackRevealContinuation()
                            return
                        }

                        if endIndex >= self.fullText.count {
                            // Caught up to all text received so far. Stop the timer.
                            // Do NOT call complete() here — fullText is still growing
                            // while streaming is active. setFullText() will restart
                            // the timer when more text arrives. complete() is only
                            // called by the external post-stream handler.
                            self.logger.info("⏸️ Caught up to current fullText — stopping timer until more text arrives")
                            self.stopRevealTimer()
                        }
                    }
                }
            }
        }
    }

    /// Continuation of fallback reveal after alignment data exhausted
    /// Starts from currentCharIndex and reveals remaining characters
    /// Uses faster speed (50 chars/sec) to catch up with audio completion
    private func startFallbackRevealContinuation() {
        let timestamp = Date()
        let timestampStr = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)
        let remaining = fullText.count - currentCharIndex
        logger.info("[\(timestampStr)] ⏱️ FALLBACK CONTINUATION - Revealing remaining \(remaining) chars at \(fastFallbackCharsPerSecond) chars/sec")

        let intervalPerChar = 1.0 / fastFallbackCharsPerSecond

        revealTimer = Timer.scheduledTimer(withTimeInterval: intervalPerChar, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.currentCharIndex < self.fullText.count {
                    self.currentCharIndex += 1
                    self.visibleText = String(self.fullText.prefix(self.currentCharIndex))
                    if self.currentCharIndex % 10 == 0 {
                        self.logger.debug("🖥️ [fallback] rendered \(self.currentCharIndex)/\(self.fullText.count) | tail: \"\(self.visibleText.suffix(30))\"")
                    }
                } else {
                    self.logger.info("⏸️ Fallback continuation caught up — stopping timer until more text arrives")
                    self.stopRevealTimer()
                }
            }
        }
    }

    /// Fallback: Reveal text at constant speed without alignment data
    private func startFallbackReveal() {
        let timestamp = Date()
        let timestampStr = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)
        logger.warning("[\(timestampStr)] ⏱️ FALLBACK MODE - Revealing at \(fallbackCharsPerSecond) chars/sec (no alignment data)")

        let intervalPerChar = 1.0 / fallbackCharsPerSecond

        revealTimer = Timer.scheduledTimer(withTimeInterval: intervalPerChar, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.currentCharIndex < self.fullText.count {
                    self.currentCharIndex += 1
                    self.visibleText = String(self.fullText.prefix(self.currentCharIndex))
                } else {
                    self.logger.info("⏸️ Fallback caught up — stopping timer until more text arrives")
                    self.stopRevealTimer()
                }
            }
        }
    }

    /// Stop the reveal timer
    private func stopRevealTimer() {
        revealTimer?.invalidate()
        revealTimer = nil
    }
}
