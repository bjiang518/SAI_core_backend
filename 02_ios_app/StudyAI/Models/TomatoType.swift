//
//  TomatoType.swift
//  StudyAI
//
//  番茄类型定义 - 多层级稀有度系统
//

import Foundation
import SwiftUI

/// 番茄类型
enum TomatoType: String, Codable, CaseIterable {
    // 普通番茄 (Ordinary) - tmt1, tmt2, tmt3, tmt4, tmt5, tmt6
    case classic = "classic"        // 经典番茄 - tmt1
    case curly = "curly"            // 卷藤番茄 - tmt2
    case cute = "cute"              // 萌萌番茄 - tmt3
    case tmt4 = "tmt4"              // 普通番茄4 - tmt4
    case tmt5 = "tmt5"              // 普通番茄5 - tmt5
    case tmt6 = "tmt6"              // 普通番茄6 - tmt6

    // 稀有番茄 (Rare) - 卡通角色
    case batman = "batman"          // 蝙蝠侠番茄
    case ironman = "ironman"        // 钢铁侠番茄
    case mario = "mario"            // 马里奥番茄
    case pokemon = "pokemon"        // 宝可梦番茄

    // 超稀有番茄 (Super Rare)
    case golden = "golden"          // 金色番茄
    case platinum = "platinum"      // 铂金番茄

    // 传说番茄 (Legendary)
    case diamond = "diamond"        // 钻石番茄

    /// 显示名称
    var displayName: String {
        switch self {
        case .classic:
            return "经典番茄"
        case .curly:
            return "卷藤番茄"
        case .cute:
            return "萌萌番茄"
        case .tmt4:
            return "普通番茄4"
        case .tmt5:
            return "普通番茄5"
        case .tmt6:
            return "普通番茄6"
        case .batman:
            return "蝙蝠侠番茄"
        case .ironman:
            return "钢铁侠番茄"
        case .mario:
            return "马里奥番茄"
        case .pokemon:
            return "宝可梦番茄"
        case .golden:
            return "金色番茄"
        case .platinum:
            return "铂金番茄"
        case .diamond:
            return "钻石番茄"
        }
    }

    /// 图片名称（对应Assets中的图片）
    var imageName: String {
        switch self {
        case .classic:
            return "tmt1"
        case .curly:
            return "tmt2"
        case .cute:
            return "tmt3"
        case .tmt4:
            return "tmt4"
        case .tmt5:
            return "tmt5"
        case .tmt6:
            return "tmt6"
        case .batman:
            return "tmt_batman"
        case .ironman:
            return "tmt_ironman"
        case .mario:
            return "tmt_mario"
        case .pokemon:
            return "tmt_pokemon"
        case .golden:
            return "tmt_gold"
        case .platinum:
            return "tmt_platinum"
        case .diamond:
            return "tmt_diamond"
        }
    }

    /// 描述
    var description: String {
        switch self {
        case .classic:
            return "最经典的番茄，简单可爱"
        case .curly:
            return "带着卷曲藤蔓的番茄，活力十足"
        case .cute:
            return "粉嫩可爱的番茄，温柔贴心"
        case .tmt4:
            return "普通番茄，朴实无华"
        case .tmt5:
            return "普通番茄，简单快乐"
        case .tmt6:
            return "普通番茄，勤奋可爱"
        case .batman:
            return "黑暗骑士守护者，正义的化身"
        case .ironman:
            return "科技与力量的完美结合"
        case .mario:
            return "勇敢的水管工冒险家"
        case .pokemon:
            return "神奇的宝可梦伙伴"
        case .golden:
            return "金光闪闪的番茄，象征财富与荣耀"
        case .platinum:
            return "铂金般珍贵，闪耀着高贵光芒"
        case .diamond:
            return "传说中的钻石番茄，极其珍贵稀有"
        }
    }

    /// 稀有度等级（1=普通，2=稀有，3=超稀有，4=传说）
    var rarity: Int {
        switch self {
        case .classic, .curly, .cute, .tmt4, .tmt5, .tmt6:
            return 1  // 普通
        case .batman, .ironman, .mario, .pokemon:
            return 2  // 稀有
        case .golden, .platinum:
            return 3  // 超稀有
        case .diamond:
            return 4  // 传说
        }
    }

    /// 稀有度颜色
    var rarityColor: String {
        switch rarity {
        case 1:
            return "gray"      // 普通 - 灰色
        case 2:
            return "blue"      // 稀有 - 蓝色
        case 3:
            return "purple"    // 超稀有 - 紫色
        case 4:
            return "orange"    // 传说 - 橙色
        default:
            return "gray"
        }
    }

    /// 稀有度标签
    var rarityLabel: String {
        switch rarity {
        case 1:
            return "普通"
        case 2:
            return "稀有"
        case 3:
            return "超稀有"
        case 4:
            return "传说"
        default:
            return "未知"
        }
    }

    /// 随机获取一个番茄类型（基于稀有度加权）
    static func random() -> TomatoType {
        let weights: [TomatoType: Int] = [
            // 普通番茄 - 70% 总概率 (6种番茄)
            .classic: 12,   // 12%
            .curly: 12,     // 12%
            .cute: 12,      // 12%
            .tmt4: 11,      // 11%
            .tmt5: 11,      // 11%
            .tmt6: 12,      // 12%

            // 稀有番茄 - 24% 总概率
            .batman: 6,     // 6%
            .ironman: 6,    // 6%
            .mario: 6,      // 6%
            .pokemon: 6,    // 6%

            // 超稀有番茄 - 5% 总概率
            .golden: 2,     // 2%
            .platinum: 3,   // 3%

            // 传说番茄 - 1% 总概率
            .diamond: 1     // 1%
        ]

        let totalWeight = weights.values.reduce(0, +)
        let randomValue = Int.random(in: 1...totalWeight)

        var currentWeight = 0
        for (type, weight) in weights {
            currentWeight += weight
            if randomValue <= currentWeight {
                return type
            }
        }

        return .classic  // Fallback
    }

    /// 获取指定稀有度的所有番茄类型
    static func types(withRarity rarity: Int) -> [TomatoType] {
        return TomatoType.allCases.filter { $0.rarity == rarity }
    }

    /// 获取随机的稀有番茄（用于兑换）
    static func randomRare() -> TomatoType {
        let rareTypes: [TomatoType] = [.batman, .ironman, .mario, .pokemon]
        return rareTypes.randomElement() ?? .batman
    }

    /// 获取随机的超稀有番茄（用于兑换）
    static func randomSuperRare() -> TomatoType {
        let superRareTypes: [TomatoType] = [.golden, .platinum]
        return superRareTypes.randomElement() ?? .golden
    }
}

/// 番茄实例 - 用户获得的每一个番茄
struct Tomato: Identifiable, Codable {
    let id: String
    let type: TomatoType
    let earnedDate: Date
    let focusDuration: TimeInterval  // 专注时长（秒）

    init(id: String = UUID().uuidString,
         type: TomatoType,
         earnedDate: Date = Date(),
         focusDuration: TimeInterval) {
        self.id = id
        self.type = type
        self.earnedDate = earnedDate
        self.focusDuration = focusDuration
    }

    /// 格式化专注时长
    var formattedDuration: String {
        let minutes = Int(focusDuration / 60)
        if minutes < 60 {
            return "\(minutes)分钟"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)小时\(remainingMinutes)分钟"
        }
    }

    /// 格式化日期
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: earnedDate)
    }
}

/// 番茄园统计
struct TomatoGardenStats {
    var totalTomatoes: Int = 0
    var totalFocusTime: TimeInterval = 0

    // 普通番茄
    var classicCount: Int = 0
    var curlyCount: Int = 0
    var cuteCount: Int = 0
    var tmt4Count: Int = 0
    var tmt5Count: Int = 0
    var tmt6Count: Int = 0

    // 稀有番茄
    var batmanCount: Int = 0
    var ironmanCount: Int = 0
    var marioCount: Int = 0
    var pokemonCount: Int = 0

    // 超稀有番茄
    var goldenCount: Int = 0
    var platinumCount: Int = 0

    // 传说番茄
    var diamondCount: Int = 0

    var longestSession: TimeInterval = 0
    var firstTomatoDate: Date?

    /// 格式化总专注时间
    var formattedTotalTime: String {
        let hours = Int(totalFocusTime / 3600)
        let minutes = Int((totalFocusTime.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        } else {
            return "\(minutes)分钟"
        }
    }

    /// 获取指定类型的番茄数量
    func count(for type: TomatoType) -> Int {
        switch type {
        case .classic: return classicCount
        case .curly: return curlyCount
        case .cute: return cuteCount
        case .tmt4: return tmt4Count
        case .tmt5: return tmt5Count
        case .tmt6: return tmt6Count
        case .batman: return batmanCount
        case .ironman: return ironmanCount
        case .mario: return marioCount
        case .pokemon: return pokemonCount
        case .golden: return goldenCount
        case .platinum: return platinumCount
        case .diamond: return diamondCount
        }
    }

    /// 是否已解锁（获得过至少一次）
    func isUnlocked(_ type: TomatoType) -> Bool {
        return count(for: type) > 0
    }

    /// 已解锁的番茄类型数量
    var unlockedCount: Int {
        var count = 0
        for type in TomatoType.allCases {
            if isUnlocked(type) {
                count += 1
            }
        }
        return count
    }

    /// 收集进度（百分比）
    var collectionProgress: Double {
        return Double(unlockedCount) / Double(TomatoType.allCases.count) * 100
    }

    /// 普通番茄总数
    var ordinaryCount: Int {
        return classicCount + curlyCount + cuteCount + tmt4Count + tmt5Count + tmt6Count
    }

    /// 稀有番茄总数
    var rareCount: Int {
        return batmanCount + ironmanCount + marioCount + pokemonCount
    }

    /// 超稀有番茄总数
    var superRareCount: Int {
        return goldenCount + platinumCount
    }

    /// 最受欢迎的番茄类型
    var favoriteTomato: TomatoType? {
        let counts = TomatoType.allCases.map { ($0, count(for: $0)) }
        return counts.max(by: { $0.1 < $1.1 })?.0
    }
}
