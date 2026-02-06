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

    /// Whether to use word-based reveal (vs character-based)
    private let useWordBasedReveal: Bool = true

    // MARK: - Public API

    /// Start a new synchronized rendering session
    func startSession() {
        logger.info("🎬 Starting new synchronized rendering session")
        reset()
        isSynchronizing = true
    }

    /// Add full text that needs to be revealed
    /// - Parameter text: Complete text content
    func setFullText(_ text: String) {
        fullText = text
        visibleText = "" // Hide all text initially
        currentCharIndex = 0
        logger.info("📝 Set full text: \(text.count) chars")
    }

    /// Process an audio chunk with alignment data
    /// - Parameters:
    ///   - text: Text corresponding to this audio chunk
    ///   - alignmentData: Optional alignment timing data from ElevenLabs
    func processAudioChunk(text: String, alignmentData: Data?) {
        logger.info("🎵 Processing audio chunk: \(text.count) chars")

        // Parse alignment data if available
        var alignment: AudioAlignment?
        if let data = alignmentData {
            do {
                alignment = try JSONDecoder().decode(AudioAlignment.self, from: data)
                logger.info("✅ Parsed alignment data: \(alignment?.characters?.count ?? 0) chars")
            } catch {
                logger.warning("⚠️ Failed to parse alignment data: \(error)")
            }
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

            // Append timing data with offset for accumulated audio duration
            for i in 0..<chars.count {
                let timing = (
                    char: chars[i],
                    startMs: startTimes[i] + totalAudioDurationMs,
                    endMs: endTimes[i] + totalAudioDurationMs
                )
                characterTimings.append(timing)
            }

            // Update total duration
            if let lastEndTime = endTimes.last {
                totalAudioDurationMs = lastEndTime + totalAudioDurationMs
            }

            logger.info("📊 Total character timings: \(characterTimings.count), duration: \(totalAudioDurationMs)ms")
        } else {
            logger.warning("⚠️ No valid alignment data, will use fallback timing")
        }

        // Start revealing if not already started
        if audioStartTime == nil {
            audioStartTime = Date()
            startRevealingText()
        }
    }

    /// Signal that audio playback has started
    func audioPlaybackStarted() {
        if audioStartTime == nil {
            audioStartTime = Date()
            logger.info("▶️ Audio playback started - beginning text reveal")
            startRevealingText()
        }
    }

    /// Stop synchronization and show all text immediately
    func complete() {
        logger.info("🏁 Synchronization complete - showing full text")
        stopRevealTimer()
        visibleText = fullText
        isSynchronizing = false
    }

    /// Reset state for new session
    func reset() {
        logger.info("🔄 Resetting synchronized text renderer")
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
        guard !fullText.isEmpty else {
            logger.warning("⚠️ No full text set, cannot start reveal")
            return
        }

        logger.info("🎬 Starting text reveal animation")

        // Use alignment-based reveal if we have timing data
        if !characterTimings.isEmpty {
            startAlignmentBasedReveal()
        } else {
            // Fallback: Time-based reveal without alignment
            startFallbackReveal()
        }
    }

    /// Reveal text using ElevenLabs character timing data
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

                        if endIndex >= self.fullText.count {
                            self.logger.info("✅ All text revealed")
                            self.complete()
                        }
                    }
                }
            }
        }
    }

    /// Fallback: Reveal text at constant speed without alignment data
    private func startFallbackReveal() {
        logger.info("⏱️ Using fallback reveal at \(fallbackCharsPerSecond) chars/sec")

        let intervalPerChar = 1.0 / fallbackCharsPerSecond

        revealTimer = Timer.scheduledTimer(withTimeInterval: intervalPerChar, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.currentCharIndex < self.fullText.count {
                    self.currentCharIndex += 1
                    self.visibleText = String(self.fullText.prefix(self.currentCharIndex))
                } else {
                    self.complete()
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
