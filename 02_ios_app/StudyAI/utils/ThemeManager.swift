import SwiftUI
import Combine

// MARK: - Theme Mode Enum

enum ThemeMode: String, CaseIterable, Identifiable {
    case `default` = "default"
    case colorful = "colorful"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .default:
            return NSLocalizedString("theme.default", comment: "Default mode theme")
        case .colorful:
            return NSLocalizedString("theme.colorful", comment: "Colorful Life theme")
        }
    }

    var icon: String {
        switch self {
        case .default:
            return "circle.lefthalf.filled"
        case .colorful:
            return "heart.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .default:
            return nil  // Follows system appearance (auto light/dark)
        case .colorful:
            return .light // Colorful Life uses light scheme with pastel colors
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
        case .colorful:
            return .light
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
        }
    }

    var cardBackground: Color {
        switch currentTheme {
        case .default:
            return Color(.secondarySystemBackground)
        case .colorful:
            return DesignTokens.Colors.Cute.mintLight.opacity(0.4)
        }
    }

    var primaryText: Color {
        switch currentTheme {
        case .default:
            return Color.primary
        case .colorful:
            return DesignTokens.Colors.Cute.textPrimary
        }
    }

    var secondaryText: Color {
        switch currentTheme {
        case .default:
            return Color.secondary
        case .colorful:
            return DesignTokens.Colors.Cute.textSecondary
        }
    }

    var accentColor: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return DesignTokens.Colors.Cute.mint
        }
    }

    var buttonBackground: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return DesignTokens.Colors.Cute.buttonBlack
        }
    }

    var buttonText: Color {
        switch currentTheme {
        case .default, .colorful:
            return .white
        }
    }

    // MARK: - Greeting Card Background

    var greetingCardBackground: Color {
        switch currentTheme {
        case .default:
            return .clear  // Use gradient in Default mode
        case .colorful:
            return DesignTokens.Colors.Cute.blue  // Solid blue in Colorful Life
        }
    }

    // MARK: - Tab Bar Background

    var tabBarBackground: Color {
        switch currentTheme {
        case .default:
            return .clear  // Use system default
        case .colorful:
            return DesignTokens.Colors.Cute.tabBarBackground  // Black in Colorful Life
        }
    }

    var tabBarItemColor: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return .white  // White icons on black tab bar
        }
    }

    var tabBarSelectedItemColor: Color {
        switch currentTheme {
        case .default:
            return DesignTokens.Colors.primary
        case .colorful:
            return .black  // Black icon when selected (on white selection box)
        }
    }

    var tabBarSelectionBoxColor: Color {
        switch currentTheme {
        case .default:
            return .clear
        case .colorful:
            return .white  // White selection box in Colorful Life
        }
    }

    // MARK: - Feature Card Colors

    func featureCardColor(_ featureName: String) -> Color {
        switch currentTheme {
        case .default:
            // Use existing feature colors
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
            // Use colorful pastel colors
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
