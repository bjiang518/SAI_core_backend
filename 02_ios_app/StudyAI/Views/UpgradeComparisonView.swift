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
    @State private var purchasingUltra = false
    @State private var purchasingPremium = false

    // MARK: - Design tokens
    private let teal       = DesignTokens.Colors.libraryTeal
    private let badgeBlue  = Color(hex: "7EC8E3")   // Free badge — Cute blue
    private let badgeGold  = Color(hex: "D97706")   // Family badge — amber/gold
    private let cardBg     = Color(.systemBackground)
    private let pageBg     = Color(.systemGroupedBackground)

    // MARK: - Comparison table data

    private struct PlanRow {
        let feature: String   // label column
        let free: String      // "10/mo" | "—" | "✓"
        let premium: String
        let family: String
    }

    private var planRows: [PlanRow] {[
        PlanRow(feature: NSLocalizedString("upgrade.comparison.featureHomework", comment: ""),    free: "10/mo",  premium: "50/mo",   family: "✓"),
        PlanRow(feature: NSLocalizedString("upgrade.comparison.featureAiChat", comment: ""),      free: "50/mo",  premium: "500/mo",  family: "✓"),
        PlanRow(feature: NSLocalizedString("upgrade.comparison.featureLiveTutor", comment: ""),   free: "—",      premium: NSLocalizedString("upgrade.comparison.valueLiveTutor", comment: ""), family: "✓"),
        PlanRow(feature: NSLocalizedString("upgrade.comparison.featurePractice", comment: ""),    free: "30 qs",  premium: "200 qs",  family: "✓"),
        PlanRow(feature: NSLocalizedString("upgrade.comparison.featureWeakness", comment: ""),    free: "5/mo",   premium: "✓",       family: "✓"),
        PlanRow(feature: NSLocalizedString("upgrade.comparison.featureReports", comment: ""),     free: "✓",      premium: "2/mo",    family: "✓"),
        PlanRow(feature: NSLocalizedString("upgrade.comparison.featureMultipleKids", comment: ""), free: "—",     premium: "—",       family: NSLocalizedString("upgrade.comparison.valueMultipleKids", comment: "")),
    ]}

    // Fixed width for the feature-label column
    private let labelW: CGFloat = 72

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 44)
                    headerSection
                        .padding(.bottom, 2)
                    usageSummaryBanner
                        .padding(.bottom, 4)
                    upgradeAnimation
                        .padding(.bottom, 2)
                    comparisonTable
                        .padding(.bottom, 20)
                    bottomCTAs
                        .padding(.bottom, 12)
                    continueFreeLink
                    termsText
                        .padding(.top, 12)
                    restoreLink
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
            }

            // Floating close button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(white: 0.0, opacity: 0.07))
                    .clipShape(Circle())
            }
            .padding(.top, 16)
            .padding(.leading, 20)
        }
        .task {
            #if DEBUG
            print("🛒 [UpgradeView] View appeared — loading products")
            #endif
            await storeKit.loadProducts()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text(NSLocalizedString("upgrade.comparison.headerTitle", comment: ""))
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            Text(NSLocalizedString("upgrade.comparison.headerSubtitle", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Lottie animation

    private var upgradeAnimation: some View {
        LottieView(
            animationName: "Upgrade",
            loopMode: .loop,
            animationSpeed: 1.0
        )
        .frame(width: 300, height: 300)
        .scaleEffect(0.25)
        .frame(height: 80)   // collapse layout space after scaling
    }

    // MARK: - Comparison table

    private var comparisonTable: some View {
        VStack(spacing: 0) {

            // ── Row 1: Badge strip ──────────────────────────────────────
            HStack(spacing: 0) {
                Spacer().frame(width: labelW)
                badgeStrip(NSLocalizedString("upgrade.comparison.badgeFreeToTry", comment: ""),    icon: "moon.fill",    bg: badgeBlue)
                badgeStrip(NSLocalizedString("upgrade.comparison.badgeMostPopular", comment: ""), icon: "star.fill",   bg: teal)
                badgeStrip(NSLocalizedString("upgrade.comparison.badgeBestValue", comment: ""),   icon: "sun.max.fill", bg: badgeGold)
            }

            // ── Row 2: Plan name + price ────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                // label col header — empty
                Spacer().frame(width: labelW)

                planHeader(NSLocalizedString("upgrade.comparison.planFree", comment: ""),    dollars: "0",     period: nil,   accentColor: badgeBlue)
                planHeader(NSLocalizedString("upgrade.comparison.planPremium", comment: ""), dollars: "9.99",  period: NSLocalizedString("upgrade.comparison.pricePeriod", comment: ""), accentColor: teal)
                planHeader(NSLocalizedString("upgrade.comparison.planUltra", comment: ""),   dollars: "19.99", period: NSLocalizedString("upgrade.comparison.pricePeriod", comment: ""), accentColor: badgeGold)
            }

            Divider().padding(.horizontal, 4)

            // ── Rows 3…n: Feature rows ──────────────────────────────────
            ForEach(Array(planRows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 0) {
                    Text(row.feature)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(width: labelW, alignment: .leading)
                        .padding(.leading, 10)

                    dataCell(row.free)
                    dataCell(row.premium)
                    dataCell(row.family)
                }
                .padding(.vertical, 12)
                .background(idx % 2 == 1 ? Color(.systemFill).opacity(0.25) : Color.clear)

                if idx < planRows.count - 1 {
                    Divider().padding(.horizontal, 4).opacity(0.35)
                }
            }

            Spacer().frame(height: 10)
        }
        .background(cardBg)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 3)
    }

    // Full-width badge strip — colour and icon vary per column
    private func badgeStrip(_ label: String, icon: String, bg: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(bg)
    }

    // Plan name + price cell in the header row
    private func planHeader(_ title: String, dollars: String, period: String?, accentColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            // Price + period on a single line: $9.99/mo
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("$")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
                Text(dollars)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(accentColor)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                if let period {
                    Text(period)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    // Individual data cell: checkmark / dash / text
    @ViewBuilder
    private func dataCell(_ value: String) -> some View {
        Group {
            switch value {
            case "✓":
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(teal)
            case "—":
                Text("—")
                    .font(.system(size: 16))
                    .foregroundColor(Color(.systemGray4))
            default:
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom section

    private var bottomCTAs: some View {
        VStack(spacing: 10) {
            Button {
                #if DEBUG
                print("🛒 [UpgradeView] Start Ultra tapped — products: \(storeKit.products.count)")
                #endif
                Task {
                    if let product = storeKit.products.first(where: { $0.id.contains("ultra") }) {
                        #if DEBUG
                        print("🛒 [UpgradeView] Purchasing: \(product.id) price=\(product.displayPrice)")
                        #endif
                        purchasingUltra = true
                        await storeKit.purchase(product)
                        purchasingUltra = false
                        if storeKit.purchaseError == nil { onDismiss() }
                    } else {
                        #if DEBUG
                        print("⚠️ [UpgradeView] No ultra product. Available: \(storeKit.products.map { "\($0.id) \($0.displayPrice)" })")
                        #endif
                    }
                }
            } label: {
                Group {
                    if purchasingUltra {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                    } else {
                        let ultraPrice = storeKit.products.first(where: { $0.id.contains("ultra") })?.displayPrice ?? "$19.99"
                        Text(String(format: NSLocalizedString("upgrade.comparison.ctaUltra", comment: ""), ultraPrice + NSLocalizedString("upgrade.comparison.pricePeriod", comment: "")))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
                .background(badgeGold)
                .cornerRadius(14)
            }
            .disabled(purchasingUltra || purchasingPremium)

            Button {
                #if DEBUG
                print("🛒 [UpgradeView] Start Premium tapped — products: \(storeKit.products.count)")
                #endif
                Task {
                    if let product = storeKit.products.first(where: { $0.id.contains("premium") && !$0.id.contains("ultra") }) {
                        #if DEBUG
                        print("🛒 [UpgradeView] Purchasing: \(product.id) price=\(product.displayPrice)")
                        #endif
                        purchasingPremium = true
                        await storeKit.purchase(product)
                        purchasingPremium = false
                        if storeKit.purchaseError == nil { onDismiss() }
                    } else {
                        #if DEBUG
                        print("⚠️ [UpgradeView] No premium product. Available: \(storeKit.products.map { "\($0.id) \($0.displayPrice)" })")
                        #endif
                    }
                }
            } label: {
                Group {
                    if purchasingPremium {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                    } else {
                        let premiumPrice = storeKit.products.first(where: { $0.id.contains("premium") && !$0.id.contains("ultra") })?.displayPrice ?? "$9.99"
                        Text(String(format: NSLocalizedString("upgrade.comparison.ctaPremium", comment: ""), premiumPrice + NSLocalizedString("upgrade.comparison.pricePeriod", comment: "")))
                            .fontWeight(.semibold)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
                .background(teal)
                .cornerRadius(14)
            }
            .disabled(purchasingUltra || purchasingPremium)

            if let error = storeKit.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var continueFreeLink: some View {
        Button { onDismiss() } label: {
            HStack(spacing: 3) {
                Text(NSLocalizedString("upgrade.comparison.continueFree", comment: ""))
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }

    // Required by App Store Guideline 3.1.1
    private var restoreLink: some View {
        Button {
            Task { await StoreKitService.shared.restorePurchases() }
        } label: {
            Text(NSLocalizedString("upgrade.comparison.restorePurchases", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // Subscription renewal disclosure required by App Store guidelines
    private var termsText: some View {
        Text(NSLocalizedString("upgrade.comparison.terms", comment: ""))
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }

    // MARK: - Usage summary banner

    private struct UsageItem {
        let icon: String
        let label: String
        let used: Int
        let limit: Int
        var ratio: Double { Double(used) / Double(limit) }
    }

    private var usageSummaryBanner: some View {
        let freeLimits: [(key: String, icon: String, label: String, limit: Int)] = [
            ("homework_single", "📚", NSLocalizedString("upgrade.comparison.usageHomework", comment: ""), 10),
            ("chat_messages",   "💬", NSLocalizedString("upgrade.comparison.usageChat", comment: ""),      50),
            ("questions",       "❓", NSLocalizedString("upgrade.comparison.usagePractice", comment: ""),  30),
        ]

        let items: [UsageItem] = freeLimits.compactMap { entry in
            guard let remaining = usageService.remainingUsage[entry.key] else { return nil }
            let used = max(0, entry.limit - remaining)
            return UsageItem(icon: entry.icon, label: entry.label, used: used, limit: entry.limit)
        }
        .sorted { $0.ratio > $1.ratio }
        .prefix(2)
        .map { $0 }

        guard !items.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 6) {
                Text(NSLocalizedString("upgrade.comparison.yourCurrentUsage", comment: ""))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    ForEach(items, id: \.label) { item in
                        VStack(spacing: 4) {
                            Text("\(item.icon) \(item.label)")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                            Text(String(format: NSLocalizedString("upgrade.comparison.usageUsed", comment: ""), item.used, item.limit))
                                .font(.caption2)
                                .foregroundColor(item.ratio >= 0.8 ? Color(hex: "D97706") : .secondary)
                                .monospacedDigit()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color(.systemFill))
                                        .frame(height: 4)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(item.ratio >= 0.8 ? Color(hex: "D97706") : teal)
                                        .frame(width: geo.size.width * min(1.0, item.ratio), height: 4)
                                }
                            }
                            .frame(height: 4)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemFill), lineWidth: 1)
                )
            }
        )
    }
}
