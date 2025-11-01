//
//  FocusTreeGardenService.swift
//  StudyAI
//
//  Service for managing the focus tree garden and statistics
//

import Foundation
import Combine

class FocusTreeGardenService: ObservableObject {
    static let shared = FocusTreeGardenService()

    // MARK: - Published Properties
    @Published var trees: [FocusTree] = []
    @Published var statistics: GardenStatistics = GardenStatistics()

    // MARK: - Private Properties
    private let treesKey = "focus_garden_trees"
    private let statisticsKey = "focus_garden_statistics"

    private init() {
        loadTrees()
        loadStatistics()
    }

    // MARK: - Tree Management

    /// Add a new tree to the garden from a completed focus session
    func plantTree(from session: FocusSession) -> FocusTree {
        guard session.isCompleted,
              let treeType = session.earnedTreeType else {
            print("⚠️ Cannot plant tree: session not completed or no tree type")
            // Return a default sapling tree as fallback
            let fallbackTree = FocusTree(
                type: .sapling,
                focusDuration: 0,
                sessionId: session.id
            )
            return fallbackTree
        }

        let tree = FocusTree(
            type: treeType,
            focusDuration: session.duration,
            sessionId: session.id
        )

        trees.append(tree)
        updateStatistics(newTree: tree)
        saveTrees()

        print("🌳 New tree planted: \(treeType.displayName) from \(tree.formattedDuration) focus")
        return tree
    }

    /// Remove a tree from the garden
    func removeTree(id: String) {
        if let index = trees.firstIndex(where: { $0.id == id }) {
            let tree = trees[index]
            trees.remove(at: index)

            // Update statistics
            statistics.totalTrees = max(0, statistics.totalTrees - 1)
            statistics.totalFocusTime = max(0, statistics.totalFocusTime - tree.focusDuration)

            if let count = statistics.treesByType[tree.type] {
                statistics.treesByType[tree.type] = max(0, count - 1)
            }

            saveTrees()
            saveStatistics()
            print("🗑️ Tree removed: \(tree.id)")
        }
    }

    /// Clear all trees from the garden
    func clearGarden() {
        trees.removeAll()
        statistics = GardenStatistics()
        saveTrees()
        saveStatistics()
        print("🗑️ Garden cleared")
    }

    // MARK: - Statistics

    private func updateStatistics(newTree: FocusTree) {
        statistics.totalTrees += 1
        statistics.totalFocusTime += newTree.focusDuration
        statistics.longestSession = max(statistics.longestSession, newTree.focusDuration)

        // Update tree count by type
        let currentCount = statistics.treesByType[newTree.type] ?? 0
        statistics.treesByType[newTree.type] = currentCount + 1

        // Update streak
        updateStreak()

        saveStatistics()
    }

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get unique dates from trees
        let uniqueDates = Set(trees.map { tree in
            calendar.startOfDay(for: tree.earnedDate)
        }).sorted(by: >)

        guard !uniqueDates.isEmpty else {
            statistics.currentStreak = 0
            return
        }

        // Calculate consecutive days
        var streak = 0
        var currentDate = today

        for date in uniqueDates {
            if calendar.isDate(date, inSameDayAs: currentDate) {
                streak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else {
                break
            }
        }

        statistics.currentStreak = streak
    }

    func recalculateStatistics() {
        var stats = GardenStatistics()

        stats.totalTrees = trees.count
        stats.totalFocusTime = trees.reduce(0) { $0 + $1.focusDuration }
        stats.longestSession = trees.map { $0.focusDuration }.max() ?? 0

        // Calculate trees by type
        for tree in trees {
            let currentCount = stats.treesByType[tree.type] ?? 0
            stats.treesByType[tree.type] = currentCount + 1
        }

        statistics = stats
        updateStreak()
        saveStatistics()
    }

    // MARK: - Filtering

    func trees(ofType type: TreeType) -> [FocusTree] {
        return trees.filter { $0.type == type }
    }

    func recentTrees(limit: Int = 10) -> [FocusTree] {
        return Array(trees.sorted { $0.earnedDate > $1.earnedDate }.prefix(limit))
    }

    func treesEarnedToday() -> [FocusTree] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return trees.filter { tree in
            calendar.isDate(tree.earnedDate, inSameDayAs: today)
        }
    }

    func treesEarnedThisWeek() -> [FocusTree] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        return trees.filter { $0.earnedDate >= weekAgo }
    }

    // MARK: - Persistence

    private func saveTrees() {
        if let encoded = try? JSONEncoder().encode(trees) {
            UserDefaults.standard.set(encoded, forKey: treesKey)
            print("💾 Trees saved: \(trees.count) trees")
        }
    }

    private func loadTrees() {
        guard let data = UserDefaults.standard.data(forKey: treesKey),
              let loadedTrees = try? JSONDecoder().decode([FocusTree].self, from: data) else {
            print("📂 No saved trees found")
            return
        }

        trees = loadedTrees
        print("📂 Loaded \(trees.count) trees from storage")
    }

    private func saveStatistics() {
        if let encoded = try? JSONEncoder().encode(statistics) {
            UserDefaults.standard.set(encoded, forKey: statisticsKey)
            print("💾 Statistics saved")
        }
    }

    private func loadStatistics() {
        guard let data = UserDefaults.standard.data(forKey: statisticsKey),
              let loadedStats = try? JSONDecoder().decode(GardenStatistics.self, from: data) else {
            print("📂 No saved statistics found, using defaults")
            return
        }

        statistics = loadedStats
        print("📂 Statistics loaded")
    }

    // MARK: - Achievements

    func hasAchievement(_ achievement: GardenAchievement) -> Bool {
        switch achievement {
        case .firstTree:
            return statistics.totalTrees >= 1
        case .tenTrees:
            return statistics.totalTrees >= 10
        case .fiftyTrees:
            return statistics.totalTrees >= 50
        case .hundredTrees:
            return statistics.totalTrees >= 100
        case .oneHourSession:
            return statistics.longestSession >= 3600
        case .twoHourSession:
            return statistics.longestSession >= 7200
        case .sevenDayStreak:
            return statistics.currentStreak >= 7
        case .thirtyDayStreak:
            return statistics.currentStreak >= 30
        }
    }
}

// MARK: - Garden Achievements

enum GardenAchievement: String, CaseIterable {
    case firstTree = "first_tree"
    case tenTrees = "ten_trees"
    case fiftyTrees = "fifty_trees"
    case hundredTrees = "hundred_trees"
    case oneHourSession = "one_hour_session"
    case twoHourSession = "two_hour_session"
    case sevenDayStreak = "seven_day_streak"
    case thirtyDayStreak = "thirty_day_streak"

    var displayName: String {
        switch self {
        case .firstTree:
            return NSLocalizedString("focus.achievement.firstTree", comment: "First Tree")
        case .tenTrees:
            return NSLocalizedString("focus.achievement.tenTrees", comment: "10 Trees")
        case .fiftyTrees:
            return NSLocalizedString("focus.achievement.fiftyTrees", comment: "50 Trees")
        case .hundredTrees:
            return NSLocalizedString("focus.achievement.hundredTrees", comment: "100 Trees")
        case .oneHourSession:
            return NSLocalizedString("focus.achievement.oneHour", comment: "1 Hour Session")
        case .twoHourSession:
            return NSLocalizedString("focus.achievement.twoHours", comment: "2 Hour Session")
        case .sevenDayStreak:
            return NSLocalizedString("focus.achievement.sevenDays", comment: "7 Day Streak")
        case .thirtyDayStreak:
            return NSLocalizedString("focus.achievement.thirtyDays", comment: "30 Day Streak")
        }
    }

    var icon: String {
        switch self {
        case .firstTree:
            return "🌱"
        case .tenTrees, .fiftyTrees, .hundredTrees:
            return "🌳"
        case .oneHourSession, .twoHourSession:
            return "⏱️"
        case .sevenDayStreak, .thirtyDayStreak:
            return "🔥"
        }
    }
}
