//
//  ViewModifiers.swift
//  StudyAI
//
//  View modifiers for consistent UI styling across iOS versions
//

import SwiftUI

// MARK: - Navigation Bar Styling

/// Applies iOS version-appropriate navigation bar styling
/// - iOS 18+: Uses enhanced "liquid glass" translucent material effects
/// - iOS < 18: Uses solid color backgrounds with subtle transparency
struct AdaptiveNavigationBarStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            // iOS 18+ "Liquid Glass" effect
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        } else {
            // iOS < 18: Fallback with solid background and subtle transparency
            content
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(
                    colorScheme == .dark ?
                        Color(red: 0.05, green: 0.05, blue: 0.1).opacity(0.95) :
                        Color.white.opacity(0.95),
                    for: .navigationBar
                )
                .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
    }
}

/// Applies hidden navigation bar style with optional custom background
struct TransparentNavigationBarStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
    }
}

// MARK: - View Extension

extension View {
    /// Applies adaptive navigation bar styling based on iOS version
    /// - iOS 18+: Uses liquid glass effect with ultra thin material
    /// - iOS < 18: Uses solid background with opacity
    func adaptiveNavigationBar() -> some View {
        modifier(AdaptiveNavigationBarStyle())
    }

    /// Applies transparent navigation bar style
    func transparentNavigationBar() -> some View {
        modifier(TransparentNavigationBarStyle())
    }
}
