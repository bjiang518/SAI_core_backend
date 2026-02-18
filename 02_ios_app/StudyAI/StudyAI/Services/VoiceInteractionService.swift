//
//  VoiceInteractionService.swift
//  StudyAI
//
//  Created by Claude Code on 9/8/25.
//

import Foundation
import Combine
import AVFoundation

class VoiceInteractionService: ObservableObject {

    // MARK: - Debug Mode

    /// Enable verbose logging for debugging (default: false)
    private static let debugMode = false

    // MARK: - Published Properties
    
    @Published var interactionState: VoiceInteractionState = .idle
    @Published var voiceSettings = VoiceSettings.load()
    @Published var permissionStatus: VoicePermissionStatus = .notDetermined
    @Published var isVoiceEnabled = true
    @Published var lastRecognizedText = ""
    @Published var errorMessage: String?
    @Published var isPaused = false
    @Published var currentSpeakingMessageId: String? = nil

    // ✅ Phase 3.6 (2026-02-16): Track when TTS is loading audio to prevent race conditions
    /// True when EnhancedTTS is making network request to fetch audio
    /// Prevents observer from firing multiple times while audio is loading
    @Published var isProcessingTTS: Bool = false
    
    // MARK: - Services
    
    private let speechRecognitionService = SpeechRecognitionService()
    private let textToSpeechService = TextToSpeechService()
    private let enhancedTTSService = EnhancedTTSService()
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private var currentVoiceInputCompletion: ((String) -> Void)?
    
    // MARK: - Singleton
    
    static let shared = VoiceInteractionService()
    
    private init() {
        setupBindings()
        setupAudioNotifications()
        
        // Load saved settings
        voiceSettings = VoiceSettings.load()
        textToSpeechService.updateVoiceSettings(voiceSettings)
        enhancedTTSService.updateVoiceSettings(voiceSettings)
        
        // Request permissions on initialization
        Task {
            await requestPermissions()
        }
    }
    
    // MARK: - Setup
    
    private func setupBindings() {
        // Bind speech recognition state
        speechRecognitionService.$isListening
            .sink { [weak self] isListening in
                DispatchQueue.main.async {
                    if isListening {
                        self?.interactionState = .listening
                    } else if self?.interactionState == .listening {
                        self?.interactionState = .processing
                    }
                }
            }
            .store(in: &cancellables)
        
        // Bind permission status
        speechRecognitionService.$permissionStatus
            .sink { [weak self] status in
                DispatchQueue.main.async {
                    self?.permissionStatus = status
                }
            }
            .store(in: &cancellables)
        
        // Bind TTS state - prioritize enhanced TTS when speaking
        Publishers.CombineLatest(
            textToSpeechService.$isSpeaking,
            enhancedTTSService.$isSpeaking
        )
        .sink { [weak self] (systemTTSSpeaking, enhancedTTSSpeaking) in
            DispatchQueue.main.async {
                let anySpeaking = systemTTSSpeaking || enhancedTTSSpeaking
                if anySpeaking {
                    self?.interactionState = .speaking
                } else if self?.interactionState == .speaking {
                    self?.interactionState = .idle
                    // Clear current speaking message when TTS finishes
                    self?.clearCurrentSpeakingMessage()
                }
            }
        }
        .store(in: &cancellables)
        
        // Bind TTS paused state - combine both services
        Publishers.CombineLatest(
            textToSpeechService.$isPaused,
            enhancedTTSService.$isPaused
        )
        .sink { [weak self] (systemPaused, enhancedPaused) in
            DispatchQueue.main.async {
                self?.isPaused = systemPaused || enhancedPaused
            }
        }
        .store(in: &cancellables)

        // ✅ Phase 3.6 (2026-02-16): Bind EnhancedTTS processing state
        // This tracks when EnhancedTTS is making network requests to prevent race conditions
        enhancedTTSService.$isProcessing
            .sink { [weak self] isProcessing in
                DispatchQueue.main.async {
                    self?.isProcessingTTS = isProcessing
                }
            }
            .store(in: &cancellables)
        
        // Bind error messages from all services
        Publishers.Merge3(
            speechRecognitionService.$errorMessage,
            textToSpeechService.$errorMessage,
            enhancedTTSService.$errorMessage
        )
        .compactMap { $0 }
        .sink { [weak self] errorMessage in
            DispatchQueue.main.async {
                self?.errorMessage = errorMessage
                self?.interactionState = .error(errorMessage)
            }
        }
        .store(in: &cancellables)
    }
    
    private func setupAudioNotifications() {
        // Handle audio interruptions (calls, other apps)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // Handle route changes (headphones, speaker)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }
    
    // MARK: - Public Methods
    
    func requestPermissions() async {
        await speechRecognitionService.requestPermissions()
    }
    
    func startVoiceInput(completion: @escaping (String) -> Void) {
        guard isVoiceEnabled && permissionStatus.canUseVoice else {
            completion("")
            errorMessage = permissionStatus.displayMessage
            return
        }
        
        // Stop any current TTS
        textToSpeechService.stopSpeech()
        
        // Store completion handler
        currentVoiceInputCompletion = completion
        
        // Start listening
        speechRecognitionService.startListening { [weak self] result in
            DispatchQueue.main.async {
                self?.handleVoiceInputResult(result)
            }
        }
    }
    
    func stopVoiceInput() {
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: stopVoiceInput called")
            }
        
        // Don't clear completion handler yet - let the speech service finish processing
        speechRecognitionService.stopListening()
        
        DispatchQueue.main.async {
            self.interactionState = .idle
        }
    }
    
    func speakResponse(_ text: String, autoSpeak: Bool = true) {
        guard isVoiceEnabled else { return }
        
        // Check if auto-speak is enabled or explicitly requested
        if voiceSettings.autoSpeakResponses || autoSpeak {
            speakTextWithBestService(text)
        }
    }
    
    func speakText(_ text: String, autoSpeak: Bool = false) {
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: speakText() called with: '\(text)', autoSpeak: \(autoSpeak)")
            }
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: isVoiceEnabled = \(isVoiceEnabled)")
            }
        guard isVoiceEnabled else { 
            if Self.debugMode {
            print("🎙️ VoiceInteractionService: Voice is disabled, not speaking")
            }
            return 
        }
        
        // Always stop previous speech when starting new speech (interruption behavior)
        if interactionState == .speaking {
            if Self.debugMode {
            print("🎙️ VoiceInteractionService: Interrupting current speech to start new message")
            }
            stopSpeech()
        }
        
        // Update state to speaking
        DispatchQueue.main.async {
            self.interactionState = .speaking
        }
        
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: Using premium TTS service for enhanced voice quality")
            }
        speakTextWithBestService(text)
    }
    
    func speakText(_ text: String) {
        speakText(text, autoSpeak: false)
    }
    
    private func speakTextWithBestService(_ text: String) {
        // Use enhanced TTS for premium voice types (Elsa, friendly, professional)
        if shouldUseEnhancedTTS(for: voiceSettings.voiceType) {
            if Self.debugMode {
            print("🎙️ VoiceInteractionService: Using EnhancedTTSService for premium voice: \(voiceSettings.voiceType)")
            }
            enhancedTTSService.speak(text, with: voiceSettings)
        } else {
            if Self.debugMode {
            print("🎙️ VoiceInteractionService: Using system TTS for voice: \(voiceSettings.voiceType)")
            }
            textToSpeechService.speakWithQueue(text, with: voiceSettings)
        }
    }
    
    func shouldUseEnhancedTTS(for voiceType: VoiceType) -> Bool {
        // Use enhanced TTS for character voices
        switch voiceType {
        // Character voices - always use enhanced TTS for best character experience
        case .adam, .eva, .max, .mia:
            return true
        }
    }
    
    func pauseSpeech() {
        textToSpeechService.pauseSpeech()
        enhancedTTSService.pauseSpeech()
    }
    
    func resumeSpeech() {
        textToSpeechService.resumeSpeech()
        enhancedTTSService.resumeSpeech()
    }
    
    func stopSpeech() {
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: Stopping all speech")
            }
        textToSpeechService.stopSpeech()
        enhancedTTSService.stopSpeech()
        
        // Update interaction state to idle
        DispatchQueue.main.async {
            self.interactionState = .idle
            self.currentSpeakingMessageId = nil
        }
    }
    
    func updateVoiceSettings(_ settings: VoiceSettings) {
        let previousVoiceType = voiceSettings.voiceType
        
        voiceSettings = settings
        settings.save()
        
        // Stop current speech if voice character changed
        if previousVoiceType != settings.voiceType {
            if Self.debugMode {
            print("🎙️ VoiceInteractionService: Voice character changed from \(previousVoiceType.displayName) to \(settings.voiceType.displayName), stopping current speech")
            }
            stopSpeech()
            
            // Update interaction state to reflect the change
            DispatchQueue.main.async {
                self.interactionState = .idle
                self.currentSpeakingMessageId = nil
            }
        }
        
        // Update services with new settings
        textToSpeechService.updateVoiceSettings(settings)
        enhancedTTSService.updateVoiceSettings(settings)
    }
    
    // MARK: - Message Tracking
    
    func setCurrentSpeakingMessage(_ messageId: String) {
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: Setting current speaking message: \(messageId)")
            }
        currentSpeakingMessageId = messageId
    }
    
    func clearCurrentSpeakingMessage() {
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: Clearing current speaking message")
            }
        currentSpeakingMessageId = nil
    }
    
    func isMessageCurrentlySpeaking(_ messageId: String) -> Bool {
        return currentSpeakingMessageId == messageId && interactionState == .speaking
    }
    
    func toggleVoiceEnabled() {
        isVoiceEnabled.toggle()
        
        if !isVoiceEnabled {
            stopVoiceInput()
            stopSpeech()
        }
    }
    
    func previewVoiceSettings() {
        let previewText = "Hello! This is how I sound with these voice settings. I'm here to help you learn!"
        
        // Use the best service for preview too
        if shouldUseEnhancedTTS(for: voiceSettings.voiceType) {
            enhancedTTSService.previewVoice(text: previewText)
        } else {
            textToSpeechService.speak(previewText, with: voiceSettings)
        }
    }
    
    // MARK: - Private Methods
    
    private func handleVoiceInputResult(_ result: VoiceInputResult) {
        if Self.debugMode {
        print("🎙️ VoiceInteractionService: handleVoiceInputResult called")
            }
        if Self.debugMode {
        print("🎙️ Result text: '\(result.recognizedText)'")
            }
        if Self.debugMode {
        print("🎙️ Is final: \(result.isFinal)")
            }
        
        lastRecognizedText = result.recognizedText
        
        if result.isFinal {
            if Self.debugMode {
            print("🎙️ VoiceInteractionService: Calling completion handler with: '\(result.recognizedText)'")
            }
            // Call completion handler
            currentVoiceInputCompletion?(result.recognizedText)
            currentVoiceInputCompletion = nil
            
            // Update state
            interactionState = .idle
            // Clear current speaking message when speech input ends
            clearCurrentSpeakingMessage()
        }
    }
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Audio interruption began - pause voice activities
            stopVoiceInput()
            textToSpeechService.pauseSpeech()
            
        case .ended:
            // Audio interruption ended - optionally resume
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    textToSpeechService.resumeSpeech()
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        // Handle route changes (e.g., headphones plugged/unplugged)
        // You could adjust voice settings based on the audio output route
    }
    
    // MARK: - Utility Methods
    
    func isAvailable() -> Bool {
        return speechRecognitionService.isAvailable() && permissionStatus.canUseVoice
    }
    
    func getSupportedLanguages() -> [String] {
        // Get intersection of languages supported by both services
        let speechLanguages = Set(speechRecognitionService.getSupportedLanguages())
        let ttsLanguages = Set(textToSpeechService.getSupportedLanguages())
        return Array(speechLanguages.intersection(ttsLanguages)).sorted()
    }
    
    func getVoicePreview(for voiceType: VoiceType) -> String {
        switch voiceType {
        case .adam:
            return "Hi there! I'm Adam, your friendly learning buddy. I'm here to help you understand everything clearly and make studying fun!"
        case .eva:
            return "Hello! I'm Eva, your study companion. Let's explore knowledge together and make learning an amazing adventure!"
        case .max:
            return "Hey! I'm Max, your energetic study buddy. Let's tackle these questions together and have some fun while learning!"
        case .mia:
            return "Hi! I'm Mia, your playful learning friend. I'll make studying exciting and help you succeed!"
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Accessors
    
    var speechServiceErrorMessage: String? {
        return speechRecognitionService.errorMessage
    }
}