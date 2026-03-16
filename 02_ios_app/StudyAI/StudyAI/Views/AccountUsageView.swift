//
//  AccountUsageView.swift
//  StudyAI
//
//  Shows per-feature usage vs. limits for the current account,
//  and links directly to the upgrade paywall.
//

import SwiftUI
import StoreKit

struct AccountUsageView: View {

    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var authService = AuthenticationService.shared

    @State private var usageData: AccountUsageData?
    @State private var isLoading = true
    @State private var showingUpgrade = false

    // Design tokens
    private let mint   = Color(hex: "7FDBCA")
    private let yellow = Color(hex: "FFE066")
    private let peach  = Color(hex: "FFB6A3")
    private let teal   = DesignTokens.Colors.libraryTeal
    private let gold   = Color(hex: "D97706")

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let data = usageData {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            tierCard(data)
                            featuresSection(data)
                            if !isUnlimitedTier(data.tier) {
                                upgradeButton
                            }
                            if isPaidTier(data.tier) {
                                manageSubscriptionButton
                            }
                            restorePurchasesButton
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("account.usage.loadError", comment: ""))
                            .foregroundColor(themeManager.secondaryText)
                        Button(NSLocalizedString("common.retry", comment: "")) { Task { await loadData() } }
                            .foregroundColor(teal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(NSLocalizedString("account.usage.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await loadData() }
        .refreshable { await loadData() }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeComparisonView(
                blockedFeature: "",
                reason: .featureBlocked,
                onDismiss: { showingUpgrade = false }
            )
        }
    }

    // MARK: - Tier card

    private func tierCard(_ data: AccountUsageData) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: tierIcon(data.tier, isAnonymous: data.isAnonymous))
                    .font(.system(size: 22))
                    .foregroundColor(tierColor(data.tier, isAnonymous: data.isAnonymous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(tierTitle(data.tier, isAnonymous: data.isAnonymous))
                        .font(.headline)
                        .foregroundColor(themeManager.primaryText)

                    if data.isAnonymous {
                        Text(NSLocalizedString("account.usage.lifetimeLimits", comment: ""))
                            .font(.caption)
                            .foregroundColor(themeManager.secondaryText)
                    } else if let resetsAt = data.resetsAt, let date = isoDate(resetsAt) {
                        Text(String(format: NSLocalizedString("account.usage.resetsOn", comment: ""), date.formatted(.dateTime.month(.abbreviated).day())))
                            .font(.caption)
                            .foregroundColor(themeManager.secondaryText)
                    }
                }

                Spacer()

                // Tier badge pill
                Text(tierBadge(data.tier, isAnonymous: data.isAnonymous))
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tierColor(data.tier, isAnonymous: data.isAnonymous).opacity(0.15))
                    .foregroundColor(tierColor(data.tier, isAnonymous: data.isAnonymous))
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(themeManager.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // MARK: - Features section

    private func featuresSection(_ data: AccountUsageData) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(data.features.enumerated()), id: \.offset) { idx, feature in
                featureRow(feature)
                if idx < data.features.count - 1 {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(themeManager.cardBackground)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func featureRow(_ feature: FeatureUsage) -> some View {
        let localizedLabel = NSLocalizedString("account.usage.feature.\(feature.key)", value: feature.label, comment: "")
        return VStack(spacing: 8) {
            HStack {
                Text(localizedLabel)
                    .font(.subheadline)
                    .foregroundColor(themeManager.primaryText)

                Spacer()

                rightLabel(feature)
            }

            // Progress bar (only when there's an actual quota)
            if let limit = feature.limit, limit > 0 {
                progressBar(used: feature.used, limit: limit)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func rightLabel(_ feature: FeatureUsage) -> some View {
        if feature.limit == nil {
            // Unlimited
            HStack(spacing: 4) {
                Image(systemName: "infinity")
                    .font(.caption.bold())
                Text(NSLocalizedString("account.usage.unlimited", comment: ""))
                    .font(.caption.bold())
            }
            .foregroundColor(teal)
        } else if feature.limit == 0 {
            // Blocked for tier
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                Text(NSLocalizedString("account.usage.upgradeLabel", comment: ""))
                    .font(.caption.bold())
            }
            .foregroundColor(.secondary)
        } else if let limit = feature.limit {
            let remaining = max(0, limit - feature.used)
            let suffix = feature.unit.map { " \($0)" } ?? ""
            Text("\(feature.used) / \(limit)\(suffix)")
                .font(.caption.bold())
                .foregroundColor(barColor(used: feature.used, limit: limit))
                .monospacedDigit()
            + Text(remaining == 0 ? " ⚠" : "")
                .font(.caption.bold())
                .foregroundColor(peach)
        }
    }

    private func progressBar(used: Int, limit: Int) -> some View {
        let ratio = min(1.0, Double(used) / Double(limit))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemFill))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor(used: used, limit: limit))
                    .frame(width: geo.size.width * ratio, height: 6)
                    .animation(.easeOut(duration: 0.4), value: ratio)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Upgrade button

    private var upgradeButton: some View {
        Button { showingUpgrade = true } label: {
            HStack {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 18))
                Text(NSLocalizedString("account.usage.upgradePlan", comment: ""))
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
            }
            .foregroundColor(.white)
            .padding(16)
            .background(
                LinearGradient(
                    colors: [teal, Color(hex: "5BB5D5")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
        }
    }

    // Required by App Store Guideline 3.1.1 — visible wherever purchases are possible
    private var restorePurchasesButton: some View {
        Button {
            Task { await StoreKitService.shared.restorePurchases() }
        } label: {
            Text(NSLocalizedString("account.usage.restorePurchases", comment: ""))
                .font(.subheadline)
                .foregroundColor(teal)
                .frame(maxWidth: .infinity)
        }
    }

    // Shown for paid tiers — lets user manage or cancel their subscription
    private var manageSubscriptionButton: some View {
        Button {
            Task {
                if let scene = await UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                    try? await AppStore.showManageSubscriptions(in: scene)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gear")
                Text(NSLocalizedString("account.usage.manageSubscription", comment: ""))
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func loadData() async {
        isLoading = true
        usageData = await NetworkService.shared.fetchAccountUsage()
        isLoading = false
    }

    private func isUnlimitedTier(_ tier: String) -> Bool {
        tier == "premium_plus"
    }

    private func isPaidTier(_ tier: String) -> Bool {
        tier == "premium" || tier == "premium_plus"
    }

    private func barColor(used: Int, limit: Int) -> Color {
        let ratio = Double(used) / Double(limit)
        if ratio >= 1.0 { return peach }
        if ratio >= 0.8 { return peach }
        if ratio >= 0.5 { return yellow }
        return mint
    }

    private func tierColor(_ tier: String, isAnonymous: Bool) -> Color {
        if isAnonymous { return .secondary }
        switch tier {
        case "premium":      return teal
        case "premium_plus": return gold
        default:             return .secondary
        }
    }

    private func tierIcon(_ tier: String, isAnonymous: Bool) -> String {
        if isAnonymous { return "person.crop.circle.badge.questionmark" }
        switch tier {
        case "premium":      return "crown.fill"
        case "premium_plus": return "crown.fill"
        default:             return "person.circle.fill"
        }
    }

    private func tierTitle(_ tier: String, isAnonymous: Bool) -> String {
        if isAnonymous { return NSLocalizedString("account.usage.tierGuest", comment: "") }
        switch tier {
        case "premium":      return NSLocalizedString("account.usage.tierPremium", comment: "")
        case "premium_plus": return NSLocalizedString("account.usage.tierUltra", comment: "")
        default:             return NSLocalizedString("account.usage.tierFree", comment: "")
        }
    }

    private func tierBadge(_ tier: String, isAnonymous: Bool) -> String {
        if isAnonymous { return NSLocalizedString("account.usage.badgeGuest", comment: "") }
        switch tier {
        case "premium":      return NSLocalizedString("account.usage.tierPremium", comment: "")
        case "premium_plus": return NSLocalizedString("account.usage.tierUltra", comment: "")
        default:             return NSLocalizedString("account.usage.tierFree", comment: "")
        }
    }

    private func isoDate(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)
    }
}
