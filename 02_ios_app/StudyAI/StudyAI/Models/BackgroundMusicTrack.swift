//
//  BackgroundMusicTrack.swift
//  StudyAI
//
//  Background music track model for focus sessions
//  Supports local, remote downloadable, and user library tracks
//

import Foundation
import SwiftUI
import MediaPlayer

struct BackgroundMusicTrack: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let fileName: String  // Audio file in bundle or cache
    let category: MusicCategory
    let duration: TimeInterval
    let source: TrackSource

    // Remote download properties
    var remoteURL: String?  // URL for downloadable tracks
    var fileSize: Int64?    // Size in bytes
    var description: String?  // Track description for remote tracks
    var isDownloaded: Bool = false

    // User library properties
    var userLibraryPersistentID: String?  // For user's own music

    enum TrackSource: String, Codable {
        case bundle      // Pre-bundled with app
        case remote      // Downloadable from server
        case userLibrary // From user's music library

        var displayName: String {
            switch self {
            case .bundle: return "Built-in"
            case .remote: return "Download"
            case .userLibrary: return "My Music"
            }
        }

        var icon: String {
            switch self {
            case .bundle: return "app.badge.checkmark"
            case .remote: return "arrow.down.circle"
            case .userLibrary: return "music.note.house"
            }
        }
    }

    enum MusicCategory: String, CaseIterable, Codable {
        case lofi = "lofi"
        case nature = "nature"
        case classical = "classical"
        case ambient = "ambient"
        case userMusic = "user_music"  // New category for user's music

        var displayName: String {
            switch self {
            case .lofi:
                return NSLocalizedString("focus.music.category.lofi", comment: "Lo-fi Beats")
            case .nature:
                return NSLocalizedString("focus.music.category.nature", comment: "Nature Sounds")
            case .classical:
                return NSLocalizedString("focus.music.category.classical", comment: "Classical")
            case .ambient:
                return NSLocalizedString("focus.music.category.ambient", comment: "Ambient")
            case .userMusic:
                return NSLocalizedString("focus.music.category.userMusic", comment: "My Music")
            }
        }

        var icon: String {
            switch self {
            case .lofi:
                return "music.note.list"
            case .nature:
                return "leaf.fill"
            case .classical:
                return "music.note"
            case .ambient:
                return "waveform"
            case .userMusic:
                return "person.fill.badge.plus"
            }
        }

        var color: Color {
            switch self {
            case .lofi:
                return .purple
            case .nature:
                return .green
            case .classical:
                return .blue
            case .ambient:
                return .cyan
            case .userMusic:
                return .pink
            }
        }
    }

    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: BackgroundMusicTrack, rhs: BackgroundMusicTrack) -> Bool {
        return lhs.id == rhs.id
    }

    // Formatted file size
    var formattedFileSize: String? {
        guard let size = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // Check if track needs download
    var needsDownload: Bool {
        return source == .remote && !isDownloaded
    }

    // Initializer for bundle tracks (backward compatible)
    init(id: String, name: String, fileName: String, category: MusicCategory, duration: TimeInterval) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.category = category
        self.duration = duration
        self.source = .bundle
        self.isDownloaded = true  // Bundle tracks are always "downloaded"
    }

    // Full initializer with all properties (supports bundle and remote)
    init(id: String, name: String, fileName: String, category: MusicCategory, duration: TimeInterval,
         source: TrackSource, fileSize: Int64? = nil, description: String? = nil, remoteURL: String? = nil) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.category = category
        self.duration = duration
        self.source = source
        self.fileSize = fileSize
        self.description = description
        self.remoteURL = remoteURL
        self.isDownloaded = (source == .bundle)  // Bundle tracks are always available
    }

    // Initializer for remote tracks (backward compatible)
    init(id: String, name: String, fileName: String, category: MusicCategory, duration: TimeInterval,
         remoteURL: String, fileSize: Int64) {
        self.id = id
        self.name = name
        self.fileName = fileName
        self.category = category
        self.duration = duration
        self.source = .remote
        self.remoteURL = remoteURL
        self.fileSize = fileSize
        self.isDownloaded = false
    }

    // Initializer for user library tracks
    init(id: String, name: String, category: MusicCategory, duration: TimeInterval, persistentID: String) {
        self.id = id
        self.name = name
        self.fileName = ""  // Not used for user library
        self.category = category
        self.duration = duration
        self.source = .userLibrary
        self.userLibraryPersistentID = persistentID
        self.isDownloaded = true  // User library tracks are always "available"
    }
}
