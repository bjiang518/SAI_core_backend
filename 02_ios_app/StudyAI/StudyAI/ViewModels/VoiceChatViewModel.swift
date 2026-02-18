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
            return
        }

        connectionState = .connecting

        // Configure audio session early for bidirectional audio
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

        // Send end session message
        sendWebSocketMessage(type: "end_session", data: [:])

        // Close WebSocket
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil

        // Stop audio
        stopRecording()
        stopAudioPlayback()

        connectionState = .disconnected
    }

    /// Start recording from microphone
    func startRecording() {
        guard !isRecording else { return }

        logger.info("Starting microphone recording")

        isRecording = true
        errorMessage = nil

        // Configure audio session for bidirectional audio (recording + playback)
        configureAudioSession(for: .playAndRecord)

        // Start audio engine
        do {
            try startAudioEngine()
        } catch {
            logger.error("Failed to start audio engine: \(error)")
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            isRecording = false
        }
    }

    /// Stop recording
    func stopRecording() {
        guard isRecording else { return }

        logger.info("Stopping microphone recording")

        isRecording = false

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
            }

        case "audio_chunk":
            if let audioBase64 = json["data"] as? String,
               let audioData = Data(base64Encoded: audioBase64) {
                playAudioChunk(audioData)
            }

        case "turn_complete":
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
            logger.info("AI interrupted by user")

        case "session_ended":
            logger.info("Gemini Live session ended")
            connectionState = .disconnected

        case "error":
            if let errorMsg = json["error"] as? String {
                logger.error("Server error: \(errorMsg)")
                errorMessage = errorMsg
            }

        default:
            logger.debug("Unknown message type: \(type)")
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

            // Calculate audio level for visual feedback
            self.calculateAudioLevel(from: buffer)

            // Convert to 16-bit PCM at 24kHz (Gemini Live format)
            if let convertedData = self.convertAudioToGeminiFormat(buffer: buffer) {
                let base64Audio = convertedData.base64EncodedString()

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

        do {
            switch mode {
            case .recording:
                try audioSession.setCategory(.record, mode: .measurement, options: [])
            case .playback:
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            case .playAndRecord:
                try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            }

            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error)")
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
