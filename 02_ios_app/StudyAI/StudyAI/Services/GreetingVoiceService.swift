//
//  GreetingVoiceService.swift
//  StudyAI
//
//  Interactive greeting service with voice for the home screen spiral animation
//

import Foundation
import Combine

class GreetingVoiceService: ObservableObject {

    static let shared = GreetingVoiceService()

    @Published var isSpeaking = false
    @Published var isPreloading = false  // Published so UI can react to preloading state
    @Published var currentVoiceType: VoiceType = .eva  // Published so UI reacts to voice type changes

    private let ttsService = EnhancedTTSService()
    private let voiceInteractionService = VoiceInteractionService.shared  // Access user's voice settings
    private var currentGreeting: String = ""
    private var cancellables = Set<AnyCancellable>()  // For observing voice settings changes

    // 20 diverse greeting messages
    private let greetings = [
        "Hello! Ready to have some fun in study today?",
        "Hey there! Let's make learning awesome together!",
        "Welcome back! Your study buddy is here to help!",
        "Hi! Excited to explore new topics with you today?",
        "Good to see you! What shall we discover today?",
        "Hey! Ready to unlock some knowledge?",
        "Welcome! Let's turn curiosity into understanding!",
        "Hi there! Time to make studying feel like an adventure!",
        "Hello friend! Your brain is going to love this!",
        "Hey! Let's tackle some challenges together!",
        "Welcome! Every question is a step closer to mastery!",
        "Hi! Ready to surprise yourself with what you can learn?",
        "Hello! Let's make today's study session count!",
        "Hey there! I've got some cool stuff to share with you!",
        "Welcome back! Your future self will thank you for this!",
        "Hi! Let's transform confusion into clarity together!",
        "Hello! Study time just got a whole lot more interesting!",
        "Hey! Ready to level up your knowledge today?",
        "Welcome! Let's make learning feel effortless!",
        "Hi there! Your study journey continues here!"
    ]

    private init() {
        // Initialize with current voice type
        currentVoiceType = voiceInteractionService.voiceSettings.voiceType

        // Observe voice settings changes and update currentVoiceType
        voiceInteractionService.$voiceSettings
            .map { $0.voiceType }
            .removeDuplicates()
            .sink { [weak self] newVoiceType in
                self?.currentVoiceType = newVoiceType
            }
            .store(in: &cancellables)

        // Preload all greetings in background
        Task {
            await preloadGreetings()
        }
    }

    // Preload all greetings to cache them
    private func preloadGreetings() async {
        // Set preloading state to true at the start
        await MainActor.run {
            self.isPreloading = true
        }

        // Use user's voice settings for preloading
        let userSettings = voiceInteractionService.voiceSettings
        let voiceSettings = VoiceSettings(
            voiceType: userSettings.voiceType,  // Use user's selected voice (Adam or Eva)
            speakingRate: userSettings.speakingRate,
            voicePitch: userSettings.voicePitch,
            volume: userSettings.volume,
            expressiveness: 1.2  // More expressive for greetings
        )

        for greeting in greetings {
            do {
                // Use the new preloadAudio method to actually cache the audio
                try await ttsService.preloadAudio(greeting, with: voiceSettings)

                // Small delay to avoid overwhelming the server
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } catch {
                // Continue with next greeting even if one fails
            }
        }

        // Set preloading state to false when done
        await MainActor.run {
            self.isPreloading = false
        }
    }

    // Speak a random greeting
    func speakRandomGreeting() {
        guard !isSpeaking else { return }

        // Pick a random greeting
        currentGreeting = greetings.randomElement() ?? greetings[0]

        // Set speaking state IMMEDIATELY before calling TTS
        DispatchQueue.main.async {
            self.isSpeaking = true
        }

        // Use user's voice settings from VoiceInteractionService
        let userSettings = voiceInteractionService.voiceSettings
        let voiceSettings = VoiceSettings(
            voiceType: userSettings.voiceType,  // Use user's selected voice
            speakingRate: userSettings.speakingRate,
            voicePitch: userSettings.voicePitch,
            volume: userSettings.volume,
            expressiveness: 1.2  // More expressive for greetings
        )

        ttsService.speak(self.currentGreeting, with: voiceSettings)

        // Start monitoring immediately to sync animation with actual playback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.observeSpeakingState()
        }
    }

    private func observeSpeakingState() {
        // Monitor the TTS service speaking state
        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                // When TTS service stops speaking, update our state immediately
                if !self.ttsService.isSpeaking && self.isSpeaking {
                    self.isSpeaking = false
                    timer.invalidate()
                }
            }
        }

        // Safety timeout - assume finished after 20 seconds
        Task {
            try? await Task.sleep(nanoseconds: 20_000_000_000) // 20 seconds
            await MainActor.run {
                if self.isSpeaking {
                    self.isSpeaking = false
                }
            }
        }
    }

    // Get current greeting text (for debugging)
    func getCurrentGreeting() -> String {
        return currentGreeting
    }
}

// Helper extension for comparable range clamping
extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}