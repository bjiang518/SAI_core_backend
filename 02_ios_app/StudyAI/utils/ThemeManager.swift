import SwiftUI
import Combine

// MARK: - Theme Mode Enum

enum ThemeMode: String, CaseIterable, Identifiable {
    case `default` = "default"
    case colorful = "colorful"
    case oceanNight = "oceanNight"
    case forest = "forest"
    case sakura = "sakura"
    case pureDark = "pureDark"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .default:
            return NSLocalizedString("theme.default", comment: "Default mode theme")
        case .colorful:
            return NSLocalizedString("theme.colorful", comment: "Colorful Life theme")
        case .oceanNight:
            return NSLocalizedString("theme.oceanNight", comment: "Ocean Night theme")
        case .forest:
            return NSLocalizedString("theme.forest", comment: "Forest Green theme")
        case .sakura:
            return NSLocalizedString("theme.sakura", comment: "Sakura theme")
        case .pureDark:
            return NSLocalizedString("theme.pureDark", comment: "Pure Dark theme")
        }
    }

    var icon: String {
        switch self {
        case .default:
            return "circle.lefthalf.filled"
        case .colorful:
            return "heart.fill"
        case .oceanNight:
            return "moon.stars.fill"
        case .forest:
            return "leaf.fill"
        case .sakura:
            return "sparkles"
        case .pureDark:
            return "circle.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .default:
            return nil  // Follows system appearance (auto light/dark)
        case .colorful:
            return .light
        case .oceanNight:
            return .dark
        case .forest:
            return .light
        case .sakura:
            return .light
        case .pureDark:
            return .dark
        }
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: ThemeMode {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme")
        }
    }

    /// Override for Default Mode: "auto" | "light" | "dark"
    @Published var defaultModeOverride: String {
        didSet {
            UserDefaults.standard.set(defaultModeOverride, forKey: "defaultModeOverride")
        }
    }

    /// The color scheme actually applied to the app window.
    var effectiveColorScheme: ColorScheme? {
        switch currentTheme {
        case .colorful, .forest, .sakura:
            return .light
        case .oceanNight, .pureDark:
            return .dark
        case .default:
            switch defaultModeOverride {
            case "light": return .light
            case "dark":  return .dark
            default:      return nil  // follows system
            }
        }
    }

    private init() {
        // Load saved theme; migrate old "day"/"night" values to "default"
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme") {
            if let theme = ThemeMode(rawValue: savedTheme) {
                self.currentTheme = theme
            } else if savedTheme == "day" || savedTheme == "night" {
                self.currentTheme = .default
                UserDefaults.standard.set(ThemeMode.default.rawValue, forKey: "selectedTheme")
            } else if savedTheme == "cute" {
                self.currentTheme = .colorful
                UserDefaults.standard.set(ThemeMode.colorful.rawValue, forKey: "selectedTheme")
            } else {
                self.currentTheme = .colorful
            }
        } else {
            self.currentTheme = .colorful
        }

        self.defaultModeOverride = UserDefaults.standard.string(forKey: "defaultModeOverride") ?? "auto"
    }

    func setTheme(_ theme: ThemeMode) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
    }

    // MARK: - Color Getters

    var backgroundColor: Color {
        switch currentTheme {
        case .default:
            return Color(.systemBackground)
        case .colorful:
            return DesignTokens.Colors.Cute.backgroundCream
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.background
        case .forest:
            return DesignTokens.Colors.Forest.background
        case .sakura:
            return DesignTokens.Colors.Sakura.background
        case .pureDark:
            return DesignTokens.Colors.PureDark.background
        }
    }

    var cardBackground: Color {
        switch currentTheme {
        case .default:
            return Color(.secondarySystemBackground)
        case .colorful:
            return DesignTokens.Colors.Cute.mintLight.opacity(0.4)
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.card
        case .forest:
            return DesignTokens.Colors.Forest.card
        case .sakura:
            return DesignTokens.Colors.Sakura.card
        case .pureDark:
            return DesignTokens.Colors.PureDark.card
        }
    }

    var primaryText: Color {
        switch currentTheme {
        case .default:
            return Color.primary
        case .colorful:
            return DesignTokens.Colors.Cute.textPrimary
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.textPrimary
        case .forest:
            return DesignTokens.Colors.Forest.textPrimary
        case .sakura:
            return DesignTokens.Colors.Sakura.textPrimary
        case .pureDark:
            return DesignTokens.Colors.PureDark.textPrimary
        }
    }

    var secondaryText: Color {
        switch currentTheme {
        case .default:
            return Color.secondary
        case .colorful:
            return DesignTokens.Colors.Cute.textSecondary
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.textSecondary
        case .forest:
            return DesignTokens.Colors.Forest.textSecondary
        case .sakura:
            return DesignTokens.Colors.Sakura.textSecondary
        case .pureDark:
            return DesignTokens.Colors.PureDark.textSecondary
        }
    }

    var accentColor: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return DesignTokens.Colors.Cute.mint
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

    var buttonBackground: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return DesignTokens.Colors.Cute.buttonBlack
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent
        case .forest:
            return DesignTokens.Colors.Forest.buttonBg
        case .sakura:
            return DesignTokens.Colors.Sakura.accent
        case .pureDark:
            return DesignTokens.Colors.PureDark.accent
        }
    }

    var buttonText: Color {
        switch currentTheme {
        case .default, .colorful, .forest, .sakura, .pureDark:
            return .white
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.background  // Dark text on teal button
        }
    }

    // MARK: - Greeting Card Background

    var greetingCardBackground: Color {
        switch currentTheme {
        case .default:
            return .clear
        case .colorful:
            return DesignTokens.Colors.Cute.blue
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.greetingCard
        case .forest:
            return DesignTokens.Colors.Forest.greetingCard
        case .sakura:
            return DesignTokens.Colors.Sakura.greetingCard
        case .pureDark:
            return DesignTokens.Colors.PureDark.greetingCard
        }
    }

    // MARK: - Tab Bar Background

    var tabBarBackground: Color {
        switch currentTheme {
        case .default:
            return .clear
        case .colorful:
            return DesignTokens.Colors.Cute.tabBarBackground
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.tabBar
        case .forest:
            return DesignTokens.Colors.Forest.tabBar
        case .sakura:
            return DesignTokens.Colors.Sakura.tabBar
        case .pureDark:
            return DesignTokens.Colors.PureDark.background  // Pure black
        }
    }

    var tabBarItemColor: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return .white
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.textSecondary
        case .forest:
            return DesignTokens.Colors.Forest.tabItemLight
        case .sakura:
            return DesignTokens.Colors.Sakura.tabItemDustyRose
        case .pureDark:
            return DesignTokens.Colors.PureDark.textSecondary
        }
    }

    var tabBarSelectedItemColor: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return .black
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent
        case .forest:
            return .white
        case .sakura:
            return DesignTokens.Colors.Sakura.cherryBlossom
        case .pureDark:
            return DesignTokens.Colors.PureDark.accent
        }
    }

    var tabBarSelectionBoxColor: Color {
        switch currentTheme {
        case .default:
            return .clear
        case .colorful:
            return .white
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent.opacity(0.15)
        case .forest:
            return Color.white.opacity(0.2)
        case .sakura:
            return DesignTokens.Colors.Sakura.cherryBlossom.opacity(0.2)
        case .pureDark:
            return DesignTokens.Colors.PureDark.accent.opacity(0.15)
        }
    }

    // MARK: - Feature Card Colors

    func featureCardColor(_ featureName: String) -> Color {
        switch currentTheme {
        case .default:
            switch featureName {
            case "homework":
                return DesignTokens.Colors.homeworkGraderCoral
            case "chat":
                return DesignTokens.Colors.chatYellow
            case "library":
                return DesignTokens.Colors.libraryPurple
            case "progress":
                return DesignTokens.Colors.progressGreen
            default:
                return DesignTokens.Colors.primary
            }
        case .colorful:
            switch featureName {
            case "homework":
                return DesignTokens.Colors.Cute.peach
            case "chat":
                return DesignTokens.Colors.Cute.yellow
            case "library":
                return DesignTokens.Colors.Cute.lavender
            case "progress":
                return DesignTokens.Colors.Cute.mint
            case "practice":
                return DesignTokens.Colors.Cute.blue
            case "reports":
                return DesignTokens.Colors.Cute.peach
            default:
                return DesignTokens.Colors.Cute.mint
            }
        case .oceanNight:
            switch featureName {
            case "homework":
                return DesignTokens.Colors.OceanNight.homework
            case "chat":
                return DesignTokens.Colors.OceanNight.chat
            case "library":
                return DesignTokens.Colors.OceanNight.library
            case "progress":
                return DesignTokens.Colors.OceanNight.progress
            case "practice":
                return DesignTokens.Colors.OceanNight.practice
            case "reports":
                return DesignTokens.Colors.OceanNight.reports
            default:
                return DesignTokens.Colors.OceanNight.accent
            }
        case .forest:
            switch featureName {
            case "homework":
                return DesignTokens.Colors.Forest.homework
            case "chat":
                return DesignTokens.Colors.Forest.chat
            case "library":
                return DesignTokens.Colors.Forest.library
            case "progress":
                return DesignTokens.Colors.Forest.progress
            case "practice":
                return DesignTokens.Colors.Forest.practice
            case "reports":
                return DesignTokens.Colors.Forest.reports
            default:
                return DesignTokens.Colors.Forest.accent
            }
        case .sakura:
            switch featureName {
            case "homework":
                return DesignTokens.Colors.Sakura.homework
            case "chat":
                return DesignTokens.Colors.Sakura.chat
            case "library":
                return DesignTokens.Colors.Sakura.library
            case "progress":
                return DesignTokens.Colors.Sakura.progress
            case "practice":
                return DesignTokens.Colors.Sakura.practice
            case "reports":
                return DesignTokens.Colors.Sakura.reports
            default:
                return DesignTokens.Colors.Sakura.accent
            }
        case .pureDark:
            switch featureName {
            case "homework":
                return DesignTokens.Colors.PureDark.homework
            case "chat":
                return DesignTokens.Colors.PureDark.chat
            case "library":
                return DesignTokens.Colors.PureDark.library
            case "progress":
                return DesignTokens.Colors.PureDark.progress
            case "practice":
                return DesignTokens.Colors.PureDark.practice
            case "reports":
                return DesignTokens.Colors.PureDark.reports
            default:
                return DesignTokens.Colors.PureDark.accent
            }
        }
    }

    // MARK: - Quick Action Card Styling

    /// Card fill color for QuickActionCard_New (large home screen cards)
    func quickActionCardFill(color: Color, cuteCircleColor: Color, isPressed: Bool, colorScheme: ColorScheme) -> Color {
        switch currentTheme {
        case .colorful:
            return cuteCircleColor.opacity(isPressed ? 0.70 : 0.80)
        case .sakura:
            return Color.white.opacity(isPressed ? 0.85 : 1.0)
        case .oceanNight:
            return Color.white.opacity(isPressed ? 0.85 : 1.0)
        case .pureDark:
            return Color.white.opacity(isPressed ? 0.85 : 1.0)
        case .forest:
            return Color(hex: "FAFAF5")
        case .default:
            return colorScheme == .dark ? Color(white: 0.93) : Color.white
        }
    }

    /// Border overlay for QuickActionCard_New. Returns nil if no border needed.
    func quickActionCardBorder(color: Color, isPressed: Bool) -> (color: Color, width: CGFloat)? {
        switch currentTheme {
        case .colorful, .sakura:
            return nil  // Solid fill, no border
        case .oceanNight:
            return (DesignTokens.Colors.OceanNight.accent.opacity(isPressed ? 0.35 : 0.2), 1.0)
        case .pureDark:
            return (DesignTokens.Colors.PureDark.accent.opacity(isPressed ? 0.5 : 0.3), 1.5)
        case .forest:
            return (color.opacity(isPressed ? 0.5 : 0.35), 1.5)
        case .default:
            return (color.opacity(isPressed ? 0.85 : 0.70), 2.0)
        }
    }

    /// Shadow for QuickActionCard_New
    func quickActionCardShadow(color: Color, isPressed: Bool, colorScheme: ColorScheme) -> (color: Color, radius: CGFloat) {
        switch currentTheme {
        case .colorful:
            return (Color.clear, 0)
        case .sakura:
            return (DesignTokens.Colors.Sakura.accent.opacity(0.08), 6)
        case .oceanNight:
            return (DesignTokens.Colors.OceanNight.accent.opacity(isPressed ? 0.2 : 0.12), 8)
        case .pureDark:
            return (Color.clear, 0)  // OLED: shadows invisible on black
        case .forest:
            return (Color(hex: "8B7355").opacity(isPressed ? 0.15 : 0.08), 6)
        case .default:
            return colorScheme == .dark
                ? (Color.clear, 0)
                : (color.opacity(isPressed ? 0.18 : 0.10), 6)
        }
    }

    // MARK: - Horizontal Action Button Styling

    /// Card fill for HorizontalActionButton (smaller action rows)
    func horizontalCardFill(color: Color, isPressed: Bool, colorScheme: ColorScheme) -> Color {
        switch currentTheme {
        case .colorful:
            return color.opacity(isPressed ? 0.12 : 0.15)
        case .sakura:
            return color.opacity(isPressed ? 0.15 : 0.20)
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.card.opacity(isPressed ? 0.7 : 0.8)
        case .pureDark:
            return isPressed
                ? DesignTokens.Colors.PureDark.card.opacity(0.8)
                : DesignTokens.Colors.PureDark.card
        case .forest:
            return isPressed
                ? color.opacity(0.1)
                : Color(hex: "FAFAF5")
        case .default:
            return isPressed
                ? color.opacity(colorScheme == .dark ? 0.05 : 0.1)
                : (colorScheme == .dark ? DesignTokens.Colors.cardBackground : Color.white)
        }
    }

    /// Border for HorizontalActionButton. Returns nil if no border.
    func horizontalCardBorder(color: Color, isPressed: Bool, colorScheme: ColorScheme) -> (color: Color, width: CGFloat)? {
        switch currentTheme {
        case .colorful, .sakura:
            return nil
        case .oceanNight:
            return (DesignTokens.Colors.OceanNight.accent.opacity(isPressed ? 0.3 : 0.15), 1.0)
        case .pureDark:
            return (DesignTokens.Colors.PureDark.accent.opacity(isPressed ? 0.45 : 0.25), 1.5)
        case .forest:
            return (color.opacity(isPressed ? 0.5 : 0.35), 1.5)
        case .default:
            return (
                isPressed
                    ? color.opacity(colorScheme == .dark ? 0.6 : 0.7)
                    : color.opacity(colorScheme == .dark ? 0.3 : 0.4),
                isPressed ? 2.0 : 1.5
            )
        }
    }

    /// Shadow for HorizontalActionButton
    func horizontalCardShadow(color: Color, isPressed: Bool, colorScheme: ColorScheme) -> (color: Color, radius: CGFloat) {
        switch currentTheme {
        case .colorful:
            return (Color.clear, 0)
        case .sakura:
            return (DesignTokens.Colors.Sakura.accent.opacity(0.06), 4)
        case .oceanNight:
            return (DesignTokens.Colors.OceanNight.accent.opacity(0.08), 4)
        case .pureDark:
            return (Color.clear, 0)
        case .forest:
            return (Color(hex: "8B7355").opacity(isPressed ? 0.12 : 0.06), 4)
        case .default:
            return colorScheme == .dark
                ? (Color.white.opacity(isPressed ? 0.1 : 0.05), isPressed ? 6 : 2)
                : (isPressed ? color.opacity(0.2) : Color.black.opacity(0.03), isPressed ? 6 : 2)
        }
    }

    // MARK: - Icon Circle Styling

    /// Fill color for icon circles inside cards
    func iconCircleFill(color: Color, isPressed: Bool) -> Color {
        switch currentTheme {
        case .colorful:
            return Color.white.opacity(0.3)
        case .sakura:
            return Color.white.opacity(0.4)
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent.opacity(isPressed ? 0.2 : 0.15)
        case .pureDark:
            return DesignTokens.Colors.PureDark.accent.opacity(isPressed ? 0.25 : 0.2)
        case .forest, .default:
            return color.opacity(isPressed ? 0.3 : 0.15)
        }
    }

    /// Icon symbol color inside cards
    func iconSymbolColor(color: Color, isPressed: Bool) -> Color {
        switch currentTheme {
        case .colorful:
            return DesignTokens.Colors.Cute.textPrimary
        case .sakura:
            return DesignTokens.Colors.Sakura.textPrimary
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.textPrimary
        case .pureDark:
            return DesignTokens.Colors.PureDark.textPrimary
        case .forest:
            return isPressed ? color.opacity(0.7) : color
        case .default:
            return isPressed ? color.opacity(0.7) : color
        }
    }

    // MARK: - Card Text Colors

    /// Primary text color for content inside feature cards
    var cardTextPrimary: Color {
        switch currentTheme {
        case .colorful:
            return DesignTokens.Colors.Cute.textPrimary
        case .sakura:
            return DesignTokens.Colors.Sakura.textPrimary
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.textPrimary
        case .pureDark:
            return DesignTokens.Colors.PureDark.textPrimary
        case .forest:
            return DesignTokens.Colors.Forest.textPrimary
        case .default:
            return .primary
        }
    }

    /// Secondary text color for content inside feature cards
    var cardTextSecondary: Color {
        switch currentTheme {
        case .colorful:
            return DesignTokens.Colors.Cute.textSecondary
        case .sakura:
            return DesignTokens.Colors.Sakura.textSecondary
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.textSecondary
        case .pureDark:
            return DesignTokens.Colors.PureDark.textSecondary
        case .forest:
            return DesignTokens.Colors.Forest.textSecondary
        case .default:
            return .secondary
        }
    }

    // MARK: - Custom Tab Bar Properties

    /// Whether to show custom CuteTabBar instead of system tab bar
    var usesCustomTabBar: Bool {
        switch currentTheme {
        case .colorful, .oceanNight, .sakura:
            return true
        case .default, .forest, .pureDark:
            return false
        }
    }

    /// Background color of the custom tab bar shape
    var tabBarShapeColor: Color {
        switch currentTheme {
        case .colorful:
            return Color(red: 0.08, green: 0.08, blue: 0.08)  // Near-black
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.tabBar
        case .sakura:
            return DesignTokens.Colors.Sakura.tabBar
        default:
            return Color(red: 0.08, green: 0.08, blue: 0.08)
        }
    }

    /// Gradient colors for the selected-tab bubble in custom tab bar
    var tabBarBubbleGradient: [Color] {
        switch currentTheme {
        case .colorful:
            return [Color.orange, Color.orange.opacity(0.9)]
        case .oceanNight:
            return [DesignTokens.Colors.OceanNight.accent, DesignTokens.Colors.OceanNight.accent.opacity(0.85)]
        case .sakura:
            return [DesignTokens.Colors.Sakura.cherryBlossom, DesignTokens.Colors.Sakura.accent.opacity(0.8)]
        default:
            return [Color.orange, Color.orange.opacity(0.9)]
        }
    }

    /// Shadow color for the selected-tab bubble
    var tabBarBubbleShadowColor: Color {
        switch currentTheme {
        case .colorful:
            return Color.orange.opacity(0.5)
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent.opacity(0.4)
        case .sakura:
            return DesignTokens.Colors.Sakura.accent.opacity(0.3)
        default:
            return Color.orange.opacity(0.5)
        }
    }

    // MARK: - Notebook / Paper Properties

    /// Background color for torn-notebook paper
    var notebookPaperColor: Color {
        switch currentTheme {
        case .colorful:
            return Color(hex: "FFFFFF")
        case .sakura:
            return Color(hex: "FFF0F5")           // Soft pink paper
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.card
        case .pureDark:
            return DesignTokens.Colors.PureDark.card
        case .forest:
            return Color(hex: "F5F0E0")            // Warm parchment
        case .default:
            return Color(hex: "FAF6EE")            // Default light is cream; dark handled by colorScheme
        }
    }

    /// Notebook paper color for dark mode (only used by .default theme)
    var notebookPaperColorDark: Color {
        return Color(hex: "27251F")
    }

    /// Grid line color on notebook paper
    var notebookGridLineColor: Color {
        switch currentTheme {
        case .colorful:
            return Color(hex: "B8C4C0").opacity(0.3)  // Very subtle
        case .sakura:
            return Color(hex: "E8C4D4").opacity(0.4)   // Soft pink grid
        case .oceanNight:
            return DesignTokens.Colors.OceanNight.accent.opacity(0.15)
        case .pureDark:
            return Color(hex: "3A3A3E").opacity(0.5)
        case .forest:
            return Color(hex: "8BB08B").opacity(0.3)    // Warm green grid
        case .default:
            return Color(hex: "B8C4C0").opacity(0.55)   // Default light; dark handled separately
        }
    }

    /// Whether to draw grid lines on notebook paper
    var showsNotebookGridLines: Bool {
        switch currentTheme {
        case .colorful:
            return false  // Keep original behavior: white paper, no grid in Colorful
        case .default, .oceanNight, .forest, .sakura, .pureDark:
            return true
        }
    }
}

// MARK: - Theme Environment Key

struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeManager.shared
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
