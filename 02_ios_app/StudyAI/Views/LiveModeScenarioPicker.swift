//
//  LiveModeScenarioPicker.swift
//  StudyAI
//
//  Bottom sheet for selecting a Live Mode scenario.
//  Presented from the Chat tab's ··· menu.
//

import SwiftUI

struct LiveModeScenarioPicker: View {
    @StateObject private var themeManager = ThemeManager.shared
    let onSelect: (LiveModeScenario) -> Void
    @Environment(\.dismiss) private var dismiss

    // 2-column grid
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DesignTokens.Spacing.md) {
                    // Header
                    VStack(spacing: 4) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(DesignTokens.Colors.Cute.blue)
                        Text(NSLocalizedString("live.scenarioPicker.title", value: "选择 Live 场景", comment: ""))
                            .font(.title3.weight(.bold))
                            .foregroundColor(themeManager.primaryText)
                        Text(NSLocalizedString("live.scenarioPicker.subtitle", value: "AI 会引导你完成整个对话", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(themeManager.secondaryText)
                    }
                    .padding(.top, DesignTokens.Spacing.md)

                    // Scenario grid
                    LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.sm) {
                        ForEach(LiveModeScenario.allCases) { scenario in
                            ScenarioCard(scenario: scenario) {
                                dismiss()
                                // Small delay so sheet dismiss animation completes first
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    onSelect(scenario)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.bottom, DesignTokens.Spacing.xl)
                }
            }
            .background(themeManager.backgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Scenario Card

private struct ScenarioCard: View {
    @StateObject private var themeManager = ThemeManager.shared
    let scenario: LiveModeScenario
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(scenario.color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: scenario.icon)
                        .font(.system(size: 20))
                        .foregroundColor(scenario.color)
                }

                Spacer(minLength: 0)

                Text(scenario.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(themeManager.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(scenario.subtitle)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(themeManager.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(scenario.color.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
