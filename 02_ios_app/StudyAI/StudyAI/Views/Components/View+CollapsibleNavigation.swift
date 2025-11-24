//
//  View+CollapsibleNavigation.swift
//  StudyAI
//
//  View extension for easy collapsible navigation bar integration
//

import SwiftUI

extension View {
    /// Apply collapsible navigation bar to any view
    /// - Parameters:
    ///   - title: Navigation bar title
    ///   - showBackButton: Whether to show back button
    ///   - onBack: Back button action
    ///   - trailingContent: Trailing toolbar items
    func collapsibleNavigationBar<Content: View>(
        title: String,
        showBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailingContent: @escaping () -> Content = { EmptyView() }
    ) -> some View {
        ZStack(alignment: .top) {
            // Original content
            self
                .navigationBarHidden(true)

            // Collapsible navigation bar overlay
            CollapsibleNavigationBar(
                title: title,
                showBackButton: showBackButton,
                onBack: onBack,
                trailingContent: trailingContent
            )
            .zIndex(100)
        }
    }

    /// Apply collapsible navigation bar with Environment-based dismiss
    func collapsibleNavigationBar<Content: View>(
        title: String,
        @ViewBuilder trailingContent: @escaping () -> Content = { EmptyView() }
    ) -> some View {
        modifier(CollapsibleNavigationModifier(title: title, trailingContent: trailingContent))
    }
}

// MARK: - Collapsible Navigation Modifier

struct CollapsibleNavigationModifier<TrailingContent: View>: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let trailingContent: TrailingContent

    init(title: String, @ViewBuilder trailingContent: () -> TrailingContent) {
        self.title = title
        self.trailingContent = trailingContent()
    }

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
                .navigationBarHidden(true)

            CollapsibleNavigationBar(
                title: title,
                showBackButton: true,
                onBack: {
                    dismiss()
                }
            ) {
                trailingContent
            }
            .zIndex(100)
        }
    }
}
