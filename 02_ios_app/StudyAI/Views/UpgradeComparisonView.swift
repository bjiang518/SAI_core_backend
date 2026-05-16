//
//  UpgradeComparisonView.swift
//  StudyAI
//

import SwiftUI
import Lottie
import StoreKit

struct UpgradeComparisonView: View {

    enum Reason {
        case featureBlocked
        case limitReached
    }

    let blockedFeature: String
    let reason: Reason
    var onDismiss: () -> Void

    @StateObject private var storeKit = StoreKitService.shared
    @StateObject private var usageService = UsageService.shared
    @StateObject private var authService = AuthenticationService.shared
    @State private var purchasingUltra = false
    @State private var purchasingPremium = false

    private var premiumTrialEligible: Bool { storeKit.trialEligibility["com.studyai.premium.monthly"] == true }
    private var ultraTrialEligible: Bool   { storeKit.trialEligibility["com.studyai.ultra.monthly"]   == true }

    // MARK: - Promo code state

    private enum PromoState {
        case idle
        case loading
        case success(Date?, UserTier)
        case error(String)
    }

    @State private var promoCode = ""
    @State private var promoExpanded = false
    @State private var promoState: PromoState = .idle

    // MARK: - Design tokens
    private let freeColor    = Color(hex: "7EC8E3")
    private let premiumColor = Color(hex: "5B7FFF")
    private let ultraColor   = Color(hex: "F59E0B")
    private let silver       = Color(hex: "8C95A6")
    private let badgeGold    = Color(hex: "D4AF37")
    private let cardBg       = Color(.systemBackground)
    private let pageBg       = Color(.systemGroupedBackground)

    // MARK: - Comparison table data

    private struct PlanRow {
        let icon: String
        let iconColor: Color
        let feature: String
        let free: String
        let premium: String
        let family: String
    }

    private var planRows: [PlanRow] {[
        PlanRow(icon: "doc.text.fill",              iconColor: Color(hex: "5B7FFF"),
                feature: NSLocalizedString("upgrade.comparison.featureHomework", comment: ""),
                free: "5/mo", premium: "50/mo", family: "✓"),
        PlanRow(icon: "bubble.left.fill",           iconColor: Color(hex: "9B5FFF"),
                feature: NSLocalizedString("upgrade.comparison.featureAiChat", comment: ""),
                free: "20/mo", premium: "500/mo", family: "✓"),
        PlanRow(icon: "mic.fill",                   iconColor: Color(hex: "34C759"),
                feature: NSLocalizedString("upgrade.comparison.featureLiveTutor", comment: ""),
                free: "—", premium: NSLocalizedString("upgrade.comparison.valueLiveTutor", comment: ""), family: "✓"),
        PlanRow(icon: "checkmark.circle.fill",      iconColor: Color(hex: "F59E0B"),
                feature: NSLocalizedString("upgrade.comparison.featurePractice", comment: ""),
                free: "10 qs", premium: "200 qs", family: "✓"),
        PlanRow(icon: "chart.bar.fill",             iconColor: Color(hex: "5B7FFF"),
                feature: NSLocalizedString("upgrade.comparison.featureWeakness", comment: ""),
                free: "3/mo", premium: "✓", family: "✓"),
        PlanRow(icon: "figure.2.and.child.holdinghands", iconColor: Color(hex: "FF7BAC"),
                feature: NSLocalizedString("upgrade.comparison.featureReports", comment: ""),
                free: "—", premium: "✓", family: "✓"),
        PlanRow(icon: "person.2.fill",              iconColor: Color(hex: "F59E0B"),
                feature: NSLocalizedString("upgrade.comparison.featureMultipleKids", comment: ""),
                free: "—", premium: "—",
                family: NSLocalizedString("upgrade.comparison.valueMultipleKids", comment: "")),
    ]}

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    Spacer().frame(height: 32)

                    headerSection
                        .padding(.horizontal, 20)

                    comparisonTable
                        .padding(.horizontal, 16)

                    bottomCTAs
                        .padding(.horizontal, 16)

                    promoSection
                        .padding(.horizontal, 16)

                    continueFreeLink

                    termsText
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    restoreLink
                        .padding(.bottom, 32)
                }
            }

            // Floating close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.systemGray5))
                    .clipShape(Circle())
            }
            .padding(.top, 16)
            .padding(.leading, 16)
        }
        .task { await storeKit.loadProducts() }
        .onAppear {
            JourneyTracker.shared.track("upgrade_prompt_shown", [
                "feature": blockedFeature,
                "reason": reason == .featureBlocked ? "feature_blocked" : "limit_reached"
            ])
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("upgrade.comparison.headerLine1", value: "Upgrade your", comment: ""))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)
                    Text("StudyAgent")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(premiumColor)
                }

                Text(NSLocalizedString("upgrade.comparison.headerSubtitle", comment: ""))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if premiumTrialEligible || ultraTrialEligible {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                        Text(NSLocalizedString("upgrade.comparison.trialBadge",
                             value: "7-Day Free Trial  •  Cancel anytime", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(premiumColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(premiumColor.opacity(0.1))
                    .cornerRadius(20)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("upgrade_robot")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
        }
    }

    // MARK: - Comparison table

    // Feature column has fixed width; 3 value columns share remaining space equally.
    private let featureColW: CGFloat = 112

    private var comparisonTable: some View {
        VStack(spacing: 0) {

            // ── Badges (above the white card) ───────────────────────────
            HStack(spacing: 0) {
                Color.clear.frame(width: featureColW)
                Color.clear.frame(maxWidth: .infinity)  // Free: no badge

                // Premium — Most Popular
                HStack(spacing: 3) {
                    Image(systemName: "star.fill").font(.system(size: 9))
                    Text(NSLocalizedString("upgrade.comparison.badgeMostPopular", comment: ""))
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(premiumColor)
                .cornerRadius(8, corners: [.topLeft, .topRight])

                // Ultra — Best Value
                HStack(spacing: 3) {
                    Image(systemName: "crown.fill").font(.system(size: 9))
                    Text(NSLocalizedString("upgrade.comparison.badgeBestValue", comment: ""))
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(ultraColor)
                .cornerRadius(8, corners: [.topLeft, .topRight])
            }

            // ── Plan headers (above the white card) ────────────────────
            HStack(spacing: 0) {
                Color.clear.frame(width: featureColW)

                planHeaderCell(NSLocalizedString("upgrade.comparison.planFree", comment: ""),
                               price: "$0", period: nil, color: freeColor)

                planHeaderCell(NSLocalizedString("upgrade.comparison.planPremium", comment: ""),
                               price: "$9.99",
                               period: NSLocalizedString("upgrade.comparison.pricePeriod", comment: ""),
                               color: premiumColor)
                .background(premiumColor.opacity(0.06))

                planHeaderCell(NSLocalizedString("upgrade.comparison.planUltra", comment: ""),
                               price: "$19.99",
                               period: NSLocalizedString("upgrade.comparison.pricePeriod", comment: ""),
                               color: ultraColor)
                .background(ultraColor.opacity(0.06))
            }

            // ── Feature rows — white card starts here ──────────────────
            VStack(spacing: 0) {
                ForEach(Array(planRows.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 0) {
                        // Icon + label
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(row.iconColor.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: row.icon)
                                    .font(.system(size: 15))
                                    .foregroundColor(row.iconColor)
                            }
                            Text(row.feature)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: featureColW, alignment: .leading)
                        .padding(.leading, 10)

                        dataCell(row.free,    checkColor: freeColor)
                        dataCell(row.premium, checkColor: premiumColor)
                            .background(premiumColor.opacity(0.03))
                        dataCell(row.family,  checkColor: ultraColor, isUltra: true)
                            .background(ultraColor.opacity(0.03))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)

                    if idx < planRows.count - 1 {
                        Divider().padding(.leading, featureColW + 8).opacity(0.35)
                    }
                }
                Spacer().frame(height: 8)
            }
            .background(cardBg)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 3)
        }
        .frame(maxWidth: .infinity)
    }

    private func planHeaderCell(_ title: String, price: String, period: String?,
                                color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(price)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(color)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                if let period {
                    Text(period)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func dataCell(_ value: String, checkColor: Color, isUltra: Bool = false) -> some View {
        Group {
            switch value {
            case "✓":
                ZStack {
                    Circle().fill(checkColor.opacity(0.15)).frame(width: 26, height: 26)
                    Image(systemName: "infinity")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(checkColor)
                }
            case "—":
                Text("—").font(.system(size: 14)).foregroundColor(Color(.systemGray4))
            default:
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isUltra ? checkColor : .primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 30)
    }

    // MARK: - Bottom CTAs

    private var bottomCTAs: some View {
        VStack(spacing: 10) {
            // Ultra — gold button
            Button {
                JourneyTracker.shared.track("upgrade_tapped", ["tier": "ultra", "feature": blockedFeature])
                Task {
                    if let product = storeKit.products.first(where: { $0.id.contains("ultra") }) {
                        purchasingUltra = true
                        await storeKit.purchase(product)
                        purchasingUltra = false
                        if storeKit.purchaseError == nil { onDismiss() }
                    }
                }
            } label: {
                HStack {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.25)).frame(width: 38, height: 38)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                    }
                    if purchasingUltra {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ultraTrialEligible
                                 ? NSLocalizedString("upgrade.comparison.ctaUltraTrial", comment: "")
                                 : String(format: NSLocalizedString("upgrade.comparison.ctaUltra", comment: ""),
                                          (storeKit.products.first(where: { $0.id.contains("ultra") })?.displayPrice ?? "$19.99")
                                          + NSLocalizedString("upgrade.comparison.pricePeriod", comment: "")))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            if ultraTrialEligible {
                                let price = storeKit.products.first(where: { $0.id.contains("ultra") })?.displayPrice ?? "$19.99"
                                Text(String(format: NSLocalizedString("upgrade.comparison.trialSubtext", comment: ""),
                                            price + NSLocalizedString("upgrade.comparison.pricePeriod", comment: "")))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "F5B731"), Color(hex: "E07B00")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .disabled(purchasingUltra || purchasingPremium)

            // Premium — blue button
            Button {
                JourneyTracker.shared.track("upgrade_tapped", ["tier": "premium", "feature": blockedFeature])
                Task {
                    if let product = storeKit.products.first(where: { $0.id.contains("premium") && !$0.id.contains("ultra") }) {
                        purchasingPremium = true
                        await storeKit.purchase(product)
                        purchasingPremium = false
                        if storeKit.purchaseError == nil { onDismiss() }
                    }
                }
            } label: {
                HStack {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.2)).frame(width: 38, height: 38)
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    if purchasingPremium {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(premiumTrialEligible
                                 ? NSLocalizedString("upgrade.comparison.ctaPremiumTrial", comment: "")
                                 : String(format: NSLocalizedString("upgrade.comparison.ctaPremium", comment: ""),
                                          (storeKit.products.first(where: { $0.id.contains("premium") && !$0.id.contains("ultra") })?.displayPrice ?? "$9.99")
                                          + NSLocalizedString("upgrade.comparison.pricePeriod", comment: "")))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            if premiumTrialEligible {
                                let price = storeKit.products.first(where: { $0.id.contains("premium") && !$0.id.contains("ultra") })?.displayPrice ?? "$9.99"
                                Text(String(format: NSLocalizedString("upgrade.comparison.trialSubtext", comment: ""),
                                            price + NSLocalizedString("upgrade.comparison.pricePeriod", comment: "")))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "6B7FFF"), Color(hex: "4B5FEE")],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .disabled(purchasingUltra || purchasingPremium)

            if let error = storeKit.purchaseError {
                Text(error)
                    .font(.caption).foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Continue Free

    private var continueFreeLink: some View {
        Button { onDismiss() } label: {
            HStack(spacing: 3) {
                Text(NSLocalizedString("upgrade.comparison.continueFree", comment: ""))
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.subheadline)
            .foregroundColor(premiumColor)
        }
    }

    // MARK: - Promo code section (unchanged logic)

    private var promoSection: some View {
        VStack(spacing: 8) {
            if authService.currentUser?.isAnonymous == true {
                Text(NSLocalizedString("promo.guestHint", comment: ""))
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else if case .success(let expiresAt, let tier) = promoState {
                let isDowngrade = tier == .free
                HStack(spacing: 8) {
                    Image(systemName: isDowngrade ? "arrow.down.circle.fill" : tier == .premiumPlus ? "crown.fill" : "checkmark.circle.fill")
                        .foregroundColor(isDowngrade ? .orange : tier == .premiumPlus ? badgeGold : .green)
                    let dateStr: String = {
                        if let d = expiresAt { return DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .none) }
                        return ""
                    }()
                    let successKey = isDowngrade ? "promo.success.downgrade" : tier == .premiumPlus ? "promo.success.ultra" : "promo.success"
                    Text(isDowngrade
                         ? NSLocalizedString(successKey, comment: "")
                         : String(format: NSLocalizedString(successKey, comment: ""), dateStr))
                        .font(.footnote.bold())
                        .foregroundColor(isDowngrade ? .orange : tier == .premiumPlus ? badgeGold : .green)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background((isDowngrade ? Color.orange : tier == .premiumPlus ? badgeGold : Color.green).opacity(0.1))
                .cornerRadius(10)
            } else if promoExpanded {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField(NSLocalizedString("promo.placeholder", comment: ""), text: $promoCode)
                            .font(.system(.body, design: .monospaced))
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .onSubmit { Task { await applyPromoCode() } }
                        if !promoCode.isEmpty {
                            Button { promoCode = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(.systemFill))
                    .cornerRadius(10)

                    if case .error(let msg) = promoState {
                        Text(msg).font(.caption).foregroundColor(.red).multilineTextAlignment(.center)
                    }

                    Button { Task { await applyPromoCode() } } label: {
                        Group {
                            if case .loading = promoState {
                                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                            } else {
                                Text(NSLocalizedString("promo.button.apply", comment: ""))
                                    .fontWeight(.semibold).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                            }
                        }
                        .background(premiumColor).cornerRadius(12)
                    }
                    .disabled(promoCode.trimmingCharacters(in: .whitespaces).isEmpty || { if case .loading = promoState { return true }; return false }())
                }
            } else {
                Button { promoExpanded = true } label: {
                    Text(NSLocalizedString("promo.link", comment: ""))
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: promoExpanded)
    }

    private func applyPromoCode() async {
        let trimmed = promoCode.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        promoState = .loading
        let result = await NetworkService.shared.redeemPromoCode(trimmed)
        await MainActor.run {
            if result.success {
                promoState = .success(result.tierExpiresAt, result.grantedTier ?? .premium)
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    onDismiss()
                }
            } else {
                let msg: String
                switch result.errorCode {
                case "ALREADY_REDEEMED": msg = NSLocalizedString("promo.error.alreadyRedeemed", comment: "")
                case "EXPIRED":          msg = NSLocalizedString("promo.error.expired", comment: "")
                case "MAX_USES_REACHED": msg = NSLocalizedString("promo.error.maxUses", comment: "")
                default:                 msg = NSLocalizedString("promo.error.invalid", comment: "")
                }
                promoState = .error(msg)
            }
        }
    }

    // MARK: - Footer

    private var restoreLink: some View {
        Button { Task { await StoreKitService.shared.restorePurchases() } } label: {
            Text(NSLocalizedString("upgrade.comparison.restorePurchases", comment: ""))
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private var termsText: some View {
        let termsKey = (premiumTrialEligible || ultraTrialEligible)
            ? "upgrade.comparison.termsTrial" : "upgrade.comparison.terms"
        return VStack(spacing: 6) {
            Text(NSLocalizedString(termsKey, comment: ""))
                .font(.caption2).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link(NSLocalizedString("upgrade.comparison.termsLink", comment: ""),
                     destination: AppURLs.termsOfService)
                    .font(.caption2).foregroundColor(.secondary)
                Link(NSLocalizedString("upgrade.comparison.privacyLink", comment: ""),
                     destination: AppURLs.privacyPolicy)
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Corner radius helper

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
