//
//  CuteTabBar.swift
//  StudyAI
//
//  Custom wavy tab bar with orange bubble for Cute Mode
//

import SwiftUI

struct CuteTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [TabItem]

    struct TabItem {
        let icon: String
        let tag: Int
        let title: String
    }

    @State private var bubbleOffset: CGFloat = 0
    @State private var bubbleScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let tabWidth = geometry.size.width / CGFloat(tabs.count)

            ZStack(alignment: .bottom) {
                // Solid black wavy background with rounded corners
                WavyTabBarShape(selectedIndex: selectedTab, tabCount: tabs.count)
                    .fill(Color(red: 0.08, green: 0.08, blue: 0.08))  // Much darker, more solid black
                    .frame(height: 110)  // Further reduced height
                    .offset(y: 55)  // Move down to 55pt to cover bottom completely
                    .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: -8)

                // Orange bubble for selected item (smooth spring animation)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.orange.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: tabs[selectedTab].icon)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundColor(.white)
                            .animation(nil, value: selectedTab)  // ✅ FIX: No animation on icon change - instant update
                    )
                    .shadow(color: Color.orange.opacity(0.5), radius: 12, x: 0, y: 5)
                    .scaleEffect(bubbleScale)  // Animated scale
                    .offset(x: bubbleOffset, y: -5)  // Lower position, closer to bar
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bubbleOffset)  // ✅ FIX: Only animate offset
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: bubbleScale)

                // Unselected icons on the dark gray bar
                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Button(action: {
                            // Simple smooth spring animation
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedTab = tabs[index].tag
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: tabs[index].icon)
                                    .font(.system(size: 22))
                                    .foregroundColor(selectedTab == tabs[index].tag ? .clear : Color.white.opacity(0.7))
                                    .frame(height: 24)

                                // Tab label text
                                Text(tabs[index].title)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(selectedTab == tabs[index].tag ? .clear : Color.white.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .padding(.bottom, -5)  // Negative padding to move buttons up relative to bar
            }
            .onChange(of: selectedTab) { _, newValue in
                let index = tabs.firstIndex(where: { $0.tag == newValue }) ?? 0
                let centerX = tabWidth * CGFloat(index) + tabWidth / 2 - geometry.size.width / 2
                bubbleOffset = centerX
            }
            .onAppear {
                let index = tabs.firstIndex(where: { $0.tag == selectedTab }) ?? 0
                let centerX = tabWidth * CGFloat(index) + tabWidth / 2 - geometry.size.width / 2
                bubbleOffset = centerX
            }
        }
        .frame(height: 100)
        .ignoresSafeArea(.all, edges: .bottom)  // Force ignore safe area
    }
}

// Custom shape for wavy tab bar with smooth cutout
struct WavyTabBarShape: Shape {
    let selectedIndex: Int
    let tabCount: Int

    var animatableData: Double {
        get { Double(selectedIndex) }
        set { }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let cornerRadius: CGFloat = 25  // Rounded corners

        // Start from bottom left
        path.move(to: CGPoint(x: 0, y: rect.height))

        // Left edge up to corner
        path.addLine(to: CGPoint(x: 0, y: cornerRadius))

        // Top-left rounded corner
        path.addArc(
            center: CGPoint(x: cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        // Top edge - clean straight line across (no dent)
        path.addLine(to: CGPoint(x: rect.width - cornerRadius, y: 0))

        // Top-right rounded corner
        path.addArc(
            center: CGPoint(x: rect.width - cornerRadius, y: cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Right edge down to bottom
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))

        // Bottom edge
        path.closeSubpath()

        return path
    }
}

#Preview {
    CuteTabBar(
        selectedTab: .constant(0),
        tabs: [
            CuteTabBar.TabItem(icon: "house.fill", tag: 0, title: "Home"),
            CuteTabBar.TabItem(icon: "camera.fill", tag: 1, title: "Grader"),
            CuteTabBar.TabItem(icon: "message.fill", tag: 2, title: "Chat"),
            CuteTabBar.TabItem(icon: "chart.bar.fill", tag: 3, title: "Progress"),
            CuteTabBar.TabItem(icon: "book.fill", tag: 4, title: "Library")
        ]
    )
    .background(Color(red: 1.0, green: 0.97, blue: 0.94))
}
