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
            logger.error("❌ No auth token available")
            return
        }

        connectionState = .connecting
        logger.info("🔄 Connecting to Gemini Live...")

        // ✅ CRITICAL: Stop InteractiveTTS to avoid audio engine conflicts
        // InteractiveTTS will be restarted when we disconnect
        logger.info("🔇 Stopping InteractiveTTS to prevent audio conflicts...")
        NotificationCenter.default.post(name: NSNotification.Name("StopInteractiveTTS"), object: nil)

        // Configure audio session early for bidirectional audio
        configureAudioSession(for: .playAndRecord)

        // Build WebSocket URL
        let baseURL = networkService.apiBaseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")

        guard let wsURL = URL(string: "\(baseURL)/api/ai/gemini-live/connect?token=\(token)&sessionId=\(sessionId)") else {
            errorMessage = "Invalid WebSocket URL"
            connectionState = .error("Invalid URL")
            logger.error("❌ Invalid WebSocket URL")
            return
        }

        logger.info("🌐 Connecting to Gemini Live: \(wsURL.absoluteString)")

        // Create WebSocket task
        webSocket = URLSession.shared.webSocketTask(with: wsURL)
        webSocket?.resume()

        logger.info("✅ WebSocket task created and resumed")

        // Send start_session immediately
        sendWebSocketMessage(type: "start_session", data: [
            "subject": subject,
            "language": getCurrentLanguage()
        ])

        // Start receiving messages
        receiveWebSocketMessages()

        connectionState = .connected
        logger.info("✅ Connection state set to connected")
    }

    /// Disconnect from Gemini Live
    func disconnect() {
        logger.info("Disconnecting from Gemini Live")

        // Send end session message
        sendWebSocketMessage(type: "end_session", data: [:])

        // Close WebSocket
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil

        // Stop audio
        stopRecording()
        stopAudioPlayback()

        // Deactivate audio session to allow InteractiveTTS to resume
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            logger.info("✅ Audio session deactivated - InteractiveTTS can resume")
        } catch {
            logger.error("Failed to deactivate audio session: \(error)")
        }

        // ✅ Allow InteractiveTTS to resume after we're done
        logger.info("🔊 Notifying SessionChatView that InteractiveTTS can resume")
        NotificationCenter.default.post(name: NSNotification.Name("ResumeInteractiveTTS"), object: nil)

        connectionState = .disconnected
    }

    /// Start recording from microphone
    func startRecording() {
        logger.info("🎙️ startRecording() called")

        guard !isRecording else {
            logger.warn("⚠️ Already recording, ignoring startRecording() call")
            return
        }

        logger.info("✅ Starting microphone recording (isRecording was false)")

        isRecording = true
        errorMessage = nil

        logger.info("🔊 Configuring audio session for bidirectional audio...")
        // Configure audio session for bidirectional audio (recording + playback)
        configureAudioSession(for: .playAndRecord)

        // Start audio engine
        logger.info("🎤 Attempting to start audio engine...")
        do {
            try startAudioEngine()
            logger.info("✅ Audio engine started successfully - isRecording: \(isRecording)")
        } catch {
            logger.error("❌ Failed to start audio engine: \(error)")
            logger.error("   Error description: \(error.localizedDescription)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            isRecording = false
            logger.info("⚠️ Set isRecording to false due to error")
        }
    }

    /// Stop recording
    func stopRecording() {
        logger.info("🛑 stopRecording() called")

        guard isRecording else {
            logger.warn("⚠️ Not currently recording, ignoring stopRecording() call")
            return
        }

        logger.info("✅ Stopping microphone recording (isRecording was true)")

        isRecording = false

        // Stop audio engine
        logger.info("🎤 Stopping audio engine...")
        stopAudioEngine()

        // Stop level timer
        logger.info("⏱️ Invalidating level timer...")
        levelTimer?.invalidate()
        levelTimer = nil
        recordingLevel = 0.0

        logger.info("✅ Recording stopped - isRecording: \(isRecording)")
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
            logger.error("❌ Failed to serialize WebSocket message type: \(type)")
            return
        }

        logger.info("📤 Sending WebSocket message: \(type)")
        logger.debug("   Payload: \(jsonString)")

        webSocket?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                self?.logger.error("❌ WebSocket send error for \(type): \(error)")
                Task { @MainActor in
                    self?.errorMessage = "Failed to send message"
                }
            } else {
                self?.logger.debug("✅ Successfully sent \(type) message")
            }
        }
    }

    private func receiveWebSocketMessages() {
        logger.debug("👂 Starting to receive WebSocket messages...")

        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.logger.info("📥 Received WebSocket message")
                    self.logger.debug("   Content: \(text.prefix(200))...")
                    Task { @MainActor in
                        self.handleWebSocketMessage(text)
                    }
                case .data(let data):
                    self.logger.debug("📥 Received binary data: \(data.count) bytes")
                @unknown default:
                    break
                }

                // Continue listening
                self.receiveWebSocketMessages()

            case .failure(let error):
                self.logger.error("❌ WebSocket receive error: \(error)")
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
            logger.error("❌ Failed to parse WebSocket message")
            return
        }

        logger.debug("🔍 Processing message type: \(type)")

        switch type {
        case "session_ready":
            logger.info("✅ Gemini Live session ready")
            errorMessage = nil

        case "text_chunk":
            if let textChunk = json["text"] as? String {
                logger.debug("📝 Received text chunk: \(textChunk.prefix(50))...")
                liveTranscription += textChunk
                isAISpeaking = true
            }

        case "audio_chunk":
            if let audioBase64 = json["data"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                logger.debug("🔊 Received audio chunk: \(audioData.count) bytes")
                playAudioChunk(audioData)
            }

        case "turn_complete":
            logger.info("✅ Turn complete")
            // AI finished speaking
            if !liveTranscription.isEmpty {
                messages.append(VoiceMessage(
                    role: .assistant,
                    text: liveTranscription,
                    isVoice: true
                ))
                liveTranscription = ""
            }
            isAISpeaking = false

        case "interrupted":
            logger.info("⚠️ AI interrupted by user")

        case "session_ended":
            logger.info("🔚 Gemini Live session ended")
            connectionState = .disconnected

        case "error":
            if let errorMsg = json["error"] as? String {
                logger.error("❌ Server error: \(errorMsg)")
                errorMessage = errorMsg
            }

        default:
            logger.debug("❓ Unknown message type: \(type)")
        }
    }

    // MARK: - Audio Recording

    private var audioChunkCounter = 0 // Track number of audio chunks sent

    private func startAudioEngine() throws {
        logger.info("🎤 startAudioEngine() called - Creating AVAudioEngine...")
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            logger.error("❌ Failed to create AVAudioEngine")
            return
        }

        logger.info("✅ AVAudioEngine created successfully")

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        logger.info("📊 Audio format: \(recordingFormat)")
        logger.info("   Sample rate: \(recordingFormat.sampleRate) Hz")
        logger.info("   Channels: \(recordingFormat.channelCount)")
        logger.info("   Format: \(recordingFormat.commonFormat.rawValue)")

        // Reset chunk counter
        audioChunkCounter = 0

        // Install tap to capture audio
        logger.info("🔧 Installing audio tap on input node...")
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }

            // Calculate audio level for visual feedback
            self.calculateAudioLevel(from: buffer)

            // Log first few chunks to verify tap is working
            if self.audioChunkCounter < 3 {
                self.logger.debug("🎵 Audio tap callback fired - chunk #\(self.audioChunkCounter + 1), frameLength: \(buffer.frameLength)")
            }

            // Convert to 16-bit PCM at 16kHz (Gemini Live format)
            if let convertedData = self.convertAudioToGeminiFormat(buffer: buffer) {
                self.audioChunkCounter += 1

                // Log every 50th chunk to avoid spam
                if self.audioChunkCounter % 50 == 0 {
                    self.logger.debug("✅ Successfully converted audio chunk #\(self.audioChunkCounter), size: \(convertedData.count) bytes")
                }

                let base64Audio = convertedData.base64EncodedString()

                // Send to backend
                Task { @MainActor in
                    if self.audioChunkCounter == 1 || self.audioChunkCounter % 50 == 0 {
                        self.logger.debug("📤 Sending audio chunk #\(self.audioChunkCounter) to backend")
                    }
                    self.sendWebSocketMessage(type: "audio_chunk", data: ["audio": base64Audio])
                }
            } else {
                if self.audioChunkCounter == 0 {
                    self.logger.error("❌ Failed to convert audio chunk to Gemini format (first chunk)")
                }
            }
        }

        logger.info("✅ Audio tap installed successfully")

        logger.info("🚀 Starting AVAudioEngine...")
        try audioEngine.start()
        logger.info("✅ AVAudioEngine started successfully")

        // Start level monitoring
        logger.info("📊 Starting level monitoring...")
        startLevelMonitoring()
        logger.info("✅ Audio engine setup complete - Total chunks sent: \(audioChunkCounter)")
    }

    private func stopAudioEngine() {
        logger.info("🛑 stopAudioEngine() called - Total chunks sent: \(audioChunkCounter)")

        if let engine = audioEngine {
            logger.debug("   Stopping audio engine...")
            engine.stop()
            logger.debug("   Removing input tap...")
            engine.inputNode.removeTap(onBus: 0)
            logger.info("✅ Audio engine stopped and tap removed")
        } else {
            logger.warn("⚠️ Audio engine was already nil")
        }

        audioEngine = nil
        audioChunkCounter = 0
    }

    private func convertAudioToGeminiFormat(buffer: AVAudioPCMBuffer) -> Data? {
        // Gemini Live input: 16-bit PCM at 16kHz (output is 24kHz)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )

        guard let targetFormat = targetFormat else {
            logger.error("❌ Failed to create target audio format (16kHz PCM16)")
            return nil
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            logger.error("❌ Failed to create audio converter from \(buffer.format.sampleRate)Hz to 16000Hz")
            return nil
        }

        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            logger.error("❌ Failed to create converted PCM buffer with capacity: \(capacity)")
            return nil
        }

        var error: NSError?
        converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            logger.error("❌ Audio conversion error: \(error)")
            return nil
        }

        // Convert to Data
        let audioBuffer = convertedBuffer.audioBufferList.pointee.mBuffers
        let dataSize = Int(audioBuffer.mDataByteSize)

        // Log first conversion for verification
        if audioChunkCounter == 0 {
            logger.debug("✅ First audio conversion successful: \(dataSize) bytes (from \(buffer.frameLength) frames)")
        }

        return Data(bytes: audioBuffer.mData!, count: dataSize)
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
        // Initialize playback engine if needed
        if playbackEngine == nil {
            setupPlaybackEngine()
        }

        isAISpeaking = true

        // Convert data to PCM buffer
        guard let buffer = convertDataToPCMBuffer(data: audioData) else {
            logger.error("Failed to convert audio data to PCM buffer")
            return
        }

        // Add to queue
        audioBufferQueue.append(buffer)

        // Start playback if not already playing
        if !isPlayingAudio {
            playNextBuffer()
        }
    }

    private func setupPlaybackEngine() {
        playbackEngine = AVAudioEngine()
        audioPlayer = AVAudioPlayerNode()

        guard let playbackEngine = playbackEngine,
              let audioPlayer = audioPlayer else { return }

        playbackEngine.attach(audioPlayer)

        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!

        playbackEngine.connect(audioPlayer, to: playbackEngine.mainMixerNode, format: format)

        do {
            try playbackEngine.start()
        } catch {
            logger.error("Failed to start playback engine: \(error)")
        }
    }

    private func playNextBuffer() {
        guard let audioPlayer = audioPlayer,
              !audioBufferQueue.isEmpty else {
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
            audioPlayer.play()
        }
    }

    private func stopAudioPlayback() {
        audioPlayer?.stop()
        audioBufferQueue.removeAll()
        isPlayingAudio = false

        playbackEngine?.stop()
        playbackEngine = nil
        audioPlayer = nil
    }

    private func convertDataToPCMBuffer(data: Data) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!

        let frameCount = UInt32(data.count) / format.streamDescription.pointee.mBytesPerFrame

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { ptr in
            memcpy(buffer.audioBufferList.pointee.mBuffers.mData, ptr.baseAddress, data.count)
        }

        return buffer
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession(for mode: AudioSessionMode) {
        let audioSession = AVAudioSession.sharedInstance()

        logger.info("🔊 Configuring audio session for mode: \(mode)")

        do {
            switch mode {
            case .recording:
                logger.debug("   Setting category: .record, mode: .measurement")
                try audioSession.setCategory(.record, mode: .measurement, options: [])
            case .playback:
                logger.debug("   Setting category: .playback, mode: .spokenAudio")
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            case .playAndRecord:
                // Use .duckOthers to lower volume of InteractiveTTS instead of interrupting it
                logger.debug("   Setting category: .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers]")
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            }

            logger.debug("   Activating audio session with .notifyOthersOnDeactivation...")
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            logger.info("✅ Audio session configured successfully for mode: \(mode)")
        } catch {
            logger.error("❌ Failed to configure audio session for mode \(mode): \(error)")
            logger.error("   Error description: \(error.localizedDescription)")
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
    let text: String
    let isVoice: Bool
    let timestamp = Date()

    enum MessageRole {
        case user
        case assistant
    }
}
