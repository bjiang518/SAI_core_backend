//
//  UpgradeComparisonView.swift
//  StudyAI
//

import SwiftUI

struct UpgradeComparisonView: View {

    enum Reason {
        case featureBlocked
        case limitReached
    }

    let blockedFeature: String
    let reason: Reason
    var onDismiss: () -> Void

    @StateObject private var themeManager = ThemeManager.shared

    // MARK: - Feature table data

    private struct FeatureRow {
        let icon: String
        let name: String
        let featureKey: String   // matches blockedFeature
        let freeValue: String
        let premiumValue: String
        let premiumPlusValue: String
    }

    private let rows: [FeatureRow] = [
        FeatureRow(icon: "camera.fill",      name: "Homework Analysis",   featureKey: "homework_single",  freeValue: "10/mo",    premiumValue: "50/mo",     premiumPlusValue: "∞"),
        FeatureRow(icon: "doc.on.doc.fill",  name: "Batch Homework",      featureKey: "homework_batch",   freeValue: "—",        premiumValue: "20/mo",     premiumPlusValue: "∞"),
        FeatureRow(icon: "message.fill",     name: "AI Chat Messages",    featureKey: "chat_messages",    freeValue: "50/mo",    premiumValue: "500/mo",    premiumPlusValue: "∞"),
        FeatureRow(icon: "checkmark.square", name: "Practice Questions",  featureKey: "questions",        freeValue: "30/mo",    premiumValue: "200/mo",    premiumPlusValue: "∞"),
        FeatureRow(icon: "magnifyingglass",  name: "Error Analysis",      featureKey: "error_analysis",   freeValue: "5/mo",     premiumValue: "∞",         premiumPlusValue: "∞"),
        FeatureRow(icon: "chart.bar.fill",   name: "Parent Reports",      featureKey: "reports",          freeValue: "—",        premiumValue: "2/mo",      premiumPlusValue: "∞"),
        FeatureRow(icon: "waveform",         name: "Voice Chat",          featureKey: "voice_minutes",    freeValue: "—",        premiumValue: "300 min",   premiumPlusValue: "∞"),
        FeatureRow(icon: "books.vertical",   name: "Archive Practice",    featureKey: "",                 freeValue: "—",        premiumValue: "✓",         premiumPlusValue: "✓"),
    ]

    // MARK: - Computed helpers

    private var featureDisplayName: String {
        rows.first(where: { $0.featureKey == blockedFeature })?.name ?? "This Feature"
    }

    private var headerIcon: String {
        switch reason {
        case .featureBlocked: return "lock.circle.fill"
        case .limitReached:   return "chart.bar.fill"
        }
    }

    private var titleText: String {
        switch reason {
        case .featureBlocked: return "Unlock \(featureDisplayName)"
        case .limitReached:   return "You've hit your limit"
        }
    }

    private var subtitleText: String {
        switch reason {
        case .featureBlocked: return "This feature requires Premium. Upgrade to unlock it."
        case .limitReached:   return "Upgrade to continue using \(featureDisplayName)."
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: headerIcon)
                        .font(.system(size: 48))
                        .foregroundColor(themeManager.accentColor)

                    Text(titleText)
                        .font(.title2.bold())
                        .foregroundColor(themeManager.primaryText)
                        .multilineTextAlignment(.center)

                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundColor(themeManager.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 24)
                .padding(.bottom, 16)

                // Comparison table
                ScrollView {
                    VStack(spacing: 0) {
                        // Column headers
                        comparisonHeaderRow()
                            .padding(.bottom, 4)

                        // Pricing row
                        pricingRow()

                        Divider().padding(.horizontal, 16)

                        // Feature rows
                        ForEach(rows, id: \.name) { row in
                            featureRow(row)
                            if row.name != rows.last?.name {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(themeManager.cardBackground)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }

                // CTA buttons
                VStack(spacing: 10) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Upgrade to Premium")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(themeManager.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Text("Upgrade to Premium+")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.clear)
                            .foregroundColor(themeManager.accentColor)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(themeManager.accentColor, lineWidth: 1.5)
                            )
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Text("Continue with Free")
                            .font(.subheadline)
                            .foregroundColor(themeManager.secondaryText)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .background(themeManager.backgroundColor.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.dismiss", comment: "")) {
                        onDismiss()
                    }
                    .foregroundColor(themeManager.secondaryText)
                }
            }
        }
    }

    // MARK: - Table subviews

    @ViewBuilder
    private func comparisonHeaderRow() -> some View {
        HStack(spacing: 0) {
            Text("Feature")
                .font(.caption.bold())
                .foregroundColor(themeManager.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            columnHeader("Free")
            columnHeader("Premium")
            columnHeader("Plus")
        }
        .padding(.vertical, 10)
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private func columnHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundColor(themeManager.secondaryText)
            .frame(width: 66, alignment: .center)
    }

    @ViewBuilder
    private func pricingRow() -> some View {
        HStack(spacing: 0) {
            Text("Price")
                .font(.caption)
                .foregroundColor(themeManager.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            pricingCell("$0")
            pricingCell("$4.99")
            pricingCell("$9.99")
        }
        .padding(.vertical, 10)
        .padding(.trailing, 8)
    }

    @ViewBuilder
    private func pricingCell(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(themeManager.secondaryText)
            .frame(width: 66, alignment: .center)
    }

    @ViewBuilder
    private func featureRow(_ row: FeatureRow) -> some View {
        let isHighlighted = row.featureKey == blockedFeature && !blockedFeature.isEmpty
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: row.icon)
                    .font(.caption)
                    .foregroundColor(isHighlighted ? themeManager.accentColor : themeManager.secondaryText)
                    .frame(width: 16)
                Text(row.name)
                    .font(.caption)
                    .foregroundColor(isHighlighted ? themeManager.accentColor : themeManager.primaryText)
                    .fontWeight(isHighlighted ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 16)

            valueCell(row.freeValue, highlighted: isHighlighted)
            valueCell(row.premiumValue, highlighted: isHighlighted)
            valueCell(row.premiumPlusValue, highlighted: isHighlighted)
        }
        .padding(.vertical, 10)
        .padding(.trailing, 8)
        .background(isHighlighted ? themeManager.accentColor.opacity(0.08) : Color.clear)
    }

    @ViewBuilder
    private func valueCell(_ text: String, highlighted: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(text == "—" ? themeManager.secondaryText.opacity(0.5) : (highlighted ? themeManager.accentColor : themeManager.primaryText))
            .frame(width: 66, alignment: .center)
    }
}
