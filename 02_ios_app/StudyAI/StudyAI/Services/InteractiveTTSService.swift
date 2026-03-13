//
//  InteractiveTTSService.swift
//  StudyAI
//
//  Created for Interactive Mode - Phase 3
//  Handles real-time audio playback using AVAudioEngine
//
//  Flow:
//  1. Receive base64 audio chunks from backend
//  2. Decode MP3 → PCM buffers
//  3. Queue buffers in AVAudioEngine
//  4. Play seamlessly with automatic chaining
//

import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
class InteractiveTTSService: NSObject, ObservableObject {

    // MARK: - Debug Mode

    /// Enable verbose logging for debugging (default: false)
    private static let debugMode = false

    // MARK: - Published Properties

    @Published var isPlaying = false
    @Published var isPaused = false
    @Published var currentPlaybackTime: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var audioChunksReceived: Int = 0

    // MARK: - Private Properties

    private let logger = AppLogger.forFeature("InteractiveTTS")

    private var audioEngine: AVAudioEngine!
    private var playerNode: AVAudioPlayerNode!
    private var timePitchNode: AVAudioUnitTimePitch!
    private var audioFormat: AVAudioFormat!
    private var audioQueue: [AVAudioPCMBuffer] = []
    private var isSchedulingBuffers = false

    // Temporary file tracking for cleanup
    private var tempFiles: Set<URL> = []

    // Audio session interruption tracking
    private var wasPlayingBeforeInterruption = false

    // Voice chat coordination flag
    private var isVoiceChatActive = false

    // ✅ NEW: Timing metrics for latency measurement
    private var firstAudioChunkTime: Date?
    private var firstPlaybackStartTime: Date?

    // ✅ NEW: Callback for when audio playback actually completes
    var onPlaybackComplete: (() -> Void)?

    // ✅ NEW: Track if streaming is complete (no more audio coming from backend)
    private var isStreamingComplete = false

    // ✅ Track chunks submitted to inner tasks but not yet decoded/queued
    // Prevents notifyStreamingComplete from firing while decode tasks are still pending
    private var pendingAudioChunks = 0

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioEngine()
        setupAudioInterruptionHandling()
    }

    deinit {
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)

        // Cleanup temp files synchronously in deinit
        for tempFile in tempFiles {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitchNode = AVAudioUnitTimePitch()
        timePitchNode.rate = 1.2

        // Standard audio format for MP3 decoded output
        // 44.1kHz stereo (will be converted from MP3 format)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        )!

        audioEngine.attach(playerNode)
        audioEngine.attach(timePitchNode)
        audioEngine.connect(playerNode, to: timePitchNode, format: audioFormat)
        audioEngine.connect(timePitchNode, to: audioEngine.mainMixerNode, format: audioFormat)

        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)

            try audioEngine.start()
            if Self.debugMode {
            logger.debug("✅ AVAudioEngine started successfully for interactive TTS")
            }
        } catch {
            logger.error("❌ Failed to start AVAudioEngine: \(error)")
            errorMessage = "Audio engine initialization failed"
        }
    }

    private func setupAudioInterruptionHandling() {
        logger.info("🔧 [InteractiveTTS] Setting up audio interruption handling and voice chat coordination")

        // Handle audio session interruptions (phone calls, system sounds, keyboard, etc.)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )

        // Handle audio engine configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: audioEngine
        )

        // Handle app lifecycle
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        // ✅ NEW: Voice chat coordination
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStopInteractiveTTS),
            name: NSNotification.Name("StopInteractiveTTS"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResumeInteractiveTTS),
            name: NSNotification.Name("ResumeInteractiveTTS"),
            object: nil
        )

        logger.info("✅ [InteractiveTTS] All notification observers registered (including voice chat coordination)")
    }

    // MARK: - Audio Interruption Handling

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Audio interruption began (phone call, system sound, keyboard, etc.)
            logger.info("⚠️ [InteractiveTTS] Audio session interruption began")
            wasPlayingBeforeInterruption = isPlaying

            // Pause playback but keep queue
            if isPlaying {
                playerNode.pause()
                isPlaying = false
                isPaused = true
            }

        case .ended:
            // Audio interruption ended - optionally resume
            logger.info("✅ [InteractiveTTS] Audio session interruption ended")

            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

                if options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                    logger.info("▶️ [InteractiveTTS] Resuming playback after interruption")

                    // Try to reactivate audio session and resume
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)

                        // Restart audio engine if needed
                        if !audioEngine.isRunning {
                            try audioEngine.start()
                        }

                        // Resume playback
                        playerNode.play()
                        isPlaying = true
                        isPaused = false

                        // Continue scheduling if queue has items
                        if !audioQueue.isEmpty && !isSchedulingBuffers {
                            scheduleNextBuffer()
                        }
                    } catch {
                        logger.error("❌ [InteractiveTTS] Failed to resume after interruption: \(error)")
                        errorMessage = "Failed to resume audio"
                    }
                }
            }

            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    @objc private func handleAudioEngineConfigurationChange(_ notification: Notification) {
        logger.info("🔔 [InteractiveTTS] Audio engine configuration change detected. isVoiceChatActive = \(isVoiceChatActive)")

        // ✅ Skip restart if voice chat is active
        if isVoiceChatActive {
            logger.info("⏭️ [InteractiveTTS] Skipping audio engine restart - voice chat is active")
            return
        }

        // Audio engine configuration changed (headphones plugged/unplugged, route change)
        logger.warning("⚠️ [InteractiveTTS] Audio engine configuration changed, restarting engine...")

        // Stop current playback
        playerNode.stop()

        // Restart audio engine
        do {
            if audioEngine.isRunning {
                audioEngine.stop()
            }

            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()

            logger.info("✅ [InteractiveTTS] Audio engine restarted after configuration change")

            // Resume playback if there's queue
            if !audioQueue.isEmpty {
                isPlaying = false
                isSchedulingBuffers = false
                scheduleNextBuffer()
            }
        } catch {
            logger.error("❌ [InteractiveTTS] Failed to restart audio engine: \(error)")
            errorMessage = "Audio configuration error"
        }
    }

    @objc private func handleAppWillResignActive(_ notification: Notification) {
        // App going to background - pause playback but keep queue
        logger.info("⚠️ [InteractiveTTS] App will resign active, pausing playback")
        if isPlaying {
            wasPlayingBeforeInterruption = true
            playerNode.pause()
            isPlaying = false
            isPaused = true
        }
    }

    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        // App returning to foreground - resume if was playing
        logger.info("✅ [InteractiveTTS] App did become active")

        if wasPlayingBeforeInterruption && !audioQueue.isEmpty {
            logger.info("▶️ [InteractiveTTS] Resuming playback after app became active")

            do {
                // Reactivate audio session
                try AVAudioSession.sharedInstance().setActive(true)

                // Restart audio engine if needed
                if !audioEngine.isRunning {
                    try audioEngine.start()
                }

                // Resume playback
                playerNode.play()
                isPlaying = true
                isPaused = false

                // Continue scheduling if needed
                if !isSchedulingBuffers {
                    scheduleNextBuffer()
                }

                wasPlayingBeforeInterruption = false
            } catch {
                logger.error("❌ [InteractiveTTS] Failed to resume after app became active: \(error)")
            }
        }
    }

    // MARK: - Voice Chat Coordination

    @objc private func handleStopInteractiveTTS(_ notification: Notification) {
        logger.info("🔇 [InteractiveTTS] Voice chat starting - stopping playback and disabling auto-restart")

        // Set flag to prevent audio engine restarts
        isVoiceChatActive = true

        // Stop playback completely
        stopPlayback()

        // Stop audio engine to release audio session
        if audioEngine.isRunning {
            audioEngine.stop()
            logger.info("🔇 [InteractiveTTS] Audio engine stopped for voice chat")
        }
    }

    @objc private func handleResumeInteractiveTTS(_ notification: Notification) {
        logger.info("🔊 [InteractiveTTS] Voice chat ended - re-enabling audio engine")

        // Clear flag to allow audio engine restarts
        isVoiceChatActive = false

        // Audio engine will restart automatically when next audio chunk arrives
    }

    // MARK: - Audio Processing

    /// Process incoming audio chunk from backend
    /// - Parameter base64Audio: Base64-encoded MP3 audio data
    func processAudioChunk(_ base64Audio: String) {
        // Increment BEFORE the inner task so notifyStreamingComplete() sees it as pending
        pendingAudioChunks += 1
        Task { @MainActor in
            defer { self.pendingAudioChunks -= 1 }  // always decrement when done
            let timestamp = Date()
            let timestampStr = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)

            if Self.debugMode {
                if Self.debugMode {
                logger.info("[\(timestampStr)] 📥 processAudioChunk called with \(base64Audio.count) chars base64")
                }
            }

            // ✅ Track timing for first audio chunk
            if firstAudioChunkTime == nil {
                firstAudioChunkTime = Date()
                if Self.debugMode {
                    if Self.debugMode {
                    logger.info("[\(timestampStr)] ⏱️ [TIMING] First audio chunk received")
                    }
                }
            }

            // Ensure audio engine is running
            if !audioEngine.isRunning {
                logger.warning("[\(timestampStr)] ⚠️ [InteractiveTTS] Audio engine NOT RUNNING - attempting restart...")
                do {
                    // Reactivate audio session first
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setActive(true)
                    logger.info("[\(timestampStr)] ✅ Audio session reactivated")

                    try audioEngine.start()
                    logger.info("[\(timestampStr)] ✅ Audio engine restarted successfully")
                } catch {
                    logger.error("[\(timestampStr)] ❌ Failed to restart audio engine: \(error)")
                    errorMessage = "Audio engine failed to start"
                    return
                }
            } else {
                if Self.debugMode {
                    logger.info("[\(timestampStr)] ✅ Audio engine running")
                }
            }

            guard let audioData = Data(base64Encoded: base64Audio) else {
                logger.error("❌ Failed to decode base64 audio")
                errorMessage = "Audio decoding failed"
                return
            }

            audioChunksReceived += 1
            if Self.debugMode {
                if Self.debugMode {
                logger.info("📥 [InteractiveTTS] Processing audio chunk #\(audioChunksReceived) (\(audioData.count) bytes)")
                }
            }

            // Decode MP3 to PCM buffer
            if Self.debugMode {
                if Self.debugMode {
                logger.info("🎵 [InteractiveTTS] Calling decodeMp3ToPCM for chunk #\(audioChunksReceived)...")
                }
            }
            if let pcmBuffer = decodeMp3ToPCM(audioData) {
                audioQueue.append(pcmBuffer)
                if Self.debugMode {
                    if Self.debugMode {
                    logger.info("✅ [InteractiveTTS] Chunk #\(audioChunksReceived) decoded and queued (queue size: \(audioQueue.count))")
                    }
                }

                if !isSchedulingBuffers {
                    if Self.debugMode {
                        if Self.debugMode {
                        logger.info("▶️ [InteractiveTTS] Starting buffer scheduling...")
                        }
                    }
                    scheduleNextBuffer()
                }
            } else {
                logger.error("❌ [InteractiveTTS] Failed to decode MP3 audio chunk #\(audioChunksReceived)")
                errorMessage = "MP3 decoding failed"
            }
        }
    }

    /// Decode MP3 data to PCM buffer
    /// - Parameter mp3Data: Raw MP3 audio data
    /// - Returns: PCM buffer ready for playback, or nil if decoding fails
    private func decodeMp3ToPCM(_ mp3Data: Data) -> AVAudioPCMBuffer? {
        if Self.debugMode {
            if Self.debugMode {
            logger.info("🎵 [Decode] decodeMp3ToPCM called with \(mp3Data.count) bytes")
            }
        }

        // Create temporary file for MP3 data (AVAudioFile requires file-based input)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        if Self.debugMode {
        logger.info("🎵 [Decode] Temp file path: \(tempURL.path)")
        }

        do {
            // Write MP3 data to temp file
            try mp3Data.write(to: tempURL)
            tempFiles.insert(tempURL)
            if Self.debugMode {
            logger.info("✅ [Decode] MP3 data written to temp file")
            }

            // Open audio file
            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = UInt32(audioFile.length)

            if Self.debugMode {
            logger.info("✅ [Decode] Audio file opened - \(frameCount) frames, \(audioFile.processingFormat.sampleRate)Hz, \(audioFile.processingFormat.channelCount) channels")
            }

            // Create PCM buffer matching the file's format
            guard let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else {
                logger.error("❌ [Decode] Failed to create PCM buffer")
                try? FileManager.default.removeItem(at: tempURL)
                tempFiles.remove(tempURL)
                return nil
            }

            // Read audio file into buffer
            try audioFile.read(into: pcmBuffer)
            pcmBuffer.frameLength = frameCount

            if Self.debugMode {
            logger.info("✅ [Decode] Read \(frameCount) frames into buffer")
            }

            // Convert to engine format if needed (mono → stereo)
            let finalBuffer: AVAudioPCMBuffer
            if audioFile.processingFormat.channelCount != audioFormat.channelCount {
                if Self.debugMode {
                logger.info("🔄 [Decode] Converting \(audioFile.processingFormat.channelCount) channel(s) → \(audioFormat.channelCount) channel(s)")
                }

                guard let convertedBuffer = convertBuffer(pcmBuffer, from: audioFile.processingFormat, to: audioFormat) else {
                    logger.error("❌ [Decode] Failed to convert audio format")
                    try? FileManager.default.removeItem(at: tempURL)
                    tempFiles.remove(tempURL)
                    return nil
                }
                if Self.debugMode {
                logger.info("✅ [Decode] Format conversion successful")
                }
                finalBuffer = convertedBuffer
            } else {
                if Self.debugMode {
                logger.info("ℹ️ [Decode] No format conversion needed")
                }
                finalBuffer = pcmBuffer
            }

            // Schedule cleanup of temp file after a delay
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    tempFiles.remove(tempURL)
                }
            }

            if Self.debugMode {
            logger.info("✅ [Decode] Successfully decoded MP3 → PCM")
            }
            return finalBuffer

        } catch {
            logger.error("❌ [Decode] MP3 decode error: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            tempFiles.remove(tempURL)
            return nil
        }
    }

    /// Convert audio buffer from one format to another (e.g., mono → stereo)
    /// - Parameters:
    ///   - buffer: Source PCM buffer
    ///   - sourceFormat: Source audio format
    ///   - targetFormat: Target audio format
    /// - Returns: Converted buffer, or nil if conversion fails
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            logger.error("❌ Failed to create audio converter")
            return nil
        }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            logger.error("❌ Failed to create converted buffer")
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            logger.error("❌ Audio conversion error: \(error)")
            return nil
        }

        convertedBuffer.frameLength = convertedBuffer.frameCapacity
        return convertedBuffer
    }

    /// Schedule next buffer for playback
    private func scheduleNextBuffer() {
        let timestamp = Date()
        let timestampStr = DateFormatter.localizedString(from: timestamp, dateStyle: .none, timeStyle: .medium)

        if Self.debugMode {
        logger.info("[\(timestampStr)] 🔄 scheduleNextBuffer - queue size: \(audioQueue.count), streaming complete: \(isStreamingComplete)")
        }

        guard !audioQueue.isEmpty else {
            isSchedulingBuffers = false

            // Only complete if streaming is done AND all decode tasks have finished
            if isStreamingComplete && pendingAudioChunks == 0 {
                logger.info("[\(timestampStr)] 🏁 Queue empty + streaming complete + no pending chunks = Audio playback finished!")
                isPlaying = false
                onPlaybackComplete?()
            } else if isStreamingComplete {
                logger.info("[\(timestampStr)] ⏸️ Queue empty, streaming complete but \(pendingAudioChunks) chunks still decoding — waiting...")
            } else {
                // Queue empty but more audio may be coming
                logger.info("[\(timestampStr)] ⏸️ Queue empty but streaming NOT complete - waiting for more audio...")
            }

            return
        }

        isSchedulingBuffers = true
        let buffer = audioQueue.removeFirst()

        if Self.debugMode {
        logger.info("📋 [Schedule] Scheduling buffer with \(buffer.frameLength) frames")
        }

        // Schedule buffer with completion handler for chaining
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }

                // Check if audio engine is still running and not interrupted
                guard self.audioEngine.isRunning else {
                    self.logger.warning("⚠️ [Schedule] Audio engine not running in completion handler, skipping next buffer")
                    self.isSchedulingBuffers = false
                    self.isPlaying = false
                    return
                }

                // Check if we're not paused/interrupted
                guard !self.isPaused else {
                    self.logger.info("⏸️ [Schedule] Playback paused, not scheduling next buffer")
                    self.isSchedulingBuffers = false
                    return
                }

                self.logger.info("✅ [Schedule] Buffer playback completed, scheduling next...")
                self.scheduleNextBuffer()
            }
        }

        // Start playback if not already playing
        if !playerNode.isPlaying {
            if Self.debugMode {
            logger.info("▶️ [Schedule] Starting audio playback...")
            }

            // ✅ Track timing for first playback start
            if firstPlaybackStartTime == nil {
                firstPlaybackStartTime = Date()
                if let firstChunkTime = firstAudioChunkTime {
                    let latency = Date().timeIntervalSince(firstChunkTime) * 1000
                    if Self.debugMode {
                    logger.info("⏱️ [TIMING] First playback started - Latency from first chunk: \(Int(latency))ms")
                    }
                } else {
                    if Self.debugMode {
                    logger.info("⏱️ [TIMING] First playback started")
                    }
                }
            }

            // Ensure audio session is active before playing
            do {
                let audioSession = AVAudioSession.sharedInstance()
                if !audioSession.isOtherAudioPlaying {
                    try audioSession.setActive(true)
                    if Self.debugMode {
                    logger.info("✅ [Schedule] Audio session activated")
                    }
                }
            } catch {
                logger.error("❌ [Schedule] Failed to activate audio session: \(error)")
            }

            playerNode.play()
            isPlaying = true
            let playTs = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            logger.info("[\(playTs)] ▶️ [AUDIO TIMELINE] isPlaying → true (playback started)")
        } else {
            if Self.debugMode {
            logger.info("ℹ️ [Schedule] Player already playing, buffer added to queue")
            }
        }
    }

    // MARK: - Playback Control

    /// Notify that streaming is complete (no more audio chunks coming from backend)
    /// This allows the service to trigger completion when the last buffer finishes
    func notifyStreamingComplete() {
        isStreamingComplete = true
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logger.info("[\(ts)] 🏁 [Streaming] Backend signaled streaming complete (pendingChunks=\(pendingAudioChunks), queue=\(audioQueue.count), scheduling=\(isSchedulingBuffers), playing=\(isPlaying))")

        // Only complete immediately if all decode tasks have finished AND the queue is empty
        // If pendingAudioChunks > 0, the decode tasks haven't run yet (Task ordering race) —
        // scheduleNextBuffer() will fire completion once the last decoded buffer drains.
        if audioQueue.isEmpty && !isSchedulingBuffers && pendingAudioChunks == 0 && !isPlaying {
            logger.info("[\(ts)] 🏁 [Streaming] No audio in flight — completing immediately")
            onPlaybackComplete?()
        }
    }

    /// Stop playback and clear queue
    func stopPlayback() {
        playerNode.stop()
        audioQueue.removeAll()
        isSchedulingBuffers = false
        isPlaying = false
        isPaused = false
        audioChunksReceived = 0
        if Self.debugMode {
        logger.debug("⏹️ Audio playback stopped, queue cleared")
        }
    }

    /// Pause playback (maintains queue)
    func pausePlayback() {
        playerNode.pause()
        isPlaying = false
        isPaused = true
        if Self.debugMode {
        logger.debug("⏸️ Audio playback paused")
        }
    }

    /// Resume playback
    func resumePlayback() {
        if isPaused && !audioQueue.isEmpty {
            playerNode.play()
            isPlaying = true
            isPaused = false
            if Self.debugMode {
            logger.debug("▶️ Audio playback resumed")
            }
        }
    }

    /// Reset service for new session
    func reset() {
        stopPlayback()
        audioQueue.removeAll()
        audioChunksReceived = 0
        errorMessage = nil

        // ✅ Reset timing metrics
        firstAudioChunkTime = nil
        firstPlaybackStartTime = nil

        // ✅ Reset streaming complete flag
        isStreamingComplete = false
        pendingAudioChunks = 0

        // ❌ DON'T clear callback - it's persistent across sessions
        // onPlaybackComplete should remain set for all interactive sessions

        if Self.debugMode {
        logger.debug("🔄 Interactive TTS service reset")
        }
    }

    // MARK: - Metrics

    func getMetrics() -> [String: Any] {
        return [
            "isPlaying": isPlaying,
            "isPaused": isPaused,
            "audioChunksReceived": audioChunksReceived,
            "queueLength": audioQueue.count
        ]
    }
}
