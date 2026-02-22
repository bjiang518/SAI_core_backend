//
//  VoiceModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/8/25.
//

import Foundation
import AVFoundation

// MARK: - Voice Settings Model

struct VoiceSettings: Codable {
    var voiceType: VoiceType = .eva  // Default to Eva voice
    var speakingRate: Float = 0.75 // Faster default pace - was 0.55, now 0.75
    var voicePitch: Float = 1.0
    var autoSpeakResponses: Bool = true
    var language: String = "en-US"
    var volume: Float = 0.85 // Comfortable default volume
    var useEnhancedVoices: Bool = true // Prefer high-quality voices
    var expressiveness: Float = 1.0 // Natural expressiveness for Elsa
    
    // Convert to AVSpeechSynthesisVoice
    var synthesisVoice: AVSpeechSynthesisVoice? {
        return AVSpeechSynthesisVoice(language: language)
    }
    
    // Save to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "voice_settings")
        }
    }
    
    // Load from UserDefaults
    static func load() -> VoiceSettings {
        guard let data = UserDefaults.standard.data(forKey: "voice_settings"),
              let settings = try? JSONDecoder().decode(VoiceSettings.self, from: data) else {
            return VoiceSettings() // Return default
        }
        return settings
    }
}

// MARK: - Voice Type Enum

enum VoiceType: String, CaseIterable, Codable {
    // Kid-Friendly Voice Characters (ElevenLabs powered)
    case adam = "adam"  // Friendly boy voice
    case eva = "eva"    // Kind girl voice
    case max = "max"    // Energetic boy voice
    case mia = "mia"    // Playful girl voice

    var displayName: String {
        switch self {
        case .adam:
            return "Adam"
        case .eva:
            return "Eva"
        case .max:
            return "Max"
        case .mia:
            return "Mia"
        }
    }

    var description: String {
        switch self {
        case .adam:
            return NSLocalizedString("voiceSettings.avatar.adam.desc", comment: "")
        case .eva:
            return NSLocalizedString("voiceSettings.avatar.eva.desc", comment: "")
        case .max:
            return NSLocalizedString("voiceSettings.avatar.max.desc", comment: "")
        case .mia:
            return NSLocalizedString("voiceSettings.avatar.mia.desc", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .adam:
            return "person.fill"
        case .eva:
            return "person.crop.circle.fill"
        case .max:
            return "figure.run"
        case .mia:
            return "star.fill"
        }
    }

    // Voice characteristics for TTS
    var speakingRateMultiplier: Float {
        switch self {
        case .adam:
            return 1.0 // Natural, comfortable pace
        case .eva:
            return 1.05 // Slightly warmer pace
        case .max:
            return 1.15 // Faster, more energetic
        case .mia:
            return 1.08 // Upbeat, playful pace
        }
    }

    var pitchMultiplier: Float {
        switch self {
        case .adam:
            return 0.95 // Slightly lower pitch for boy voice
        case .eva:
            return 1.25 // Higher pitch for girl voice
        case .max:
            return 1.0 // Natural boy pitch, slightly higher than Adam
        case .mia:
            return 1.3 // Bright, playful girl pitch
        }
    }

    // TTS Provider (OpenAI or ElevenLabs)
    var ttsProvider: String {
        switch self {
        case .adam, .eva:
            return "openai"
        case .max, .mia:
            return "elevenlabs"
        }
    }

    // OpenAI Voice IDs (for Adam and Eva)
    var openAIVoiceId: String {
        switch self {
        case .adam:
            return "echo" // Friendly male voice
        case .eva:
            return "nova" // Kind female voice
        case .max, .mia:
            return "" // Not used for ElevenLabs voices
        }
    }

    // ElevenLabs Voice IDs (for Max and Mia)
    var elevenLabsVoiceId: String {
        switch self {
        case .adam, .eva:
            return "" // Not used for OpenAI voices
        case .max:
            return "zZLmKvCp1i04X8E0FJ8B" // Vince - Energetic Male
        case .mia:
            return "aEO01A4wXwd1O8GPgGlF" // Arabella - Playful Female
        }
    }

    // Personality traits for text processing
    var personality: CharacterPersonality {
        switch self {
        case .adam:
            return CharacterPersonality(
                greetingStyle: "Hey buddy!",
                encouragementPhrases: ["Awesome work!", "You're doing great!"],
                thinkingWord: "Hmm..."
            )
        case .eva:
            return CharacterPersonality(
                greetingStyle: "Hi there!",
                encouragementPhrases: ["That's wonderful!", "Great job!"],
                thinkingWord: "Let me think..."
            )
        case .max:
            return CharacterPersonality(
                greetingStyle: "Hey! Ready to learn?",
                encouragementPhrases: ["Yes! You got it!", "Awesome!", "Amazing!"],
                thinkingWord: "Okay so..."
            )
        case .mia:
            return CharacterPersonality(
                greetingStyle: "Hi friend!",
                encouragementPhrases: ["Yay! Good job!", "That's so cool!", "You're amazing!"],
                thinkingWord: "Ooh, let's see..."
            )
        }
    }
    
    // Preferred voice names for better quality (if available)
    var preferredVoiceNames: [String] {
        switch self {
        case .adam:
            return ["Daniel (Enhanced)", "Alex (Enhanced)", "Tom (Enhanced)", "Daniel", "Alex", "Tom", "Fred"] // Male voices
        case .eva:
            return ["Ava (Enhanced)", "Samantha (Enhanced)", "Victoria (Enhanced)", "Ava", "Samantha", "Victoria", "Karen"] // Female voices
        case .max:
            return ["James (Enhanced)", "Reed (Enhanced)", "James", "Reed", "Aaron"] // Energetic male voices
        case .mia:
            return ["Nicky (Enhanced)", "Shelley (Enhanced)", "Nicky", "Shelley", "Emily"] // Playful female voices
        }
    }
}

// MARK: - Character Personality

struct CharacterPersonality {
    let greetingStyle: String
    let encouragementPhrases: [String]
    let thinkingWord: String
}

// MARK: - Voice Interaction State

enum VoiceInteractionState: Equatable {
    case idle
    case listening
    case processing
    case speaking
    case error(String)
    
    var isActive: Bool {
        switch self {
        case .idle, .error:
            return false
        case .listening, .processing, .speaking:
            return true
        }
    }
    
    var displayText: String {
        switch self {
        case .idle:
            return "Ready to listen"
        case .listening:
            return "Listening..."
        case .processing:
            return "Processing..."
        case .speaking:
            return "Speaking..."
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

// MARK: - Voice Permission Status

enum VoicePermissionStatus {
    case notDetermined
    case granted
    case denied
    case restricted
    
    var canUseVoice: Bool {
        return self == .granted
    }
    
    var displayMessage: String {
        switch self {
        case .notDetermined:
            return "Voice features require microphone and speech recognition permissions"
        case .granted:
            return "Voice features are ready to use"
        case .denied:
            return "Please enable microphone and speech recognition in Settings"
        case .restricted:
            return "Voice features are restricted on this device"
        }
    }
}

// MARK: - Voice Interaction Models

struct VoiceInputResult {
    let recognizedText: String
    let confidence: Float
    let isFinal: Bool
    let timestamp: Date
    
    init(recognizedText: String, confidence: Float = 1.0, isFinal: Bool = true) {
        self.recognizedText = recognizedText
        self.confidence = confidence
        self.isFinal = isFinal
        self.timestamp = Date()
    }
}

struct VoiceOutputConfiguration {
    let text: String
    let voiceSettings: VoiceSettings
    let shouldQueue: Bool
    let interruptCurrent: Bool
    
    init(text: String, voiceSettings: VoiceSettings, shouldQueue: Bool = false, interruptCurrent: Bool = true) {
        self.text = text
        self.voiceSettings = voiceSettings
        self.shouldQueue = shouldQueue
        self.interruptCurrent = interruptCurrent
    }
}