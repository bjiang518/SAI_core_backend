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
            guard let audioData = Data(base64Encoded: base64Audio) else {
                logger.error("❌ Failed to decode base64 audio")
                errorMessage = "Audio decoding failed"
                return
            }

            audioChunksReceived += 1
            logger.debug("📥 Processing audio chunk #\(audioChunksReceived) (\(audioData.count) bytes)")

            // Decode MP3 to PCM buffer
            if let pcmBuffer = decodeMp3ToPCM(audioData) {
                audioQueue.append(pcmBuffer)
                logger.debug("📥 Audio chunk #\(audioChunksReceived) queued (\(audioQueue.count) in queue)")

                if !isSchedulingBuffers {
                    scheduleNextBuffer()
                }
            } else {
                logger.error("❌ Failed to decode MP3 audio chunk #\(audioChunksReceived)")
                errorMessage = "MP3 decoding failed"
            }
        }
    }

    /// Decode MP3 data to PCM buffer
    /// - Parameter mp3Data: Raw MP3 audio data
    /// - Returns: PCM buffer ready for playback, or nil if decoding fails
    private func decodeMp3ToPCM(_ mp3Data: Data) -> AVAudioPCMBuffer? {
        // Create temporary file for MP3 data (AVAudioFile requires file-based input)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")

        do {
            // Write MP3 data to temp file
            try mp3Data.write(to: tempURL)
            tempFiles.insert(tempURL)

            // Open audio file
            let audioFile = try AVAudioFile(forReading: tempURL)
            let frameCount = UInt32(audioFile.length)

            // Create PCM buffer matching the file's format
            guard let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else {
                logger.error("❌ Failed to create PCM buffer")
                try? FileManager.default.removeItem(at: tempURL)
                tempFiles.remove(tempURL)
                return nil
            }

            // Read audio file into buffer
            try audioFile.read(into: pcmBuffer)
            pcmBuffer.frameLength = frameCount

            logger.debug("✅ Decoded MP3 → PCM: \(frameCount) frames, \(audioFile.processingFormat.sampleRate)Hz")

            // Schedule cleanup of temp file after a delay
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    tempFiles.remove(tempURL)
                }
            }

            return pcmBuffer

        } catch {
            logger.error("❌ MP3 decode error: \(error)")
            try? FileManager.default.removeItem(at: tempURL)
            tempFiles.remove(tempURL)
            return nil
        }
    }

    /// Schedule next buffer for playback
    private func scheduleNextBuffer() {
        guard !audioQueue.isEmpty else {
            isSchedulingBuffers = false
            if isPlaying {
                logger.debug("🎵 Audio queue empty, playback continuing until last buffer finishes")
            }
            return
        }

        isSchedulingBuffers = true
        let buffer = audioQueue.removeFirst()

        // Schedule buffer with completion handler for chaining
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.scheduleNextBuffer()
            }
        }

        // Start playback if not already playing
        if !playerNode.isPlaying {
            playerNode.play()
            isPlaying = true
            logger.debug("▶️ Audio playback started")
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
