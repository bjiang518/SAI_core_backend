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

    /// Gold color matching HomeView's star badge
    private let starGold = Color(red: 1.0, green: 0.84, blue: 0.0)

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
                    EarnTabView(pointsManager: pointsManager, dismissSheet: { dismiss() })
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
                .foregroundColor(starGold)

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
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        )
    }
}

// MARK: - Earn Tab

private struct EarnTabView: View {
    @ObservedObject var pointsManager: PointsEarningManager
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showingShareSheet = false
    let dismissSheet: () -> Void

    /// Gold color matching HomeView's star badge
    private let starGold = Color(red: 1.0, green: 0.84, blue: 0.0)

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
                                     min(max(pointsManager.currentStreak, 1), PointsEarningManager.maxDailyPointsPerItem)),
                    pointsText: "+\(min(max(pointsManager.currentStreak, 1), PointsEarningManager.maxDailyPointsPerItem))",
                    status: pointsManager.hasClaimedStreakBonusToday ? .checkedOut : .claimable,
                    onClaim: { let _ = pointsManager.claimDailyStreakBonus() },
                    goAction: nil
                )

                // 2. Correct Answers
                manualClaimRow(
                    icon: "checkmark.circle.fill", iconColor: .green,
                    title: NSLocalizedString("points.earn.correct.title", comment: ""),
                    type: .correctAnswers,
                    goAction: { dismissSheet(); AppState.shared.selectedTab = .grader }
                )

                // 3. Homework Scanning
                manualClaimRow(
                    icon: "camera.viewfinder", iconColor: .indigo,
                    title: NSLocalizedString("points.earn.scan.title", comment: ""),
                    type: .homeworkScan,
                    goAction: { dismissSheet(); AppState.shared.selectedTab = .grader }
                )

                // 4. Practice Completion
                manualClaimRow(
                    icon: "text.badge.checkmark", iconColor: .purple,
                    title: NSLocalizedString("points.earn.practice.title", comment: ""),
                    type: .practiceCompletion,
                    goAction: {
                        dismissSheet()
                        AppState.shared.selectedTab = .home
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            AppState.shared.shouldOpenPracticeLibrary = true
                        }
                    }
                )

                // 5. Mistake Review
                manualClaimRow(
                    icon: "arrow.counterclockwise.circle.fill", iconColor: .blue,
                    title: NSLocalizedString("points.earn.review.title", comment: ""),
                    type: .mistakeReview,
                    goAction: {
                        dismissSheet()
                        AppState.shared.selectedTab = .home
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            AppState.shared.shouldOpenMistakeReview = true
                        }
                    }
                )

                // 6. Focus Session
                manualClaimRow(
                    icon: "timer", iconColor: .red,
                    title: NSLocalizedString("points.earn.focus.title", comment: ""),
                    type: .focusSession,
                    goAction: {
                        dismissSheet()
                        AppState.shared.selectedTab = .home
                        // Trigger focus mode after sheet dismisses
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            AppState.shared.shouldOpenFocusMode = true
                        }
                    }
                )

                // 7. Chat Session
                manualClaimRow(
                    icon: "bubble.left.and.bubble.right.fill", iconColor: .teal,
                    title: NSLocalizedString("points.earn.chat.title", comment: ""),
                    type: .chatSession,
                    goAction: { dismissSheet(); AppState.shared.selectedTab = .chat }
                )

                // 8. Weakness Conversion
                manualClaimRow(
                    icon: "target", iconColor: .orange,
                    title: NSLocalizedString("points.earn.weakness.title", value: "Overcome Weakness", comment: ""),
                    type: .weaknessConversion,
                    goAction: {
                        dismissSheet()
                        AppState.shared.selectedTab = .home
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            AppState.shared.shouldOpenMistakeReview = true
                        }
                    }
                )

                // 8. Rate App — two-phase: prompt first, then claim
                if !AppReviewService.shared.hasEarnedRatingPoints {
                    let prompted = AppReviewService.shared.hasPromptedRating
                    earnRow(
                        icon: "star.bubble.fill", iconColor: starGold,
                        title: NSLocalizedString("points.earn.rate.title", comment: ""),
                        subtitle: prompted
                            ? NSLocalizedString("points.earn.rate.claimNow",
                                value: "Rating submitted — tap ⭐ to claim reward", comment: "")
                            : NSLocalizedString("points.earn.rate.desc", comment: ""),
                        pointsText: "+\(AppReviewService.ratingPointsReward)",
                        status: .claimable,
                        onClaim: {
                            if prompted {
                                let _ = AppReviewService.shared.claimRatingPoints()
                            } else {
                                AppReviewService.shared.promptRatingForPoints()
                            }
                        },
                        goAction: nil
                    )
                }

                // 9. Share App — two-phase: share first, then claim
                if !AppReviewService.shared.hasEarnedSharePoints {
                    let sharePrompted = AppReviewService.shared.hasPromptedShare
                    earnRow(
                        icon: "square.and.arrow.up.fill", iconColor: .cyan,
                        title: NSLocalizedString("points.earn.share.title", comment: ""),
                        subtitle: sharePrompted
                            ? NSLocalizedString("points.earn.share.claimNow",
                                value: "Shared — tap ⭐ to claim reward", comment: "")
                            : NSLocalizedString("points.earn.share.desc", comment: ""),
                        pointsText: "+\(AppReviewService.sharePointsReward)",
                        status: .claimable,
                        onClaim: {
                            if sharePrompted {
                                let _ = AppReviewService.shared.claimSharePoints()
                            } else {
                                AppReviewService.shared.markSharePrompted()
                                showingShareSheet = true
                            }
                        },
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

    // MARK: - Manual Claim Row (wraps earnRow with claim logic)

    private func manualClaimRow(
        icon: String, iconColor: Color,
        title: String,
        type: PointsEarningManager.EarningType,
        goAction: (() -> Void)?
    ) -> some View {
        let pending = pointsManager.pendingPoints(for: type)
        let claimed = pointsManager.claimedPoints(for: type)
        let activity = pointsManager.activityCount(for: type)
        let claimedU = pointsManager.claimedUnits(for: type)
        let cap = type.dailyUnitCap

        let status: EarnStatus = {
            if pending > 0 { return .claimable }
            if claimedU > 0 { return .checkedOut }
            return .notAvailable
        }()

        let pointsText = status == .checkedOut ? "+\(claimed)" : "+\(pending)"

        let subtitle: String = {
            if pending > 0 {
                return String(format: NSLocalizedString("points.earn.unclaimed",
                    value: "%d unclaimed — tap ⭐ to collect", comment: ""),
                    pointsManager.pendingUnits(for: type))
            } else if claimedU > 0 {
                return String(format: NSLocalizedString("points.earn.claimedToday",
                    value: "%d/%d pts earned today", comment: ""),
                    claimed, PointsEarningManager.maxDailyPointsPerItem)
            } else {
                return type.howToEarn
            }
        }()

        // Daily cap progress (0.0 - 1.0)
        let progress = Double(claimed) / Double(PointsEarningManager.maxDailyPointsPerItem)

        return earnRow(
            icon: icon, iconColor: iconColor,
            title: title,
            subtitle: subtitle,
            pointsText: pointsText,
            progress: claimedU > 0 || pending > 0 ? progress : nil,
            status: status,
            onClaim: { let _ = pointsManager.claimEarning(type: type) },
            goAction: goAction
        )
    }

    // MARK: - Earn Row (unified with star system)

    private func earnRow(
        icon: String, iconColor: Color,
        title: String, subtitle: String,
        pointsText: String,
        progress: Double? = nil,
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

            // Title + subtitle + progress bar
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(themeManager.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
                    .lineLimit(1)

                // Daily cap progress bar
                if let progress = progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.15))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(iconColor.opacity(0.7))
                                .frame(width: geo.size.width * min(progress, 1.0), height: 3)
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 2)
                }
            }

            Spacer()

            // Points — fixed width
            Text(pointsText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(status == .checkedOut ? .green : (status == .claimable ? starGold : .gray))
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
                .fill(Color(.secondarySystemGroupedBackground))
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
    private let starGold = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 20))
            .foregroundColor(starGold)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    angle = 8
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
    @State private var revealedTomatoType: TomatoType?
    @State private var showingReveal = false
    @State private var revealPhase: RevealPhase = .card
    // Transaction history
    @State private var transactions: [NetworkService.PointTransaction] = []

    private enum RevealPhase {
        case card, flip, reveal
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ForEach(ShopSection.allCases, id: \.self) { section in
                    shopSection(section)
                }

                // Recent Activity section
                if !transactions.isEmpty {
                    recentActivitySection
                }
            }
            .padding()
        }
        .task {
            transactions = await NetworkService.shared.fetchPointTransactions(limit: 20) ?? []
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
        .overlay {
            if showingReveal, let tomatoType = revealedTomatoType {
                tomatoRevealOverlay(tomatoType)
            }
        }
    }

    // MARK: - Tomato Reveal Animation

    @ViewBuilder
    private func tomatoRevealOverlay(_ tomatoType: TomatoType) -> some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    // Mystery card (back side)
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [rarityGradientColor(tomatoType.rarity), rarityGradientColor(tomatoType.rarity).opacity(0.6)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 200, height: 260)
                        .overlay(
                            VStack(spacing: 8) {
                                Text("?")
                                    .font(.system(size: 80, weight: .black, design: .rounded))
                                    .foregroundColor(.white.opacity(0.9))
                                Text(tomatoType.rarityLabel)
                                    .font(.caption.bold())
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        )
                        .shadow(color: rarityGradientColor(tomatoType.rarity).opacity(0.5), radius: 20)
                        .opacity(revealPhase == .card ? 1 : 0)
                        .scaleEffect(revealPhase == .card ? 1 : 0.8)
                        .rotation3DEffect(.degrees(revealPhase == .flip ? 90 : 0), axis: (x: 0, y: 1, z: 0))

                    // Revealed tomato (front side)
                    VStack(spacing: 16) {
                        Image(tomatoType.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .shadow(color: rarityGradientColor(tomatoType.rarity).opacity(0.6), radius: 16)

                        Text(tomatoType.displayName)
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Text(tomatoType.rarityLabel)
                            .font(.subheadline.bold())
                            .foregroundColor(rarityGradientColor(tomatoType.rarity))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(rarityGradientColor(tomatoType.rarity).opacity(0.2))
                            .clipShape(Capsule())

                        Text(tomatoType.description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .opacity(revealPhase == .reveal ? 1 : 0)
                    .scaleEffect(revealPhase == .reveal ? 1 : 0.5)
                }

                Spacer()

                Button(action: dismissReveal) {
                    Text(NSLocalizedString("shop.blindbox.collect", value: "Collect", comment: ""))
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(rarityGradientColor(tomatoType.rarity))
                        .cornerRadius(14)
                        .padding(.horizontal, 40)
                }
                .opacity(revealPhase == .reveal ? 1 : 0)
                .padding(.bottom, 40)
            }
        }
        .transition(.opacity)
        .onAppear { runRevealAnimation() }
    }

    private func runRevealAnimation() {
        revealPhase = .card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.3)) {
                revealPhase = .flip
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    revealPhase = .reveal
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let success = UINotificationFeedbackGenerator()
                    success.notificationOccurred(.success)
                }
            }
        }
    }

    private func dismissReveal() {
        withAnimation(.easeOut(duration: 0.2)) {
            showingReveal = false
            revealedTomatoType = nil
            revealPhase = .card
        }
    }

    private func rarityGradientColor(_ rarity: Int) -> Color {
        switch rarity {
        case 2: return DesignTokens.Colors.Cute.blue
        case 3: return DesignTokens.Colors.Cute.lavender
        case 4: return DesignTokens.Colors.Cute.peach
        default: return DesignTokens.Colors.Cute.mint
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
                    .fill(Color(.secondarySystemGroupedBackground))
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
            // Refresh transaction history
            transactions = await NetworkService.shared.fetchPointTransactions(limit: 20) ?? transactions
        case .tomatoRevealed(let type, _):
            revealedTomatoType = type
            revealPhase = .card
            withAnimation(.easeIn(duration: 0.3)) {
                showingReveal = true
            }
            // Refresh transaction history
            transactions = await NetworkService.shared.fetchPointTransactions(limit: 20) ?? transactions
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

    // MARK: - Recent Activity Section

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(NSLocalizedString("points.shop.history", comment: ""))
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(transactions.prefix(20).enumerated()), id: \.element.id) { index, tx in
                    transactionRow(tx)
                    if index < min(transactions.count, 20) - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
            )
        }
    }

    private func transactionRow(_ tx: NetworkService.PointTransaction) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(tx.type == "earn" ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: tx.type == "earn" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(tx.type == "earn" ? .green : .red)
            }

            // Description
            VStack(alignment: .leading, spacing: 2) {
                Text(localizedTransactionDescription(tx))
                    .font(.caption.weight(.medium))
                    .foregroundColor(themeManager.primaryText)
                    .lineLimit(1)
                Text(relativeTime(tx.createdAt))
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }

            Spacer()

            // Amount
            Text(tx.type == "earn" ? "+\(tx.amount)" : "-\(tx.amount)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(tx.type == "earn" ? .green : .red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func localizedTransactionDescription(_ tx: NetworkService.PointTransaction) -> String {
        let key: String
        switch tx.feature {
        case "premium_trial":   key = "points.tx.premiumTrial"
        case "chat_messages":   key = "points.tx.chatMessages"
        case "homework_pages":  key = "points.tx.homeworkPages"
        case "voice_minutes":   key = "points.tx.voiceMinutes"
        case "error_analysis":  key = "points.tx.errorAnalysis"
        case "questions":       key = "points.tx.questions"
        case "streak_freeze":   key = "points.tx.streakFreeze"
        default:                return tx.description
        }
        let template = NSLocalizedString(key, comment: "")
        return template == key ? tx.description : String(format: template, tx.amount)
    }

    private func relativeTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) else {
            return ""
        }
        let relFormatter = RelativeDateTimeFormatter()
        relFormatter.unitsStyle = .abbreviated
        return relFormatter.localizedString(for: date, relativeTo: Date())
    }
}
