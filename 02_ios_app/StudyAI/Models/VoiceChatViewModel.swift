//
//  VoiceChatViewModel.swift
//  StudyAI
//
//  Gemini Live API Voice Chat ViewModel
//  Manages WebSocket connection and bidirectional audio streaming
//

import Foundation
import AVFoundation
import Combine
import UIKit

@MainActor
class VoiceChatViewModel: ObservableObject {

    // MARK: - Published State

    /// All voice messages in the conversation
    @Published var messages: [VoiceMessage] = []

    /// Current recording state
    @Published var isRecording = false

    /// AI is currently speaking
    @Published var isAISpeaking = false

    /// Live transcription of AI response (updated in real-time)
    @Published var liveTranscription = ""

    /// Connection status
    @Published var connectionState: ConnectionState = .disconnected

    /// Error message to display
    @Published var errorMessage: String?

    /// Recording level for visual feedback (0.0 to 1.0)
    @Published var recordingLevel: Float = 0.0

    /// True while an image is being serialized + sent over WebSocket.
    /// UI shows a "Sending image…" banner and recording is paused during this window.
    @Published var isSendingImage = false

    /// True when the Live session was interrupted (app backgrounded / WebSocket dropped)
    /// and needs the user to tap "Tap to Reactivate" before voice input is re-enabled.
    @Published var isSessionSuspended = false

    // MARK: - Private Properties

    /// WebSocket connection to backend
    private var webSocket: URLSessionWebSocketTask?

    /// Timer for client-side WebSocket keepalive pings (prevents Railway proxy from closing idle connections)
    private var keepAliveTimer: Timer?

    /// Audio engine for recording
    private var audioEngine: AVAudioEngine?

    /// Dedicated background actor for audio playback (persistent across turns)
    private var audioStreamManager: AudioStreamManager?

    /// Timer for recording level updates
    private var levelTimer: Timer?

    /// Current session ID
    private let sessionId: String

    /// Subject for the session
    private let subject: String

    /// Network service
    private let networkService = NetworkService.shared

    /// Authentication service
    private let authService = AuthenticationService.shared

    /// Logger
    private let logger = AppLogger.forFeature("VoiceChat")

    /// Cancellables
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Recording Capture (for voice bubble playback)

    /// Completed user recordings keyed by recording UUID.
    /// SessionChatView observes messages.count changes and drains this dict
    /// to pair each new user VoiceMessage with its raw PCM data.
    @Published var completedUserRecordings: [UUID: Data] = [:]

    /// UUID assigned to the recording that is currently in progress
    private var currentRecordingID: UUID?

    /// Accumulates 16-bit PCM bytes from the audio tap during recording.
    /// Protected by recordingBufferQueue — mutated from audio thread and main thread.
    private var currentRecordingBuffer = Data()

    /// Serial queue that serializes all access to currentRecordingBuffer and currentRecordingID
    /// from both the audio tap (background thread) and startRecording/stopRecording (main thread).
    private let recordingBufferQueue = DispatchQueue(label: "com.studyai.recordingBuffer")

    /// ID of the most recent user placeholder bubble waiting for transcription
    private var pendingUserMessageID: UUID?

    /// When true the audio tap captures and sends data; false = engine warm but discarding
    private var isCapturing = false

    // MARK: - Connection State

    enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Initialization

    init(sessionId: String, subject: String) {
        self.sessionId = sessionId
        self.subject = subject

        logger.info("VoiceChatViewModel initialized for session: \(sessionId), subject: \(subject)")

        // Request microphone permission on init
        requestMicrophonePermission()
    }

    // MARK: - Public Methods

    /// Connect to Gemini Live WebSocket
    func connectToGeminiLive() {
        guard let token = authService.getAuthToken() else {
            errorMessage = "Authentication token not found"
            connectionState = .error("Not authenticated")
            return
        }

        connectionState = .connecting

        // ✅ CRITICAL: Stop InteractiveTTS to avoid audio engine conflicts
        // InteractiveTTS will be restarted when we disconnect
        logger.info("🔇 Stopping InteractiveTTS to prevent audio conflicts...")
        NotificationCenter.default.post(name: NSNotification.Name("StopInteractiveTTS"), object: nil)

        // ✅ Configure audio session for bidirectional voice chat ONCE
        logger.info("🔊 Configuring audio session for bidirectional voice chat (.playAndRecord mode)")
        configureAudioSession(for: .playAndRecord)

        // ✅ Pre-warm audio engine so first recording has zero startup latency
        prewarmAudioEngine()

        // ✅ Create persistent AudioStreamManager (lives for the full session)
        let manager = AudioStreamManager()
        audioStreamManager = manager
        // Wire the drain callback back to @MainActor to update isAISpeaking
        manager.onPlaybackDrained = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only clear isAISpeaking if we didn't already stop intentionally
                if self.isAISpeaking {
                    self.isAISpeaking = false
                    self.logger.info("✅ AudioStreamManager drain → isAISpeaking = false")
                }
            }
        }

        // Build WebSocket URL
        let baseURL = networkService.apiBaseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")

        guard let wsURL = URL(string: "\(baseURL)/api/ai/gemini-live/connect?token=\(token)&sessionId=\(sessionId)") else {
            errorMessage = "Invalid WebSocket URL"
            connectionState = .error("Invalid URL")
            return
        }

        logger.info("Connecting to Gemini Live: \(wsURL.absoluteString)")

        // Create WebSocket task
        webSocket = URLSession.shared.webSocketTask(with: wsURL)
        webSocket?.resume()

        // Send WebSocket ping every 10s to keep Railway proxy connection alive
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self, let ws = self.webSocket else { return }
            ws.sendPing { error in
                if let error = error {
                    self.logger.warning("Keepalive ping failed: \(error.localizedDescription)")
                }
            }
        }

        // Start session
        sendWebSocketMessage(type: "start_session", data: [
            "subject": subject,
            "language": getCurrentLanguage()
        ])

        // Start receiving messages
        receiveWebSocketMessages()

        connectionState = .connected
    }

    /// Disconnect from Gemini Live
    func disconnect() {
        logger.info("Disconnecting from Gemini Live")

        // Stop keepalive pings
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil

        // Send end session message
        sendWebSocketMessage(type: "end_session", data: [:])

        // Close WebSocket
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil

        // Stop audio — stop capturing, tear down recording engine, tear down playback actor
        isCapturing = false
        stopAudioEngine()
        if let manager = audioStreamManager {
            Task.detached { await manager.tearDown() }
            audioStreamManager = nil
        }

        // ✅ Re-enable InteractiveTTS now that voice chat is done
        logger.info("🔊 Re-enabling InteractiveTTS after voice chat...")
        NotificationCenter.default.post(name: NSNotification.Name("ResumeInteractiveTTS"), object: nil)

        connectionState = .disconnected
    }

    /// Reconnect to Gemini Live after a tab-switch interruption.
    /// Keeps existing messages visible; creates a fresh WebSocket + Gemini session.
    func reconnect() {
        logger.info("🔄 Reconnecting to Gemini Live after suspension")
        isSessionSuspended = false

        // Tear down any stale socket without clearing messages or audio storage
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        if let manager = audioStreamManager {
            Task.detached { await manager.tearDown() }
            audioStreamManager = nil
        }

        // Re-run the full connect sequence (re-warms audio, creates new WS + AudioStreamManager)
        connectToGeminiLive()
    }

    /// Start recording from microphone
    func startRecording() {
        guard !isRecording else { return }

        logger.info("🎙️ Starting microphone recording")

        isRecording = true
        errorMessage = nil

        // Clear pending ID so previous bubble stops receiving transcription updates
        pendingUserMessageID = nil

        // Reset the PCM buffer on the recording queue (serialized with the tap closure)
        let newID = UUID()
        recordingBufferQueue.sync {
            self.currentRecordingID = newID
            self.currentRecordingBuffer = Data()
        }

        if audioEngine != nil {
            // Engine already pre-warmed — flip gate to start capturing immediately (zero latency)
            isCapturing = true
            logger.info("✅ Audio capture started (pre-warmed engine, zero latency)")
        } else {
            // Fallback: engine wasn't pre-warmed, start it now
            do {
                try startAudioEngine()
                logger.info("✅ Audio engine started for recording (cold start)")
            } catch {
                logger.error("❌ Failed to start audio engine: \(error)")
                errorMessage = "Failed to start recording: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    /// Cancel recording — discard audio, no bubble, no send
    func cancelRecording() {
        guard isRecording else { return }
        logger.info("🎙️ Recording cancelled by user (slide to cancel)")

        isRecording = false
        isCapturing = false

        // Discard the buffer on the recording queue
        recordingBufferQueue.sync {
            self.currentRecordingID = nil
            self.currentRecordingBuffer = Data()
        }

        recordingLevel = 0.0
        levelTimer?.invalidate()
        levelTimer = nil

        // No placeholder bubble, no audio_stream_end — just drop everything
        logger.info("Recording cancelled — buffer discarded")
    }

    /// Stop recording
    func stopRecording() {
        guard isRecording else { return }

        logger.info("Stopping microphone recording")

        isRecording = false

        // Stop capturing first so tap stops appending after we read the buffer
        isCapturing = false

        // Drain the buffer on the recording queue to get a consistent snapshot
        var capturedID: UUID?
        var capturedData = Data()
        recordingBufferQueue.sync {
            capturedID = self.currentRecordingID
            capturedData = self.currentRecordingBuffer
            self.currentRecordingID = nil
            self.currentRecordingBuffer = Data()
        }

        // Save accumulated PCM recording for voice bubble playback
        if let recordingID = capturedID, !capturedData.isEmpty {
            completedUserRecordings[recordingID] = capturedData
        }

        // Immediately append a placeholder bubble — text updated when transcription arrives
        let placeholder = VoiceMessage(role: .user, text: "", isVoice: true)
        messages.append(placeholder)
        pendingUserMessageID = placeholder.id

        // Send audio_stream_end to flush cached audio on backend
        sendWebSocketMessage(type: "audio_stream_end", data: [:])

        recordingLevel = 0.0

        // Stop level timer
        levelTimer?.invalidate()
        levelTimer = nil
    }

    /// Interrupt AI speaking — stops audio and commits any partial text as a completed bubble.
    func interruptAI() {
        logger.info("Interrupting AI")

        // Commit partial transcription so text stays on screen as a completed message
        if !liveTranscription.isEmpty {
            messages.append(VoiceMessage(role: .assistant, text: liveTranscription, isVoice: true))
            liveTranscription = ""
        }

        isAISpeaking = false

        // Stop playback on the actor — engine stays alive for next turn (no teardown)
        if let manager = audioStreamManager {
            Task.detached { await manager.stopPlayback() }
        }

        // Send interrupt signal
        sendWebSocketMessage(type: "interrupt", data: [:])
    }

    /// Send a text message (alongside voice)
    func sendTextMessage(_ text: String) {
        logger.info("Sending text message: \(text)")

        // Add user message to conversation
        messages.append(VoiceMessage(role: .user, text: text, isVoice: false))

        // Send to backend
        sendWebSocketMessage(type: "text_message", data: ["text": text])
    }

    /// Send an image to Gemini Live.
    /// - Scales to long-edge 1024px (optimal Gemini vision resolution).
    /// - Encodes as JPEG @ 0.8 quality (~100-200 KB).
    /// - Pauses audio capture for the duration of the upload to avoid
    ///   head-of-line blocking on the uplink WebSocket connection.
    func sendImage(_ image: UIImage) {
        logger.info("📸 Sending image to Gemini Live")

        // Scale so the long edge is at most 1024px (Gemini vision sweet-spot)
        let maxDimension: CGFloat = 1024
        let size = image.size
        let scale = min(maxDimension / max(size.width, size.height), 1.0)
        let targetSize = CGSize(width: (size.width * scale).rounded(),
                                height: (size.height * scale).rounded())

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.8) else {
            logger.error("❌ Failed to encode image as JPEG")
            errorMessage = "Failed to encode image"
            return
        }

        let base64 = jpegData.base64EncodedString()
        logger.info("📸 Image encoded: \(jpegData.count / 1024) KB, \(Int(targetSize.width))×\(Int(targetSize.height))px")

        // Add a user bubble carrying the JPEG data so it renders as an image in the chat
        messages.append(VoiceMessage(role: .user, text: "", isVoice: false, imageData: jpegData))

        // Pause audio capture so the large WebSocket frame doesn't block incoming audio chunks
        let wasCapturing = isCapturing
        isCapturing = false
        isSendingImage = true

        sendWebSocketMessage(type: "image_message", data: [
            "imageBase64": base64,
            "mimeType": "image/jpeg"
        ])

        // Resume capture immediately after the send call returns — the WS send is async
        // so there's no guarantee the frame is fully flushed, but the main thread is
        // unblocked and audio can resume on the next engine tap cycle.
        isSendingImage = false
        if wasCapturing { isCapturing = true }
    }

    // MARK: - WebSocket Communication

    private func sendWebSocketMessage(type: String, data: [String: Any]) {
        var payload = data
        payload["type"] = type

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("Failed to serialize WebSocket message")
            return
        }

        webSocket?.send(.string(jsonString)) { error in
            if let error = error {
                self.logger.error("WebSocket send error: \(error)")
                Task { @MainActor in
                    self.errorMessage = "Failed to send message"
                }
            }
        }
    }

    private func receiveWebSocketMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    // Fast path: route audio_chunk directly to AudioStreamManager
                    // off the main thread — no @MainActor contention during audio processing.
                    if text.contains("\"audio_chunk\""),
                       let msgData = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: msgData) as? [String: Any],
                       let base64 = json["data"] as? String,
                       let manager = self.audioStreamManager {
                        Task.detached(priority: .userInitiated) {
                            await manager.scheduleAudioChunk(base64: base64)
                        }
                        // Still set isAISpeaking on main actor (lightweight, non-blocking)
                        Task { @MainActor in
                            self.isAISpeaking = true
                        }
                    } else {
                        // All non-audio messages go to handleWebSocketMessage on main actor
                        Task { @MainActor in
                            self.handleWebSocketMessage(text)
                        }
                    }
                case .data(let data):
                    self.logger.debug("Received binary data: \(data.count) bytes")
                @unknown default:
                    break
                }

                // Continue listening
                self.receiveWebSocketMessages()

            case .failure(let error):
                self.logger.error("WebSocket receive error: \(error)")
                Task { @MainActor in
                    self.connectionState = .error(error.localizedDescription)
                    self.errorMessage = "Connection lost"
                    // Mark session as suspended so UI shows "Tap to Reactivate"
                    self.isSessionSuspended = true
                }
            }
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            logger.error("Failed to parse WebSocket message")
            return
        }

        logger.debug("Received WebSocket message type: \(type)")

        switch type {
        case "session_ready":
            logger.info("Gemini Live session ready")
            errorMessage = nil

        case "text_chunk":
            if let textChunk = json["text"] as? String {
                liveTranscription += textChunk
                isAISpeaking = true
            } else {
                logger.error("text_chunk message missing 'text' field")
            }

        case "user_transcription":
            // Transcription is context-only — update the pending bubble caption if available.
            // Multiple streaming chunks may arrive; all update the same bubble in-place.
            // Never create a new bubble from transcription — bubbles are local-only (stopRecording).
            if let userText = json["text"] as? String,
               let pendingID = pendingUserMessageID,
               let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                messages[idx].text = userText
            }

        case "audio_chunk":
            // audio_chunk is handled in receiveWebSocketMessages() fast path.
            // If it falls through here, route it to the actor.
            if let audioBase64 = json["data"] as? String,
               let manager = audioStreamManager {
                Task.detached(priority: .userInitiated) {
                    await manager.scheduleAudioChunk(base64: audioBase64)
                }
                isAISpeaking = true
            }

        case "turn_complete":
            if !liveTranscription.isEmpty {
                messages.append(VoiceMessage(
                    role: .assistant,
                    text: liveTranscription,
                    isVoice: true
                ))
                liveTranscription = ""
            }
            // Do NOT set isAISpeaking = false here.
            // AudioStreamManager's drain callback does it once all buffered audio finishes,
            // preventing the speaking indicator from disappearing before the last sample plays.

        case "interrupted":
            logger.info("AI interrupted by user")

        case "session_ended":
            logger.info("Gemini Live session ended by server")
            connectionState = .disconnected
            // Mark as suspended so UI shows "Tap to Reactivate" rather than silently breaking
            if !isSessionSuspended { isSessionSuspended = true }

        case "error":
            if let errorMsg = json["error"] as? String {
                logger.error("Server error: \(errorMsg)")
                errorMessage = errorMsg
            }

        default:
            logger.warning("Unknown message type '\(type)'")
        }
    }

    // MARK: - Audio Recording

    private func startAudioEngine() throws {
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else { return }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        logger.info("Audio format: \(recordingFormat)")

        // Install tap to capture audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // ✅ Voice Activity Detection: Calculate audio level first
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frames = buffer.frameLength
            var sum: Float = 0

            for i in 0..<Int(frames) {
                sum += abs(channelData[i])
            }

            let average = sum / Float(frames)
            let scaledLevel = min(average * 10, 1.0)

            // Update UI level
            Task { @MainActor in
                self.recordingLevel = scaledLevel
            }

            // ✅ CRITICAL: Only send audio if level exceeds threshold (filter background noise)
            // Threshold: 0.02 = ~2% of max volume (filters silence and background noise)
            let silenceThreshold: Float = 0.02

            guard scaledLevel > silenceThreshold else {
                // Skip sending - this is just background noise
                return
            }

            // Convert to 16-bit PCM at 24kHz (Gemini Live format)
            if let convertedData = self.convertAudioToGeminiFormat(buffer: buffer) {
                let base64Audio = convertedData.base64EncodedString()

                // Accumulate PCM bytes for voice bubble playback
                self.currentRecordingBuffer.append(convertedData)

                // Send to backend
                Task { @MainActor in
                    self.sendWebSocketMessage(type: "audio_chunk", data: ["audio": base64Audio])
                }
            }
        }

        try audioEngine.start()

        // Start level monitoring
        startLevelMonitoring()
    }

    /// Start engine immediately with tap installed but capturing disabled.
    /// This pre-warms the hardware so startRecording() has zero latency.
    private func prewarmAudioEngine() {
        guard audioEngine == nil else { return }
        do {
            audioEngine = AVAudioEngine()
            guard let engine = audioEngine else { return }
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                guard let self, self.isCapturing else { return }
                // Same processing as startAudioEngine tap — reuse existing logic
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frames = buffer.frameLength
                var sum: Float = 0
                for i in 0..<Int(frames) { sum += abs(channelData[i]) }
                let scaledLevel = min((sum / Float(frames)) * 10, 1.0)
                Task { @MainActor in self.recordingLevel = scaledLevel }
                let silenceThreshold: Float = 0.02
                guard scaledLevel > silenceThreshold else { return }
                if let convertedData = self.convertAudioToGeminiFormat(buffer: buffer) {
                    // Append to buffer inside the serial queue to avoid data race with
                    // startRecording() resetting the buffer on the main thread.
                    self.recordingBufferQueue.async {
                        self.currentRecordingBuffer.append(convertedData)
                    }
                    let base64Audio = convertedData.base64EncodedString()
                    Task { @MainActor in
                        self.sendWebSocketMessage(type: "audio_chunk", data: ["audio": base64Audio])
                    }
                }
            }
            try engine.start()
            logger.info("🎙️ Audio engine pre-warmed")
        } catch {
            logger.error("❌ Audio engine pre-warm failed: \(error)")
            audioEngine = nil
        }
    }

    private func stopAudioEngine() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    private func convertAudioToGeminiFormat(buffer: AVAudioPCMBuffer) -> Data? {
        // Gemini Live expects 16-bit PCM at 24kHz
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )

        guard let targetFormat = targetFormat,
              let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return nil
        }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            logger.error("Audio conversion error: \(error)")
            return nil
        }

        // Convert to Data
        let audioBuffer = convertedBuffer.audioBufferList.pointee.mBuffers
        return Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }

    private func calculateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }

        let frames = buffer.frameLength
        var sum: Float = 0

        for i in 0..<Int(frames) {
            sum += abs(channelData[i])
        }

        let average = sum / Float(frames)

        Task { @MainActor in
            self.recordingLevel = min(average * 10, 1.0) // Scale and clamp to 0-1
        }
    }

    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Level is updated in calculateAudioLevel
        }
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession(for mode: AudioSessionMode) {
        let audioSession = AVAudioSession.sharedInstance()

        logger.info("🔧 Configuring audio session for mode: \(mode)")

        do {
            switch mode {
            case .recording:
                logger.info("   Setting category: .record, mode: .measurement")
                try audioSession.setCategory(.record, mode: .measurement, options: [])
            case .playback:
                logger.info("   Setting category: .playback, mode: .spokenAudio")
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            case .playAndRecord:
                logger.info("   Setting category: .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth]")
                // Use .default mode (not .voiceChat) — .voiceChat forces earpiece routing
                // regardless of .defaultToSpeaker. .default respects .defaultToSpeaker.
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            }

            try audioSession.setActive(true)
            logger.info("✅ Audio session configured successfully and activated")
        } catch {
            logger.error("❌ Failed to configure audio session: \(error)")
        }
    }

    private enum AudioSessionMode {
        case recording
        case playback
        case playAndRecord
    }

    // MARK: - Microphone Permission

    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                Task { @MainActor in
                    self.errorMessage = "Microphone permission is required for voice chat"
                }
            }
        }
    }

    // MARK: - Utilities

    private func getCurrentLanguage() -> String {
        let preferredLanguage = Locale.preferredLanguages.first ?? "en"

        if preferredLanguage.hasPrefix("zh") {
            if preferredLanguage.contains("Hans") {
                return "zh-Hans"
            } else if preferredLanguage.contains("Hant") {
                return "zh-Hant"
            }
            return "zh-Hans"
        }

        return "en"
    }
}

// MARK: - Voice Message Model

struct VoiceMessage: Identifiable, Equatable {
    let id = UUID()
    let role: MessageRole
    var text: String          // mutable: starts empty, updated when transcription arrives
    let isVoice: Bool
    let imageData: Data?      // JPEG data for image messages (nil for voice/text)
    let timestamp = Date()

    init(role: MessageRole, text: String, isVoice: Bool, imageData: Data? = nil) {
        self.role = role
        self.text = text
        self.isVoice = isVoice
        self.imageData = imageData
    }

    enum MessageRole {
        case user
        case assistant
    }
}
