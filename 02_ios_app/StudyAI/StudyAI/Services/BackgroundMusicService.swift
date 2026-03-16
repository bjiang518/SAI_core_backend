//
//  BackgroundMusicService.swift
//  StudyAI
//
//  Enhanced background music player with playlist support
//  Supports looping audio playback, playlists, and auto-advance
//

import Foundation
import AVFoundation
import Combine

class BackgroundMusicService: NSObject, ObservableObject {
    static let shared = BackgroundMusicService()

    // MARK: - Published Properties
    @Published var isPlaying = false
    @Published var currentTrack: BackgroundMusicTrack?
    @Published var currentPlaylist: MusicPlaylist?
    @Published var currentTrackIndex: Int = 0
    @Published var volume: Float = 0.5 {
        didSet {
            audioPlayer?.volume = volume
            UserDefaults.standard.set(volume, forKey: volumeKey)
        }
    }

    // MARK: - Private Properties
    private var audioPlayer: AVAudioPlayer?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    private var playlists: [MusicPlaylist] = []
    private let downloadService = MusicDownloadService.shared
    private let libraryService = MusicLibraryService.shared
    private var authCancellable: AnyCancellable?
    private var uid: String { AuthenticationService.shared.currentUser?.id ?? "anonymous" }
    private var volumeKey: String { "focus_music_volume_\(uid)" }
    private var playlistsKey: String { "focus_music_playlists_\(uid)" }

    // MARK: - Available Tracks
    var availableTracks: [BackgroundMusicTrack] {
        var tracks: [BackgroundMusicTrack] = [
            // No Music option
            BackgroundMusicTrack(
                id: "no_music",
                name: NSLocalizedString("focus.noMusic", comment: "No Music"),
                fileName: "",
                category: .ambient,
                duration: 0
            ),

            // === BUNDLED TRACKS (Always available, ~10MB total) ===
            // These are included in app bundle for instant playback

            BackgroundMusicTrack(
                id: "focus_flow",
                name: "Focus Flow",
                fileName: "Focus_Flow_2025-10-30T054503",
                category: .lofi,
                duration: 125,  // 2:05
                source: .bundle
            ),

            BackgroundMusicTrack(
                id: "peaceful_piano",
                name: "Peaceful Piano",
                fileName: "peaceful-piano-instrumental-for-studying",
                category: .classical,
                duration: 210,  // 3:30
                source: .bundle
            ),

            BackgroundMusicTrack(
                id: "nature_sounds",
                name: "Nature Sounds",
                fileName: "nature",
                category: .nature,
                duration: 180,  // 3:00
                source: .bundle
            ),

            // === REMOTE DOWNLOADABLE TRACKS (High Quality, ~15MB total) ===
            // These are downloaded on-demand from server

            BackgroundMusicTrack(
                id: "meditation_focus",
                name: "Meditation & Focus",
                fileName: "meditation-amp-focus.mp3",
                category: .lofi,
                duration: 274,  // 4:34
                source: .remote,
                fileSize: 8_400_000,  // ~8.4MB
                description: "Deep focus meditation with lo-fi beats",
                remoteURL: "https://sai-backend-production.up.railway.app/api/music/download/meditation_focus"
            ),

            BackgroundMusicTrack(
                id: "magic_healing",
                name: "Magic Healing",
                fileName: "magic-healing.mp3",
                category: .ambient,
                duration: 200,  // 3:20
                source: .remote,
                fileSize: 7_300_000,  // ~7.3MB
                description: "Peaceful ambient music for deep concentration",
                remoteURL: "https://sai-backend-production.up.railway.app/api/music/download/magic_healing"
            )
        ]

        // Add user library tracks
        tracks.append(contentsOf: libraryService.userTracks)

        return tracks
    }

    private override init() {
        super.init()

        // Load saved volume preference for current user
        let savedVolume = UserDefaults.standard.float(forKey: volumeKey)
        if savedVolume > 0 {
            volume = savedVolume
        }

        loadPlaylists()
        configureAudioSession()

        authCancellable = AuthenticationService.shared.$isAuthenticated
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let saved = UserDefaults.standard.float(forKey: self.volumeKey)
                if saved > 0 { self.volume = saved }
                self.loadPlaylists()
            }
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        do {
            // ✅ FIX: Configure for HIGH-QUALITY music playback
            // Previous: mode: .default (voice quality, mono, low bitrate)
            // Fixed: mode: .moviePlayback (stereo, high quality, optimized for music)
            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,  // ✅ High-quality stereo music mode
                options: [.mixWithOthers]  // Allow mixing with other audio
            )

            // ✅ FIX: Set high sample rate for music (44.1kHz standard)
            // iPhone defaults to 8kHz-16kHz for .default mode (terrible quality)
            try audioSession.setPreferredSampleRate(44100.0)

            // ✅ FIX: Optimize buffer for smooth playback without crackling
            try audioSession.setPreferredIOBufferDuration(0.005)  // 5ms buffer

            try audioSession.setActive(true)

            debugPrint("✅ Audio session configured for HIGH-QUALITY music playback")
            debugPrint("   🎵 Mode: .moviePlayback (stereo, high fidelity)")
            debugPrint("   📊 Sample Rate: 44.1kHz")
            debugPrint("   ⚡ Buffer: 5ms (low latency)")
        } catch {
            debugPrint("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Playback Control

    /// Start playing a single track
    func play(track: BackgroundMusicTrack) {
        // Handle "No Music" option
        if track.id == "no_music" {
            stop()
            currentTrack = track
            currentPlaylist = nil
            return
        }

        // Stop current playback
        stop()

        // Re-activate audio session in case it was interrupted or reconfigured
        configureAudioSession()

        currentTrack = track
        currentPlaylist = nil
        currentTrackIndex = 0

        playTrack(track)
    }

    /// Start playing a playlist
    func playPlaylist(_ playlist: MusicPlaylist, startIndex: Int = 0) {
        guard !playlist.isEmpty, startIndex < playlist.trackIds.count else {
            debugPrint("⚠️ Cannot play empty playlist or invalid index")
            return
        }

        stop()

        // Re-activate audio session in case it was interrupted or reconfigured
        configureAudioSession()

        currentPlaylist = playlist
        currentTrackIndex = startIndex

        if let trackId = playlist.trackIds[safe: startIndex],
           let track = availableTracks.first(where: { $0.id == trackId }) {
            currentTrack = track
            playTrack(track, inPlaylist: true)
        }
    }

    /// Internal method to play a track
    private func playTrack(_ track: BackgroundMusicTrack, inPlaylist: Bool = false) {
        // Get audio URL based on track source
        let audioURL: URL?

        switch track.source {
        case .bundle:
            // Try different extensions for bundled tracks
            audioURL = Bundle.main.url(forResource: track.fileName, withExtension: "mp3") ??
                       Bundle.main.url(forResource: track.fileName, withExtension: "m4a") ??
                       Bundle.main.url(forResource: track.fileName, withExtension: "wav")

        case .remote:
            // Check if downloaded
            if downloadService.isTrackDownloaded(track.id) {
                audioURL = downloadService.getLocalURL(for: track.fileName)
            } else {
                debugPrint("❌ Track not downloaded: \(track.name)")
                // Could trigger download here or show alert
                return
            }

        case .userLibrary:
            // Get from user's music library
            audioURL = libraryService.getAssetURL(for: track)
        }

        guard let url = audioURL else {
            debugPrint("❌ Audio file not found: \(track.fileName)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.numberOfLoops = inPlaylist ? 0 : -1  // Single play for playlist, loop for single track
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            isPlaying = true
            debugPrint("✅ Playing track: \(track.name)")
            debugPrint("📊 Duration: \(audioPlayer?.duration ?? 0) seconds")
            debugPrint("🎵 Source: \(track.source.displayName)")
        } catch {
            debugPrint("❌ Failed to initialize audio player: \(error.localizedDescription)")
        }
    }

    /// Play next track in playlist
    func playNext() {
        guard let playlist = currentPlaylist else {
            // If no playlist, restart current track
            if let track = currentTrack {
                play(track: track)
            }
            return
        }

        let nextIndex = currentTrackIndex + 1
        if nextIndex < playlist.trackIds.count {
            currentTrackIndex = nextIndex
            if let trackId = playlist.trackIds[safe: nextIndex],
               let track = availableTracks.first(where: { $0.id == trackId }) {
                currentTrack = track
                playTrack(track, inPlaylist: true)
            }
        } else {
            // Restart playlist
            currentTrackIndex = 0
            if let trackId = playlist.trackIds[safe: 0],
               let track = availableTracks.first(where: { $0.id == trackId }) {
                currentTrack = track
                playTrack(track, inPlaylist: true)
            }
        }
    }

    /// Play previous track in playlist
    func playPrevious() {
        guard let playlist = currentPlaylist else { return }

        let prevIndex = currentTrackIndex - 1
        if prevIndex >= 0 {
            currentTrackIndex = prevIndex
            if let trackId = playlist.trackIds[safe: prevIndex],
               let track = availableTracks.first(where: { $0.id == trackId }) {
                currentTrack = track
                playTrack(track, inPlaylist: true)
            }
        }
    }

    /// Get next track info
    var nextTrack: BackgroundMusicTrack? {
        guard let playlist = currentPlaylist else { return nil }

        let nextIndex = (currentTrackIndex + 1) % playlist.trackIds.count
        guard let trackId = playlist.trackIds[safe: nextIndex] else { return nil }

        return availableTracks.first(where: { $0.id == trackId })
    }

    /// Pause playback
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        debugPrint("⏸️ Playback paused")
    }

    /// Resume playback
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        debugPrint("▶️ Playback resumed")
    }

    /// Stop playback
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        debugPrint("⏹️ Playback stopped")
    }

    /// Toggle play/pause
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if audioPlayer != nil {
            resume()
        }
    }

    // MARK: - Playlist Management

    /// Create a new playlist
    func createPlaylist(name: String, trackIds: [String]) -> MusicPlaylist {
        let playlist = MusicPlaylist(name: name, trackIds: trackIds)
        playlists.append(playlist)
        savePlaylists()
        debugPrint("✅ Created playlist: \(name) with \(trackIds.count) tracks")
        return playlist
    }

    /// Delete a playlist
    func deletePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
        debugPrint("🗑️ Deleted playlist: \(id)")
    }

    /// Update a playlist
    func updatePlaylist(_ playlist: MusicPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
            savePlaylists()
            debugPrint("✏️ Updated playlist: \(playlist.name)")
        }
    }

    /// Get all playlists
    func getAllPlaylists() -> [MusicPlaylist] {
        return playlists
    }

    // MARK: - Persistence

    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: playlistsKey)
        }
    }

    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: playlistsKey),
              let loadedPlaylists = try? JSONDecoder().decode([MusicPlaylist].self, from: data) else {
            debugPrint("📂 No saved playlists found")
            return
        }

        playlists = loadedPlaylists
        debugPrint("📂 Loaded \(playlists.count) playlists")
    }

    // MARK: - Track Management

    func getTracks(category: BackgroundMusicTrack.MusicCategory) -> [BackgroundMusicTrack] {
        return availableTracks.filter { $0.category == category && $0.id != "no_music" }
    }

    func getTrack(byId id: String) -> BackgroundMusicTrack? {
        return availableTracks.first { $0.id == id }
    }
}

// MARK: - AVAudioPlayerDelegate

extension BackgroundMusicService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if flag, currentPlaylist != nil {
            // Auto-advance to next track in playlist
            playNext()
        }
    }
}

// MARK: - Array Extension for Safe Access

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
