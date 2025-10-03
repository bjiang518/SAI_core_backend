import SwiftUI

// MARK: - Design Tokens

struct DesignTokens {
    
    // MARK: - Colors
    struct Colors {
        // Primary Colors - Refined Palette
        static let primary = Color(hex: "3B82F6") // Blue - AI features
        static let primaryVariant = Color(hex: "2563EB") // Darker blue

        // Feature Colors
        static let aiBlue = Color(hex: "3B82F6") // AI/Chat features
        static let learningGreen = Color(hex: "10B981") // Learning/Growth
        static let analyticsPlum = Color(hex: "8B5CF6") // Analytics/Progress
        static let reviewOrange = Color(hex: "F59E0B") // Review/Alerts
        static let libraryTeal = Color(hex: "14B8A6") // Library/Archive

        // Secondary Colors
        static let secondary = Color("Secondary", bundle: .main) ?? Color.gray
        static let secondaryVariant = Color("SecondaryVariant", bundle: .main) ?? Color.gray.opacity(0.6)

        // Surface Colors
        static let surface = Color(hex: "F8FAFC") // Light background
        static let surfaceVariant = Color("SurfaceVariant", bundle: .main) ?? Color(.secondarySystemBackground)
        static let cardBackground = Color.white

        // Text Colors
        static let onSurface = Color("OnSurface", bundle: .main) ?? Color.primary
        static let onSurfaceVariant = Color("OnSurfaceVariant", bundle: .main) ?? Color.secondary
        static let textSecondary = Color.primary.opacity(0.7)

        // Status Colors
        static let success = Color(hex: "10B981")
        static let warning = Color(hex: "F59E0B")
        static let error = Color(hex: "EF4444")
        static let info = Color(hex: "3B82F6")

        // Archive-specific Colors
        static let archived = Color("Archived", bundle: .main) ?? Color.orange
        static let unarchived = Color("Unarchived", bundle: .main) ?? Color.green

        // Conversation Colors
        static let conversationBackground = Color("ConversationBackground", bundle: .main) ?? Color.white
        static let conversationBorder = Color("ConversationBorder", bundle: .main) ?? Color.gray.opacity(0.2)

        // Filter Colors
        static let filterActive = Color("FilterActive", bundle: .main) ?? Color.blue.opacity(0.1)
        static let filterInactive = Color("FilterInactive", bundle: .main) ?? Color(.systemGray6)

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
        static let archive = "archivebox"
        static let unarchive = "archivebox.fill"
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