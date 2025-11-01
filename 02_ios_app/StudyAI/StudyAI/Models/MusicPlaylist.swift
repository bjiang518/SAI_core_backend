//
//  MusicPlaylist.swift
//  StudyAI
//
//  Model for managing music playlists
//

import Foundation

struct MusicPlaylist: Codable, Identifiable {
    let id: String
    var name: String
    var trackIds: [String]
    var createdDate: Date

    init(id: String = UUID().uuidString, name: String, trackIds: [String]) {
        self.id = id
        self.name = name
        self.trackIds = trackIds
        self.createdDate = Date()
    }

    var trackCount: Int {
        trackIds.count
    }

    var isEmpty: Bool {
        trackIds.isEmpty
    }
}
