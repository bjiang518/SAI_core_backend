//
//  FocusSession.swift
//  StudyAI
//
//  Focus session model for tracking study focus time
//

import Foundation
import SwiftUI

struct FocusSession: Identifiable, Codable {
    let id: String
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval  // in seconds
    let backgroundMusicTrack: String?
    var isCompleted: Bool
    var earnedTreeType: TreeType?

    var durationInMinutes: Int {
        return Int(duration / 60)
    }

    var durationInHours: Double {
        return duration / 3600
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    init(id: String = UUID().uuidString,
         startTime: Date = Date(),
         endTime: Date? = nil,
         duration: TimeInterval = 0,
         backgroundMusicTrack: String? = nil,
         isCompleted: Bool = false,
         earnedTreeType: TreeType? = nil) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.backgroundMusicTrack = backgroundMusicTrack
        self.isCompleted = isCompleted
        self.earnedTreeType = earnedTreeType
    }
}

enum TreeType: String, Codable, CaseIterable {
    case sapling = "sapling"           // 0-15 min
    case youngTree = "young_tree"      // 15-30 min
    case matureTree = "mature_tree"    // 30-60 min
    case ancientTree = "ancient_tree"  // 60+ min

    var displayName: String {
        switch self {
        case .sapling:
            return NSLocalizedString("focus.tree.sapling", comment: "Sapling")
        case .youngTree:
            return NSLocalizedString("focus.tree.youngTree", comment: "Young Tree")
        case .matureTree:
            return NSLocalizedString("focus.tree.matureTree", comment: "Mature Tree")
        case .ancientTree:
            return NSLocalizedString("focus.tree.ancientTree", comment: "Ancient Tree")
        }
    }

    var icon: String {
        switch self {
        case .sapling:
            return "leaf.fill"
        case .youngTree:
            return "tree.fill"
        case .matureTree:
            return "tree"
        case .ancientTree:
            return "figure.walk"  // or use a custom icon
        }
    }

    var minMinutes: Int {
        switch self {
        case .sapling:
            return 0
        case .youngTree:
            return 15
        case .matureTree:
            return 30
        case .ancientTree:
            return 60
        }
    }

    var color: Color {
        switch self {
        case .sapling:
            return .green.opacity(0.6)
        case .youngTree:
            return .green
        case .matureTree:
            return Color(red: 0.2, green: 0.5, blue: 0.2)
        case .ancientTree:
            return Color(red: 0.3, green: 0.4, blue: 0.2)
        }
    }

    var emoji: String {
        switch self {
        case .sapling:
            return "🌱"
        case .youngTree:
            return "🌿"
        case .matureTree:
            return "🌳"
        case .ancientTree:
            return "🏛️"
        }
    }

    /// Determine tree type based on focus duration in minutes
    static func from(minutes: Int) -> TreeType {
        if minutes >= 60 {
            return .ancientTree
        } else if minutes >= 30 {
            return .matureTree
        } else if minutes >= 15 {
            return .youngTree
        } else {
            return .sapling
        }
    }

    /// Determine tree type based on duration in seconds
    static func from(seconds: TimeInterval) -> TreeType {
        return from(minutes: Int(seconds / 60))
    }
}
