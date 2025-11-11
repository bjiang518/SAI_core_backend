//
//  MusicLibraryService.swift
//  StudyAI
//
//  Service for accessing user's music library
//  Uses MediaPlayer framework to let users select their own songs
//

import Foundation
import MediaPlayer
import Combine

class MusicLibraryService: ObservableObject {
    static let shared = MusicLibraryService()

    // MARK: - Published Properties
    @Published var authorizationStatus: MPMediaLibraryAuthorizationStatus = .notDetermined
    @Published var userTracks: [BackgroundMusicTrack] = []

    // MARK: - Initialization

    private init() {
        checkAuthorizationStatus()
        loadUserTracks()
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                self.authorizationStatus = status
                completion(status == .authorized)
            }
        }
    }

    // MARK: - Track Management

    /// Create a track from MPMediaItem
    func createTrack(from mediaItem: MPMediaItem) -> BackgroundMusicTrack? {
        guard let persistentID = mediaItem.value(forProperty: MPMediaItemPropertyPersistentID) as? NSNumber else {
            return nil
        }

        let trackName = mediaItem.title ?? "Unknown Track"
        let duration = mediaItem.playbackDuration

        let track = BackgroundMusicTrack(
            id: "user_\(persistentID.uint64Value)",
            name: trackName,
            category: .userMusic,
            duration: duration,
            persistentID: String(persistentID.uint64Value)
        )

        return track
    }

    /// Add a track from user's library
    func addUserTrack(_ track: BackgroundMusicTrack) {
        guard track.source == .userLibrary else { return }

        // Avoid duplicates
        if !userTracks.contains(where: { $0.id == track.id }) {
            userTracks.append(track)
            saveUserTracks()
            print("✅ Added user track: \(track.name)")
        }
    }

    /// Remove a user track
    func removeUserTrack(_ trackId: String) {
        userTracks.removeAll { $0.id == trackId }
        saveUserTracks()
        print("🗑️ Removed user track: \(trackId)")
    }

    /// Get MPMediaItem for a track
    func getMediaItem(for track: BackgroundMusicTrack) -> MPMediaItem? {
        guard track.source == .userLibrary,
              let persistentIDString = track.userLibraryPersistentID,
              let persistentID = UInt64(persistentIDString) else {
            return nil
        }

        let predicate = MPMediaPropertyPredicate(
            value: NSNumber(value: persistentID),
            forProperty: MPMediaItemPropertyPersistentID
        )

        let query = MPMediaQuery(filterPredicates: [predicate])
        return query.items?.first
    }

    /// Get asset URL for playback
    func getAssetURL(for track: BackgroundMusicTrack) -> URL? {
        guard let mediaItem = getMediaItem(for: track) else { return nil }
        return mediaItem.assetURL
    }

    // MARK: - Persistence

    private func saveUserTracks() {
        if let encoded = try? JSONEncoder().encode(userTracks) {
            UserDefaults.standard.set(encoded, forKey: "user_music_library_tracks")
        }
    }

    private func loadUserTracks() {
        if let data = UserDefaults.standard.data(forKey: "user_music_library_tracks"),
           let tracks = try? JSONDecoder().decode([BackgroundMusicTrack].self, from: data) {
            userTracks = tracks
            print("📂 Loaded \(userTracks.count) user tracks")
        }
    }
}
