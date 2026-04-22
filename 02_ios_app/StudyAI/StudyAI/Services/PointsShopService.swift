//
//  PointsShopService.swift
//  StudyAI
//
//  Points Shop catalog, purchase logic, and music unlock tracking
//

import Foundation
import SwiftUI
import Combine
import os.log

// MARK: - Shop Item Model

struct ShopItem: Identifiable {
    let id: String
    let nameKey: String
    let descriptionKey: String
    let price: Int
    let icon: String             // SF Symbol or tomato image name
    let action: ShopAction
    let section: ShopSection

    var localizedName: String { NSLocalizedString(nameKey, comment: "") }
    var localizedDescription: String { NSLocalizedString(descriptionKey, comment: "") }
}

enum ShopSection: String, CaseIterable {
    case studyBoost = "study_boost"
    case tomatoBlindBox = "tomato_blind_box"
    case focusMusic = "focus_music"

    var localizedName: String {
        NSLocalizedString("points.shop.section.\(rawValue)", comment: "")
    }

    var icon: String {
        switch self {
        case .studyBoost: return "book.and.wrench.fill"
        case .tomatoBlindBox: return "gift.fill"
        case .focusMusic: return "music.note"
        }
    }
}

// Keep ShopCategory for backward compat but it's no longer used in the UI
enum ShopCategory: String, CaseIterable {
    case streakProtection = "streak"
    case aiUsage = "ai_usage"
    case tomatoes = "tomatoes"
    case music = "music"

    var localizedName: String {
        NSLocalizedString("points.shop.category.\(rawValue)", comment: "")
    }

    var icon: String {
        switch self {
        case .streakProtection: return "snowflake"
        case .aiUsage: return "sparkles"
        case .tomatoes: return "leaf.fill"
        case .music: return "music.note"
        }
    }
}

enum ShopAction {
    case buyStreakFreeze
    case addChatMessages(Int)
    case addHomeworkPages(Int)
    case addVoiceMinutes(Int)
    case addErrorAnalysis(Int)
    case addQuestions(Int)
    case premiumTrial(days: Int)      // 1-week premium trial
    case tomatoBlindBox(rarity: Int)  // 2=rare, 3=super rare
    case unlockMusic(String)
}

enum PurchaseResult {
    case success(String)
    case tomatoRevealed(type: TomatoType, message: String)
    case insufficientPoints
    case networkError(String)
    case limitReached(String)
}

// MARK: - Points Shop Service

@MainActor
class PointsShopService: ObservableObject {
    static let shared = PointsShopService()

    private let logger = Logger(subsystem: "com.studyai", category: "PointsShop")
    private let userDefaults = UserDefaults.standard

    @Published var unlockedMusicTracks: Set<String> = []

    private var userKeyPrefix: String {
        let userId = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        return "studyai_\(userId)_"
    }

    private var unlockedMusicKey: String { userKeyPrefix + "unlocked_music_tracks" }
    private var premiumTrialCountKey: String { userKeyPrefix + "premium_trial_count" }

    /// How many times user has redeemed premium trial (max 3, hidden from UI)
    var premiumTrialCount: Int {
        userDefaults.integer(forKey: premiumTrialCountKey)
    }

    // MARK: - Shop Catalog (3 sections)

    func items(for section: ShopSection) -> [ShopItem] {
        switch section {
        case .studyBoost:
            return studyBoostItems
        case .tomatoBlindBox:
            return tomatoBlindBoxItems
        case .focusMusic:
            return focusMusicItems
        }
    }

    private var studyBoostItems: [ShopItem] {
        var items: [ShopItem] = [
            ShopItem(id: "freeze_card", nameKey: "shop.item.freeze", descriptionKey: "shop.item.freeze.desc",
                     price: 15, icon: "snowflake", action: .buyStreakFreeze, section: .studyBoost),
            ShopItem(id: "chat_10", nameKey: "shop.item.chat10", descriptionKey: "shop.item.chat10.desc",
                     price: 20, icon: "bubble.left.fill", action: .addChatMessages(10), section: .studyBoost),
            ShopItem(id: "hw_5", nameKey: "shop.item.hw5", descriptionKey: "shop.item.hw5.desc",
                     price: 40, icon: "doc.text.fill", action: .addHomeworkPages(5), section: .studyBoost),
            ShopItem(id: "voice_30", nameKey: "shop.item.voice30", descriptionKey: "shop.item.voice30.desc",
                     price: 60, icon: "waveform.circle.fill", action: .addVoiceMinutes(30), section: .studyBoost),
            ShopItem(id: "error_5", nameKey: "shop.item.error5", descriptionKey: "shop.item.error5.desc",
                     price: 30, icon: "magnifyingglass.circle.fill", action: .addErrorAnalysis(5), section: .studyBoost),
            ShopItem(id: "questions_20", nameKey: "shop.item.questions20", descriptionKey: "shop.item.questions20.desc",
                     price: 15, icon: "questionmark.circle.fill", action: .addQuestions(20), section: .studyBoost),
        ]

        // Premium trial — only show if user has used < 3
        if premiumTrialCount < 3 {
            items.append(ShopItem(
                id: "premium_trial_7d", nameKey: "shop.item.premiumTrial", descriptionKey: "shop.item.premiumTrial.desc",
                price: 300, icon: "crown.fill", action: .premiumTrial(days: 7), section: .studyBoost
            ))
        }

        return items
    }

    private var tomatoBlindBoxItems: [ShopItem] {
        [
            ShopItem(id: "blindbox_normal", nameKey: "shop.item.blindbox.normal", descriptionKey: "shop.item.blindbox.normal.desc",
                     price: 5, icon: "gift.fill", action: .tomatoBlindBox(rarity: 1), section: .tomatoBlindBox),
            ShopItem(id: "blindbox_rare", nameKey: "shop.item.blindbox.rare", descriptionKey: "shop.item.blindbox.rare.desc",
                     price: 30, icon: "gift.fill", action: .tomatoBlindBox(rarity: 2), section: .tomatoBlindBox),
            ShopItem(id: "blindbox_super", nameKey: "shop.item.blindbox.super", descriptionKey: "shop.item.blindbox.super.desc",
                     price: 100, icon: "gift.fill", action: .tomatoBlindBox(rarity: 3), section: .tomatoBlindBox),
        ]
    }

    private var focusMusicItems: [ShopItem] {
        [
            ShopItem(id: "music_meditation", nameKey: "shop.item.music.meditation", descriptionKey: "shop.item.music.meditation.desc",
                     price: 25, icon: "music.note", action: .unlockMusic("meditation_focus"), section: .focusMusic),
            ShopItem(id: "music_magic", nameKey: "shop.item.music.magic", descriptionKey: "shop.item.music.magic.desc",
                     price: 25, icon: "music.note", action: .unlockMusic("magic_healing"), section: .focusMusic),
        ]
    }

    // MARK: - Init

    private init() {
        loadUnlockedMusic()
    }

    func reloadForCurrentUser() {
        loadUnlockedMusic()
    }

    // MARK: - Music Unlock Tracking

    private func loadUnlockedMusic() {
        if let data = userDefaults.data(forKey: unlockedMusicKey),
           let tracks = try? JSONDecoder().decode(Set<String>.self, from: data) {
            unlockedMusicTracks = tracks
        } else {
            unlockedMusicTracks = []
        }
    }

    private func saveUnlockedMusic() {
        if let data = try? JSONEncoder().encode(unlockedMusicTracks) {
            userDefaults.set(data, forKey: unlockedMusicKey)
        }
    }

    func isMusicUnlocked(_ trackId: String) -> Bool {
        unlockedMusicTracks.contains(trackId)
    }

    // MARK: - Tomato Blind Box

    private func randomTomato(rarity: Int) -> TomatoType {
        switch rarity {
        case 1:
            // Normal blind box: weighted random from full pool (70% common, 24% rare, 5% super rare, 1% legendary)
            return TomatoType.random()
        case 2:
            // Rare blind box: guaranteed rare or higher
            let pool: [TomatoType] = [.darkKnight, .ironSuit, .superTomatorio, .flashingTomato,
                                       .golden, .platinum, .diamond]
            return pool.randomElement() ?? .darkKnight
        case 3:
            // Super rare blind box: guaranteed super rare or higher
            let pool: [TomatoType] = [.golden, .platinum, .diamond]
            return pool.randomElement() ?? .golden
        default:
            return TomatoType.random()
        }
    }

    // MARK: - Purchase

    func purchase(_ item: ShopItem) async -> PurchaseResult {
        let pointsManager = PointsEarningManager.shared

        guard pointsManager.pointsBalance >= item.price else {
            return .insufficientPoints
        }

        switch item.action {
        case .buyStreakFreeze:
            if pointsManager.purchaseStreakFreezeCard() {
                logger.info("🛒 Purchased streak freeze card")
                let success = await NetworkService.shared.spendPointsForLocalItem(
                    feature: "streak_freeze", pointsSpent: item.price)
                if !success {
                    pointsManager.streakFreezeCards -= 1
                    pointsManager.pointsBalance += item.price
                    pointsManager.forceSave()
                    return .networkError(NSLocalizedString("shop.error.network", comment: ""))
                }
                return .success(NSLocalizedString("shop.purchased.freeze", comment: ""))
            }
            return .insufficientPoints

        case .addChatMessages(let count):
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            let success = await NetworkService.shared.redeemPointsForUsage(
                feature: "chat_messages", amount: count, pointsSpent: item.price
            )
            if !success {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            await refreshUsageLimits()
            return .success(String(format: NSLocalizedString("shop.purchased.chat", comment: ""), count))

        case .addHomeworkPages(let count):
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            let success = await NetworkService.shared.redeemPointsForUsage(
                feature: "homework_pages", amount: count, pointsSpent: item.price
            )
            if !success {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            await refreshUsageLimits()
            return .success(String(format: NSLocalizedString("shop.purchased.homework", comment: ""), count))

        case .addVoiceMinutes(let count):
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            let success = await NetworkService.shared.redeemPointsForUsage(
                feature: "voice_minutes", amount: count, pointsSpent: item.price
            )
            if !success {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            await refreshUsageLimits()
            return .success(String(format: NSLocalizedString("shop.purchased.voice", comment: ""), count))

        case .addErrorAnalysis(let count):
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            let success = await NetworkService.shared.redeemPointsForUsage(
                feature: "error_analysis", amount: count, pointsSpent: item.price
            )
            if !success {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            await refreshUsageLimits()
            return .success(String(format: NSLocalizedString("shop.purchased.error", comment: ""), count))

        case .addQuestions(let count):
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            let success = await NetworkService.shared.redeemPointsForUsage(
                feature: "questions", amount: count, pointsSpent: item.price
            )
            if !success {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            await refreshUsageLimits()
            return .success(String(format: NSLocalizedString("shop.purchased.questions", comment: ""), count))

        case .premiumTrial:
            // Check hidden 3x limit
            guard premiumTrialCount < 3 else {
                return .limitReached(NSLocalizedString("shop.error.trialLimit", comment: ""))
            }
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            // Generate a unique promo code via backend
            let result = await NetworkService.shared.generateTrialCode(pointsSpent: item.price)
            if !result.success || result.code == nil {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                if result.code == "TRIAL_LIMIT_REACHED" {
                    return .limitReached(NSLocalizedString("shop.error.trialLimit", comment: ""))
                }
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            // Increment local trial count as backup
            userDefaults.set(premiumTrialCount + 1, forKey: premiumTrialCountKey)
            // Auto-redeem the code
            let redeemResult = await NetworkService.shared.redeemPromoCode(result.code!)
            if redeemResult.success {
                logger.info("🎫 Trial code \(result.code!) generated and auto-redeemed")
                return .success(NSLocalizedString("shop.purchased.premium", comment: ""))
            } else {
                // Code generated but redeem failed — user can redeem manually later
                logger.info("🎫 Trial code \(result.code!) generated but auto-redeem failed")
                return .success(String(format: NSLocalizedString("shop.purchased.premiumCode", comment: ""), result.code!))
            }

        case .tomatoBlindBox(let rarity):
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            let tomatoFeature = "tomato_blind_box_r\(rarity)"
            let success = await NetworkService.shared.spendPointsForLocalItem(
                feature: tomatoFeature, pointsSpent: item.price)
            if !success {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            let tomatoType = randomTomato(rarity: rarity)
            let tomato = Tomato(type: tomatoType, earnedDate: Date(), focusDuration: 0)
            TomatoGardenService.shared.tomatoes.append(tomato)
            TomatoGardenService.shared.saveTomatoes()
            TomatoGardenService.shared.updateStats()
            logger.info("🎁 Blind box opened: \(tomatoType.rawValue) (rarity \(rarity))")
            return .tomatoRevealed(type: tomatoType, message: String(format: NSLocalizedString("shop.purchased.blindbox", comment: ""), tomatoType.displayName))

        case .unlockMusic(let trackId):
            guard pointsManager.spendPoints(item.price) else { return .insufficientPoints }
            let musicSuccess = await NetworkService.shared.spendPointsForLocalItem(
                feature: "music_track", pointsSpent: item.price)
            if !musicSuccess {
                pointsManager.pointsBalance += item.price
                pointsManager.forceSave()
                return .networkError(NSLocalizedString("shop.error.network", comment: ""))
            }
            unlockedMusicTracks.insert(trackId)
            saveUnlockedMusic()
            return .success(NSLocalizedString("shop.purchased.music", comment: ""))
        }
    }

    // MARK: - Usage Refresh

    /// Fetch updated usage limits from backend after a shop purchase and update UsageService.
    private func refreshUsageLimits() async {
        guard let usageData = await NetworkService.shared.fetchAccountUsage() else { return }
        for feature in usageData.features {
            if let limit = feature.limit, limit > 0 {
                let remaining = max(0, limit - feature.used)
                UsageService.shared.update(feature: feature.key, remaining: remaining)
            }
        }
        logger.info("🔄 [SHOP] Refreshed usage limits after purchase")
    }

    /// Sync points balance with server after any purchase.
    private func syncBalanceAfterPurchase() async {
        await PointsEarningManager.shared.syncBalanceWithServer()
    }
}
