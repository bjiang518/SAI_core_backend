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
    var voiceType: VoiceType = .elsa  // Default to Elsa voice
    var speakingRate: Float = 0.55 // Normal pace that works well with character multipliers
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
    // Classic Educational Voices
    case friendly = "friendly"
    case teacher = "teacher" 
    case encouraging = "encouraging"
    case playful = "playful"
    
    // Popular Character Voices
    case elsa = "elsa"
    case optimusPrime = "optimus_prime"
    case spiderman = "spiderman"
    case groot = "groot"
    case yoda = "yoda"
    case ironMan = "iron_man"
    
    var displayName: String {
        switch self {
        // Classic voices
        case .friendly:
            return "Friendly Helper"
        case .teacher:
            return "Patient Teacher"
        case .encouraging:
            return "Cheerful Coach"
        case .playful:
            return "Fun Buddy"
            
        // Character voices
        case .elsa:
            return "Elsa"
        case .optimusPrime:
            return "Optimus Prime"
        case .spiderman:
            return "Spider-Man"
        case .groot:
            return "Groot"
        case .yoda:
            return "Yoda"
        case .ironMan:
            return "Iron Man"
        }
    }
    
    var description: String {
        switch self {
        // Classic voices
        case .friendly:
            return "Warm and approachable voice"
        case .teacher:
            return "Clear and educational tone"
        case .encouraging:
            return "Motivating and positive"
        case .playful:
            return "Fun and energetic"
            
        // Character voices
        case .elsa:
            return "Clear, crisp, and magical tone"
        case .optimusPrime:
            return "Noble, heroic, and inspiring leader"
        case .spiderman:
            return "Witty, energetic, and friendly neighborhood hero"
        case .groot:
            return "Gentle giant with simple wisdom"
        case .yoda:
            return "Wise, ancient, and thoughtful Jedi Master"
        case .ironMan:
            return "Confident, clever, and tech-savvy genius"
        }
    }
    
    var icon: String {
        switch self {
        // Classic voices
        case .friendly:
            return "heart.fill"
        case .teacher:
            return "graduationcap.fill"
        case .encouraging:
            return "star.fill"
        case .playful:
            return "party.popper.fill"
            
        // Character voices
        case .elsa:
            return "snowflake"
        case .optimusPrime:
            return "shield.righthalf.filled"
        case .spiderman:
            return "network"
        case .groot:
            return "tree.fill"
        case .yoda:
            return "sparkles"
        case .ironMan:
            return "bolt.circle.fill"
        }
    }
    
    // Voice characteristics for TTS
    var speakingRateMultiplier: Float {
        switch self {
        // Classic voices
        case .friendly:
            return 1.0 // Natural, comfortable pace
        case .teacher:
            return 0.85 // Slower for clear explanations
        case .encouraging:
            return 1.05 // Slightly upbeat
        case .playful:
            return 1.15 // More dynamic and fun
            
        // Character voices with personality-matched pacing
        case .elsa:
            return 0.96 // Clear, measured pace (0.43 base * 0.96 ≈ 0.41)
        case .optimusPrime:
            return 0.78 // Slow, commanding, thoughtful leader
        case .spiderman:
            return 1.25 // Fast-talking, energetic web-slinger
        case .groot:
            return 0.65 // Very slow, gentle giant
        case .yoda:
            return 0.88 // Deliberate, wise, contemplative
        case .ironMan:
            return 1.18 // Quick-witted, confident, fast talker
        }
    }
    
    var pitchMultiplier: Float {
        switch self {
        // Classic voices
        case .friendly:
            return 1.05 // Slightly warmer than default
        case .teacher:
            return 1.0 // Natural, authoritative
        case .encouraging:
            return 1.1 // Uplifting and positive
        case .playful:
            return 1.15 // Higher and more animated
            
        // Character voices with personality-matched pitch
        case .elsa:
            return 1.18 // Bright, clear, slightly higher pitch
        case .optimusPrime:
            return 0.85 // Deep, resonant, commanding voice
        case .spiderman:
            return 1.12 // Youthful, energetic, slightly higher
        case .groot:
            return 0.92 // Gentle, warm, tree-like resonance
        case .yoda:
            return 1.08 // Distinctive, wise, slightly higher with age
        case .ironMan:
            return 1.02 // Confident, clear, slightly elevated
        }
    }
    
    // Preferred voice names for better quality (if available)
    var preferredVoiceNames: [String] {
        switch self {
        // Classic voices
        case .friendly:
            return ["Samantha", "Alex", "Victoria", "Karen", "Daniel"]
        case .teacher:
            return ["Alex", "Daniel", "Victoria", "Karen", "Samantha"]
        case .encouraging:
            return ["Samantha", "Victoria", "Alex", "Karen", "Daniel"]
        case .playful:
            return ["Samantha", "Victoria", "Karen", "Alex", "Daniel"]
            
        // Character voices with personality-matched voice selection
        case .elsa:
            return ["Ava (Enhanced)", "Samantha (Enhanced)", "Victoria (Enhanced)", "Ava", "Samantha", "Victoria"]
        case .optimusPrime:
            return ["Daniel", "Alex", "Fred", "Ralph", "Tom"] // Deep, authoritative male voices
        case .spiderman:
            return ["Alex", "Daniel", "Tom", "Fred", "Victoria"] // Youthful, energetic voices
        case .groot:
            return ["Fred", "Ralph", "Daniel", "Alex", "Tom"] // Gentle, deeper voices
        case .yoda:
            return ["Fred", "Alex", "Daniel", "Ralph", "Tom"] // Character-appropriate voices
        case .ironMan:
            return ["Alex", "Daniel", "Tom", "Fred", "Victoria"] // Confident, clear voices
        }
    }
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