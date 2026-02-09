import SwiftUI

struct ThemeSelectionView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
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
    }

    private var iconBackgroundColor: Color {
        switch mode {
        case .day:
            return Color.yellow.opacity(0.2)
        case .night:
            return Color.indigo.opacity(0.2)
        case .cute:
            return DesignTokens.Colors.Cute.pink.opacity(0.2)
        }
    }

    private var iconColor: Color {
        switch mode {
        case .day:
            return Color.orange
        case .night:
            return Color.indigo
        case .cute:
            return DesignTokens.Colors.Cute.pink
        }
    }

    private var cardBackground: Color {
        if mode == .cute && isSelected {
            return DesignTokens.Colors.Cute.backgroundSoftPink
        }
        return themeManager.cardBackground
    }

    private var descriptionKey: String {
        switch mode {
        case .day:
            return NSLocalizedString("theme.description.day", comment: "")
        case .night:
            return NSLocalizedString("theme.description.night", comment: "")
        case .cute:
            return NSLocalizedString("theme.description.cute", comment: "")
        }
    }
}

// MARK: - Preview

struct ThemeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ThemeSelectionView()
    }
}
