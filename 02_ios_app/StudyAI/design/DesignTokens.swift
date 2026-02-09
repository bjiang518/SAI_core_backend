import SwiftUI

// MARK: - Design Tokens

struct DesignTokens {
    
    // MARK: - Colors
    struct Colors {
        // Primary Colors - Refined Palette
        static let primary = Color(hex: "3B82F6") // Blue - AI features
        static let primaryVariant = Color(hex: "2563EB") // Darker blue

        // Feature Colors - Harmonious Palette for Main Cards
        static let homeworkGraderCoral = Color(hex: "FF6B6B") // Homework Grader - Vibrant Coral Red
        static let chatYellow = Color(hex: "FFD93D") // Chat - Bright Yellow
        static let libraryPurple = Color(hex: "A78BFA") // Library - Soft Purple
        static let progressGreen = Color(hex: "51CF66") // Progress - Fresh Green

        // Legacy Feature Colors (kept for compatibility)
        static let aiBlue = Color(hex: "3B82F6") // AI/Chat features
        static let learningGreen = Color(hex: "10B981") // Learning/Growth
        static let analyticsPlum = Color(hex: "8B5CF6") // Analytics/Progress
        static let reviewOrange = Color(hex: "F59E0B") // Review/Alerts
        static let libraryTeal = Color(hex: "14B8A6") // Library/Archive

        // Secondary Colors
        static let secondary = Color("Secondary", bundle: .main)
        static let secondaryVariant = Color("SecondaryVariant", bundle: .main)

        // Surface Colors - Now Adaptive to Dark Mode
        static let surface = Color(.systemBackground) // Adapts to light/dark mode
        static let surfaceVariant = Color(.secondarySystemBackground) // Adapts to light/dark mode
        static let cardBackground = Color(.secondarySystemBackground) // Adapts to light/dark mode

        // Text Colors
        static let onSurface = Color("OnSurface", bundle: .main)
        static let onSurfaceVariant = Color("OnSurfaceVariant", bundle: .main)
        static let textSecondary = Color.primary.opacity(0.7)

        // Status Colors
        static let success = Color(hex: "10B981")
        static let warning = Color(hex: "F59E0B")
        static let error = Color(hex: "EF4444")
        static let info = Color(hex: "3B82F6")

        // Archive-specific Colors
        static let archived = Color("Archived", bundle: .main)
        static let unarchived = Color("Unarchived", bundle: .main)

        // Conversation Colors
        static let conversationBackground = Color("ConversationBackground", bundle: .main)
        static let conversationBorder = Color("ConversationBorder", bundle: .main)

        // Filter Colors
        static let filterActive = Color("FilterActive", bundle: .main)
        static let filterInactive = Color("FilterInactive", bundle: .main)

        // Gradient Colors
        static let gradientBlue = LinearGradient(
            colors: [Color(hex: "3B82F6"), Color(hex: "60A5FA")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let gradientGreen = LinearGradient(
            colors: [Color(hex: "10B981"), Color(hex: "34D399")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let gradientPurple = LinearGradient(
            colors: [Color(hex: "8B5CF6"), Color(hex: "A78BFA")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // MARK: - Adaptive Rainbow Colors for Cards
        // These colors automatically adjust saturation and brightness for dark mode

        // Rainbow Cards - Adaptive Colors (use in views with colorScheme environment)
        // Light mode: Bright, vibrant, high saturation
        // Dark mode: Muted, darker tones
        struct rainbowRed {
            static let light = Color(red: 1.0, green: 0.3, blue: 0.3)      // Bright vibrant red
            static let dark = Color(red: 0.7, green: 0.25, blue: 0.25)     // Darker muted red
        }

        struct rainbowOrange {
            static let light = Color(red: 1.0, green: 0.65, blue: 0.1)     // Bright vibrant orange
            static let dark = Color(red: 0.85, green: 0.5, blue: 0.2)      // Darker muted orange
        }

        struct rainbowYellow {
            static let light = Color(red: 1.0, green: 0.85, blue: 0.0)     // Bright vibrant yellow
            static let dark = Color(red: 0.75, green: 0.65, blue: 0.2)     // Darker muted yellow
        }

        struct rainbowGreen {
            static let light = Color(red: 0.3, green: 0.85, blue: 0.3)     // Bright vibrant green
            static let dark = Color(red: 0.25, green: 0.65, blue: 0.25)    // Darker muted green
        }

        struct rainbowBlue {
            static let light = Color(red: 0.3, green: 0.6, blue: 1.0)      // Bright vibrant blue
            static let dark = Color(red: 0.25, green: 0.45, blue: 0.85)    // Darker muted blue
        }

        struct rainbowIndigo {
            static let light = Color(red: 0.5, green: 0.3, blue: 0.9)      // Bright vibrant indigo
            static let dark = Color(red: 0.35, green: 0.2, blue: 0.6)      // Darker muted indigo
        }

        struct rainbowViolet {
            static let light = Color(red: 0.7, green: 0.3, blue: 0.95)     // Bright vibrant violet
            static let dark = Color(red: 0.55, green: 0.25, blue: 0.7)     // Darker muted violet
        }

        struct rainbowPink {
            static let light = Color(red: 1.0, green: 0.45, blue: 0.75)    // Bright vibrant pink
            static let dark = Color(red: 0.85, green: 0.4, blue: 0.65)     // Darker muted pink
        }

        // MARK: - Cute Mode Colors (Solid & Vivid - Routio Style)
        struct Cute {
            // Solid Vivid Pastel Colors (more saturated than before)
            static let pink = Color(hex: "FF85C1")           // Vivid Pink (was FFB3D9)
            static let pinkLight = Color(hex: "FFB3D9")      // Light variant
            static let blue = Color(hex: "7EC8E3")           // Vivid Blue (was A8D8EA)
            static let blueLight = Color(hex: "A8D8EA")      // Light variant
            static let yellow = Color(hex: "FFE066")         // Vivid Yellow (was FFF4A3)
            static let yellowLight = Color(hex: "FFF4A3")    // Light variant
            static let mint = Color(hex: "7FDBCA")           // Vivid Mint (was B8E6D5)
            static let mintLight = Color(hex: "B8E6D5")      // Light variant
            static let lavender = Color(hex: "C9A0DC")       // Vivid Lavender (was E1D4F5)
            static let lavenderLight = Color(hex: "E1D4F5")  // Light variant
            static let peach = Color(hex: "FFB6A3")          // Vivid Peach (was FFD6BA)
            static let peachLight = Color(hex: "FFD6BA")     // Light variant

            // Background Colors
            static let backgroundCream = Color(hex: "FFF8F0")      // Cream background
            static let backgroundSoftPink = Color(hex: "FFF0F5")   // Soft pink background

            // Contrast Elements
            static let buttonBlack = Color(hex: "000000")          // Black for buttons/cards
            static let textOnBlack = Color(hex: "FFFFFF")          // White text on black
            static let softBlack = Color(hex: "2D2D2D")            // Soft black alternative

            // Tab Bar
            static let tabBarBackground = Color(hex: "000000")     // Black tab bar background

            // Text Colors for Cute Mode
            static let textPrimary = Color(hex: "2D2D2D")          // Soft black for readability
            static let textSecondary = Color(hex: "666666")        // Gray for secondary text
        }
    }

    // MARK: - Adaptive Colors for Dark Mode Support
    struct AdaptiveColors {
        // Text Colors
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let tertiaryText = Color(.tertiaryLabel)

        // Background Colors
        static let cardBackground = Color(.secondarySystemBackground)
        static let cardBackgroundElevated = Color(.tertiarySystemBackground)
        static let groupedBackground = Color(.systemGroupedBackground)
        static let secondaryGroupedBackground = Color(.secondarySystemGroupedBackground)

        // Performance Summary Gradient (adaptive to dark mode)
        static func performanceGradient(colorScheme: ColorScheme) -> LinearGradient {
            if colorScheme == .dark {
                return LinearGradient(
                    colors: [
                        Color(red: 0.2, green: 0.3, blue: 0.5),   // Dark blue
                        Color(red: 0.3, green: 0.2, blue: 0.4)    // Dark purple
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.6, blue: 0.95),  // Bright blue
                        Color(red: 0.6, green: 0.4, blue: 0.9)    // Bright purple
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }

        // Shimmer Overlay (adaptive)
        static func shimmerOverlay(colorScheme: ColorScheme) -> some View {
            if colorScheme == .dark {
                return LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                return LinearGradient(
                    colors: [
                        Color.white.opacity(0.2),
                        Color.white.opacity(0.4),
                        Color.white.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }

        // Summary Background (adaptive)
        static func summaryBackground(colorScheme: ColorScheme) -> Color {
            if colorScheme == .dark {
                return Color(.systemGray6)
            } else {
                return Color(.systemGray6)
            }
        }

        // Selection Background (adaptive)
        static func selectionBackground(colorScheme: ColorScheme) -> Color {
            if colorScheme == .dark {
                return Color.blue.opacity(0.2)
            } else {
                return Color.blue.opacity(0.1)
            }
        }

        // Border Color (adaptive)
        static func border(colorScheme: ColorScheme) -> Color {
            if colorScheme == .dark {
                return Color(.systemGray4)
            } else {
                return Color(.systemGray5)
            }
        }
    }

    // MARK: - Typography
    struct Typography {
        // Headings - Refined sizes
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title1 = Font.system(size: 24, weight: .bold, design: .rounded)
        static let title2 = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let title3 = Font.system(size: 17, weight: .semibold, design: .rounded)

        // Body Text
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyEmphasized = Font.system(size: 17, weight: .medium, design: .default)
        static let bodySecondary = Font.system(size: 15, weight: .regular, design: .default)

        // Labels and Captions
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption1 = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)

        // Conversation-specific Typography
        static let conversationTitle = Font.system(size: 17, weight: .medium, design: .default)
        static let conversationMessage = Font.system(size: 15, weight: .regular, design: .default)
        static let conversationDate = Font.system(size: 12, weight: .regular, design: .default)
        static let conversationTag = Font.system(size: 11, weight: .medium, design: .default)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32

        // Component-specific spacing
        static let cardPadding: CGFloat = 16
        static let cardSpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 24
        static let listItemVertical: CGFloat = 12
        static let listItemHorizontal: CGFloat = 20
        static let filterSpacing: CGFloat = 16
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let pill: CGFloat = 999
        
        // Component-specific radius
        static let card: CGFloat = 12
        static let button: CGFloat = 10
        static let searchField: CGFloat = 10
        static let tag: CGFloat = 8
    }
    
    // MARK: - Shadows
    struct Shadows {
        static let light = Shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        static let medium = Shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        static let heavy = Shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        
        // Component-specific shadows
        static let card = Shadow(color: .gray.opacity(0.1), radius: 3, x: 0, y: 2)
        static let button = Shadow(color: .blue.opacity(0.2), radius: 5, x: 0, y: 3)
    }
    
    // MARK: - Icons
    struct Icons {
        // Navigation
        static let history = "clock.arrow.circlepath"
        static let archive = "books.vertical.fill"
        static let unarchive = "books.vertical.fill"
        static let search = "magnifyingglass"
        static let filter = "line.3.horizontal.decrease.circle"
        static let calendar = "calendar"
        static let clear = "xmark.circle.fill"
        
        // Actions
        static let delete = "trash"
        static let edit = "pencil"
        static let share = "square.and.arrow.up"
        
        // Status
        static let success = "checkmark.circle.fill"
        static let warning = "exclamationmark.triangle.fill"
        static let error = "xmark.circle.fill"
        static let info = "info.circle.fill"
        
        // Content
        static let conversation = "bubble.left.and.bubble.right"
        static let participants = "person.2.fill"
        static let tags = "tag.fill"
        static let date = "calendar.badge.clock"
    }
}

// MARK: - Shadow Helper

struct Shadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - Date Formatter Extension

extension DateFormatter {
    static let accessibilityFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}