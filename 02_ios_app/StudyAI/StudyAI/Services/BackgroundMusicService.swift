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
            UserDefaults.standard.set(volume, forKey: "focus_music_volume")
        }
    }

    // MARK: - Private Properties
    private var audioPlayer: AVAudioPlayer?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    private var playlists: [MusicPlaylist] = []

    // MARK: - Available Tracks
    let availableTracks: [BackgroundMusicTrack] = [
        // Lo-fi Beats Category
        BackgroundMusicTrack(
            id: "focus_flow",
            name: "Focus Flow",
            fileName: "Focus_Flow_2025-10-30T054503",
            category: .lofi,
            duration: 0
        ),

        // Nature Sounds Category
        BackgroundMusicTrack(
            id: "soft_rain",
            name: "Soft Rain",
            fileName: "AMBRoom-Soft_rain_tapping_on-Elevenlabs",
            category: .nature,
            duration: 0
        ),

        // No Music option
        BackgroundMusicTrack(
            id: "no_music",
            name: NSLocalizedString("focus.noMusic", comment: "No Music"),
            fileName: "",
            category: .ambient,
            duration: 0
        )
    ]

    private override init() {
        super.init()

        // Load saved volume preference
        let savedVolume = UserDefaults.standard.float(forKey: "focus_music_volume")
        if savedVolume > 0 {
            volume = savedVolume
        }

        loadPlaylists()
        configureAudioSession()
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        do {
            // Configure for background audio playback
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("✅ Audio session configured for background playback")
        } catch {
            print("❌ Failed to configure audio session: \(error.localizedDescription)")
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

        currentTrack = track
        currentPlaylist = nil
        currentTrackIndex = 0

        playTrack(track)
    }

    /// Start playing a playlist
    func playPlaylist(_ playlist: MusicPlaylist, startIndex: Int = 0) {
        guard !playlist.isEmpty, startIndex < playlist.trackIds.count else {
            print("⚠️ Cannot play empty playlist or invalid index")
            return
        }

        stop()

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
        guard let audioURL = Bundle.main.url(forResource: track.fileName, withExtension: "mp3") ??
                             Bundle.main.url(forResource: track.fileName, withExtension: "m4a") ??
                             Bundle.main.url(forResource: track.fileName, withExtension: "wav") else {
            print("❌ Audio file not found: \(track.fileName)")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = self
            audioPlayer?.numberOfLoops = inPlaylist ? 0 : -1  // Single play for playlist, loop for single track
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            isPlaying = true
            print("✅ Playing track: \(track.name)")
            print("📊 Duration: \(audioPlayer?.duration ?? 0) seconds")
        } catch {
            print("❌ Failed to initialize audio player: \(error.localizedDescription)")
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
        print("⏸️ Playback paused")
    }

    /// Resume playback
    func resume() {
        audioPlayer?.play()
        isPlaying = true
        print("▶️ Playback resumed")
    }

    /// Stop playback
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        print("⏹️ Playback stopped")
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
        print("✅ Created playlist: \(name) with \(trackIds.count) tracks")
        return playlist
    }

    /// Delete a playlist
    func deletePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
        print("🗑️ Deleted playlist: \(id)")
    }

    /// Update a playlist
    func updatePlaylist(_ playlist: MusicPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = playlist
            savePlaylists()
            print("✏️ Updated playlist: \(playlist.name)")
        }
    }

    /// Get all playlists
    func getAllPlaylists() -> [MusicPlaylist] {
        return playlists
    }

    // MARK: - Persistence

    private func savePlaylists() {
        if let encoded = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(encoded, forKey: "focus_music_playlists")
        }
    }

    private func loadPlaylists() {
        guard let data = UserDefaults.standard.data(forKey: "focus_music_playlists"),
              let loadedPlaylists = try? JSONDecoder().decode([MusicPlaylist].self, from: data) else {
            print("📂 No saved playlists found")
            return
        }

        playlists = loadedPlaylists
        print("📂 Loaded \(playlists.count) playlists")
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
