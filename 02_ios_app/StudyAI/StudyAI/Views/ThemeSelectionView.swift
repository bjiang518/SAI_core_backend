import SwiftUI

struct ThemeSelectionView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 50))
                            .foregroundColor(themeManager.accentColor)

                        Text(NSLocalizedString("theme.title", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                    .padding(.top, 20)

                    // Theme Options
                    VStack(spacing: 16) {
                        ForEach(ThemeMode.allCases) { mode in
                            ThemeCard(
                                mode: mode,
                                isSelected: themeManager.currentTheme == mode,
                                action: {
                                    themeManager.setTheme(mode)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
            }
            .background(themeManager.backgroundColor.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                    .foregroundColor(themeManager.accentColor)
                }
            }
        }
    }
}

// MARK: - Theme Card

struct ThemeCard: View {
    let mode: ThemeMode
    let isSelected: Bool
    let action: () -> Void

    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Theme Icon
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 60, height: 60)

                    Image(systemName: mode.icon)
                        .font(.system(size: 28))
                        .foregroundColor(iconColor)
                }

                // Theme Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundColor(themeManager.primaryText)

                    Text(descriptionKey)
                        .font(.subheadline)
                        .foregroundColor(themeManager.secondaryText)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(themeManager.accentColor)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? themeManager.accentColor : Color.clear,
                                lineWidth: 2
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())

        // Appearance override picker — shown below the card when Default Mode is selected
        if mode == .default && isSelected {
            AppearanceOverridePicker()
                .padding(.horizontal, 16)
                .padding(.top, -8)
        }
    }

    private var iconBackgroundColor: Color {
        switch mode {
        case .default:
            return Color.blue.opacity(0.15)
        case .colorful:
            return DesignTokens.Colors.Cute.pink.opacity(0.2)
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent.opacity(0.2)
        case .forest:
            return DesignTokens.Colors.Forest.accent.opacity(0.2)
        case .sakura:
            return DesignTokens.Colors.Sakura.accent.opacity(0.2)
        case .pureDark:
            return DesignTokens.Colors.PureDark.accent.opacity(0.2)
        }
    }

    private var iconColor: Color {
        switch mode {
        case .default:
            return Color.blue
        case .colorful:
            return DesignTokens.Colors.Cute.pink
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent
        case .forest:
            return DesignTokens.Colors.Forest.accent
        case .sakura:
            return DesignTokens.Colors.Sakura.accent
        case .pureDark:
            return DesignTokens.Colors.PureDark.accent
        }
    }

    private var cardBackground: Color {
        if isSelected {
            switch mode {
            case .colorful:
                return DesignTokens.Colors.Cute.backgroundSoftPink
            case .oceanNight:
                return DesignTokens.Colors.OceanNight.card
            case .forest:
                return DesignTokens.Colors.Forest.card
            case .sakura:
                return DesignTokens.Colors.Sakura.card
            case .pureDark:
                return DesignTokens.Colors.PureDark.card
            case .default:
                return themeManager.cardBackground
            }
        }
        return themeManager.cardBackground
    }

    private var descriptionKey: String {
        switch mode {
        case .default:
            return NSLocalizedString("theme.description.default", comment: "")
        case .colorful:
            return NSLocalizedString("theme.description.colorful", comment: "")
        case .oceanNight:
            return NSLocalizedString("theme.description.oceanNight", comment: "")
        case .forest:
            return NSLocalizedString("theme.description.forest", comment: "")
        case .sakura:
            return NSLocalizedString("theme.description.sakura", comment: "")
        case .pureDark:
            return NSLocalizedString("theme.description.pureDark", comment: "")
        }
    }
}

// MARK: - Appearance Override Picker

struct AppearanceOverridePicker: View {
    @StateObject private var themeManager = ThemeManager.shared

    private let options: [(label: String, value: String, icon: String)] = [
        (NSLocalizedString("theme.override.auto",  comment: ""), "auto",  "circle.lefthalf.filled"),
        (NSLocalizedString("theme.override.light", comment: ""), "light", "sun.max.fill"),
        (NSLocalizedString("theme.override.dark",  comment: ""), "dark",  "moon.stars.fill"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        themeManager.defaultModeOverride = option.value
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.system(size: 13, weight: .medium))
                        Text(option.label)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(themeManager.defaultModeOverride == option.value
                                  ? themeManager.accentColor.opacity(0.15)
                                  : Color.clear)
                    )
                    .foregroundColor(themeManager.defaultModeOverride == option.value
                                     ? themeManager.accentColor
                                     : themeManager.secondaryText)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(themeManager.accentColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

struct ThemeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ThemeSelectionView()
    }
}
