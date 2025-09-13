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
        case .adam:
            // Friendly, encouraging boy voice
            processedText = processedText.replacingOccurrences(of: "Great!", with: "Awesome work, buddy!")
            processedText = processedText.replacingOccurrences(of: "Good", with: "Really good")
            
        case .eva:
            // Kind, supportive girl voice
            processedText = processedText.replacingOccurrences(of: "Great!", with: "That's wonderful!")
            processedText = processedText.replacingOccurrences(of: "Let's", with: "Let's explore this together")
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
        // Use OpenAI for character voices
        switch voiceType {
        // Character voices - always use OpenAI for best character experience
        case .adam, .eva:
            return true
        }
    }
    
    private func generateOpenAIAudio(for request: TTSRequest) {
        isProcessing = true
        
        let cacheKey = createCacheKey(for: request)
        
        // Check cache first
        if let cachedData = audioCache.object(forKey: cacheKey as NSString) {
            print("🎵 EnhancedTTSService: Found cached audio")
            playAudioData(cachedData as Data, for: request)
            return
        }
        
        // Generate audio via server-side TTS endpoint
        Task {
            do {
                let audioData = try await requestServerTTS(for: request)
                
                // Cache the audio data
                audioCache.setObject(audioData as NSData, forKey: cacheKey as NSString)
                
                await MainActor.run {
                    self.playAudioData(audioData, for: request)
                }
            } catch {
                print("🎵 EnhancedTTSService: Server TTS failed: \(error)")
                await MainActor.run {
                    self.useFallbackTTS(for: request)
                }
            }
        }
    }
    
    private func requestServerTTS(for request: TTSRequest) async throws -> Data {
        print("🎵 EnhancedTTSService: Requesting server-side TTS")
        
        // Use same baseURL as NetworkService
        let serverTTSURL = "https://sai-backend-production.up.railway.app/api/ai/tts/generate"
        
        guard let url = URL(string: serverTTSURL) else {
            throw TTSError.invalidURL
        }
        
        // Map voice type to OpenAI voice
        let openAIVoice = mapToOpenAIVoice(request.voiceSettings.voiceType)
        
        // Calculate final speaking rate
        let baseRate = request.voiceSettings.speakingRate
        let voiceTypeMultiplier = request.voiceSettings.voiceType.speakingRateMultiplier
        let expressiveness = request.voiceSettings.expressiveness
        let finalRate = baseRate * voiceTypeMultiplier * expressiveness
        
        let requestBody = [
            "text": request.text,
            "voice": openAIVoice,
            "speed": finalRate.clamped(to: 0.25...4.0)
        ] as [String: Any]
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 60.0 // Increased timeout for TTS generation
        
        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("🎵 EnhancedTTSService: Server TTS Response: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                print("🎵 EnhancedTTSService: Received audio data: \(data.count) bytes")
                return data
            } else {
                let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("🎵 EnhancedTTSService: Server TTS Error (\(httpResponse.statusCode)): \(errorString)")
                
                // Provide specific error messages for common issues
                switch httpResponse.statusCode {
                case 503:
                    throw TTSError.apiError(httpResponse.statusCode, "TTS service temporarily unavailable - using fallback voice")
                case 401, 403:
                    throw TTSError.apiError(httpResponse.statusCode, "Authentication failed - using fallback voice")
                case 500:
                    throw TTSError.apiError(httpResponse.statusCode, "Server configuration error - using fallback voice")
                default:
                    throw TTSError.apiError(httpResponse.statusCode, errorString)
                }
            }
        }
        
        throw TTSError.noResponse
    }
    
    private func mapToOpenAIVoice(_ voiceType: VoiceType) -> String {
        // Map character voice types to OpenAI's available voices with personality matching
        switch voiceType {
        case .adam:
            return "echo" // Clear, youthful male voice for Adam
        case .eva:
            return "nova" // Sweet, engaging female voice for Eva
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