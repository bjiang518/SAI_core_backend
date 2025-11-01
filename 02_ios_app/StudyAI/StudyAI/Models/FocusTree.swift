//
//  FocusTree.swift
//  StudyAI
//
//  Focus tree model for garden collection
//

import Foundation

struct FocusTree: Identifiable, Codable {
    let id: String
    let type: TreeType
    let earnedDate: Date
    let focusDuration: TimeInterval  // in seconds
    let sessionId: String

    var durationInMinutes: Int {
        return Int(focusDuration / 60)
    }

    var formattedDuration: String {
        let hours = Int(focusDuration) / 3600
        let minutes = Int(focusDuration) / 60 % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: earnedDate)
    }

    init(id: String = UUID().uuidString,
         type: TreeType,
         earnedDate: Date = Date(),
         focusDuration: TimeInterval,
         sessionId: String) {
        self.id = id
        self.type = type
        self.earnedDate = earnedDate
        self.focusDuration = focusDuration
        self.sessionId = sessionId
    }
}

// MARK: - Garden Statistics

struct GardenStatistics: Codable {
    var totalTrees: Int
    var totalFocusTime: TimeInterval  // in seconds
    var longestSession: TimeInterval
    var currentStreak: Int  // consecutive days with focus sessions
    var treesByType: [TreeType: Int]

    var totalFocusHours: Double {
        return totalFocusTime / 3600
    }

    var formattedTotalFocusTime: String {
        let hours = Int(totalFocusTime) / 3600
        let minutes = Int(totalFocusTime) / 60 % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }

    init() {
        self.totalTrees = 0
        self.totalFocusTime = 0
        self.longestSession = 0
        self.currentStreak = 0
        self.treesByType = [:]
    }
}
