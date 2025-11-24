//
//  CollapsibleNavigationBar.swift
//  StudyAI
//
//  Collapsible navigation bar with liquid glass effect
//  Can be collapsed to a small dot and expanded with smooth animations
//

import SwiftUI

/// Global state manager for navigation bar collapse state
class NavigationBarState: ObservableObject {
    static let shared = NavigationBarState()

    @Published var isCollapsed = false

    private init() {}

    func toggle() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            isCollapsed.toggle()
        }
    }

    func collapse() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            isCollapsed = true
        }
    }

    func expand() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            isCollapsed = false
        }
    }
}

/// Collapsible Navigation Bar Component
struct CollapsibleNavigationBar<Content: View>: View {
    @StateObject private var navState = NavigationBarState.shared

    let title: String
    let showBackButton: Bool
    let onBack: (() -> Void)?
    let trailingContent: Content

    init(
        title: String,
        showBackButton: Bool = true,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailingContent: () -> Content = { EmptyView() }
    ) {
        self.title = title
        self.showBackButton = showBackButton
        self.onBack = onBack
        self.trailingContent = trailingContent()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if navState.isCollapsed {
                // Collapsed state: Small circular button
                collapsedButton
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.1, anchor: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.1, anchor: .leading).combined(with: .opacity)
                    ))
            } else {
                // Expanded state: Full navigation bar
                expandedNavigationBar
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.1, anchor: .leading).combined(with: .opacity),
                        removal: .scale(scale: 0.1, anchor: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Collapsed Button

    private var collapsedButton: some View {
        Button(action: {
            navState.expand()

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }) {
            ZStack {
                // Liquid glass background
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 50, height: 50)
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)

                // Icon: Three horizontal dots
                HStack(spacing: 3) {
                    ForEach(0..<3) { _ in
                        Circle()
                            .fill(Color.primary.opacity(0.6))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Expanded Navigation Bar

    private var expandedNavigationBar: some View {
        HStack(spacing: 12) {
            // Collapse button (left)
            collapseButton

            // Back button (if needed)
            if showBackButton {
                backButton
            }

            // Title
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            // Trailing content (e.g., menu, archive button)
            trailingContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Collapse Button

    private var collapseButton: some View {
        Button(action: {
            navState.collapse()

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            ZStack {
                // Small circular background
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 32, height: 32)

                // Collapse icon: Double chevron left
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button(action: {
            onBack?()

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 32, height: 32)

                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CollapsibleNavigationBar(
            title: "数字作业本",
            showBackButton: true,
            onBack: {}
        ) {
            Button(action: {}) {
                Image(systemName: "archivebox")
                    .foregroundColor(.blue)
            }
        }

        Spacer()
    }
    .padding(.top, 50)
}
