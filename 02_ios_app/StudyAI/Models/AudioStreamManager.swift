//
//  AudioStreamManager.swift
//  StudyAI
//
//  Dedicated Swift Actor for Gemini Live audio playback.
//
//  Responsibilities:
//  - Owns AVAudioEngine + AVAudioPlayerNode for the lifetime of the live session.
//  - Converts incoming Int16 PCM bytes → Float32 using vDSP (Accelerate framework).
//  - Schedules AVAudioPCMBuffer onto the player node entirely off the main thread.
//  - Reports playback state changes back to the caller via async callbacks.
//
//  This isolates all CPU-heavy audio work away from @MainActor so SwiftUI
//  rendering is never blocked by audio processing.
//

import AVFoundation
import Accelerate
import Foundation

// MARK: - AudioStreamManager

/// A Swift Actor that owns the persistent playback engine and handles
/// all Int16 → Float32 conversion + buffer scheduling off the main thread.
actor AudioStreamManager {

    // MARK: - Private Properties

    private let engine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let playbackFormat: AVAudioFormat

    /// Number of AVAudioPCMBuffers that have been scheduled but whose completion
    /// callback has not yet fired. Used to determine when "all audio is done".
    private var pendingBufferCount = 0

    /// Minimum buffers to pre-load before calling player.play() — prevents
    /// choppy cold-start on the first turn.
    private let startThreshold = 3

    /// True once player.play() has been called; reset only on stop/interrupt.
    private var isPlayerStarted = false

    /// Closure called on the main actor when playback drains to zero.
    /// Registered by VoiceChatViewModel to flip isAISpeaking = false.
    nonisolated(unsafe) var onPlaybackDrained: (() -> Void)?

    // MARK: - Init / Deinit

    init() {
        engine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // 24 kHz mono Float32 — AVAudioEngine's native path, zero format conversion.
        playbackFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: playbackFormat)

        do {
            try engine.start()
        } catch {
            print("❌ [AudioStreamManager] engine start failed: \(error)")
        }
    }

    // MARK: - Public API

    /// Decode base64 → Int16 PCM → Float32, then schedule onto the player node.
    /// Returns immediately; all work happens on the actor's executor (background thread).
    func scheduleAudioChunk(base64: String) {
        guard let int16Data = Data(base64Encoded: base64) else {
            print("❌ [AudioStreamManager] failed to base64-decode audio chunk")
            return
        }
        guard !int16Data.isEmpty, int16Data.count % 2 == 0 else { return }

        let frameCount = AVAudioFrameCount(int16Data.count / 2)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount) else {
            print("❌ [AudioStreamManager] failed to allocate PCM buffer")
            return
        }
        buffer.frameLength = frameCount

        guard let dst = buffer.floatChannelData?[0] else { return }

        // vDSP-accelerated Int16 → Float32 conversion (replaces scalar loop)
        // vDSP_vflt16 converts Int16 → Float32, then vDSP_vsdiv normalizes by 32768.
        int16Data.withUnsafeBytes { rawPtr in
            let src = rawPtr.bindMemory(to: Int16.self).baseAddress!
            var tmp = [Float](repeating: 0, count: Int(frameCount))
            // Convert Int16 → Float (range -32768...32767)
            vDSP_vflt16(src, 1, &tmp, 1, vDSP_Length(frameCount))
            // Normalize: divide every element by 32768.0 → range -1.0...1.0
            var divisor: Float = 32768.0
            vDSP_vsdiv(&tmp, 1, &divisor, dst, 1, vDSP_Length(frameCount))
        }

        pendingBufferCount += 1
        let capturedCount = pendingBufferCount

        // Schedule the buffer; completion fires on an arbitrary background thread.
        playerNode.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                await self.bufferDidFinish()
            }
        }

        // Start playback once we have enough pre-buffered data.
        if !isPlayerStarted && capturedCount >= startThreshold {
            isPlayerStarted = true
            playerNode.play()
        }

        // (single-chunk edge case: player will start naturally on the next chunk or drain)
    }

    /// Stop playback immediately (user interrupt or session end).
    /// Does NOT tear down the engine — keeps it alive for the next turn.
    func stopPlayback() {
        playerNode.stop()
        pendingBufferCount = 0
        isPlayerStarted = false
    }

    func tearDown() {
        playerNode.stop()
        engine.stop()
    }

    private func bufferDidFinish() {
        pendingBufferCount = max(0, pendingBufferCount - 1)
        if pendingBufferCount == 0 {
            isPlayerStarted = false
            let callback = onPlaybackDrained
            Task { @MainActor in
                callback?()
            }
        }
    }
}
