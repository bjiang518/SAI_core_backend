//
//  BackgroundMusicTrack.swift
//  StudyAI
//
//  Background music track model for focus sessions
//

import Foundation
import SwiftUI

struct BackgroundMusicTrack: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let fileName: String  // Audio file in bundle
    let category: MusicCategory
    let duration: TimeInterval

    enum MusicCategory: String, CaseIterable, Codable {
        case lofi = "lofi"
        case nature = "nature"
        case classical = "classical"
        case ambient = "ambient"

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
}
