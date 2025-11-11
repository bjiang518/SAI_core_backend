//
//  MusicDownloadService.swift
//  StudyAI
//
//  Service for downloading and caching remote music tracks
//  Manages download queue, progress tracking, and storage
//

import Foundation
import Combine

class MusicDownloadService: NSObject, ObservableObject {
    static let shared = MusicDownloadService()

    // MARK: - Published Properties
    @Published var downloadProgress: [String: Double] = [:]  // trackId -> progress (0.0-1.0)
    @Published var downloadedTracks: Set<String> = []  // Set of downloaded track IDs

    // MARK: - Private Properties
    private var urlSession: URLSession!
    private var activeDownloads: [String: URLSessionDownloadTask] = [:]
    private let cacheDirectory: URL

    // MARK: - Initialization

    private override init() {
        // Setup cache directory
        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.cacheDirectory = documentDir.appendingPathComponent("MusicCache", isDirectory: true)

        super.init()

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure URLSession
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Load downloaded tracks list
        loadDownloadedTracks()

        print("🎵 MusicDownloadService initialized")
        print("📁 Cache directory: \(cacheDirectory.path)")
    }

    // MARK: - Download Management

    /// Start downloading a track
    func downloadTrack(_ track: BackgroundMusicTrack) {
        guard track.source == .remote, let urlString = track.remoteURL else {
            print("❌ Cannot download track: not a remote track or missing URL")
            return
        }

        guard !downloadedTracks.contains(track.id) else {
            print("⚠️ Track already downloaded: \(track.name)")
            return
        }

        guard activeDownloads[track.id] == nil else {
            print("⚠️ Track is already downloading: \(track.name)")
            return
        }

        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL for track: \(track.name)")
            return
        }

        print("📥 Starting download: \(track.name)")
        let downloadTask = urlSession.downloadTask(with: url)
        downloadTask.taskDescription = track.id  // Store track ID
        activeDownloads[track.id] = downloadTask
        downloadProgress[track.id] = 0.0
        downloadTask.resume()
    }

    /// Cancel a download
    func cancelDownload(_ trackId: String) {
        guard let task = activeDownloads[trackId] else { return }

        task.cancel()
        activeDownloads.removeValue(forKey: trackId)
        downloadProgress.removeValue(forKey: trackId)
        print("🚫 Cancelled download: \(trackId)")
    }

    /// Delete a downloaded track
    func deleteTrack(_ trackId: String, fileName: String) {
        let fileURL = cacheDirectory.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: fileURL)
        downloadedTracks.remove(trackId)
        saveDownloadedTracks()

        print("🗑️ Deleted track: \(trackId)")
    }

    /// Check if a track is downloaded
    func isTrackDownloaded(_ trackId: String) -> Bool {
        return downloadedTracks.contains(trackId)
    }

    /// Get local file URL for a downloaded track
    func getLocalURL(for fileName: String) -> URL {
        return cacheDirectory.appendingPathComponent(fileName)
    }

    /// Get cache size
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return totalSize
    }

    /// Clear all cache
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        downloadedTracks.removeAll()
        saveDownloadedTracks()

        print("🧹 Cache cleared")
    }

    // MARK: - Persistence

    private func saveDownloadedTracks() {
        let trackIds = Array(downloadedTracks)
        UserDefaults.standard.set(trackIds, forKey: "downloaded_music_tracks")
    }

    private func loadDownloadedTracks() {
        if let trackIds = UserDefaults.standard.array(forKey: "downloaded_music_tracks") as? [String] {
            downloadedTracks = Set(trackIds)
            print("📂 Loaded \(downloadedTracks.count) downloaded tracks")
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension MusicDownloadService: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let trackId = downloadTask.taskDescription else { return }

        // Get the response to determine file extension
        let suggestedFilename = downloadTask.response?.suggestedFilename ?? "\(trackId).mp3"
        let destinationURL = cacheDirectory.appendingPathComponent(suggestedFilename)

        do {
            // Remove existing file if any
            try? FileManager.default.removeItem(at: destinationURL)

            // Move downloaded file to cache
            try FileManager.default.moveItem(at: location, to: destinationURL)

            DispatchQueue.main.async {
                self.downloadedTracks.insert(trackId)
                self.activeDownloads.removeValue(forKey: trackId)
                self.downloadProgress.removeValue(forKey: trackId)
                self.saveDownloadedTracks()

                print("✅ Download completed: \(trackId)")
                print("📁 Saved to: \(destinationURL.path)")
            }
        } catch {
            print("❌ Failed to save downloaded file: \(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let trackId = downloadTask.taskDescription else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        DispatchQueue.main.async {
            self.downloadProgress[trackId] = progress
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let trackId = task.taskDescription else { return }

        if let error = error {
            print("❌ Download error for \(trackId): \(error.localizedDescription)")

            DispatchQueue.main.async {
                self.activeDownloads.removeValue(forKey: trackId)
                self.downloadProgress.removeValue(forKey: trackId)
            }
        }
    }
}
