import SwiftUI

// MARK: - Design Tokens

struct DesignTokens {
    
    // MARK: - Colors
    struct Colors {
        // Primary Colors
        static let primary = Color("Primary", bundle: .main) ?? Color.blue
        static let primaryVariant = Color("PrimaryVariant", bundle: .main) ?? Color.blue.opacity(0.8)
        
        // Secondary Colors  
        static let secondary = Color("Secondary", bundle: .main) ?? Color.gray
        static let secondaryVariant = Color("SecondaryVariant", bundle: .main) ?? Color.gray.opacity(0.6)
        
        // Surface Colors
        static let surface = Color("Surface", bundle: .main) ?? Color(.systemBackground)
        static let surfaceVariant = Color("SurfaceVariant", bundle: .main) ?? Color(.secondarySystemBackground)
        
        // Text Colors
        static let onSurface = Color("OnSurface", bundle: .main) ?? Color.primary
        static let onSurfaceVariant = Color("OnSurfaceVariant", bundle: .main) ?? Color.secondary
        
        // Status Colors
        static let success = Color("Success", bundle: .main) ?? Color.green
        static let warning = Color("Warning", bundle: .main) ?? Color.orange  
        static let error = Color("Error", bundle: .main) ?? Color.red
        static let info = Color("Info", bundle: .main) ?? Color.blue
        
        // Archive-specific Colors
        static let archived = Color("Archived", bundle: .main) ?? Color.orange
        static let unarchived = Color("Unarchived", bundle: .main) ?? Color.green
        
        // Conversation Colors
        static let conversationBackground = Color("ConversationBackground", bundle: .main) ?? Color.white
        static let conversationBorder = Color("ConversationBorder", bundle: .main) ?? Color.gray.opacity(0.2)
        
        // Filter Colors
        static let filterActive = Color("FilterActive", bundle: .main) ?? Color.blue.opacity(0.1)
        static let filterInactive = Color("FilterInactive", bundle: .main) ?? Color(.systemGray6)
    }
    
    // MARK: - Typography
    struct Typography {
        // Headings
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title1 = Font.title.weight(.bold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.medium)
        
        // Body Text
        static let body = Font.body
        static let bodyEmphasized = Font.body.weight(.medium)
        static let bodySecondary = Font.body
        
        // Labels and Captions
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption1 = Font.caption
        static let caption2 = Font.caption2
        
        // Conversation-specific Typography
        static let conversationTitle = Font.headline.weight(.medium)
        static let conversationMessage = Font.subheadline
        static let conversationDate = Font.caption
        static let conversationTag = Font.caption2.weight(.medium)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        
        // Component-specific spacing
        static let listItemVertical: CGFloat = 12
        static let listItemHorizontal: CGFloat = 16
        static let sectionSpacing: CGFloat = 24
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

// MARK: - Accessibility Helpers

extension View {
    func accessibilityLabelForConversation(_ conversation: Conversation) -> some View {
        self.accessibilityLabel(conversationAccessibilityLabel(conversation))
    }
    
    func accessibilityHintForArchiveAction(_ isArchived: Bool) -> some View {
        self.accessibilityHint(isArchived ? "Double tap to unarchive" : "Double tap to archive")
    }
    
    private func conversationAccessibilityLabel(_ conversation: Conversation) -> String {
        var label = "Conversation: \(conversation.title)"
        
        if let lastMessage = conversation.lastMessage {
            label += ". Last message: \(lastMessage)"
        }
        
        if conversation.isArchived {
            label += ". Archived"
        }
        
        label += ". Updated \(DateFormatter.accessibilityFormatter.string(from: conversation.updatedAt))"
        
        if !conversation.participants.isEmpty {
            label += ". Participants: \(conversation.participants.joined(separator: ", "))"
        }
        
        return label
    }
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