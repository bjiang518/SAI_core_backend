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
    @Environment(\.dismiss) private var dismiss

    @State private var usageData: AccountUsageData?
    @State private var isLoading = true
    @State private var showingUpgrade = false

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let data = usageData {
                        VStack(spacing: 14) {
                            tierCard(data)
                            usageSection(data)
                            if !isUnlimitedTier(data.tier) {
                                unlockCard
                            }
                            if !isUnlimitedTier(data.tier) {
                                upgradeButton
                            }
                            if isPaidTier(data.tier) {
                                manageSubscriptionButton
                            }
                            restorePurchasesButton
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("account.usage.loadError", comment: ""))
                                .foregroundColor(.secondary)
                            Button(NSLocalizedString("common.retry", comment: "")) {
                                Task { await loadData() }
                            }
                            .foregroundColor(Color(hex: "5B7FFF"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
            }
            .refreshable { await loadData() }

            // X close button
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .padding(.top, 20)
            .padding(.trailing, 20)
        }
        .task { await loadData() }
        .onChange(of: authService.currentUser?.tier) { _ in
            if let current = usageData { usageData = applyLocalTier(to: current) }
            Task {
                await silentRefresh()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await silentRefresh()
            }
        }
        .fullScreenCover(isPresented: $showingUpgrade, onDismiss: {
            Task { await loadData() }
        }) {
            UpgradeComparisonView(
                blockedFeature: "",
                reason: .featureBlocked,
                onDismiss: { showingUpgrade = false }
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 0) {
            Image("plan_usage_robot")
                .resizable()
                .scaledToFit()
                .frame(width: 110, height: 110)
                .padding(.leading, 16)

            VStack(alignment: .leading, spacing: 6) {
                Text(NSLocalizedString("account.usage.title", comment: ""))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.primary)
                Text(NSLocalizedString("account.usage.subtitle", value: "Track your usage and unlock more power with StudyAgent.", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 12)
            .padding(.trailing, 52) // leave room for X button

            Spacer()
        }
        .padding(.vertical, 20)
    }

    // MARK: - Tier card

    private func tierCard(_ data: AccountUsageData) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tierColor(data.tier, isAnonymous: data.isAnonymous).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: tierIcon(data.tier, isAnonymous: data.isAnonymous))
                    .font(.system(size: 18))
                    .foregroundColor(tierColor(data.tier, isAnonymous: data.isAnonymous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tierTitle(data.tier, isAnonymous: data.isAnonymous))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                if data.isAnonymous {
                    Text(NSLocalizedString("account.usage.lifetimeLimits", comment: ""))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else if let resetsAt = data.resetsAt, let date = isoDate(resetsAt) {
                    Text(String(format: NSLocalizedString("account.usage.resetsOn", comment: ""), date.formatted(.dateTime.month(.abbreviated).day())))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(tierBadge(data.tier, isAnonymous: data.isAnonymous))
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(tierColor(data.tier, isAnonymous: data.isAnonymous).opacity(0.12))
                .foregroundColor(tierColor(data.tier, isAnonymous: data.isAnonymous))
                .cornerRadius(20)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Usage section

    private func usageSection(_ data: AccountUsageData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(NSLocalizedString("account.usage.yourUsage", value: "Your Usage", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                if !data.isAnonymous {
                    Text(NSLocalizedString("account.usage.resetsMonthEnd", value: "Resets at the end of each month", comment: ""))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            VStack(spacing: 0) {
                ForEach(Array(data.features.enumerated()), id: \.offset) { idx, feature in
                    featureRow(feature)
                    if idx < data.features.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
    }

    private func featureRow(_ feature: FeatureUsage) -> some View {
        let info = featureInfo(feature.key)
        let localizedLabel = NSLocalizedString("account.usage.feature.\(feature.key)", value: feature.label, comment: "")

        return HStack(spacing: 12) {
            // Colored icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(info.color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: info.icon)
                    .font(.system(size: 16))
                    .foregroundColor(info.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)

                if let limit = feature.limit, limit > 0 {
                    progressBar(used: feature.used, limit: limit)
                }
            }

            Spacer()

            rightLabel(feature)

            Image(systemName: "chevron.right")
                .font(.system(size: 11))
                .foregroundColor(Color(.systemGray3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func rightLabel(_ feature: FeatureUsage) -> some View {
        if feature.limit == nil {
            HStack(spacing: 3) {
                Image(systemName: "infinity")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(Color(hex: "34C759"))
        } else if feature.limit == 0 {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                Text(NSLocalizedString("account.usage.upgradeLabel", comment: ""))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Color(hex: "5B7FFF"))
        } else if let limit = feature.limit {
            let suffix = feature.unit.map { " \($0)" } ?? ""
            Text("\(feature.used) / \(limit)\(suffix)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(barColor(used: feature.used, limit: limit))
                .monospacedDigit()
        }
    }

    private func progressBar(used: Int, limit: Int) -> some View {
        let ratio = min(1.0, Double(used) / Double(limit))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.systemFill))
                    .frame(height: 5)
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor(used: used, limit: limit))
                    .frame(width: geo.size.width * ratio, height: 5)
                    .animation(.easeOut(duration: 0.4), value: ratio)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Unlock card

    private var unlockCard: some View {
        HStack(spacing: 14) {
            // Crown illustration
            Image("plan_usage_crown")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)

            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("account.usage.unlockTitle", value: "Unlock unlimited access", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(NSLocalizedString("account.usage.unlockSubtitle", value: "Upgrade to Premium or Ultra and supercharge your learning.", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    // MARK: - Upgrade button

    private var upgradeButton: some View {
        Button { showingUpgrade = true } label: {
            HStack {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 18))
                Text(NSLocalizedString("account.usage.upgradePlan", value: "View & Upgrade Plans", comment: ""))
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13))
            }
            .foregroundColor(.white)
            .padding(16)
            .background(DesignTokens.Colors.Cute.buttonBlack)
            .cornerRadius(16)
        }
    }

    private var restorePurchasesButton: some View {
        Button {
            Task { await StoreKitService.shared.restorePurchases() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                Text(NSLocalizedString("account.usage.restorePurchases", comment: ""))
                    .font(.subheadline)
            }
            .foregroundColor(Color(hex: "5B7FFF"))
            .frame(maxWidth: .infinity)
        }
    }

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

    // MARK: - Feature icon mapping

    private struct FeatureInfo { let icon: String; let color: Color }

    private func featureInfo(_ key: String) -> FeatureInfo {
        switch key {
        case "homework_pages":  return .init(icon: "doc.text.fill",            color: Color(hex: "5B7FFF"))
        case "chat_messages":   return .init(icon: "bubble.left.fill",         color: Color(hex: "9B5FFF"))
        case "voice_minutes":   return .init(icon: "waveform",                 color: Color(hex: "F59E0B"))
        case "tts_calls":       return .init(icon: "speaker.wave.2.fill",      color: Color(hex: "F59E0B"))
        case "questions":       return .init(icon: "checkmark.circle.fill",    color: Color(hex: "34C759"))
        case "error_analysis":  return .init(icon: "chart.bar.fill",           color: Color(hex: "5B7FFF"))
        case "reports":         return .init(icon: "doc.plaintext.fill",       color: Color(hex: "FF7BAC"))
        default:                return .init(icon: "star.fill",                color: Color(hex: "D4AF37"))
        }
    }

    // MARK: - Helpers

    private func loadData() async {
        isLoading = true
        if let raw = await NetworkService.shared.fetchAccountUsage() {
            usageData = applyLocalTier(to: raw)
        } else {
            usageData = nil
        }
        isLoading = false
    }

    private func silentRefresh() async {
        if let raw = await NetworkService.shared.fetchAccountUsage() {
            usageData = applyLocalTier(to: raw)
        }
    }

    private func applyLocalTier(to data: AccountUsageData) -> AccountUsageData {
        guard let user = authService.currentUser else { return data }
        let localTier = user.isAnonymous ? "guest" : user.tier.rawValue
        guard localTier != data.tier else { return data }
        let features = data.features.map { f in
            FeatureUsage(key: f.key, label: f.label, used: f.used,
                         limit: localLimit(key: f.key, tier: localTier), unit: f.unit)
        }
        return AccountUsageData(tier: localTier, isAnonymous: data.isAnonymous,
                                resetsAt: data.resetsAt, features: features)
    }

    private func localLimit(key: String, tier: String) -> Int? {
        switch tier {
        case "premium_plus": return nil
        case "premium":
            switch key {
            case "homework_pages": return 50
            case "chat_messages":  return 500
            case "questions":      return 200
            case "voice_minutes":  return 300
            default:               return nil
            }
        case "free":
            switch key {
            case "homework_pages": return 5
            case "chat_messages":  return 20
            case "questions":      return 10
            case "error_analysis": return 3
            case "tts_calls":      return 50
            default:               return 0
            }
        case "guest":
            switch key {
            case "homework_pages": return 3
            case "chat_messages":  return 10
            case "tts_calls":      return 20
            default:               return 0
            }
        default: return nil
        }
    }

    private func isUnlimitedTier(_ tier: String) -> Bool { tier == "premium_plus" }
    private func isPaidTier(_ tier: String) -> Bool { tier == "premium" || tier == "premium_plus" }

    private func barColor(used: Int, limit: Int) -> Color {
        let ratio = Double(used) / Double(limit)
        if ratio >= 0.8 { return Color(hex: "FFB6A3") }
        if ratio >= 0.5 { return Color(hex: "FFE066") }
        return Color(hex: "5B7FFF")
    }

    private func tierColor(_ tier: String, isAnonymous: Bool) -> Color {
        if isAnonymous { return .secondary }
        switch tier {
        case "premium":      return Color(hex: "8C95A6")
        case "premium_plus": return Color(hex: "D4AF37")
        default:             return Color(hex: "5B7FFF")
        }
    }

    private func tierIcon(_ tier: String, isAnonymous: Bool) -> String {
        if isAnonymous { return "person.crop.circle.badge.questionmark" }
        switch tier {
        case "premium", "premium_plus": return "crown.fill"
        default:                         return "person.circle.fill"
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
        ISO8601DateFormatter().date(from: iso)
    }
}
