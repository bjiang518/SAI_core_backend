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

@MainActor
class InteractiveTTSService: NSObject, ObservableObject {

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
    private var audioFormat: AVAudioFormat!
    private var audioQueue: [AVAudioPCMBuffer] = []
    private var isSchedulingBuffers = false

    // Temporary file tracking for cleanup
    private var tempFiles: Set<URL> = []

    // MARK: - Initialization

    override init() {
        super.init()
        setupAudioEngine()
    }

    deinit {
        // Cleanup temp files synchronously in deinit
        for tempFile in tempFiles {
            try? FileManager.default.removeItem(at: tempFile)
        }
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Standard audio format for MP3 decoded output
        // 44.1kHz stereo (will be converted from MP3 format)
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        )!

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: audioFormat)

        // Configure audio session
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)

            try audioEngine.start()
            logger.debug("✅ AVAudioEngine started successfully for interactive TTS")
        } catch {
            logger.error("❌ Failed to start AVAudioEngine: \(error)")
            errorMessage = "Audio engine initialization failed"
        }
    }

    // MARK: - Audio Processing

    /// Process incoming audio chunk from backend
    /// - Parameter base64Audio: Base64-encoded MP3 audio data
    func processAudioChunk(_ base64Audio: String) {
        Task { @MainActor in
            logger.info("📥 [InteractiveTTS] processAudioChunk called with \(base64Audio.count) chars base64")

            // Ensure audio engine is running
            if !audioEngine.isRunning {
                logger.warning("⚠️ [InteractiveTTS] Audio engine not running, restarting...")
                do {
                    try audioEngine.start()
                    logger.info("✅ [InteractiveTTS] Audio engine restarted")
                } catch {
                    logger.error("❌ [InteractiveTTS] Failed to restart audio engine: \(error)")
                    errorMessage = "Audio engine failed to start"
                    return
                }
            }

            guard let audioData = Data(base64Encoded: base64Audio) else {
                logger.error("❌ Failed to decode base64 audio")
                errorMessage = "Audio decoding failed"
                return
            }

            audioChunksReceived += 1
            logger.info("📥 [InteractiveTTS] Processing audio chunk #\(audioChunksReceived) (\(audioData.count) bytes)")

            // Decode MP3 to PCM buffer
            logger.info("🎵 [InteractiveTTS] Calling decodeMp3ToPCM for chunk #\(audioChunksReceived)...")
            if let pcmBuffer = decodeMp3ToPCM(audioData) {
                audioQueue.append(pcmBuffer)
                logger.info("✅ [InteractiveTTS] Chunk #\(audioChunksReceived) decoded and queued (queue size: \(audioQueue.count))")

                if !isSchedulingBuffers {
                    logger.info("▶️ [InteractiveTTS] Starting buffer scheduling...")
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
        logger.info("🎵 [Decode] decodeMp3ToPCM called with \(mp3Data.count) bytes")

        // Create temporary file for MP3 data (AVAudioFile requires file-based input)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        logger.info("🎵 [Decode] Temp file path: \(tempURL.path)")

        do {
            // Write MP3 data to temp file
            try mp3Data.write(to: tempURL)
            tempFiles.insert(tempURL)
            logger.info("✅ [Decode] MP3 data written to temp file")

            // Open audio file
            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = UInt32(audioFile.length)

            logger.info("✅ [Decode] Audio file opened - \(frameCount) frames, \(audioFile.processingFormat.sampleRate)Hz, \(audioFile.processingFormat.channelCount) channels")

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

            logger.info("✅ [Decode] Read \(frameCount) frames into buffer")

            // Convert to engine format if needed (mono → stereo)
            let finalBuffer: AVAudioPCMBuffer
            if audioFile.processingFormat.channelCount != audioFormat.channelCount {
                logger.info("🔄 [Decode] Converting \(audioFile.processingFormat.channelCount) channel(s) → \(audioFormat.channelCount) channel(s)")

                guard let convertedBuffer = convertBuffer(pcmBuffer, from: audioFile.processingFormat, to: audioFormat) else {
                    logger.error("❌ [Decode] Failed to convert audio format")
                    try? FileManager.default.removeItem(at: tempURL)
                    tempFiles.remove(tempURL)
                    return nil
                }
                logger.info("✅ [Decode] Format conversion successful")
                finalBuffer = convertedBuffer
            } else {
                logger.info("ℹ️ [Decode] No format conversion needed")
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

            logger.info("✅ [Decode] Successfully decoded MP3 → PCM")
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
        logger.info("🔄 [Schedule] scheduleNextBuffer called - queue size: \(audioQueue.count)")

        guard !audioQueue.isEmpty else {
            isSchedulingBuffers = false
            if isPlaying {
                logger.info("🎵 [Schedule] Audio queue empty, playback continuing until last buffer finishes")
            } else {
                logger.info("ℹ️ [Schedule] Audio queue empty and not playing")
            }
            return
        }

        isSchedulingBuffers = true
        let buffer = audioQueue.removeFirst()

        logger.info("📋 [Schedule] Scheduling buffer with \(buffer.frameLength) frames")

        // Schedule buffer with completion handler for chaining
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.logger.info("✅ [Schedule] Buffer playback completed, scheduling next...")
                self?.scheduleNextBuffer()
            }
        }

        // Start playback if not already playing
        if !playerNode.isPlaying {
            logger.info("▶️ [Schedule] Starting audio playback...")
            playerNode.play()
            isPlaying = true
            logger.info("✅ [Schedule] Audio playback started!")
        } else {
            logger.info("ℹ️ [Schedule] Player already playing, buffer added to queue")
        }
    }

    // MARK: - Playback Control

    /// Stop playback and clear queue
    func stopPlayback() {
        playerNode.stop()
        audioQueue.removeAll()
        isSchedulingBuffers = false
        isPlaying = false
        isPaused = false
        audioChunksReceived = 0
        logger.debug("⏹️ Audio playback stopped, queue cleared")
    }

    /// Pause playback (maintains queue)
    func pausePlayback() {
        playerNode.pause()
        isPlaying = false
        isPaused = true
        logger.debug("⏸️ Audio playback paused")
    }

    /// Resume playback
    func resumePlayback() {
        if isPaused && !audioQueue.isEmpty {
            playerNode.play()
            isPlaying = true
            isPaused = false
            logger.debug("▶️ Audio playback resumed")
        }
    }

    /// Reset service for new session
    func reset() {
        stopPlayback()
        audioQueue.removeAll()
        audioChunksReceived = 0
        errorMessage = nil
        logger.debug("🔄 Interactive TTS service reset")
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
