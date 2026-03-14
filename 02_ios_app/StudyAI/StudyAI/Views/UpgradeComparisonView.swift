//
//  UpgradeComparisonView.swift
//  StudyAI
//

import SwiftUI
import Lottie

struct UpgradeComparisonView: View {

    enum Reason {
        case featureBlocked
        case limitReached
    }

    let blockedFeature: String
    let reason: Reason
    var onDismiss: () -> Void

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

    private let planRows: [PlanRow] = [
        PlanRow(feature: "Homework\nUpload",    free: "10/mo",  premium: "50/mo",   family: "✓"),
        PlanRow(feature: "AI\nChat",           free: "50/mo",  premium: "500/mo",  family: "✓"),
        PlanRow(feature: "Live\nTutor",        free: "—",      premium: "300 min", family: "✓"),
        PlanRow(feature: "Targeted\nPractice", free: "30 qs",  premium: "200 qs",  family: "✓"),
        PlanRow(feature: "Weakness\nAnalysis", free: "5/mo",   premium: "✓",       family: "✓"),
        PlanRow(feature: "Parent\nReports",    free: "✓",      premium: "2/mo",    family: "✓"),
        PlanRow(feature: "Multiple\nKids",     free: "—",      premium: "—",       family: "Up to 3"),
    ]

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
                    upgradeAnimation
                        .padding(.bottom, 2)
                    comparisonTable
                        .padding(.bottom, 20)
                    bottomCTAs
                        .padding(.bottom, 12)
                    continueFreeLink
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
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Upgrade your AI StudyMate")
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            Text("Get unlimited help with an interactive AI tutor.")
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
                badgeStrip("Free to try", icon: "moon.fill",    bg: badgeBlue)
                badgeStrip("Most Popular", icon: "star.fill",   bg: teal)
                badgeStrip("Best Value",   icon: "sun.max.fill", bg: badgeGold)
            }

            // ── Row 2: Plan name + price ────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                // label col header — empty
                Spacer().frame(width: labelW)

                planHeader("Free",         dollars: "0",     period: nil,   accentColor: badgeBlue)
                planHeader("Premium",      dollars: "9.99",  period: "/mo", accentColor: teal)
                planHeader("Ultra",        dollars: "19.99", period: "/mo", accentColor: badgeGold)
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
            Button { onDismiss() } label: {
                Text("Start Ultra")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(badgeGold)
                    .cornerRadius(14)
            }
            Button { onDismiss() } label: {
                Text("Start Premium")
                    .fontWeight(.semibold)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(teal)
                    .cornerRadius(14)
            }
        }
    }

    private var continueFreeLink: some View {
        Button { onDismiss() } label: {
            HStack(spacing: 3) {
                Text("Continue with Free")
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
}
