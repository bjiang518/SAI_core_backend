//
//  SpeechRecognitionService.swift
//  StudyAI
//
//  Created by Claude Code on 9/8/25.
//

import Foundation
import Speech
import AVFoundation
import Combine

// MARK: - Production Logging Safety
// Disable debug print statements in production builds to prevent voice input text exposure
#if !DEBUG
private func debugPrint(_ items: Any...) { }
private func debugPrint(_ items: Any...) { }
#endif

class SpeechRecognitionService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var confidence: Float = 0.0
    @Published var permissionStatus: VoicePermissionStatus = .notDetermined
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var completionHandler: ((VoiceInputResult) -> Void)?
    private var isInitialized = false
    private var listeningTimer: Timer?
    private var lastRecognizedText = ""
    private var silenceTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        // Initialize with device's preferred language, fallback to English
        let locale = Locale.current
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

        super.init()

        // Check if running on simulator
        #if targetEnvironment(simulator)
        debugPrint("🎙️ SpeechRecognitionService: Running on simulator - speech recognition unavailable")
        self.permissionStatus = .restricted
        self.errorMessage = "Speech recognition is not available in the iOS Simulator. Please test on a physical device."
        #else
        // Check if speech recognition is available
        guard speechRecognizer != nil else {
            self.permissionStatus = .restricted
            return
        }

        // Set delegate
        speechRecognizer?.delegate = self

        // Request initial permissions
        Task {
            await requestPermissions()
        }
        #endif
    }
    
    // MARK: - Permission Management
    
    @MainActor
    func requestPermissions() async {
        // Request speech recognition permission
        let speechStatus = await requestSpeechRecognitionPermission()
        
        // Request microphone permission
        let microphoneStatus = await requestMicrophonePermission()
        
        // Update overall permission status
        updatePermissionStatus(speechStatus: speechStatus, microphoneStatus: microphoneStatus)
    }
    
    private func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    private func requestMicrophonePermission() async -> AVAudioSession.RecordPermission {
        // iOS 17+ uses AVAudioApplication.recordPermission, but we need to return AVAudioSession.RecordPermission
        // The enum cases .granted/.denied are deprecated but we suppress warnings since this is a compatibility bridge
        // NOTE: Refactor to use AVAudioApplication.recordPermission directly when minimum deployment target is iOS 17+

        if #available(iOS 17.0, *) {
            // Use new iOS 17+ API
            let permission = AVAudioApplication.shared.recordPermission

            // Bridge to legacy enum - comparing enum values directly
            // Note: These comparisons use the new iOS 17 API which returns the same enum type
            switch permission {
            case .granted:
                return .granted
            case .denied:
                return .denied
            case .undetermined:
                // Permission is undetermined, request it
                let granted = await withCheckedContinuation { continuation in
                    AVAudioApplication.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
                return granted ? .granted : .denied
            @unknown default:
                return .undetermined
            }
        } else {
            // iOS 16 and earlier
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            return granted ? .granted : .denied
        }
    }

    @MainActor
    private func updatePermissionStatus(speechStatus: SFSpeechRecognizerAuthorizationStatus, microphoneStatus: AVAudioSession.RecordPermission) {
        switch (speechStatus, microphoneStatus) {
        case (.authorized, .granted):
            permissionStatus = .granted
        case (.denied, _), (_, .denied):
            permissionStatus = .denied
        case (.restricted, _), (_, .undetermined):
            permissionStatus = .restricted
        case (.notDetermined, _):
            permissionStatus = .notDetermined
        @unknown default:
            permissionStatus = .denied
        }
    }
    
    // MARK: - Speech Recognition
    
    func startListening(completion: @escaping (VoiceInputResult) -> Void) {
        debugPrint("🎙️ SpeechRecognitionService: startListening called")
        debugPrint("🎙️ Permission status: \(permissionStatus)")
        debugPrint("🎙️ Can use voice: \(permissionStatus.canUseVoice)")
        debugPrint("🎙️ Currently listening: \(isListening)")
        
        guard permissionStatus.canUseVoice else {
            debugPrint("🎙️ SpeechRecognitionService: No voice permission")
            completion(VoiceInputResult(recognizedText: "", confidence: 0.0, isFinal: true))
            errorMessage = "Voice permissions not granted"
            return
        }
        
        // Prevent multiple simultaneous calls
        if isListening {
            debugPrint("🎙️ SpeechRecognitionService: Already listening, stopping current session first")
            forceStopListening() // Use force stop to bypass the guard
        }
        
        debugPrint("🎙️ SpeechRecognitionService: Starting listening process")
        
        // Store completion handler
        self.completionHandler = completion
        
        do {
            try startAudioSession()
            try startSpeechRecognition()
            
            DispatchQueue.main.async {
                self.isListening = true
                self.recognizedText = ""
                self.errorMessage = nil
                debugPrint("🎙️ SpeechRecognitionService: Successfully started listening")
                
                // Start timeout timer (30 seconds)
                self.listeningTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
                    debugPrint("🎙️ SpeechRecognitionService: Listening timeout reached")
                    self.handleTimeout()
                }
            }
            
        } catch {
            debugPrint("🎙️ SpeechRecognitionService: Error starting listening: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to start listening: \(error.localizedDescription)"
                completion(VoiceInputResult(recognizedText: "", confidence: 0.0, isFinal: true))
            }
        }
    }
    
    func stopListening() {
        debugPrint("🎙️ SpeechRecognitionService: stopListening() called")
        
        // Ensure we're only stopping if we're actually listening
        guard isListening else {
            debugPrint("🎙️ SpeechRecognitionService: Already stopped, ignoring stopListening call")
            return
        }
        
        forceStopListening()
    }
    
    private func forceStopListening() {
        debugPrint("🎙️ SpeechRecognitionService: forceStopListening() called")
        
        DispatchQueue.main.async {
            self.isListening = false
        }
        
        // Cancel timeout timers safely
        listeningTimer?.invalidate()
        listeningTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Stop audio engine safely
        if audioEngine.isRunning {
            debugPrint("🎙️ SpeechRecognitionService: Stopping audio engine")
            
            // Check if input node has any taps before trying to remove them
            let inputNode = audioEngine.inputNode
            if inputNode.numberOfInputs > 0 {
                // Remove tap safely
                inputNode.removeTap(onBus: 0)
                debugPrint("🎙️ SpeechRecognitionService: Audio tap removed successfully")
            }
            
            // Stop the audio engine
            audioEngine.stop()
            debugPrint("🎙️ SpeechRecognitionService: Audio engine stopped")
        }
        
        // Cancel recognition task safely
        if let task = recognitionTask {
            debugPrint("🎙️ SpeechRecognitionService: Cancelling recognition task")
            task.cancel()
        }
        
        // End audio for recognition request safely
        if let request = recognitionRequest {
            debugPrint("🎙️ SpeechRecognitionService: Ending audio for recognition request")
            request.endAudio()
        }
        
        // Clean up references
        recognitionTask = nil
        recognitionRequest = nil
        
        debugPrint("🎙️ SpeechRecognitionService: forceStopListening() completed successfully")
    }
    
    private func startAudioSession() throws {
        debugPrint("🎙️ SpeechRecognitionService: Setting up audio session for recording")
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        debugPrint("🎙️ SpeechRecognitionService: Audio session configured for recording")
    }
    
    private func startSpeechRecognition() throws {
        debugPrint("🎙️ SpeechRecognitionService: startSpeechRecognition() called")
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognitionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"])
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognitionService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        // Configure recognition request
        recognitionRequest.shouldReportPartialResults = true
        debugPrint("🎙️ SpeechRecognitionService: Recognition request configured")
        
        // Create audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        debugPrint("🎙️ SpeechRecognitionService: Audio input node configured")
        
        // Ensure no existing taps before installing new one
        // Try to remove any existing tap first
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
            debugPrint("🎙️ SpeechRecognitionService: Removed existing audio tap")
        }

        // Install new tap on audio input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        debugPrint("🎙️ SpeechRecognitionService: Audio tap installed successfully")
        
        // Start audio engine
        debugPrint("🎙️ SpeechRecognitionService: Starting audio engine")
        audioEngine.prepare()
        try audioEngine.start()
        debugPrint("🎙️ SpeechRecognitionService: Audio engine started successfully")
        
        // Start recognition task
        debugPrint("🎙️ SpeechRecognitionService: Starting recognition task")
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
        debugPrint("🎙️ SpeechRecognitionService: Recognition task started successfully")
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        debugPrint("🎙️ SpeechRecognitionService: handleRecognitionResult called")
        debugPrint("🎙️ Result: \(result?.bestTranscription.formattedString ?? "nil")")
        debugPrint("🎙️ Error: \(error?.localizedDescription ?? "nil")")
        
        var isFinal = false
        var recognizedText = ""
        var confidence: Float = 0.0
        
        if let result = result {
            recognizedText = result.bestTranscription.formattedString
            confidence = result.bestTranscription.segments.last?.confidence ?? 0.0
            isFinal = result.isFinal
            
            debugPrint("🎙️ Recognized text: '\(recognizedText)'")
            debugPrint("🎙️ Is final: \(isFinal)")
            debugPrint("🎙️ Confidence: \(confidence)")
            
            // Update published properties
            self.recognizedText = recognizedText
            self.confidence = confidence
            self.lastRecognizedText = recognizedText
            
            // Reset silence timer when we get new text
            if !recognizedText.isEmpty {
                silenceTimer?.invalidate()
                silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    debugPrint("🎙️ Silence detected, finalizing with last recognized text")
                    self.finalizeSpeechRecognition()
                }
            }
            
            if isFinal {
                debugPrint("🎙️ Final result, stopping and calling completion")
                listeningTimer?.invalidate()
                listeningTimer = nil
                silenceTimer?.invalidate()
                silenceTimer = nil
                stopListening()
                completionHandler?(VoiceInputResult(recognizedText: recognizedText, confidence: confidence, isFinal: true))
            }
        }
        
        if let error = error {
            debugPrint("🎙️ Recognition error: \(error.localizedDescription)")
            
            // If we have partial text and get "No speech detected", use the partial text
            if error.localizedDescription.contains("No speech detected") && !lastRecognizedText.isEmpty {
                debugPrint("🎙️ Using last recognized text due to 'No speech detected' error: '\(lastRecognizedText)'")
                listeningTimer?.invalidate()
                listeningTimer = nil
                silenceTimer?.invalidate() 
                silenceTimer = nil
                stopListening()
                completionHandler?(VoiceInputResult(recognizedText: lastRecognizedText, confidence: confidence, isFinal: true))
            } else {
                self.errorMessage = error.localizedDescription
                stopListening()
                completionHandler?(VoiceInputResult(recognizedText: lastRecognizedText, confidence: confidence, isFinal: true))
            }
        }
    }
    
    private func handleTimeout() {
        debugPrint("🎙️ SpeechRecognitionService: Speech recognition timeout")
        DispatchQueue.main.async {
            // Use last recognized text if available
            if !self.lastRecognizedText.isEmpty {
                debugPrint("🎙️ Timeout: Using last recognized text: '\(self.lastRecognizedText)'")
                self.stopListening()
                self.completionHandler?(VoiceInputResult(recognizedText: self.lastRecognizedText, confidence: 0.0, isFinal: true))
            } else {
                self.errorMessage = "Speech recognition timeout. Please try again."
                self.stopListening()
                self.completionHandler?(VoiceInputResult(recognizedText: "", confidence: 0.0, isFinal: true))
            }
        }
    }
    
    private func finalizeSpeechRecognition() {
        debugPrint("🎙️ SpeechRecognitionService: Finalizing speech recognition with text: '\(lastRecognizedText)'")
        DispatchQueue.main.async {
            self.listeningTimer?.invalidate()
            self.listeningTimer = nil
            self.silenceTimer?.invalidate()
            self.silenceTimer = nil
            self.stopListening()
            self.completionHandler?(VoiceInputResult(recognizedText: self.lastRecognizedText, confidence: self.confidence, isFinal: true))
        }
    }
    
    // MARK: - Utility Methods
    
    func isAvailable() -> Bool {
        return speechRecognizer?.isAvailable == true && permissionStatus.canUseVoice
    }
    
    func getLastRecognizedText() -> String {
        return lastRecognizedText
    }
    
    func getSupportedLanguages() -> [String] {
        return SFSpeechRecognizer.supportedLocales().map { $0.identifier }
    }
    
    deinit {
        stopListening()
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        DispatchQueue.main.async {
            if !available && self.isListening {
                self.stopListening()
                self.errorMessage = "Speech recognition became unavailable"
            }
        }
    }
}