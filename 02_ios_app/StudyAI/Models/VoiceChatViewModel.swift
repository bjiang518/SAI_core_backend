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

    // MARK: - Private Properties

    /// WebSocket connection to backend
    private var webSocket: URLSessionWebSocketTask?

    /// Timer for client-side WebSocket keepalive pings (prevents Railway proxy from closing idle connections)
    private var keepAliveTimer: Timer?

    /// Audio engine for recording
    private var audioEngine: AVAudioEngine?

    /// Audio player for playback
    private var audioPlayer: AVAudioPlayerNode?

    /// Audio engine for playback
    private var playbackEngine: AVAudioEngine?

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

    /// Accumulated audio buffer for playback
    private var audioBufferQueue: [AVAudioPCMBuffer] = []

    /// Is currently playing audio
    private var isPlayingAudio = false

    /// Minimum buffers to accumulate before starting playback (prevents choppy audio)
    /// ✅ Increased from 2 to 5 (200ms) for smoother playback with network jitter
    private let minimumBuffersBeforePlayback = 5

    // MARK: - Recording Capture (for voice bubble playback)

    /// Completed user recordings keyed by recording UUID.
    /// SessionChatView observes messages.count changes and drains this dict
    /// to pair each new user VoiceMessage with its raw PCM data.
    @Published var completedUserRecordings: [UUID: Data] = [:]

    /// UUID assigned to the recording that is currently in progress
    private var currentRecordingID: UUID?

    /// Accumulates 16-bit PCM bytes from the audio tap during recording
    private var currentRecordingBuffer = Data()

    /// ID of the most recent user placeholder bubble waiting for transcription
    private var pendingUserMessageID: UUID?

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
                    print("⚠️ [VoiceChat] Keepalive ping failed: \(error.localizedDescription)")
                } else {
                    print("🏓 [VoiceChat] Keepalive ping sent")
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

        // Stop audio
        stopRecording()
        stopAudioPlayback()

        // ✅ Re-enable InteractiveTTS now that voice chat is done
        logger.info("🔊 Re-enabling InteractiveTTS after voice chat...")
        NotificationCenter.default.post(name: NSNotification.Name("ResumeInteractiveTTS"), object: nil)

        connectionState = .disconnected
    }

    /// Start recording from microphone
    func startRecording() {
        guard !isRecording else { return }

        logger.info("🎙️ Starting microphone recording")

        isRecording = true
        errorMessage = nil

        // Start a fresh PCM capture buffer for this recording
        currentRecordingID = UUID()
        currentRecordingBuffer = Data()

        // Audio session already configured in connectToGeminiLive() - don't reconfigure

        // Start audio engine
        do {
            try startAudioEngine()
            logger.info("✅ Audio engine started for recording")
        } catch {
            logger.error("❌ Failed to start audio engine: \(error)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            isRecording = false
        }
    }

    /// Stop recording
    func stopRecording() {
        guard isRecording else { return }

        logger.info("Stopping microphone recording")

        isRecording = false

        // Save accumulated PCM recording for voice bubble playback
        if let recordingID = currentRecordingID, !currentRecordingBuffer.isEmpty {
            completedUserRecordings[recordingID] = currentRecordingBuffer
            print("🎙️ [VoiceChat] Recording saved — pcmBytes: \(currentRecordingBuffer.count), completedRecordings: \(completedUserRecordings.count)")
        } else {
            print("⚠️ [VoiceChat] stopRecording — buffer empty or no recordingID (bytes: \(currentRecordingBuffer.count))")
        }
        currentRecordingID = nil
        currentRecordingBuffer = Data()

        // ✅ Immediately append a placeholder bubble — text updated when transcription arrives
        let placeholder = VoiceMessage(role: .user, text: "", isVoice: true)
        messages.append(placeholder)
        pendingUserMessageID = placeholder.id
        print("🎙️ [VoiceChat] Placeholder bubble appended — id: \(placeholder.id), messages.count: \(messages.count)")

        // ✅ Send audio_stream_end to flush cached audio on backend
        print("📤 [VoiceChat] Sending audio_stream_end to backend")
        sendWebSocketMessage(type: "audio_stream_end", data: [:])

        // Stop audio engine
        stopAudioEngine()

        // Stop level timer
        levelTimer?.invalidate()
        levelTimer = nil
        recordingLevel = 0.0
    }

    /// Interrupt AI speaking
    func interruptAI() {
        logger.info("Interrupting AI")

        isAISpeaking = false
        liveTranscription = ""

        // Stop audio playback
        stopAudioPlayback()

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
                    Task { @MainActor in
                        self.handleWebSocketMessage(text)
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
                print("❌ [VoiceChat WS] Receive loop error: \(error) — connection dropped")
                Task { @MainActor in
                    self.connectionState = .error(error.localizedDescription)
                    self.errorMessage = "Connection lost"
                }
            }
        }
    }

    private func handleWebSocketMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            logger.error("Failed to parse WebSocket message")
            print("❌ [VoiceChat WS] Failed to parse message: \(text.prefix(200))")
            return
        }

        print("📨 [VoiceChat WS] Received type: '\(type)'")
        logger.debug("Received WebSocket message type: \(type)")

        switch type {
        case "session_ready":
            print("✅ [VoiceChat WS] session_ready — Gemini Live is ready")
            logger.info("Gemini Live session ready")
            errorMessage = nil

        case "text_chunk":
            if let textChunk = json["text"] as? String {
                print("📝 [VoiceChat WS] text_chunk: '\(textChunk)'")
                logger.info("📝 [TEXT] Received text_chunk: '\(textChunk)'")
                liveTranscription += textChunk
                isAISpeaking = true
            } else {
                print("❌ [VoiceChat WS] text_chunk missing 'text' field: \(json)")
                logger.error("❌ [TEXT] text_chunk message has no 'text' field: \(json)")
            }

        case "user_transcription":
            if let userText = json["text"] as? String {
                print("🎤 [VoiceChat WS] user_transcription: '\(userText)'")
                logger.info("🎤 [USER] Transcribed: '\(userText)'")
                // Fill in the pending placeholder bubble with real transcription text
                if let pendingID = pendingUserMessageID,
                   let idx = messages.firstIndex(where: { $0.id == pendingID }) {
                    messages[idx].text = userText
                    pendingUserMessageID = nil
                    print("🎤 [VoiceChat WS] Updated placeholder bubble at index \(idx) with transcription")
                } else {
                    // No placeholder found — append normally (fallback)
                    print("🎤 [VoiceChat WS] No placeholder found, appending new message")
                    messages.append(VoiceMessage(role: .user, text: userText, isVoice: true))
                }
            } else {
                print("❌ [VoiceChat WS] user_transcription missing 'text' field: \(json)")
            }

        case "audio_chunk":
            if let audioBase64 = json["data"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                print("🔊 [VoiceChat WS] audio_chunk: \(audioData.count) bytes")
                logger.debug("📥 Received audio_chunk: \(audioData.count) bytes")
                playAudioChunk(audioData)
            } else {
                print("❌ [VoiceChat WS] Failed to decode audio_chunk")
                logger.error("❌ Failed to decode audio_chunk data")
            }

        case "turn_complete":
            print("✅ [VoiceChat WS] turn_complete — liveTranscription: '\(liveTranscription)', messages.count: \(messages.count)")
            if !liveTranscription.isEmpty {
                messages.append(VoiceMessage(
                    role: .assistant,
                    text: liveTranscription,
                    isVoice: true
                ))
                liveTranscription = ""
            }
            isAISpeaking = false
            print("✅ [VoiceChat WS] turn_complete handled — messages.count now: \(messages.count)")

        case "interrupted":
            print("⚡ [VoiceChat WS] interrupted")
            logger.info("AI interrupted by user")

        case "session_ended":
            print("🔴 [VoiceChat WS] session_ended")
            logger.info("Gemini Live session ended")
            connectionState = .disconnected

        case "error":
            if let errorMsg = json["error"] as? String {
                print("❌ [VoiceChat WS] server error: \(errorMsg)")
                logger.error("Server error: \(errorMsg)")
                errorMessage = errorMsg
            }

        default:
            print("⚠️ [VoiceChat WS] unknown type '\(type)' — full json: \(json)")
            logger.warning("⚠️ Unknown message type '\(type)': \(json)")
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

    // MARK: - Audio Playback

    private func playAudioChunk(_ audioData: Data) {
        logger.debug("🎵 Processing audio chunk: \(audioData.count) bytes")

        // Initialize playback engine if needed
        if playbackEngine == nil {
            logger.info("🔊 Initializing playback engine...")
            setupPlaybackEngine()
        }

        isAISpeaking = true

        // Convert data to PCM buffer
        guard let buffer = convertDataToPCMBuffer(data: audioData) else {
            logger.error("❌ Failed to convert audio data to PCM buffer")
            return
        }

        // Add to queue
        audioBufferQueue.append(buffer)

        // Start playback if not already playing AND we have enough buffers
        if !isPlayingAudio {
            if audioBufferQueue.count >= minimumBuffersBeforePlayback {
                logger.info("▶️ Prebuffering complete (\(audioBufferQueue.count) buffers), starting playback...")
                playNextBuffer()
            } else {
                logger.debug("⏳ Prebuffering... (\(audioBufferQueue.count)/\(minimumBuffersBeforePlayback))")
            }
        }
    }

    private func setupPlaybackEngine() {
        logger.info("🔊 Setting up playback engine...")

        // Audio session already configured in connectToGeminiLive() - don't reconfigure
        // Switching modes while engines are running causes error '!pri' (561017449)

        playbackEngine = AVAudioEngine()
        audioPlayer = AVAudioPlayerNode()

        guard let playbackEngine = playbackEngine,
              let audioPlayer = audioPlayer else {
            logger.error("❌ Failed to create playback engine or player node")
            return
        }

        playbackEngine.attach(audioPlayer)
        logger.info("✅ Audio player node attached to playback engine")

        // ✅ CRITICAL: Use Float32 format (AVAudioEngine's native format)
        // Int16 causes inefficient real-time conversion and audio quality issues
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!

        playbackEngine.connect(audioPlayer, to: playbackEngine.mainMixerNode, format: format)
        logger.info("✅ Audio player node connected to mixer (24kHz, 1ch, Float32)")

        do {
            try playbackEngine.start()
            logger.info("✅ Playback engine started successfully")
        } catch {
            logger.error("❌ Failed to start playback engine: \(error)")
        }
    }

    private func playNextBuffer() {
        guard let audioPlayer = audioPlayer,
              !audioBufferQueue.isEmpty else {
            logger.debug("⏹️ Playback queue empty")
            isPlayingAudio = false
            return
        }

        isPlayingAudio = true
        let buffer = audioBufferQueue.removeFirst()

        audioPlayer.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.playNextBuffer()
            }
        }

        if !audioPlayer.isPlaying {
            logger.debug("▶️ Starting audio player...")
            audioPlayer.play()
        }
    }

    private func stopAudioPlayback() {
        logger.info("🔇 Stopping audio playback")

        audioPlayer?.stop()
        audioBufferQueue.removeAll()
        isPlayingAudio = false

        playbackEngine?.stop()
        playbackEngine = nil
        audioPlayer = nil
    }

    private func convertDataToPCMBuffer(data: Data) -> AVAudioPCMBuffer? {
        // ✅ CRITICAL: Use Float32 format (AVAudioEngine's native format)
        // Gemini returns Int16 PCM, we must convert to Float32 for proper playback
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!

        // Calculate frame count: each Int16 sample is 2 bytes
        let frameCount = UInt32(data.count / 2)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        // ✅ CRITICAL: Convert Int16 → Float32
        // Int16 range: -32768 to 32767
        // Float32 range: -1.0 to 1.0
        guard let floatChannelData = buffer.floatChannelData?[0] else {
            return nil
        }

        data.withUnsafeBytes { (rawPtr: UnsafeRawBufferPointer) in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<Int(frameCount) {
                // Normalize Int16 to Float32: divide by 32768.0
                floatChannelData[i] = Float(int16Ptr[i]) / 32768.0
            }
        }

        return buffer
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
                logger.info("   Setting category: .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth]")
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
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
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
    }
}
