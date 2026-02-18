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
import CryptoKit

@MainActor
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
        // ✅ Use .documentDirectory for permanent storage instead of .cachesDirectory
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        return urls[0].appendingPathComponent("StudyAI_TTS")
    }

    // Cache version key for UserDefaults
    private let cacheVersionKey = "StudyAI_TTS_CacheVersion"

    override init() {
        super.init()
        setupAudioSession()
        setupCache()
        loadVoiceSettings()
        clearOldCacheIfNeeded() // Only clear cache when voice settings change
    }

    private func setupCache() {
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        audioCache.countLimit = 50 // Cache up to 50 audio clips
        audioCache.totalCostLimit = 50 * 1024 * 1024 // 50MB cache limit
    }

    /// Only clear cache when voice settings change to save bandwidth and improve performance
    private func clearOldCacheIfNeeded() {
        let currentVersion = getCurrentCacheVersion()
        let savedVersion = UserDefaults.standard.string(forKey: cacheVersionKey) ?? ""

        // Only clear if cache version changed (voice settings changed)
        if currentVersion != savedVersion {
            print("💾 Voice settings changed, clearing old TTS cache...")
            clearCache()
            UserDefaults.standard.set(currentVersion, forKey: cacheVersionKey)
        } else {
            print("💾 Voice settings unchanged, keeping cached TTS audio files")
        }
    }

    /// Generate a version string based on current voice settings
    private func getCurrentCacheVersion() -> String {
        let settings = currentVoiceSettings
        return "\(settings.voiceType.rawValue)_\(settings.speakingRate)_\(settings.voicePitch)_v1"
    }

    /// Clear all cached audio (only called when voice settings change)
    private func clearCache() {
        // Clear memory cache
        audioCache.removeAllObjects()

        // Clear disk cache
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.removeItem(at: cacheDirectory)
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()

            // ✅ FIX: Use .playback category (not .playAndRecord) to ensure speaker output
            // .playback category always routes to speaker, not earpiece
            // .defaultToSpeaker ensures audio plays from speaker, not receiver
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])

            // ✅ FIX: Activate immediately to ensure proper routing
            try audioSession.setActive(true, options: [])

            print("🔊 Audio session configured: category=.playback, mode=.spokenAudio")
        } catch {
            print("⚠️ Failed to setup audio session: \(error)")
            // Continue anyway - the system will use default settings
        }
    }

    // BATTERY OPTIMIZATION: Deactivate audio session to allow device to enter low-power modes
    private func deactivateAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use .notifyOthersOnDeactivation to allow other apps to resume audio
            try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
            // Non-critical error - continue anyway
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

        DispatchQueue.main.async {
            self.processRequest(request)
        }
    }

    // Preload audio without playing it - just populate the cache
    func preloadAudio(_ text: String, with settings: VoiceSettings? = nil) async throws {
        let voiceSettings = settings ?? currentVoiceSettings
        let processedText = addCharacterPersonality(to: text, for: voiceSettings.voiceType)
        let request = TTSRequest(text: processedText, voiceSettings: voiceSettings)

        let cacheKey = createCacheKey(for: request)

        // Check if already cached in memory
        if audioCache.object(forKey: cacheKey as NSString) != nil {
            return
        }

        // Check if already cached on disk
        if loadFromDiskCache(cacheKey: cacheKey) != nil {
            return
        }

        // Only preload if we should use OpenAI TTS
        guard shouldUseOpenAITTS(for: voiceSettings.voiceType) else {
            return
        }

        do {
            let audioData = try await requestServerTTS(for: request)

            // Cache the audio data in memory
            audioCache.setObject(audioData as NSData, forKey: cacheKey as NSString)

            // Save to disk cache for persistence
            saveToDiskCache(audioData: audioData, cacheKey: cacheKey)
        } catch {
            throw error
        }
    }
    
    private func addCharacterPersonality(to text: String, for voiceType: VoiceType) -> String {
        var processedText = text
        let _ = voiceType.personality

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

        case .max:
            // Energetic, enthusiastic boy voice
            processedText = processedText.replacingOccurrences(of: "Great!", with: "Yes! Awesome!")
            processedText = processedText.replacingOccurrences(of: "Good", with: "Amazing")
            processedText = processedText.replacingOccurrences(of: "Correct", with: "Yes! You got it!")

        case .mia:
            // Playful, curious girl voice
            processedText = processedText.replacingOccurrences(of: "Great!", with: "Yay! That's so cool!")
            processedText = processedText.replacingOccurrences(of: "Let's", with: "Ooh, let's")
            processedText = processedText.replacingOccurrences(of: "Good", with: "So good")
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

        // BATTERY OPTIMIZATION: Deactivate audio session when not in use
        deactivateAudioSession()

        DispatchQueue.main.async {
            self.isSpeaking = false
            self.isPaused = false
            self.speechProgress = 0.0
            self.isProcessing = false
        }
    }
    
    // MARK: - Private Methods
    
    private func processRequest(_ request: TTSRequest) {
        // Use OpenAI TTS for premium voices, fallback to system TTS
        if shouldUseOpenAITTS(for: request.voiceSettings.voiceType) {
            generateOpenAIAudio(for: request)
        } else {
            useFallbackTTS(for: request)
        }
    }
    
    private func shouldUseOpenAITTS(for voiceType: VoiceType) -> Bool {
        // Use ElevenLabs for all character voices if enhanced voices are enabled
        // All 4 characters (Adam, Eva, Max, Mia) use ElevenLabs for best quality
        return currentVoiceSettings.useEnhancedVoices
    }

    private func generateOpenAIAudio(for request: TTSRequest) {
        // ✅ Phase 3.6 (2026-02-16): Set processing flag to prevent race conditions
        // This prevents observer from firing while we're fetching audio from network
        isProcessing = true

        let cacheKey = createCacheKey(for: request)

        // Check memory cache first
        if let cachedData = audioCache.object(forKey: cacheKey as NSString) {
            // ✅ Phase 3.6: Keep processing=true during playback setup
            // Will be set to false in playAudioData when audio actually starts
            playAudioData(cachedData as Data, for: request)
            return
        }

        // Check disk cache
        if let diskData = loadFromDiskCache(cacheKey: cacheKey) {
            // Store in memory cache for faster access next time
            audioCache.setObject(diskData as NSData, forKey: cacheKey as NSString)
            // ✅ Phase 3.6: Keep processing=true during playback setup
            playAudioData(diskData, for: request)
            return
        }

        // Generate audio via server-side TTS endpoint
        Task {
            do {
                let audioData = try await requestServerTTS(for: request)

                // Cache the audio data in memory
                audioCache.setObject(audioData as NSData, forKey: cacheKey as NSString)

                // Save to disk cache for persistence across app launches
                saveToDiskCache(audioData: audioData, cacheKey: cacheKey)

                await MainActor.run {
                    self.playAudioData(audioData, for: request)
                }
            } catch {
                // ✅ Phase 3.6 (2026-02-16): ENABLE FALLBACK on network timeout/error
                // Automatically fallback to system TTS to maintain continuous playback
                print("🎵 EnhancedTTS: Network request failed (\(error)), falling back to SystemTTS")

                await MainActor.run {
                    self.isProcessing = false
                    // ✅ Fallback to system TTS instead of stopping completely
                    self.useFallbackTTS(for: request)
                }
            }
        }
    }

    // MARK: - Disk Cache Methods

    private func loadFromDiskCache(cacheKey: String) -> Data? {
        let fileURL = cacheDirectory.appendingPathComponent("\(cacheKey).mp3")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // ✅ Perform disk I/O synchronously but this method is already called from async contexts
        do {
            let data = try Data(contentsOf: fileURL)
            return data
        } catch {
            return nil
        }
    }

    private func saveToDiskCache(audioData: Data, cacheKey: String) {
        // ✅ Capture cache directory URL on main actor before detaching
        let cacheDir = cacheDirectory

        // ✅ Move disk write to background thread to prevent main thread blocking
        Task.detached(priority: .utility) {
            let fileURL = cacheDir.appendingPathComponent("\(cacheKey).mp3")

            do {
                try audioData.write(to: fileURL)
                print("💾 Cached TTS audio to disk: \(cacheKey)")
            } catch {
                print("⚠️ Failed to save TTS cache to disk: \(error)")
            }
        }
    }
    
    private func requestServerTTS(for request: TTSRequest) async throws -> Data {
        // Use same baseURL as NetworkService
        let serverTTSURL = "https://sai-backend-production.up.railway.app/api/ai/tts/generate"

        guard let url = URL(string: serverTTSURL) else {
            throw TTSError.invalidURL
        }

        let voiceType = request.voiceSettings.voiceType
        let provider = voiceType.ttsProvider

        // Get the appropriate voice ID based on provider
        let voiceId = provider == "openai" ? voiceType.openAIVoiceId : voiceType.elevenLabsVoiceId

        // Calculate final speaking rate
        let baseRate = request.voiceSettings.speakingRate
        let voiceTypeMultiplier = voiceType.speakingRateMultiplier
        let expressiveness = request.voiceSettings.expressiveness
        let finalRate = baseRate * voiceTypeMultiplier * expressiveness

        // ✅ FIX: Truncate text if too long (ElevenLabs limit is ~5000 chars, OpenAI is ~4096)
        let maxChars = provider == "elevenlabs" ? 5000 : 4096
        var textToSpeak = request.text
        if textToSpeak.count > maxChars {
            print("⚠️ TTS text too long (\(textToSpeak.count) chars), truncating to \(maxChars) chars")
            textToSpeak = String(textToSpeak.prefix(maxChars))
        }

        // Debug logging
        print("🎵 EnhancedTTS: voiceType=\(voiceType.rawValue), provider=\(provider), voiceId=\(voiceId), speed=\(finalRate), textLength=\(textToSpeak.count)")

        let requestBody = [
            "text": textToSpeak,
            "voice": voiceId,
            "speed": finalRate.clamped(to: 0.25...4.0),
            "provider": provider
        ] as [String: Any]

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // ✅ Phase 3.6 (2026-02-17): Reduced from 30s to 15s for faster fallback
        // If ElevenLabs is slow (30+ seconds), fail fast and use system TTS instead
        urlRequest.timeoutInterval = 15.0

        // Add authentication header
        if let token = AuthenticationService.shared.getAuthToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 200 {
                return data
            } else {
                // Provide specific error messages for common issues
                switch httpResponse.statusCode {
                case 503:
                    throw TTSError.apiError(httpResponse.statusCode, "TTS service temporarily unavailable - using fallback voice")
                case 401, 403:
                    throw TTSError.apiError(httpResponse.statusCode, "Authentication failed - using fallback voice")
                case 500:
                    throw TTSError.apiError(httpResponse.statusCode, "Server configuration error - using fallback voice")
                default:
                    throw TTSError.apiError(httpResponse.statusCode, "TTS request failed with status \(httpResponse.statusCode) - using fallback voice")
                }
            }
        }

        throw TTSError.noResponse
    }

    private func mapToOpenAIVoice(_ voiceType: VoiceType) -> String {
        // Return the appropriate voice ID based on provider
        return voiceType.ttsProvider == "openai" ? voiceType.openAIVoiceId : voiceType.elevenLabsVoiceId
    }
    
    private func playAudioData(_ data: Data, for request: TTSRequest) {
        // ✅ Phase 3.7 (2026-02-18): CRITICAL FIX - Use regular Task (not detached)
        // Task.detached breaks actor isolation, causing delegate to not be retained
        // Regular Task maintains @MainActor context, ensuring delegate callbacks work
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            print("🎵 [EnhancedTTS] Setting up audio playback...")

            // Activate audio session
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setActive(true)
                print("🎵 [EnhancedTTS] Audio session activated")
            } catch {
                print("🎵 EnhancedTTSService: Warning - could not activate audio session: \(error)")
            }

            // Initialize audio player on main actor (ensures delegate is properly retained)
            do {
                self.audioPlayer = try AVAudioPlayer(data: data)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.volume = request.voiceSettings.volume

                print("🎵 [EnhancedTTS] AVAudioPlayer initialized, delegate set to self")
                print("🎵 [EnhancedTTS] Audio duration: \(self.audioPlayer?.duration ?? 0)s")

                // ✅ Phase 3.7 (2026-02-18): CRITICAL FIX - Check if playback actually starts
                // AVAudioPlayer.play() returns Bool - false means playback failed to start
                let didStart = self.audioPlayer?.play() ?? false

                if didStart {
                    print("🔊 [EnhancedTTS] Playback started successfully")
                    print("   └─ Delegate is: \(self.audioPlayer?.delegate != nil ? "SET ✅" : "NIL ❌")")
                    self.isSpeaking = true
                    // ✅ Phase 3.6 (2026-02-16): Clear processing flag when audio actually starts
                    // This signals to observers that audio is now playing (not loading anymore)
                    self.isProcessing = false
                    self.speechProgress = 0.0

                    // Start progress tracking
                    self.startProgressTracking()
                } else {
                    print("⚠️⚠️⚠️ [EnhancedTTS] PLAYBACK FAILED - AVAudioPlayer.play() returned false!")
                    print("   └─ Audio session active: \(AVAudioSession.sharedInstance().isOtherAudioPlaying)")
                    print("   └─ Audio category: \(AVAudioSession.sharedInstance().category)")
                    print("   └─ This causes watchdog timeout - cleaning up")

                    // Clean up and signal completion (skip this chunk)
                    self.audioPlayer?.delegate = nil
                    self.audioPlayer = nil
                    self.isProcessing = false
                    self.isSpeaking = false

                    print("   └─ Cleanup complete - observer should trigger next chunk")
                }

            } catch {
                print("🎵 EnhancedTTSService: Audio playback failed: \(error)")
                print("⚠️ Skipping audio playback for this chunk to maintain voice consistency")
                // ✅ DISABLED FALLBACK: Don't use iOS TTS fallback to maintain consistent voice quality
                self.errorMessage = "Audio playback failed"
                self.isProcessing = false  // ✅ Phase 3.6: Clear on error too
                self.isSpeaking = false
            }
        }
    }

    private func useFallbackTTS(for request: TTSRequest) {
        // ✅ Phase 3.6 (2026-02-16): Clear processing flag when using fallback
        isProcessing = false

        // Use your existing TextToSpeechService
        fallbackTTS.speak(request.text, with: request.voiceSettings)

        // Sync the state
        isSpeaking = fallbackTTS.isSpeaking
        isPaused = fallbackTTS.isPaused
        speechProgress = fallbackTTS.speechProgress
    }
    
    private func startProgressTracking() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self,
                      let player = self.audioPlayer,
                      player.isPlaying,
                      player.duration > 0 else { return }

                // ✅ Calculate progress and update UI on main thread
                let progress = Float(player.currentTime / player.duration)
                self.speechProgress = progress
            }
        }
    }
    
    private func createCacheKey(for request: TTSRequest) -> String {
        let voiceType = request.voiceSettings.voiceType.rawValue
        let rate = String(format: "%.2f", request.voiceSettings.speakingRate)

        // ✅ Use stable MD5 hash instead of unstable hashValue
        // hashValue changes across app sessions, breaking disk cache!
        let textHash = request.text.md5Hash

        return "tts_\(voiceType)_\(rate)_\(textHash)"
    }
    
    // MARK: - Voice Preview
    
    func previewVoice(text: String = "Hello! This is how I sound with these enhanced settings. I can speak smoothly and naturally, making our conversations more engaging.") {
        speak(text, with: currentVoiceSettings)
    }
    
    func updateVoiceSettings(_ settings: VoiceSettings) {
        let oldVersion = getCurrentCacheVersion()
        currentVoiceSettings = settings
        settings.save()

        // Check if voice-related settings changed
        let newVersion = getCurrentCacheVersion()
        if oldVersion != newVersion {
            print("💾 Voice settings changed from \(oldVersion) to \(newVersion), clearing cache...")
            clearCache()
            UserDefaults.standard.set(newVersion, forKey: cacheVersionKey)
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension EnhancedTTSService: AVAudioPlayerDelegate {

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        print("🎉🎉🎉 [EnhancedTTS] audioPlayerDidFinishPlaying CALLED!")
        print("   └─ Successfully: \(flag)")
        print("   └─ Duration: \(player.duration)s")
        print("   └─ Thread: \(Thread.isMainThread ? "Main ✅" : "Background ❌")")

        progressTimer?.invalidate()
        progressTimer = nil

        DispatchQueue.main.async {
            print("🎉 [EnhancedTTS] Setting isSpeaking = false (this should trigger observer)")
            self.isSpeaking = false
            self.isPaused = false
            self.speechProgress = 1.0
            self.audioPlayer = nil

            // ✅ Phase 3.7 (2026-02-18): CRITICAL FIX - Don't deactivate audio session here!
            // EnhancedTTS doesn't manage the queue - TTSQueueService does.
            // If we deactivate here, subsequent chunks from TTSQueueService will fail to play.
            // TTSQueueService will deactivate the session when its queue is truly empty.

            // Process next in EnhancedTTS's internal queue if any (usually empty)
            if !self.speechQueue.isEmpty {
                print("🎉 [EnhancedTTS] Internal queue has items, processing next")
                let nextRequest = self.speechQueue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.processRequest(nextRequest)
                }
            } else {
                print("🎉 [EnhancedTTS] Chunk complete, observer will trigger next")
                // Don't deactivate audio session - let TTSQueueService manage this
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

// MARK: - String Extension for Stable Hashing

extension String {
    /// Generate a stable MD5 hash for cache keys
    /// Unlike hashValue, this is consistent across app sessions
    var md5Hash: String {
        let digest = Insecure.MD5.hash(data: self.data(using: .utf8) ?? Data())
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
}
