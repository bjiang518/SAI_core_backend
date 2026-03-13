//
//  TomatoGardenService.swift
//  StudyAI
//
//  番茄园服务 - 管理用户的番茄收藏
//

import Foundation
import Combine

@MainActor
class TomatoGardenService: ObservableObject {
    static let shared = TomatoGardenService()

    // MARK: - Published Properties
    @Published var tomatoes: [Tomato] = []
    @Published var stats: TomatoGardenStats = TomatoGardenStats()

    // MARK: - Private Properties
    private let userDefaults = UserDefaults.standard
    private var authCancellable: AnyCancellable?
    private var uid: String { AuthenticationService.shared.currentUser?.id ?? "anonymous" }
    private var tomatoesKey: String { "user_tomato_garden_\(uid)" }

    private init() {
        loadTomatoes()
        updateStats()
        authCancellable = AuthenticationService.shared.$isAuthenticated
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadTomatoes()
                self?.updateStats()
            }
    }

    // MARK: - Core Functions

    /// 添加一个新番茄（完成专注后调用）
    /// 时长 < 15 分钟时返回 nil（不颁发番茄）
    @discardableResult
    func addTomato(from session: FocusSession) -> Tomato? {
        guard session.duration >= 15 * 60 else {
            print("⏱️ Session too short (<15 min) — no tomato awarded")
            return nil
        }

        let tomatoType = TomatoType.randomType(forDuration: session.duration)

        let tomato = Tomato(
            type: tomatoType,
            earnedDate: Date(),
            focusDuration: session.duration
        )

        tomatoes.append(tomato)
        saveTomatoes()
        updateStats()

        print("🍅 Earned a new tomato: \(tomatoType.displayName)")
        return tomato
    }

    /// 删除指定番茄
    func removeTomato(id: String) {
        tomatoes.removeAll { $0.id == id }
        saveTomatoes()
        updateStats()
        print("🗑️ Removed tomato: \(id)")
    }

    /// 清空番茄园
    func clearGarden() {
        tomatoes.removeAll()
        saveTomatoes()
        updateStats()
        print("🧹 Cleared tomato garden")
    }

    // MARK: - Data Persistence

    /// 保存番茄到UserDefaults
    func saveTomatoes() {
        if let encoded = try? JSONEncoder().encode(tomatoes) {
            userDefaults.set(encoded, forKey: tomatoesKey)
            print("💾 Saved \(tomatoes.count) tomatoes")
        }
    }

    /// 从UserDefaults加载番茄
    private func loadTomatoes() {
        if let data = userDefaults.data(forKey: tomatoesKey),
           let decoded = try? JSONDecoder().decode([Tomato].self, from: data) {
            tomatoes = decoded
            print("📂 Loaded \(tomatoes.count) tomatoes")
        }
    }

    // MARK: - Statistics

    /// 更新统计数据
    func updateStats() {
        var newStats = TomatoGardenStats()

        newStats.totalTomatoes = tomatoes.count

        // Single-pass iteration for all statistics - O(n) instead of O(14n)
        var totalFocusTime: TimeInterval = 0
        var longestSession: TimeInterval = 0
        var earliestDate: Date? = nil

        for tomato in tomatoes {
            // Count by type
            switch tomato.type {
            case .classic: newStats.classicCount += 1
            case .curly: newStats.curlyCount += 1
            case .cute: newStats.cuteCount += 1
            case .tmt4: newStats.tmt4Count += 1
            case .tmt5: newStats.tmt5Count += 1
            case .tmt6: newStats.tmt6Count += 1
            case .batman: newStats.batmanCount += 1
            case .ironman: newStats.ironmanCount += 1
            case .mario: newStats.marioCount += 1
            case .pokemon: newStats.pokemonCount += 1
            case .golden: newStats.goldenCount += 1
            case .platinum: newStats.platinumCount += 1
            case .diamond: newStats.diamondCount += 1
            }

            // Accumulate focus time
            totalFocusTime += tomato.focusDuration

            // Track longest session
            if tomato.focusDuration > longestSession {
                longestSession = tomato.focusDuration
            }

            // Track earliest date
            if earliestDate == nil || tomato.earnedDate < earliestDate! {
                earliestDate = tomato.earnedDate
            }
        }

        newStats.totalFocusTime = totalFocusTime
        newStats.longestSession = longestSession
        newStats.firstTomatoDate = earliestDate

        stats = newStats
    }

    /// 获取按日期排序的番茄（最新的在前）
    func getTomatoesSortedByDate() -> [Tomato] {
        return tomatoes.sorted(by: { $0.earnedDate > $1.earnedDate })
    }

    /// 获取按类型分组的番茄
    func getTomatoesGroupedByType() -> [TomatoType: [Tomato]] {
        return Dictionary(grouping: tomatoes, by: { $0.type })
    }

    /// 获取今天获得的番茄
    func getTodayTomatoes() -> [Tomato] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return tomatoes.filter { tomato in
            calendar.isDate(tomato.earnedDate, inSameDayAs: today)
        }
    }

    /// 获取本周获得的番茄
    func getWeekTomatoes() -> [Tomato] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        return tomatoes.filter { $0.earnedDate >= weekAgo }
    }

    /// 获取特定类型的番茄数量
    func getTomatoCount(type: TomatoType) -> Int {
        return tomatoes.filter { $0.type == type }.count
    }

    // MARK: - Achievements & Milestones

    /// 检查成就
    func checkAchievements() -> [String] {
        var achievements: [String] = []

        // 第一个番茄
        if tomatoes.count == 1 {
            achievements.append("🎉 恭喜收获第一个番茄！")
        }

        // 10个番茄
        if tomatoes.count == 10 {
            achievements.append("🏆 收集10个番茄达成！")
        }

        // 50个番茄
        if tomatoes.count == 50 {
            achievements.append("🌟 收集50个番茄达成！")
        }

        // 100个番茄
        if tomatoes.count == 100 {
            achievements.append("💯 收集100个番茄达成！番茄大师！")
        }

        // 集齐所有类型
        if stats.classicCount > 0 && stats.curlyCount > 0 && stats.cuteCount > 0 {
            if tomatoes.count == stats.classicCount + stats.curlyCount + stats.cuteCount {
                achievements.append("🎨 集齐了所有类型的番茄！")
            }
        }

        return achievements
    }

    /// 获取下一个里程碑
    func getNextMilestone() -> (count: Int, description: String)? {
        let milestones = [10, 25, 50, 100, 200, 500]

        for milestone in milestones {
            if tomatoes.count < milestone {
                return (milestone, "收集\(milestone)个番茄")
            }
        }

        return nil
    }

    /// 距离下一个里程碑还需要多少个番茄
    func tomatoesNeededForNextMilestone() -> Int? {
        guard let milestone = getNextMilestone() else { return nil }
        return milestone.count - tomatoes.count
    }

    // MARK: - Exchange System

    /// Generic exchange function to reduce code duplication
    private func performExchange(fromRarity: Int, toType: () -> TomatoType, exchangeName: String) -> Bool {
        // 检查是否有足够的番茄
        let sourceTomatoes = tomatoes.filter { $0.type.rarity == fromRarity }
        guard sourceTomatoes.count >= 5 else {
            print("❌ Not enough tomatoes to exchange (need 5, have \(sourceTomatoes.count))")
            return false
        }

        // 移除5个番茄（按获得时间从早到晚）
        let sortedTomatoes = sourceTomatoes.sorted(by: { $0.earnedDate < $1.earnedDate })
        for i in 0..<5 {
            removeTomato(id: sortedTomatoes[i].id)
        }

        // 添加新番茄
        let newTomatoType = toType()
        let newTomato = Tomato(
            type: newTomatoType,
            earnedDate: Date(),
            focusDuration: 0  // 兑换获得的番茄没有专注时长
        )

        tomatoes.append(newTomato)
        saveTomatoes()
        updateStats()

        print("✨ \(exchangeName): \(newTomatoType.displayName)")
        return true
    }

    /// 兑换：5个普通番茄 -> 1个随机稀有番茄
    func exchangeOrdinaryToRare() -> Bool {
        return performExchange(fromRarity: 1, toType: TomatoType.randomRare, exchangeName: "Exchanged 5 ordinary tomatoes for")
    }

    /// 兑换：5个稀有番茄 -> 1个随机超稀有番茄
    func exchangeRareToSuperRare() -> Bool {
        return performExchange(fromRarity: 2, toType: TomatoType.randomSuperRare, exchangeName: "Exchanged 5 rare tomatoes for")
    }

    /// 兑换：5个超稀有番茄 -> 1个钻石番茄
    func exchangeSuperRareToDiamond() -> Bool {
        return performExchange(fromRarity: 3, toType: { .diamond }, exchangeName: "Exchanged 5 super rare tomatoes for")
    }

    /// 检查是否可以进行兑换 (using cached stats instead of filtering)
    func canExchangeOrdinaryToRare() -> Bool {
        return stats.ordinaryCount >= 5
    }

    func canExchangeRareToSuperRare() -> Bool {
        return stats.rareCount >= 5
    }

    func canExchangeSuperRareToDiamond() -> Bool {
        return stats.superRareCount >= 5
    }
}
