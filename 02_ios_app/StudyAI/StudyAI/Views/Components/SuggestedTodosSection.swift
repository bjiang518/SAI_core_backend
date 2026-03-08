//
//  SuggestedTodosSection.swift
//  StudyAI
//
//  Torn-notebook-paper style daily to-do list shown on the Home screen.
//  Visual design: white paper, faint blue ruled lines, red left margin,
//  grey binding strip, and an irregular torn-paper bottom edge.
//

import SwiftUI
import AudioToolbox

// MARK: - Torn-edge Shape

/// Full-rectangle shape whose bottom edge is replaced by an irregular zigzag,
/// simulating a page torn from a spiral notebook.
struct TornEdgeShape: Shape {
    /// Fixed peak heights (pt) for each zigzag segment.
    /// Hard-coded so the path is stable across re-renders.
    private let peaks: [CGFloat] = [6, 14, 8, 16, 5, 13, 9, 15, 7, 12, 10, 6, 14, 8, 11, 5]
    /// How far from the bottom the tear begins.
    private let tearDepth: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let segW = rect.width / CGFloat(peaks.count)

        // Straight top and sides down to the tear start
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width,
                                 y: rect.height - tearDepth + peaks[peaks.count - 1]))

        // Zigzag from right to left
        for i in stride(from: peaks.count - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(
                x: CGFloat(i) * segW,
                y: rect.height - tearDepth + peaks[i]
            ))
        }

        path.addLine(to: CGPoint(x: 0, y: rect.height - tearDepth + peaks[0]))
        path.closeSubpath()
        return path
    }
}

// MARK: - Handwritten Underline

private struct HandwrittenUnderline: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            // Gentle S-curve: starts low-left, arcs up through middle, dips back down at right
            path.move(to: CGPoint(x: 0, y: size.height * 0.75))
            path.addCurve(
                to: CGPoint(x: size.width, y: size.height * 0.3),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.0),
                control2: CGPoint(x: size.width * 0.72, y: size.height * 1.05)
            )
            ctx.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: 5)
    }
}

// MARK: - Sticker Decoration

private struct StickerDeco {
    let name: String
    let xFrac: CGFloat   // 0–1 fraction of card width
    let yFrac: CGFloat   // 0–1 fraction of card height
    let size: CGFloat    // pt
    let rotation: Double // degrees
}

// MARK: - Section View

struct SuggestedTodosSection: View {
    let todos: [SuggestedTodo]
    let onAction: (SuggestedTodo.TodoAction) -> Void
    let onDismiss: (String) -> Void
    let onRefresh: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var themeManager = ThemeManager.shared
    @State private var isRefreshing = false
    @State private var stickerDecos: [StickerDeco] = []

    // MARK: Dismiss animation state
    @State private var dismissingId: String? = nil
    @State private var shakeOffsetX: CGFloat = 0
    @State private var tearOffsetX: CGFloat = 0
    @State private var tearOffsetY: CGFloat = 0
    @State private var tearRotation: Double = 0
    @State private var tearOpacity: Double = 1.0

    // All available cartoon sticker asset names
    private let allStickerNames: [String] = [
        "arrow-03-svgrepo-com", "arrow-07-svgrepo-com",
        "arrow-10-svgrepo-com", "arrow-11-svgrepo-com",
        "book-reading-learning-svgrepo-com",
        "botanical-nature-plant-leaf-garden-11-svgrepo-com",
        "botanical-nature-plant-leaf-garden-12-svgrepo-com",
        "botanical-nature-plant-leaf-garden-15-svgrepo-com",
        "botanical-nature-plant-leaf-garden-16-svgrepo-com",
        "botanical-nature-plant-leaf-garden-19-svgrepo-com",
        "botanical-nature-plant-leaf-garden-20-svgrepo-com",
        "botanical-nature-plant-leaf-garden-21-svgrepo-com",
        "botanical-nature-plant-leaf-garden-4-svgrepo-com",
        "botanical-nature-plant-leaf-garden-7-svgrepo-com",
        "botanical-nature-plant-leaf-garden-clover-2-svgrepo-com",
        "botanical-nature-plant-leaf-garden-clover-svgrepo-com",
        "chat-message-communication-svgrepo-com",
        "edit-pencil-pen-svgrepo-com",
        "file-document-paper-svgrepo-com",
        "folder-archive-storage-svgrepo-com",
        "gear-setting-preferences-svgrepo-com",
        "gift-give-box-svgrepo-com",
        "globe-world-global-svgrepo-com",
        "loading-refresh-rotate-svgrepo-com",
        "multiple-actions-ui-svgrepo-com",
        "picture-photo-image-svgrepo-com",
        "play-player-multimedia-svgrepo-com",
        "trophy-award-winner-svgrepo-com"
    ]

    /// Pick 2 different stickers, place them in the upper-right and lower zones respectively.
    private func buildStickers() {
        let shuffled = allStickerNames.shuffled()
        // Zone A — upper-right: x 60–88%, y 4–28%
        let a = StickerDeco(
            name: shuffled[0],
            xFrac: CGFloat.random(in: 0.60...0.88),
            yFrac: CGFloat.random(in: 0.04...0.28),
            size: CGFloat.random(in: 38...62),
            rotation: Double.random(in: -22...22)
        )
        // Zone B — lower: x 42–82%, y 68–88%
        let b = StickerDeco(
            name: shuffled[1],
            xFrac: CGFloat.random(in: 0.42...0.82),
            yFrac: CGFloat.random(in: 0.68...0.88),
            size: CGFloat.random(in: 38...62),
            rotation: Double.random(in: -22...22)
        )
        stickerDecos = [a, b]
    }

    // MARK: Theme colours

    private var paperColor: Color {
        if themeManager.currentTheme == .cute {
            return Color(hex: "FFFFFF")
        }
        return colorScheme == .dark ? Color(hex: "27251F") : Color(hex: "FAF6EE")
    }
    private var lineColor: Color {
        colorScheme == .dark
            ? Color(hex: "4A4640").opacity(0.55)
            : Color(hex: "B8C4C0").opacity(0.55)
    }
    private var primaryText: Color {
        colorScheme == .dark ? Color(hex: "E8E8E8") : Color(hex: "2A2A2A")
    }
    private var secondaryText: Color {
        colorScheme == .dark ? Color(hex: "909098") : Color(hex: "888888")
    }
    private var chevronColor: Color {
        colorScheme == .dark ? Color(hex: "505058") : Color(hex: "C0C0C0")
    }
    private var dividerColor: Color {
        colorScheme == .dark
            ? Color(hex: "3A3A42").opacity(0.8)
            : Color(hex: "E0E0EC").opacity(0.9)
    }

    // MARK: Fonts

    private var isChineseLocale: Bool {
        let code = Locale.current.language.languageCode?.identifier ?? ""
        return code == "zh"
    }

    private var headerFont: Font {
        isChineseLocale
            ? Font.custom("ZCOOLKuaiLe-Regular", size: 18)
            : Font.custom("IndieFlower", size: 18)
    }
    private var itemFont: Font {
        isChineseLocale
            ? Font.custom("ZCOOLKuaiLe-Regular", size: 20)
            : Font.custom("IndieFlower", size: 20)
    }
    private var subtitleFont: Font {
        isChineseLocale
            ? Font.custom("ZCOOLKuaiLe-Regular", size: 16)
            : Font.custom("IndieFlower", size: 16)
    }

    // MARK: – Dismiss animation

    private func animateDismiss(_ id: String) {
        guard dismissingId == nil else { return }
        dismissingId = id

        // Phase 1: quick left-right shake (0 – 0.18s)
        // Haptic: sharp snap at shake start
        let snapHaptic = UIImpactFeedbackGenerator(style: .rigid)
        snapHaptic.impactOccurred()

        withAnimation(.easeInOut(duration: 0.08)) { shakeOffsetX = 9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.08)) { shakeOffsetX = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.04)) { shakeOffsetX = 0 }
        }

        // Phase 2: tear-off — item peels up-right, rotates, fades (0.22s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            // Sound: system "swipe/delete" tone timed with the visual tear
            AudioServicesPlaySystemSound(1104)
            // Haptic: softer secondary impact at the moment of "rip"
            let ripHaptic = UIImpactFeedbackGenerator(style: .medium)
            ripHaptic.impactOccurred()

            withAnimation(.easeIn(duration: 0.30)) {
                tearOffsetX = 55
                tearOffsetY = -30
                tearRotation = 12
                tearOpacity = 0
            }
        }

        // Phase 3: remove item + collapse remaining rows (0.56s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                onDismiss(id)
            }
            // Reset all state after the row is gone
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                dismissingId  = nil
                shakeOffsetX  = 0
                tearOffsetX   = 0
                tearOffsetY   = 0
                tearRotation  = 0
                tearOpacity   = 1.0
            }
        }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if todos.isEmpty {
                emptyStateRow
            } else {
                ForEach(todos) { todo in
                    todoRow(todo)
                }
            }
            // Extra bottom padding so text clears the torn edge
            Color.clear.frame(height: 22)
        }
        .background(notebookBackground)
        .shadow(
            color: colorScheme == .dark
                ? Color.black.opacity(0.35)
                : Color.black.opacity(0.10),
            radius: 5, x: 0, y: 4
        )
        .onAppear { buildStickers() }
    }

    // MARK: – Paper background

    private var notebookBackground: some View {
        GeometryReader { geo in
            ZStack {
                // 1. Warm graph-paper fill
                paperColor

                // 2. Grid lines — equal horizontal + vertical spacing
                Canvas { ctx, size in
                    let spacing: CGFloat = 24
                    let style = StrokeStyle(lineWidth: 0.5, lineCap: .round)

                    // Horizontal lines
                    var y: CGFloat = spacing
                    while y < size.height {
                        var p = Path()
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(p, with: .color(lineColor), style: style)
                        y += spacing
                    }

                    // Vertical lines
                    var x: CGFloat = spacing
                    while x < size.width {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(p, with: .color(lineColor), style: style)
                        x += spacing
                    }
                }

                // 3. Cartoon stickers — randomised each appearance, behind all content
                ForEach(stickerDecos, id: \.name) { deco in
                    Image(deco.name)
                        .resizable()
                        .scaledToFit()
                        .frame(width: deco.size, height: deco.size)
                        .rotationEffect(.degrees(deco.rotation))
                        .opacity(colorScheme == .dark ? 0.10 : 0.13)
                        .allowsHitTesting(false)
                        .position(
                            x: geo.size.width  * deco.xFrac,
                            y: geo.size.height * deco.yFrac
                        )
                }
            }
            .clipShape(TornEdgeShape())
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: – Header

    private var headerRow: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("suggestedTodo.sectionTitle", value: "建议事项", comment: ""))
                    .font(headerFont)
                    .fontWeight(.bold)
                    .foregroundColor(secondaryText)
                HandwrittenUnderline(color: secondaryText.opacity(0.65))
            }
            .fixedSize()
            Text("✏️")
                .font(.system(size: 11))
            Spacer()
            Button {
                isRefreshing = true
                onRefresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    isRefreshing = false
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(chevronColor)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(
                        isRefreshing
                            ? .linear(duration: 0.5)
                            : .default,
                        value: isRefreshing
                    )
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 36)
        .padding(.trailing, 10)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    // MARK: – Empty state

    private var emptyStateRow: some View {
        HStack {
            Text(NSLocalizedString("suggestedTodo.empty", value: "今日任务已全部完成 🎉", comment: ""))
                .font(subtitleFont)
                .foregroundColor(secondaryText)
            Spacer()
        }
        .padding(.leading, 36)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
    }

    // MARK: – Divider

    private var rowDivider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 0.5)
            .padding(.leading, 30)
    }

    // MARK: – Todo row

    private func todoRow(_ todo: SuggestedTodo) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Colour-tinted circle with SF icon (acts as "checkbox")
            ZStack {
                Circle()
                    .stroke(todo.color.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                Image(systemName: todo.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(todo.color)
            }

            // Text stack
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .font(itemFont)
                    .foregroundColor(primaryText)
                    .lineLimit(1)
                Text(todo.subtitle)
                    .font(subtitleFont)
                    .foregroundColor(secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Dismiss button
            Button {
                animateDismiss(todo.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(chevronColor)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 36)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { onAction(todo.action) }
        // Tear-off animation transforms
        .offset(
            x: dismissingId == todo.id ? shakeOffsetX + tearOffsetX : 0,
            y: dismissingId == todo.id ? tearOffsetY : 0
        )
        .rotationEffect(.degrees(dismissingId == todo.id ? tearRotation : 0),
                        anchor: .topLeading)
        .opacity(dismissingId == todo.id ? tearOpacity : 1.0)
        .zIndex(dismissingId == todo.id ? 1 : 0)
    }
}
