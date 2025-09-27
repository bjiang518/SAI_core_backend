//
//  TextToSpeechService.swift
//  StudyAI
//
//  Created by Claude Code on 9/8/25.
//

import Foundation
import AVFoundation
import Combine

class TextToSpeechService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var currentVoiceSettings = VoiceSettings()
    @Published var speechProgress: Float = 0.0
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var speechQueue: [VoiceOutputConfiguration] = []
    private var currentText: String = ""
    private var totalCharacters: Int = 0
    private var spokenCharacters: Int = 0
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        speechSynthesizer.delegate = self
        setupAudioSession()
        loadVoiceSettings()
    }
    
    private func setupAudioSession() {
        print("🔊 TextToSpeechService: Setting up audio session")
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Use playback category with enhanced options for Elsa-like voice
            try audioSession.setCategory(.playback, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("🔊 TextToSpeechService: Audio session setup successful")
            print("🔊 TextToSpeechService: Current category: \(audioSession.category)")
            print("🔊 TextToSpeechService: Current mode: \(audioSession.mode)")
        } catch {
            print("🔊 TextToSpeechService: Failed to setup audio session: \(error)")
            errorMessage = "Audio setup failed"
        }
    }
    
    private func loadVoiceSettings() {
        currentVoiceSettings = VoiceSettings.load()
    }
    
    // MARK: - Public Methods
    
    func speak(_ text: String, with settings: VoiceSettings? = nil) {
        print("🔊 TextToSpeechService: speak() called with text: '\(text)'")
        let voiceSettings = settings ?? currentVoiceSettings
        let configuration = VoiceOutputConfiguration(text: text, voiceSettings: voiceSettings)
        
        DispatchQueue.main.async {
            self.speakImmediately(configuration)
        }
    }
    
    func speakWithQueue(_ text: String, with settings: VoiceSettings? = nil) {
        let voiceSettings = settings ?? currentVoiceSettings
        let configuration = VoiceOutputConfiguration(
            text: text,
            voiceSettings: voiceSettings,
            shouldQueue: true,
            interruptCurrent: false
        )
        
        if isSpeaking {
            speechQueue.append(configuration)
        } else {
            DispatchQueue.main.async {
                self.speakImmediately(configuration)
            }
        }
    }
    
    func pauseSpeech() {
        guard isSpeaking else { return }
        
        speechSynthesizer.pauseSpeaking(at: .immediate)
        DispatchQueue.main.async {
            self.isPaused = true
        }
    }
    
    func resumeSpeech() {
        guard isPaused else { return }
        
        speechSynthesizer.continueSpeaking()
        DispatchQueue.main.async {
            self.isPaused = false
        }
    }
    
    func stopSpeech() {
        speechSynthesizer.stopSpeaking(at: .immediate)
        speechQueue.removeAll()
        
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.speechProgress = 0.0
            self.currentUtterance = nil
            self.currentText = ""
        }
    }
    
    func updateVoiceSettings(_ settings: VoiceSettings) {
        currentVoiceSettings = settings
        settings.save()
    }
    
    // MARK: - Private Methods
    
    private func speakImmediately(_ configuration: VoiceOutputConfiguration) {
        print("🔊 TextToSpeechService: speakImmediately() called")
        
        // Ensure audio session is properly configured for playback
        setupAudioSessionForPlayback()
        
        // Stop current speech if configured to interrupt
        if configuration.interruptCurrent && isSpeaking {
            print("🔊 TextToSpeechService: Stopping current speech")
            stopSpeech()
        }
        
        let utterance = createUtterance(from: configuration)
        currentUtterance = utterance
        currentText = configuration.text
        totalCharacters = configuration.text.count
        spokenCharacters = 0
        
        print("🔊 TextToSpeechService: Created utterance with voice: \(utterance.voice?.name ?? "nil")")
        print("🔊 TextToSpeechService: Rate: \(utterance.rate), Pitch: \(utterance.pitchMultiplier), Volume: \(utterance.volume)")
        
        isSpeaking = true
        isPaused = false
        speechProgress = 0.0
        errorMessage = nil
        
        print("🔊 TextToSpeechService: Starting speech synthesis")
        speechSynthesizer.speak(utterance)
    }
    
    private func setupAudioSessionForPlayback() {
        print("🔊 TextToSpeechService: Setting up audio session for playback")
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Temporarily switch to playAndRecord to allow both voice and TTS
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("🔊 TextToSpeechService: Audio session configured for playback")
        } catch {
            print("🔊 TextToSpeechService: Failed to setup playback audio session: \(error)")
        }
    }
    
    private func createUtterance(from configuration: VoiceOutputConfiguration) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: preprocessTextForSpeech(configuration.text))
        
        // Apply voice settings
        let settings = configuration.voiceSettings
        let voiceType = settings.voiceType
        
        // Set voice with preference for high-quality options
        if let voice = findBestVoice(for: settings.language) {
            utterance.voice = voice
        }
        
        // Apply speaking rate with voice type multiplier and expressiveness
        let baseRate = settings.speakingRate
        let adjustedRate = baseRate * voiceType.speakingRateMultiplier * settings.expressiveness
        utterance.rate = adjustedRate.clamped(to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
        
        // Apply pitch with voice type multiplier for warmth
        let basePitch = settings.voicePitch
        let adjustedPitch = basePitch * voiceType.pitchMultiplier
        utterance.pitchMultiplier = adjustedPitch.clamped(to: 0.5...2.0)
        
        // Apply volume - always respect user settings
        utterance.volume = settings.volume.clamped(to: 0.0...1.0)
        
        // Enhanced pre/post utterance delays for Eva voice type
        if voiceType == .eva {
            utterance.preUtteranceDelay = 0.0  // Immediate start for clarity
            utterance.postUtteranceDelay = 0.08 // Brief pause between sentences
        } else {
            utterance.preUtteranceDelay = 0.1
            utterance.postUtteranceDelay = 0.2
        }
        
        return utterance
    }
    
    private func preprocessTextForSpeech(_ text: String) -> String {
        var processedText = text
        
        // Replace mathematical expressions for better pronunciation
        processedText = processedText.replacingOccurrences(of: "x²", with: "x squared")
        processedText = processedText.replacingOccurrences(of: "²", with: " squared")
        processedText = processedText.replacingOccurrences(of: "³", with: " cubed")
        processedText = processedText.replacingOccurrences(of: "√", with: "square root of")
        
        // Replace mathematical symbols
        processedText = processedText.replacingOccurrences(of: "≠", with: "does not equal")
        processedText = processedText.replacingOccurrences(of: "≤", with: "less than or equal to")
        processedText = processedText.replacingOccurrences(of: "≥", with: "greater than or equal to")
        processedText = processedText.replacingOccurrences(of: "∞", with: "infinity")
        
        // Replace common abbreviations
        processedText = processedText.replacingOccurrences(of: "e.g.", with: "for example")
        processedText = processedText.replacingOccurrences(of: "i.e.", with: "that is")
        processedText = processedText.replacingOccurrences(of: "etc.", with: "and so on")
        
        // Add natural pauses for better flow
        processedText = processedText.replacingOccurrences(of: "\n\n", with: ". ")
        processedText = processedText.replacingOccurrences(of: "\n", with: ". ")
        
        // Add pauses after colons and semicolons for better comprehension
        processedText = processedText.replacingOccurrences(of: ":", with: ": ")
        processedText = processedText.replacingOccurrences(of: ";", with: "; ")
        
        // Improve readability of numbers
        processedText = processedText.replacingOccurrences(of: "1st", with: "first")
        processedText = processedText.replacingOccurrences(of: "2nd", with: "second")
        processedText = processedText.replacingOccurrences(of: "3rd", with: "third")
        
        // Add natural emphasis for certain words that are important for kids
        processedText = processedText.replacingOccurrences(of: "Great job", with: "Great job!")
        processedText = processedText.replacingOccurrences(of: "Well done", with: "Well done!")
        processedText = processedText.replacingOccurrences(of: "Excellent", with: "Excellent!")
        
        // Clean up multiple spaces
        processedText = processedText.replacingOccurrences(of: "  ", with: " ")
        
        return processedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func findBestVoice(for languageCode: String) -> AVSpeechSynthesisVoice? {
        print("🔊 TextToSpeechService: Finding best voice for language: \(languageCode)")
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Log all available voices for debugging
        print("🔊 Available voices:")
        for voice in voices {
            print("  - \(voice.name) (\(voice.language)) [\(voice.identifier)] - Quality: \(voice.quality.rawValue)")
        }
        
        // Get current voice type preferences
        let voiceType = currentVoiceSettings.voiceType
        let preferredNames = voiceType.preferredVoiceNames
        
        print("🔊 TextToSpeechService: Voice type: \(voiceType), preferred names: \(preferredNames)")
        
        // First, try to find preferred voices by name for the language
        for name in preferredNames {
            // Try exact match first
            if let voice = voices.first(where: { $0.name == name && $0.language.hasPrefix(languageCode) }) {
                print("🔊 TextToSpeechService: Found exact preferred voice: \(voice.name) (Quality: \(voice.quality.rawValue))")
                return voice
            }
            
            // Try partial match for enhanced voices (e.g., "Ava (Enhanced)")
            if let voice = voices.first(where: { $0.name.contains(name) && $0.language.hasPrefix(languageCode) }) {
                print("🔊 TextToSpeechService: Found partial match preferred voice: \(voice.name) (Quality: \(voice.quality.rawValue))")
                return voice
            }
        }
        
        // Fallback: Find enhanced quality voices for the language (prioritize for Elsa voice)
        let enhancedVoices = voices.filter { 
            $0.language.hasPrefix(languageCode) && $0.quality == .enhanced 
        }
        
        if !enhancedVoices.isEmpty {
            // For Eva voice type, prefer female-sounding names
            if voiceType == .eva {
                let femaleEnhancedVoices = enhancedVoices.filter { voice in
                    let femaleSoundingNames = ["Ava", "Samantha", "Victoria", "Karen", "Susan", "Emma", "Zoe"]
                    return femaleSoundingNames.contains { voice.name.contains($0) }
                }
                if let voice = femaleEnhancedVoices.first {
                    print("🔊 TextToSpeechService: Found female enhanced voice for Eva: \(voice.name)")
                    return voice
                }
            }
            
            // For Adam voice type, prefer male-sounding names
            if voiceType == .adam {
                let maleEnhancedVoices = enhancedVoices.filter { voice in
                    let maleSoundingNames = ["Daniel", "Alex", "Tom", "Fred", "Ralph", "Oliver", "William"]
                    return maleSoundingNames.contains { voice.name.contains($0) }
                }
                if let voice = maleEnhancedVoices.first {
                    print("🔊 TextToSpeechService: Found male enhanced voice for Adam: \(voice.name)")
                    return voice
                }
            }
            
            let voice = enhancedVoices.first!
            print("🔊 TextToSpeechService: Found enhanced voice: \(voice.name)")
            return voice
        }
        
        // Fallback: Find default quality voices
        let defaultVoices = voices.filter { 
            $0.language.hasPrefix(languageCode) && $0.quality == .default 
        }
        
        if !defaultVoices.isEmpty {
            let voice = defaultVoices.first!
            print("🔊 TextToSpeechService: Found default voice: \(voice.name)")
            return voice
        }
        
        // Final fallback
        let fallbackVoice = AVSpeechSynthesisVoice(language: languageCode)
        print("🔊 TextToSpeechService: Using fallback voice: \(fallbackVoice?.name ?? "system default")")
        return fallbackVoice
    }
    
    private func processNextInQueue() {
        guard !speechQueue.isEmpty else { return }
        
        let nextConfiguration = speechQueue.removeFirst()
        speakImmediately(nextConfiguration)
    }
    
    // MARK: - Utility Methods
    
    func getAvailableVoices(for languageCode: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { 
            $0.language.hasPrefix(languageCode) 
        }
    }
    
    func getSupportedLanguages() -> [String] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let languages = Set(voices.map { $0.language })
        return Array(languages).sorted()
    }
    
    func previewVoice(text: String = "Hello! This is how I sound with these settings.") {
        speak(text, with: currentVoiceSettings)
    }
    
    // MARK: - Voice Enumeration (Debug Helper)
    
    func enumerateAllVoices() {
        print("🔊 === All Available Voices ===")
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            print("Name: \(voice.name)")
            print("Language: \(voice.language)")
            print("Identifier: \(voice.identifier)")
            print("Quality: \(voice.quality.rawValue)")
            print("---")
        }
    }
    
    func getEnhancedVoicesForLanguage(_ language: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(language) && $0.quality == .enhanced
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🔊 TextToSpeechService: didStart utterance")
        DispatchQueue.main.async {
            self.isSpeaking = true
            self.isPaused = false
            self.speechProgress = 0.0
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("🔊 TextToSpeechService: didFinish utterance")
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.speechProgress = 1.0
            self.currentUtterance = nil
            
            // Process next item in queue
            if !self.speechQueue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.processNextInQueue()
                }
            }
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = true
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isPaused = false
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.speechProgress = 0.0
            self.currentUtterance = nil
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // Update progress based on character range
            self.spokenCharacters = characterRange.location + characterRange.length
            if self.totalCharacters > 0 {
                self.speechProgress = Float(self.spokenCharacters) / Float(self.totalCharacters)
            }
        }
    }
}

// MARK: - Float Extension for Clamping

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}