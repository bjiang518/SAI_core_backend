//
//  PointsShopView.swift
//  StudyAI
//
//  Points Hub — 2-tab container: Earn (daily checklist) + Shop (spend points)
//

import SwiftUI

// MARK: - Points Hub (Container)

struct PointsShopView: View {
    @StateObject private var shopService = PointsShopService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int = 0 // 0 = Earn, 1 = Shop

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Shared balance header
                balanceHeader
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Segmented picker
                Picker("", selection: $selectedTab) {
                    Text(NSLocalizedString("points.hub.tab.earn", comment: "")).tag(0)
                    Text(NSLocalizedString("points.hub.tab.shop", comment: "")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 12)

                // Tab content
                if selectedTab == 0 {
                    EarnTabView(pointsManager: pointsManager)
                } else {
                    ShopTabView(shopService: shopService, pointsManager: pointsManager, themeManager: themeManager)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(NSLocalizedString("points.hub.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(themeManager.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Balance Header

    private var balanceHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 30))
                .foregroundColor(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("points.shop.balance", comment: ""))
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)
                Text("\(pointsManager.pointsBalance)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(themeManager.primaryText)
            }

            Spacer()

            // Streak info
            if pointsManager.currentStreak > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NSLocalizedString("points.hub.streak", comment: ""))
                        .font(.caption)
                        .foregroundColor(themeManager.secondaryText)
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("\(pointsManager.currentStreak)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                }
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(NSLocalizedString("points.shop.today", comment: ""))
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)
                Text("+\(pointsManager.dailyPointsEarned)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
    }
}

// MARK: - Earn Tab

private struct EarnTabView: View {
    @ObservedObject var pointsManager: PointsEarningManager
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showingShareSheet = false

    private enum EarnStatus {
        case claimable, notAvailable, checkedOut
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Streak freeze indicator
                if pointsManager.streakFreezeCards > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "snowflake")
                            .foregroundColor(.cyan)
                            .font(.system(size: 14))
                        Text(String(format: NSLocalizedString("streak.freeze.cards.remaining", comment: ""),
                                    pointsManager.streakFreezeCards))
                            .font(.caption)
                            .foregroundColor(themeManager.primaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.cyan.opacity(0.08)))
                }

                // 1. Daily Streak Bonus
                earnRow(
                    icon: "flame.fill", iconColor: .orange,
                    title: NSLocalizedString("points.earn.streak.title", comment: ""),
                    subtitle: String(format: NSLocalizedString("points.earn.streak.desc", comment: ""),
                                     max(pointsManager.currentStreak, 1)),
                    pointsText: "+\(max(pointsManager.currentStreak, 1))",
                    status: pointsManager.hasClaimedStreakBonusToday ? .checkedOut : .claimable,
                    onClaim: { let _ = pointsManager.claimDailyStreakBonus() },
                    goAction: nil
                )

                // 2. Correct Answers
                earnRow(
                    icon: "checkmark.circle.fill", iconColor: .green,
                    title: NSLocalizedString("points.earn.correct.title", comment: ""),
                    subtitle: NSLocalizedString("points.earn.correct.desc", comment: ""),
                    pointsText: "+\(pointsManager.todayProgress?.correctAnswers ?? 0)",
                    status: (pointsManager.todayProgress?.correctAnswers ?? 0) > 0 ? .checkedOut : .notAvailable,
                    onClaim: nil,
                    goAction: { AppState.shared.selectedTab = .grader }
                )

                // 3. Homework Scanning
                earnRow(
                    icon: "camera.viewfinder", iconColor: .indigo,
                    title: NSLocalizedString("points.earn.scan.title", comment: ""),
                    subtitle: NSLocalizedString("points.earn.scan.desc", comment: ""),
                    pointsText: "+\(pointsManager.todayHomeworkScans * 2)",
                    status: pointsManager.todayHomeworkScans > 0 ? .checkedOut : .notAvailable,
                    onClaim: nil,
                    goAction: { AppState.shared.selectedTab = .grader }
                )

                // 4. Practice Completion
                earnRow(
                    icon: "text.badge.checkmark", iconColor: .purple,
                    title: NSLocalizedString("points.earn.practice.title", comment: ""),
                    subtitle: NSLocalizedString("points.earn.practice.desc", comment: ""),
                    pointsText: "+\(pointsManager.todayPracticeCompletions * 5)",
                    status: pointsManager.todayPracticeCompletions > 0 ? .checkedOut : .notAvailable,
                    onClaim: nil,
                    goAction: { AppState.shared.selectedTab = .home }
                )

                // 5. Mistake Review
                earnRow(
                    icon: "arrow.counterclockwise.circle.fill", iconColor: .blue,
                    title: NSLocalizedString("points.earn.review.title", comment: ""),
                    subtitle: NSLocalizedString("points.earn.review.desc", comment: ""),
                    pointsText: "+\(pointsManager.todayMistakeReviews * 2)",
                    status: pointsManager.todayMistakeReviews > 0 ? .checkedOut : .notAvailable,
                    onClaim: nil,
                    goAction: { AppState.shared.selectedTab = .library }
                )

                // 6. Focus Session
                earnRow(
                    icon: "timer", iconColor: .red,
                    title: NSLocalizedString("points.earn.focus.title", comment: ""),
                    subtitle: NSLocalizedString("points.earn.focus.desc", comment: ""),
                    pointsText: "+\(pointsManager.todayFocusPoints)",
                    status: pointsManager.todayFocusPoints > 0 ? .checkedOut : .notAvailable,
                    onClaim: nil,
                    goAction: { AppState.shared.selectedTab = .home }
                )

                // 7. Chat Session
                earnRow(
                    icon: "bubble.left.and.bubble.right.fill", iconColor: .teal,
                    title: NSLocalizedString("points.earn.chat.title", comment: ""),
                    subtitle: NSLocalizedString("points.earn.chat.desc", comment: ""),
                    pointsText: "+\(pointsManager.todayChatSessions)",
                    status: pointsManager.todayChatSessions > 0 ? .checkedOut : .notAvailable,
                    onClaim: nil,
                    goAction: { AppState.shared.selectedTab = .chat }
                )

                // 8. Rate App — one-time
                if !AppReviewService.shared.hasEarnedRatingPoints {
                    earnRow(
                        icon: "star.bubble.fill", iconColor: .yellow,
                        title: NSLocalizedString("points.earn.rate.title", comment: ""),
                        subtitle: NSLocalizedString("points.earn.rate.desc", comment: ""),
                        pointsText: "+\(AppReviewService.ratingPointsReward)",
                        status: .claimable,
                        onClaim: { let _ = AppReviewService.shared.rateAppForPoints() },
                        goAction: nil
                    )
                }

                // 9. Share App — one-time
                if !AppReviewService.shared.hasEarnedSharePoints {
                    earnRow(
                        icon: "square.and.arrow.up.fill", iconColor: .cyan,
                        title: NSLocalizedString("points.earn.share.title", comment: ""),
                        subtitle: NSLocalizedString("points.earn.share.desc", comment: ""),
                        pointsText: "+\(AppReviewService.sharePointsReward)",
                        status: .claimable,
                        onClaim: { showingShareSheet = true },
                        goAction: nil
                    )
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareAppView()
        }
    }

    // MARK: - Earn Row (unified with star system)

    private func earnRow(
        icon: String, iconColor: Color,
        title: String, subtitle: String,
        pointsText: String,
        status: EarnStatus,
        onClaim: (() -> Void)?,
        goAction: (() -> Void)?
    ) -> some View {
        HStack(spacing: 10) {
            // Left icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(iconColor)
            }

            // Title + subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(themeManager.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Points — fixed width
            Text(pointsText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(status == .checkedOut ? .green : (status == .claimable ? .yellow : .gray))
                .frame(width: 40, alignment: .trailing)

            // Star / checkmark — fixed width
            Group {
                switch status {
                case .claimable:
                    Button(action: {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        onClaim?()
                    }) {
                        ShakingStarView()
                    }
                    .buttonStyle(PlainButtonStyle())
                case .notAvailable:
                    Image(systemName: "star.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color.gray.opacity(0.3))
                case .checkedOut:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
            }
            .frame(width: 28, alignment: .center)

            // Go arrow — always present, fixed width
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .opacity(goAction != nil ? (status == .checkedOut ? 0.3 : 1.0) : 0)
                .frame(width: 20, alignment: .center)
                .modifier(EarnBlinkModifier(active: goAction != nil && status == .notAvailable))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(themeManager.cardBackground)
                .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let action = goAction {
                action()
            }
        }
    }
}

private struct ShakingStarView: View {
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 20))
            .foregroundColor(.yellow)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                    angle = 15
                }
            }
    }
}

private struct EarnBlinkModifier: ViewModifier {
    let active: Bool
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(active ? opacity : 1.0)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    opacity = 0.2
                }
            }
    }
}

// MARK: - Shop Tab (List with 3 sections)

private struct ShopTabView: View {
    @ObservedObject var shopService: PointsShopService
    @ObservedObject var pointsManager: PointsEarningManager
    @ObservedObject var themeManager: ThemeManager

    @State private var confirmItem: ShopItem?
    @State private var showingConfirmation = false
    @State private var purchaseMessage: String?
    @State private var showingPurchaseResult = false
    @State private var isPurchasing = false
    // Blind box reveal
    @State private var revealedTomato: String?
    @State private var showingReveal = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(ShopSection.allCases, id: \.self) { section in
                    shopSection(section)
                }
            }
            .padding()
        }
        .alert(NSLocalizedString("points.shop.confirm.title", comment: ""), isPresented: $showingConfirmation) {
            Button(NSLocalizedString("points.shop.cancel", comment: ""), role: .cancel) {}
            Button(NSLocalizedString("points.shop.buy", comment: "")) {
                if let item = confirmItem {
                    Task { await executePurchase(item) }
                }
            }
        } message: {
            if let item = confirmItem {
                Text(String(format: NSLocalizedString("points.shop.confirm.message", comment: ""),
                            item.localizedName, item.price))
            }
        }
        .alert(purchaseMessage ?? "", isPresented: $showingPurchaseResult) {
            Button("OK") {}
        }
    }

    // MARK: - Section

    private func shopSection(_ section: ShopSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(sectionColor(section))
                Text(section.localizedName)
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)
            }
            .padding(.leading, 4)

            // Items
            VStack(spacing: 0) {
                let sectionItems = shopService.items(for: section)
                ForEach(Array(sectionItems.enumerated()), id: \.element.id) { index, item in
                    shopRow(item, section: section)
                    if index < sectionItems.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(themeManager.cardBackground)
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            )
        }
    }

    // MARK: - Row

    private func shopRow(_ item: ShopItem, section: ShopSection) -> some View {
        let canAfford = pointsManager.pointsBalance >= item.price
        let isAlreadyUnlocked: Bool = {
            if case .unlockMusic(let trackId) = item.action {
                return shopService.isMusicUnlocked(trackId)
            }
            return false
        }()

        return HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(sectionColor(section).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: item.icon)
                    .font(.system(size: 18))
                    .foregroundColor(sectionColor(section))
            }

            // Name + Description
            VStack(alignment: .leading, spacing: 2) {
                Text(item.localizedName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(themeManager.primaryText)
                Text(item.localizedDescription)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Price button or unlocked badge
            if isAlreadyUnlocked {
                Text(NSLocalizedString("points.shop.unlocked", comment: ""))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.1)))
            } else {
                Button(action: {
                    confirmItem = item
                    showingConfirmation = true
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                        Text("\(item.price)")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(canAfford ? .white : themeManager.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(canAfford ? sectionColor(section) : Color.gray.opacity(0.2))
                    )
                }
                .disabled(!canAfford || isPurchasing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(canAfford || isAlreadyUnlocked ? 1.0 : 0.65)
    }

    // MARK: - Purchase

    private func executePurchase(_ item: ShopItem) async {
        isPurchasing = true
        let result = await shopService.purchase(item)
        isPurchasing = false

        switch result {
        case .success(let message):
            purchaseMessage = message
            showingPurchaseResult = true
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .insufficientPoints:
            purchaseMessage = NSLocalizedString("points.shop.error.insufficient", comment: "")
            showingPurchaseResult = true
        case .networkError(let message):
            purchaseMessage = message
            showingPurchaseResult = true
        case .limitReached(let message):
            purchaseMessage = message
            showingPurchaseResult = true
        }
    }

    private func sectionColor(_ section: ShopSection) -> Color {
        switch section {
        case .studyBoost: return .blue
        case .tomatoBlindBox: return .orange
        case .focusMusic: return .pink
        }
    }
}
