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
    // Simplified Voice Characters
    case adam = "adam"  // Boy voice
    case eva = "eva"    // Girl voice
    
    var displayName: String {
        switch self {
        case .adam:
            return "Adam"
        case .eva:
            return "Eva"
        }
    }
    
    var description: String {
        switch self {
        case .adam:
            return "Friendly boy voice for learning"
        case .eva:
            return "Kind girl voice for studying"
        }
    }
    
    var icon: String {
        switch self {
        case .adam:
            return "person.fill"  // Boy icon
        case .eva:
            return "person.crop.circle.fill"  // Girl icon
        }
    }
    
    // Voice characteristics for TTS
    var speakingRateMultiplier: Float {
        switch self {
        case .adam:
            return 1.0 // Natural, comfortable boy pace
        case .eva:
            return 1.05 // Slightly warmer girl pace
        }
    }
    
    var pitchMultiplier: Float {
        switch self {
        case .adam:
            return 0.95 // Slightly lower pitch for boy voice
        case .eva:
            return 1.15 // Higher pitch for girl voice
        }
    }
    
    // Preferred voice names for better quality (if available)
    var preferredVoiceNames: [String] {
        switch self {
        case .adam:
            return ["Daniel (Enhanced)", "Alex (Enhanced)", "Tom (Enhanced)", "Daniel", "Alex", "Tom", "Fred"] // Male voices
        case .eva:
            return ["Ava (Enhanced)", "Samantha (Enhanced)", "Victoria (Enhanced)", "Ava", "Samantha", "Victoria", "Karen"] // Female voices
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