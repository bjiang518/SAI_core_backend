//
//  EnhancedTTSService.swift
//  StudyAI
//
//  Created by Claude Code on 9/8/25.
//  Enhanced TTS with OpenAI API for smoother, more natural voices
//

import Foundation
import AVFoundation
import Combine

class EnhancedTTSService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isSpeaking = false
    @Published var isPaused = false
    @Published var speechProgress: Float = 0.0
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var currentVoiceSettings = VoiceSettings()
    
    // MARK: - Private Properties
    
    private var audioPlayer: AVAudioPlayer?
    private let fallbackTTS = TextToSpeechService()
    private var speechQueue: [TTSRequest] = []
    private let networkService = NetworkService.shared
    private var progressTimer: Timer?
    
    // OpenAI TTS Configuration
    private var openAIAPIKey: String {
        // Try to get from Info.plist first, then fall back to environment/config
        if let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
           !apiKey.isEmpty && apiKey != "your-openai-api-key" {
            return apiKey
        }
        
        // For testing, you can temporarily hardcode or use UserDefaults
        // In production, store in Keychain or secure configuration
        if let storedKey = UserDefaults.standard.string(forKey: "studyai_openai_api_key"),
           !storedKey.isEmpty {
            return storedKey
        }
        
        // Return empty string - service will fall back to system TTS
        print("⚠️ EnhancedTTSService: No OpenAI API key configured, falling back to system TTS")
        return ""
    }
    
    private let ttsAPIURL = "https://api.openai.com/v1/audio/speech"
    
    // Cache for audio files
    private let audioCache = NSCache<NSString, NSData>()
    private let fileManager = FileManager.default
    private var cacheDirectory: URL {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("StudyAI_TTS")
    }
    
    override init() {
        super.init()
        setupAudioSession()
        setupCache()
        loadVoiceSettings()
        
        print("🎵 EnhancedTTSService: Initialized with OpenAI TTS support")
    }
    
    private func setupCache() {
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        audioCache.countLimit = 50 // Cache up to 50 audio clips
        audioCache.totalCostLimit = 50 * 1024 * 1024 // 50MB cache limit
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Use a more compatible audio session configuration
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothA2DP, .duckOthers])
            
            // Don't activate immediately - let the system handle it
            print("🎵 EnhancedTTSService: Audio session configured (will activate when needed)")
        } catch {
            print("🎵 EnhancedTTSService: Audio session setup failed: \(error)")
            // Continue anyway - the system will use default settings
        }
    }
    
    private func loadVoiceSettings() {
        currentVoiceSettings = VoiceSettings.load()
    }
    
    // MARK: - Public Methods
    
    func speak(_ text: String, with settings: VoiceSettings? = nil) {
        let voiceSettings = settings ?? currentVoiceSettings
        let processedText = addCharacterPersonality(to: text, for: voiceSettings.voiceType)
        let request = TTSRequest(text: processedText, voiceSettings: voiceSettings)
        
        print("🎵 EnhancedTTSService: Speaking request - Text: '\(String(processedText.prefix(50)))...', Voice: \(voiceSettings.voiceType)")
        
        DispatchQueue.main.async {
            self.processRequest(request)
        }
    }
    
    private func addCharacterPersonality(to text: String, for voiceType: VoiceType) -> String {
        var processedText = text
        
        // Add character-specific speech patterns and personality touches
        switch voiceType {
        case .optimusPrime:
            // Add heroic, noble speech patterns
            processedText = processedText.replacingOccurrences(of: "Let's", with: "We shall")
            processedText = processedText.replacingOccurrences(of: "can't", with: "cannot")
            processedText = processedText.replacingOccurrences(of: "won't", with: "will not")
            if processedText.contains("help") {
                processedText = processedText.replacingOccurrences(of: "help", with: "assist in your noble quest for knowledge")
            }
            
        case .spiderman:
            // Add witty, energetic Spider-Man flair
            if processedText.contains("problem") || processedText.contains("question") {
                processedText += " Don't worry, your friendly neighborhood AI has got this covered!"
            }
            processedText = processedText.replacingOccurrences(of: "Great!", with: "Great job, true believer!")
            processedText = processedText.replacingOccurrences(of: "Good", with: "Web-slinging good")
            
        case .groot:
            // Keep it simple and gentle like Groot
            processedText = processedText.replacingOccurrences(of: "I understand", with: "I am Groot. I understand")
            processedText = processedText.replacingOccurrences(of: "Let me help", with: "I am Groot. Let Groot help")
            if processedText.count > 100 {
                // Groot speaks simply, so occasionally remind of his nature
                let sentences = processedText.components(separatedBy: ". ")
                if sentences.count > 2 {
                    processedText = sentences.joined(separator: ". I am Groot. ")
                }
            }
            
        case .yoda:
            // Add Yoda's distinctive speech pattern (occasionally)
            processedText = processedText.replacingOccurrences(of: "You will learn", with: "Learn, you will")
            processedText = processedText.replacingOccurrences(of: "You can do", with: "Do this, you can")
            processedText = processedText.replacingOccurrences(of: "You should", with: "Important it is that you")
            if processedText.contains("understand") {
                processedText = processedText.replacingOccurrences(of: "understand", with: "understand, hmm")
            }
            
        case .ironMan:
            // Add Tony Stark's confident, tech-savvy personality
            processedText = processedText.replacingOccurrences(of: "Let's solve", with: "Let's crack this problem with some Stark tech")
            processedText = processedText.replacingOccurrences(of: "Good work", with: "Excellent work, genius level stuff")
            if processedText.contains("calculate") || processedText.contains("compute") {
                processedText += " FRIDAY would be proud of these calculations!"
            }
            
        case .elsa:
            // Add Elsa's graceful, magical tone
            processedText = processedText.replacingOccurrences(of: "Let's learn", with: "Let's discover the magic of learning")
            processedText = processedText.replacingOccurrences(of: "Good job", with: "Wonderfully done")
            
        default:
            // No special processing for other voice types
            break
        }
        
        return processedText
    }
    
    func pauseSpeech() {
        audioPlayer?.pause()
        DispatchQueue.main.async {
            self.isPaused = true
        }
    }
    
    func resumeSpeech() {
        audioPlayer?.play()
        DispatchQueue.main.async {
            self.isPaused = false
        }
    }
    
    func stopSpeech() {
        audioPlayer?.stop()
        audioPlayer = nil
        progressTimer?.invalidate()
        progressTimer = nil
        speechQueue.removeAll()
        
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.speechProgress = 0.0
            self.isProcessing = false
        }
    }
    
    // MARK: - Private Methods
    
    private func processRequest(_ request: TTSRequest) {
        print("🎵 EnhancedTTSService: Processing TTS request")
        
        // Use OpenAI TTS for premium voices, fallback to system TTS
        if shouldUseOpenAITTS(for: request.voiceSettings.voiceType) {
            generateOpenAIAudio(for: request)
        } else {
            useFallbackTTS(for: request)
        }
    }
    
    private func shouldUseOpenAITTS(for voiceType: VoiceType) -> Bool {
        // Use OpenAI for character voices and premium educational voices
        switch voiceType {
        // Character voices - always use OpenAI for best character experience
        case .elsa, .optimusPrime, .spiderman, .groot, .yoda, .ironMan:
            return true
        // Premium educational voices
        case .friendly, .teacher:
            return true
        // Standard voices - use system TTS for cost efficiency
        case .encouraging, .playful:
            return false
        }
    }
    
    private func generateOpenAIAudio(for request: TTSRequest) {
        // Check if API key is available
        let apiKey = openAIAPIKey
        guard !apiKey.isEmpty else {
            print("🎵 EnhancedTTSService: No OpenAI API key available, using fallback TTS")
            useFallbackTTS(for: request)
            return
        }
        
        isProcessing = true
        
        let cacheKey = createCacheKey(for: request)
        
        // Check cache first
        if let cachedData = audioCache.object(forKey: cacheKey as NSString) {
            print("🎵 EnhancedTTSService: Found cached audio")
            playAudioData(cachedData as Data, for: request)
            return
        }
        
        // Generate new audio via OpenAI API
        Task {
            do {
                let audioData = try await requestOpenAITTS(for: request, apiKey: apiKey)
                
                // Cache the audio data
                audioCache.setObject(audioData as NSData, forKey: cacheKey as NSString)
                
                await MainActor.run {
                    self.playAudioData(audioData, for: request)
                }
            } catch {
                print("🎵 EnhancedTTSService: OpenAI TTS failed: \(error)")
                await MainActor.run {
                    self.useFallbackTTS(for: request)
                }
            }
        }
    }
    
    private func requestOpenAITTS(for request: TTSRequest, apiKey: String) async throws -> Data {
        print("🎵 EnhancedTTSService: Requesting OpenAI TTS")
        
        guard let url = URL(string: ttsAPIURL) else {
            throw TTSError.invalidURL
        }
        
        // Map voice type to OpenAI voice
        let openAIVoice = mapToOpenAIVoice(request.voiceSettings.voiceType)
        
        // Calculate final speaking rate with voice type multipliers
        let baseRate = request.voiceSettings.speakingRate
        let voiceTypeMultiplier = request.voiceSettings.voiceType.speakingRateMultiplier
        let expressiveness = request.voiceSettings.expressiveness
        let finalRate = baseRate * voiceTypeMultiplier * expressiveness
        
        let requestBody: [String: Any] = [
            "model": "tts-1-hd", // Use high-definition model for best quality
            "input": request.text,
            "voice": openAIVoice,
            "speed": finalRate.clamped(to: 0.25...4.0)
        ]
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        urlRequest.timeoutInterval = 30.0
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("🎵 EnhancedTTSService: OpenAI TTS Response: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                print("🎵 EnhancedTTSService: Received audio data: \(data.count) bytes")
                return data
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("🎵 EnhancedTTSService: OpenAI API Error: \(errorString)")
                throw TTSError.apiError(httpResponse.statusCode, errorString)
            }
        }
        
        throw TTSError.noResponse
    }
    
    private func mapToOpenAIVoice(_ voiceType: VoiceType) -> String {
        // Map character voice types to OpenAI's available voices with personality matching
        switch voiceType {
        // Classic voices
        case .friendly:
            return "shimmer" // Warm, friendly female voice
        case .teacher:
            return "alloy" // Clear, professional unisex voice
        case .encouraging:
            return "nova" // Uplifting, encouraging voice
        case .playful:
            return "fable" // Expressive, good for storytelling
            
        // Character voices with personality-matched OpenAI selection
        case .elsa:
            return "nova" // Sweet, engaging female voice - perfect for Elsa-like experience
        case .optimusPrime:
            return "onyx" // Deep, commanding, masculine voice perfect for heroic leader
        case .spiderman:
            return "echo" // Balanced, youthful, energetic voice
        case .groot:
            return "alloy" // Gentle, warm, tree-like resonance 
        case .yoda:
            return "fable" // Distinctive, wise, character-appropriate voice
        case .ironMan:
            return "echo" // Confident, tech-savvy, quick-witted voice
        }
    }
    
    private func playAudioData(_ data: Data, for request: TTSRequest) {
        print("🎵 EnhancedTTSService: Playing audio data")
        
        // Activate audio session just before playing
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(true)
        } catch {
            print("🎵 EnhancedTTSService: Warning - could not activate audio session: \(error)")
        }
        
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = request.voiceSettings.volume
            
            isSpeaking = true
            isProcessing = false
            speechProgress = 0.0
            
            // Start progress tracking
            startProgressTracking()
            
            audioPlayer?.play()
            
        } catch {
            print("🎵 EnhancedTTSService: Audio playback failed: \(error)")
            errorMessage = "Audio playback failed"
            isProcessing = false
            useFallbackTTS(for: request)
        }
    }
    
    private func useFallbackTTS(for request: TTSRequest) {
        print("🎵 EnhancedTTSService: Using fallback system TTS")
        isProcessing = false
        
        // Use your existing TextToSpeechService
        fallbackTTS.speak(request.text, with: request.voiceSettings)
        
        // Sync the state
        isSpeaking = fallbackTTS.isSpeaking
        isPaused = fallbackTTS.isPaused
        speechProgress = fallbackTTS.speechProgress
    }
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard let player = self.audioPlayer, player.isPlaying else { return }
            
            DispatchQueue.main.async {
                if player.duration > 0 {
                    self.speechProgress = Float(player.currentTime / player.duration)
                }
            }
        }
    }
    
    private func createCacheKey(for request: TTSRequest) -> String {
        let voiceType = request.voiceSettings.voiceType.rawValue
        let rate = String(format: "%.2f", request.voiceSettings.speakingRate)
        let textHash = String(request.text.hashValue)
        return "tts_\(voiceType)_\(rate)_\(textHash)"
    }
    
    // MARK: - Voice Preview
    
    func previewVoice(text: String = "Hello! This is how I sound with these enhanced settings. I can speak smoothly and naturally, making our conversations more engaging.") {
        speak(text, with: currentVoiceSettings)
    }
    
    func updateVoiceSettings(_ settings: VoiceSettings) {
        currentVoiceSettings = settings
        settings.save()
    }
}

// MARK: - AVAudioPlayerDelegate

extension EnhancedTTSService: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🎵 EnhancedTTSService: Audio finished playing, success: \(flag)")
        
        progressTimer?.invalidate()
        progressTimer = nil
        
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.speechProgress = 1.0
            self.audioPlayer = nil
            
            // Process next in queue if any
            if !self.speechQueue.isEmpty {
                let nextRequest = self.speechQueue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processRequest(nextRequest)
                }
            }
        }
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("🎵 EnhancedTTSService: Audio decode error: \(error?.localizedDescription ?? "Unknown")")
        
        DispatchQueue.main.async {
            self.errorMessage = "Audio playback error"
            self.isSpeaking = false
            self.isProcessing = false
        }
    }
}

// MARK: - Supporting Types

struct TTSRequest {
    let text: String
    let voiceSettings: VoiceSettings
    let timestamp: Date = Date()
}

enum TTSError: Error {
    case invalidURL
    case noResponse
    case apiError(Int, String)
    case audioPlaybackError
    
    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .noResponse:
            return "No response from TTS service"
        case .apiError(let code, let message):
            return "API Error \(code): \(message)"
        case .audioPlaybackError:
            return "Audio playback failed"
        }
    }
}

// MARK: - Float Extension

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}