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
private func print(_ items: Any...) { }
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
        print("🎙️ SpeechRecognitionService: Running on simulator - speech recognition unavailable")
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
        print("🎙️ SpeechRecognitionService: startListening called")
        print("🎙️ Permission status: \(permissionStatus)")
        print("🎙️ Can use voice: \(permissionStatus.canUseVoice)")
        print("🎙️ Currently listening: \(isListening)")
        
        guard permissionStatus.canUseVoice else {
            print("🎙️ SpeechRecognitionService: No voice permission")
            completion(VoiceInputResult(recognizedText: "", confidence: 0.0, isFinal: true))
            errorMessage = "Voice permissions not granted"
            return
        }
        
        // Prevent multiple simultaneous calls
        if isListening {
            print("🎙️ SpeechRecognitionService: Already listening, stopping current session first")
            forceStopListening() // Use force stop to bypass the guard
        }
        
        print("🎙️ SpeechRecognitionService: Starting listening process")
        
        // Store completion handler
        self.completionHandler = completion
        
        do {
            try startAudioSession()
            try startSpeechRecognition()
            
            DispatchQueue.main.async {
                self.isListening = true
                self.recognizedText = ""
                self.errorMessage = nil
                print("🎙️ SpeechRecognitionService: Successfully started listening")
                
                // Start timeout timer (30 seconds)
                self.listeningTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
                    print("🎙️ SpeechRecognitionService: Listening timeout reached")
                    self.handleTimeout()
                }
            }
            
        } catch {
            print("🎙️ SpeechRecognitionService: Error starting listening: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Failed to start listening: \(error.localizedDescription)"
                completion(VoiceInputResult(recognizedText: "", confidence: 0.0, isFinal: true))
            }
        }
    }
    
    func stopListening() {
        print("🎙️ SpeechRecognitionService: stopListening() called")
        
        // Ensure we're only stopping if we're actually listening
        guard isListening else {
            print("🎙️ SpeechRecognitionService: Already stopped, ignoring stopListening call")
            return
        }
        
        forceStopListening()
    }
    
    private func forceStopListening() {
        print("🎙️ SpeechRecognitionService: forceStopListening() called")
        
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
            print("🎙️ SpeechRecognitionService: Stopping audio engine")
            
            // Check if input node has any taps before trying to remove them
            let inputNode = audioEngine.inputNode
            if inputNode.numberOfInputs > 0 {
                // Remove tap safely
                inputNode.removeTap(onBus: 0)
                print("🎙️ SpeechRecognitionService: Audio tap removed successfully")
            }
            
            // Stop the audio engine
            audioEngine.stop()
            print("🎙️ SpeechRecognitionService: Audio engine stopped")
        }
        
        // Cancel recognition task safely
        if let task = recognitionTask {
            print("🎙️ SpeechRecognitionService: Cancelling recognition task")
            task.cancel()
        }
        
        // End audio for recognition request safely
        if let request = recognitionRequest {
            print("🎙️ SpeechRecognitionService: Ending audio for recognition request")
            request.endAudio()
        }
        
        // Clean up references
        recognitionTask = nil
        recognitionRequest = nil
        
        print("🎙️ SpeechRecognitionService: forceStopListening() completed successfully")
    }
    
    private func startAudioSession() throws {
        print("🎙️ SpeechRecognitionService: Setting up audio session for recording")
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        print("🎙️ SpeechRecognitionService: Audio session configured for recording")
    }
    
    private func startSpeechRecognition() throws {
        print("🎙️ SpeechRecognitionService: startSpeechRecognition() called")
        
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
        print("🎙️ SpeechRecognitionService: Recognition request configured")
        
        // Create audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("🎙️ SpeechRecognitionService: Audio input node configured")
        
        // Ensure no existing taps before installing new one
        // Try to remove any existing tap first
        if inputNode.numberOfInputs > 0 {
            inputNode.removeTap(onBus: 0)
            print("🎙️ SpeechRecognitionService: Removed existing audio tap")
        }

        // Install new tap on audio input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        print("🎙️ SpeechRecognitionService: Audio tap installed successfully")
        
        // Start audio engine
        print("🎙️ SpeechRecognitionService: Starting audio engine")
        audioEngine.prepare()
        try audioEngine.start()
        print("🎙️ SpeechRecognitionService: Audio engine started successfully")
        
        // Start recognition task
        print("🎙️ SpeechRecognitionService: Starting recognition task")
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
        print("🎙️ SpeechRecognitionService: Recognition task started successfully")
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        print("🎙️ SpeechRecognitionService: handleRecognitionResult called")
        print("🎙️ Result: \(result?.bestTranscription.formattedString ?? "nil")")
        print("🎙️ Error: \(error?.localizedDescription ?? "nil")")
        
        var isFinal = false
        var recognizedText = ""
        var confidence: Float = 0.0
        
        if let result = result {
            recognizedText = result.bestTranscription.formattedString
            confidence = result.bestTranscription.segments.last?.confidence ?? 0.0
            isFinal = result.isFinal
            
            print("🎙️ Recognized text: '\(recognizedText)'")
            print("🎙️ Is final: \(isFinal)")
            print("🎙️ Confidence: \(confidence)")
            
            // Update published properties
            self.recognizedText = recognizedText
            self.confidence = confidence
            self.lastRecognizedText = recognizedText
            
            // Reset silence timer when we get new text
            if !recognizedText.isEmpty {
                silenceTimer?.invalidate()
                silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    print("🎙️ Silence detected, finalizing with last recognized text")
                    self.finalizeSpeechRecognition()
                }
            }
            
            if isFinal {
                print("🎙️ Final result, stopping and calling completion")
                listeningTimer?.invalidate()
                listeningTimer = nil
                silenceTimer?.invalidate()
                silenceTimer = nil
                stopListening()
                completionHandler?(VoiceInputResult(recognizedText: recognizedText, confidence: confidence, isFinal: true))
            }
        }
        
        if let error = error {
            print("🎙️ Recognition error: \(error.localizedDescription)")
            
            // If we have partial text and get "No speech detected", use the partial text
            if error.localizedDescription.contains("No speech detected") && !lastRecognizedText.isEmpty {
                print("🎙️ Using last recognized text due to 'No speech detected' error: '\(lastRecognizedText)'")
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
        print("🎙️ SpeechRecognitionService: Speech recognition timeout")
        DispatchQueue.main.async {
            // Use last recognized text if available
            if !self.lastRecognizedText.isEmpty {
                print("🎙️ Timeout: Using last recognized text: '\(self.lastRecognizedText)'")
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
        print("🎙️ SpeechRecognitionService: Finalizing speech recognition with text: '\(lastRecognizedText)'")
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