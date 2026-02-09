import SwiftUI
import Combine

// MARK: - Theme Mode Enum

enum ThemeMode: String, CaseIterable, Identifiable {
    case day = "day"
    case night = "night"
    case cute = "cute"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .day:
            return NSLocalizedString("theme.day", comment: "Day mode theme")
        case .night:
            return NSLocalizedString("theme.night", comment: "Night mode theme")
        case .cute:
            return NSLocalizedString("theme.cute", comment: "Cute mode theme")
        }
    }

    var icon: String {
        switch self {
        case .day:
            return "sun.max.fill"
        case .night:
            return "moon.stars.fill"
        case .cute:
            return "heart.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .day:
            return .light
        case .night:
            return .dark
        case .cute:
            return .light // Cute mode uses light scheme with pastel colors
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

    private init() {
        // Load saved theme or default to day mode
        if let savedTheme = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = ThemeMode(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .day
        }
    }

    func setTheme(_ theme: ThemeMode) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
    }

    // MARK: - Color Getters

    var backgroundColor: Color {
        switch currentTheme {
        case .day:
            return Color(.systemBackground)
        case .night:
            return Color(.systemBackground)
        case .cute:
            return DesignTokens.Colors.Cute.backgroundCream
        }
    }

    var cardBackground: Color {
        switch currentTheme {
        case .day, .night:
            return Color(.secondarySystemBackground)
        case .cute:
            return DesignTokens.Colors.Cute.backgroundSoftPink
        }
    }

    var primaryText: Color {
        switch currentTheme {
        case .day, .night:
            return Color.primary
        case .cute:
            return DesignTokens.Colors.Cute.textPrimary
        }
    }

    var secondaryText: Color {
        switch currentTheme {
        case .day, .night:
            return Color.secondary
        case .cute:
            return DesignTokens.Colors.Cute.textSecondary
        }
    }

    var accentColor: Color {
        switch currentTheme {
        case .day, .night:
            return DesignTokens.Colors.primary
        case .cute:
            return DesignTokens.Colors.Cute.pink
        }
    }

    var buttonBackground: Color {
        switch currentTheme {
        case .day:
            return DesignTokens.Colors.primary
        case .night:
            return DesignTokens.Colors.primary
        case .cute:
            return DesignTokens.Colors.Cute.buttonBlack
        }
    }

    var buttonText: Color {
        switch currentTheme {
        case .day, .night, .cute:
            return .white
        }
    }

    // MARK: - Greeting Card Background

    var greetingCardBackground: Color {
        switch currentTheme {
        case .day, .night:
            return .clear  // Use gradient in Day/Night mode
        case .cute:
            return DesignTokens.Colors.Cute.blue  // Solid blue in Cute mode
        }
    }

    // MARK: - Tab Bar Background

    var tabBarBackground: Color {
        switch currentTheme {
        case .day, .night:
            return .clear  // Use system default
        case .cute:
            return DesignTokens.Colors.Cute.tabBarBackground  // Black in Cute mode
        }
    }

    var tabBarItemColor: Color {
        switch currentTheme {
        case .day, .night:
            return DesignTokens.Colors.primary
        case .cute:
            return .white  // White icons on black tab bar
        }
    }

    var tabBarSelectedItemColor: Color {
        switch currentTheme {
        case .day, .night:
            return DesignTokens.Colors.primary
        case .cute:
            return .black  // Black icon when selected (on white selection box)
        }
    }

    var tabBarSelectionBoxColor: Color {
        switch currentTheme {
        case .day, .night:
            return .clear
        case .cute:
            return .white  // White selection box in Cute mode
        }
    }

    // MARK: - Feature Card Colors

    func featureCardColor(_ featureName: String) -> Color {
        switch currentTheme {
        case .day, .night:
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
        case .cute:
            // Use cute mode pastel colors
            switch featureName {
            case "homework":
                return DesignTokens.Colors.Cute.pink
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
                return DesignTokens.Colors.Cute.pink
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
