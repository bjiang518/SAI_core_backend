//
//  SuggestedTodosSection.swift
//  StudyAI
//
//  Default theme: clean iOS-style cards.
//  Other themes: torn-notebook-paper style (white paper, ruled lines, stickers).
//

import SwiftUI
import AudioToolbox

// MARK: - Torn-edge Shape (notebook themes only)

struct TornEdgeShape: Shape {
    private let peaks: [CGFloat] = [6, 14, 8, 16, 5, 13, 9, 15, 7, 12, 10, 6, 14, 8, 11, 5]
    private let tearDepth: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let segW = rect.width / CGFloat(peaks.count)
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - tearDepth + peaks[peaks.count - 1]))
        for i in stride(from: peaks.count - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(x: CGFloat(i) * segW, y: rect.height - tearDepth + peaks[i]))
        }
        path.addLine(to: CGPoint(x: 0, y: rect.height - tearDepth + peaks[0]))
        path.closeSubpath()
        return path
    }
}

// MARK: - Highlighter Mark (notebook themes only)

private struct HighlighterMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let top = rect.height * 0.18
        let bot = rect.height * 0.88
        let l = rect.minX - 3
        let r = rect.maxX + 4
        p.move(to: CGPoint(x: l, y: top + 1.5))
        p.addCurve(to: CGPoint(x: r, y: top - 0.5),
                   control1: CGPoint(x: rect.width * 0.32, y: top - 2.5),
                   control2: CGPoint(x: rect.width * 0.70, y: top + 2.0))
        p.addLine(to: CGPoint(x: r, y: bot + 0.5))
        p.addCurve(to: CGPoint(x: l, y: bot - 0.5),
                   control1: CGPoint(x: rect.width * 0.65, y: bot + 2.5),
                   control2: CGPoint(x: rect.width * 0.28, y: bot - 2.0))
        p.closeSubpath()
        return p
    }
}

// MARK: - Handwritten Underline (notebook themes only)

private struct HandwrittenUnderline: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height * 0.75))
            path.addCurve(to: CGPoint(x: size.width, y: size.height * 0.3),
                          control1: CGPoint(x: size.width * 0.28, y: size.height * 0.0),
                          control2: CGPoint(x: size.width * 0.72, y: size.height * 1.05))
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 5)
    }
}

// MARK: - Sticker Decoration (notebook themes only)

private struct StickerDeco {
    let name: String
    let xFrac: CGFloat
    let yFrac: CGFloat
    let size: CGFloat
    let rotation: Double
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

    // Dismiss animation state
    @State private var dismissingId: String? = nil
    @State private var shakeOffsetX: CGFloat = 0
    @State private var tearOffsetX: CGFloat = 0
    @State private var tearOffsetY: CGFloat = 0
    @State private var tearRotation: Double = 0
    @State private var tearOpacity: Double = 1.0

    // Expand / collapse
    @State private var isExpanded: Bool = false

    // Folded-state rotating todo (iOS default theme only). When the section is folded
    // and there are todos, we surface a single todo card and auto-rotate it every
    // ~6 seconds so the home screen feels alive instead of showing a dead placeholder.
    @State private var collapsedRotatingIndex: Int = 0
    private let collapsedRotationInterval: UInt64 = 6_000_000_000  // 6 s in ns

    // Greeting
    @State private var greetingIndex: Int = Int.random(in: 0..<15)

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

    private func buildStickers() {
        greetingIndex = Int.random(in: 0..<15)
        let shuffled = allStickerNames.shuffled()
        stickerDecos = [
            StickerDeco(name: shuffled[0],
                        xFrac: CGFloat.random(in: 0.60...0.88),
                        yFrac: CGFloat.random(in: 0.04...0.28),
                        size: CGFloat.random(in: 38...62),
                        rotation: Double.random(in: -22...22)),
            StickerDeco(name: shuffled[1],
                        xFrac: CGFloat.random(in: 0.42...0.82),
                        yFrac: CGFloat.random(in: 0.68...0.88),
                        size: CGFloat.random(in: 38...62),
                        rotation: Double.random(in: -22...22)),
        ]
    }

    // MARK: Theme helpers

    private var currentTheme: ThemeMode { themeManager.currentTheme }
    private var isDefaultTheme: Bool { currentTheme == .default }

    private var paperColor: Color {
        if isDefaultTheme {
            return colorScheme == .dark ? themeManager.notebookPaperColorDark : themeManager.notebookPaperColor
        }
        return themeManager.notebookPaperColor
    }
    private var lineColor: Color    { themeManager.notebookGridLineColor }
    private var showGridLines: Bool { themeManager.showsNotebookGridLines }
    private var primaryText: Color  { themeManager.cardTextPrimary }
    private var secondaryText: Color { themeManager.cardTextSecondary }
    private var chevronColor: Color { themeManager.cardTextSecondary.opacity(0.6) }
    private var dividerColor: Color { themeManager.cardTextSecondary.opacity(0.2) }

    private func handwritingFont(size: CGFloat, for text: String) -> Font {
        let hasCJK = text.unicodeScalars.contains {
            (0x4E00...0x9FFF ~= $0.value) || (0x3400...0x4DBF ~= $0.value)
        }
        return hasCJK
            ? Font.custom("ZCOOLKuaiLe-Regular", size: size)
            : Font.custom("IndieFlower", size: size)
    }

    // MARK: Dismiss animations

    private func animateDismiss(_ id: String) {
        guard dismissingId == nil else { return }
        dismissingId = id
        let snapHaptic = UIImpactFeedbackGenerator(style: .rigid)
        snapHaptic.impactOccurred()
        withAnimation(.easeInOut(duration: 0.08)) { shakeOffsetX = 9 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.08)) { shakeOffsetX = -6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeOut(duration: 0.04)) { shakeOffsetX = 0 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            AudioServicesPlaySystemSound(1104)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeIn(duration: 0.30)) {
                tearOffsetX = 55; tearOffsetY = -30; tearRotation = 12; tearOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
            onDismiss(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                dismissingId = nil; shakeOffsetX = 0
                tearOffsetX = 0; tearOffsetY = 0; tearRotation = 0; tearOpacity = 1.0
            }
        }
    }

    private func animateSwipeDismiss(_ id: String, toRight: Bool, fromOffset: CGFloat = 0) {
        guard dismissingId == nil else { return }
        dismissingId = id
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        tearOffsetX = fromOffset; tearOffsetY = 0; tearRotation = 0; tearOpacity = 1.0
        withAnimation(.easeOut(duration: 0.22)) {
            tearOffsetX = toRight ? 360 : -360
            tearOffsetY = -8
            tearRotation = toRight ? 6 : -6
            tearOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            onDismiss(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                dismissingId = nil
                tearOffsetX = 0; tearOffsetY = 0; tearRotation = 0; tearOpacity = 1.0
            }
        }
    }

    // MARK: Body

    var body: some View {
        Group {
            if isDefaultTheme {
                iOSStyleBody
            } else {
                notebookStyleBody
            }
        }
        .onAppear { buildStickers() }
    }

    // MARK: – iOS-style body (default theme)

    private var iOSStyleBody: some View {
        VStack(spacing: 0) {
            iOSHeaderRow

            if isExpanded {
                VStack(spacing: 10) {
                    if todos.isEmpty {
                        iOSEmptyState
                    } else {
                        ForEach(todos) { todo in
                            TodoRowView(
                                todo: todo,
                                isIOSStyle: true,
                                dismissingId: dismissingId,
                                shakeOffsetX: shakeOffsetX,
                                tearOffsetX: tearOffsetX,
                                tearOffsetY: tearOffsetY,
                                tearRotation: tearRotation,
                                tearOpacity: tearOpacity,
                                primaryText: primaryText,
                                secondaryText: secondaryText,
                                chevronColor: chevronColor,
                                fontProvider: handwritingFont(size:for:),
                                onAction: onAction,
                                onXDismiss: animateDismiss,
                                onSwipeDismiss: animateSwipeDismiss
                            )
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 4)
                .clipped()
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                iOSCollapsedHint
                    .transition(.opacity)
            }

            iOSExpandToggleRow
        }
    }

    /// iOS-style toggle: chevron flanked by thin divider lines, matching the
    /// AdditionalActionsSection chevron in HomeView so the two sections look unified.
    private var iOSExpandToggleRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.secondary.opacity(0.09)))
                    .padding(.horizontal, 10)

                Rectangle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    private var iOSHeaderRow: some View {
        let greeting = NSLocalizedString(
            "suggestedTodo.greeting.\(greetingIndex)",
            value: "今天想一起探索点什么？",
            comment: ""
        )
        return HStack(spacing: 6) {
            Text(greeting)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(primaryText)
            Spacer()
            Button {
                isRefreshing = true
                greetingIndex = Int.random(in: 0..<15)
                onRefresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { isRefreshing = false }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.5) : .default, value: isRefreshing)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private var iOSEmptyState: some View {
        HStack {
            Text(NSLocalizedString("suggestedTodo.empty", value: "今日任务已全部完成 🎉", comment: ""))
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 12)
    }

    private var iOSCollapsedHint: some View {
        Group {
            if todos.isEmpty {
                HStack {
                    Text(NSLocalizedString("suggestedTodo.collapsed", value: "展开看看今天推荐", comment: ""))
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.75))
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 10)
            } else {
                // Show one rotating todo so the folded section still surfaces value.
                let safeIndex = collapsedRotatingIndex % max(todos.count, 1)
                let displayed = todos[safeIndex]
                TodoRowView(
                    todo: displayed,
                    isIOSStyle: true,
                    dismissingId: dismissingId,
                    shakeOffsetX: shakeOffsetX,
                    tearOffsetX: tearOffsetX,
                    tearOffsetY: tearOffsetY,
                    tearRotation: tearRotation,
                    tearOpacity: tearOpacity,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    chevronColor: chevronColor,
                    fontProvider: handwritingFont(size:for:),
                    onAction: onAction,
                    onXDismiss: animateDismiss,
                    onSwipeDismiss: animateSwipeDismiss
                )
                .id(displayed.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity.combined(with: .offset(y: -6))
                ))
                .padding(.vertical, 2)
            }
        }
        // Drive the rotation. `.task(id:)` cancels & restarts when either todo count
        // changes or the user expands/collapses the section.
        .task(id: rotationTaskKey) {
            // No rotation needed when expanded, empty, or only one todo.
            guard !isExpanded, todos.count > 1 else { return }
            // Reset index in case the underlying todos array shrank below the old index.
            collapsedRotatingIndex %= max(todos.count, 1)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: collapsedRotationInterval)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.35)) {
                    collapsedRotatingIndex = (collapsedRotatingIndex + 1) % max(todos.count, 1)
                }
            }
        }
    }

    /// Composite key so the rotation task restarts whenever any input that affects
    /// rotation behavior changes — todo count or expand/collapse state.
    private var rotationTaskKey: String {
        "\(isExpanded)-\(todos.count)"
    }

    // MARK: – Notebook-style body (other themes)

    private var notebookStyleBody: some View {
        VStack(spacing: 0) {
            headerRow

            if isExpanded {
                VStack(spacing: 0) {
                    if todos.isEmpty {
                        emptyStateRow
                    } else {
                        ForEach(todos) { todo in
                            TodoRowView(
                                todo: todo,
                                isIOSStyle: false,
                                dismissingId: dismissingId,
                                shakeOffsetX: shakeOffsetX,
                                tearOffsetX: tearOffsetX,
                                tearOffsetY: tearOffsetY,
                                tearRotation: tearRotation,
                                tearOpacity: tearOpacity,
                                primaryText: primaryText,
                                secondaryText: secondaryText,
                                chevronColor: chevronColor,
                                fontProvider: handwritingFont(size:for:),
                                onAction: onAction,
                                onXDismiss: animateDismiss,
                                onSwipeDismiss: animateSwipeDismiss
                            )
                        }
                    }
                    Color.clear.frame(height: 8)
                }
                .clipped()
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                collapsedHintRow
                    .transition(.opacity)
            }

            expandToggleRow
            Color.clear.frame(height: 22)
        }
        .background(notebookBackground)
        .shadow(
            color: colorScheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.10),
            radius: 5, x: 0, y: 4
        )
    }

    // MARK: – Paper background

    private var notebookBackground: some View {
        GeometryReader { geo in
            ZStack {
                paperColor
                if showGridLines {
                    Canvas { ctx, size in
                        let spacing: CGFloat = 24
                        let style = StrokeStyle(lineWidth: 0.5, lineCap: .round)
                        var y: CGFloat = spacing
                        while y < size.height {
                            var p = Path()
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: size.width, y: y))
                            ctx.stroke(p, with: .color(lineColor), style: style)
                            y += spacing
                        }
                        var x: CGFloat = spacing
                        while x < size.width {
                            var p = Path()
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                            ctx.stroke(p, with: .color(lineColor), style: style)
                            x += spacing
                        }
                    }
                }
                ForEach(stickerDecos, id: \.name) { deco in
                    Image(deco.name)
                        .resizable().scaledToFit()
                        .frame(width: deco.size, height: deco.size)
                        .rotationEffect(.degrees(deco.rotation))
                        .opacity(colorScheme == .dark ? 0.10 : 0.13)
                        .allowsHitTesting(false)
                        .position(x: geo.size.width * deco.xFrac, y: geo.size.height * deco.yFrac)
                }
            }
            .clipShape(TornEdgeShape())
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: – Notebook header

    private var headerRow: some View {
        let greeting = NSLocalizedString(
            "suggestedTodo.greeting.\(greetingIndex)",
            value: "今天想一起探索点什么？",
            comment: ""
        )
        return HStack(spacing: 5) {
            Text(greeting)
                .font(handwritingFont(size: 22, for: greeting))
                .fontWeight(.bold)
                .foregroundColor(secondaryText)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    HandwrittenUnderline(color: secondaryText.opacity(0.65))
                }
            Text("✏️").font(.system(size: 11))
            Spacer()
            Button {
                isRefreshing = true
                greetingIndex = Int.random(in: 0..<15)
                onRefresh()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { isRefreshing = false }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(chevronColor)
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.5) : .default, value: isRefreshing)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14).padding(.trailing, 10)
        .padding(.top, 14).padding(.bottom, 8)
    }

    private var emptyStateRow: some View {
        let text = NSLocalizedString("suggestedTodo.empty", value: "今日任务已全部完成 🎉", comment: "")
        return HStack {
            Text(text)
                .font(handwritingFont(size: 16, for: text))
                .foregroundColor(secondaryText)
            Spacer()
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
    }

    private var collapsedHintRow: some View {
        let text = NSLocalizedString("suggestedTodo.collapsed", value: "展开看看今天推荐", comment: "")
        return HStack(spacing: 6) {
            Text(text)
                .font(handwritingFont(size: 16, for: text))
                .foregroundColor(secondaryText.opacity(0.75))
            Spacer()
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
    }

    private var expandToggleRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) { isExpanded.toggle() }
        } label: {
            HStack {
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(secondaryText.opacity(0.55))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(.spring(response: 0.42, dampingFraction: 0.74), value: isExpanded)
                Spacer()
            }
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 0.5)
            .padding(.leading, 8)
    }
}

// MARK: - TodoRowView

private struct TodoRowView: View {
    let todo: SuggestedTodo
    let isIOSStyle: Bool

    let dismissingId: String?
    let shakeOffsetX: CGFloat
    let tearOffsetX: CGFloat
    let tearOffsetY: CGFloat
    let tearRotation: Double
    let tearOpacity: Double

    let primaryText: Color
    let secondaryText: Color
    let chevronColor: Color
    let fontProvider: (CGFloat, String) -> Font

    let onAction: (SuggestedTodo.TodoAction) -> Void
    let onXDismiss: (String) -> Void
    let onSwipeDismiss: (String, Bool, CGFloat) -> Void

    @State private var dragX: CGFloat = 0
    @State private var isSwiping: Bool = false

    private var isDismissing: Bool { dismissingId == todo.id }

    var body: some View {
        Group {
            if isIOSStyle {
                iOSCard
            } else {
                notebookRow
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { value in
                    guard !isDismissing else { return }
                    let h = value.translation.width
                    let v = value.translation.height
                    if isSwiping {
                        dragX = h
                    } else if abs(h) > 12 && abs(h) > abs(v) * 1.5 {
                        isSwiping = true; dragX = h
                    }
                }
                .onEnded { value in
                    let h = value.translation.width
                    if isSwiping {
                        let predicted = value.predictedEndTranslation.width
                        if abs(h) > 70 || abs(predicted) > 150 {
                            onSwipeDismiss(todo.id, h > 0, dragX)
                        } else {
                            isSwiping = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { dragX = 0 }
                        }
                    } else {
                        isSwiping = false
                    }
                }
        )
        .offset(x: isDismissing ? (shakeOffsetX + tearOffsetX) : dragX,
                y: isDismissing ? tearOffsetY : 0)
        .rotationEffect(.degrees(isDismissing ? tearRotation : 0), anchor: .topLeading)
        .opacity(isDismissing ? tearOpacity : 1.0)
        .zIndex(isDismissing || isSwiping ? 1 : 0)
    }

    // MARK: iOS card

    private var iOSCard: some View {
        Button { onAction(todo.action) } label: {
            HStack(spacing: 14) {
                // Colored circle icon
                ZStack {
                    Circle()
                        .fill(todo.color)
                        .frame(width: 46, height: 46)
                    Image(systemName: todo.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }

                // Title + subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(todo.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(primaryText)
                        .lineLimit(1)
                    // Subtitle: single line, marquee-scrolls when overflowing.
                    // Keeps every card the same height regardless of text length.
                    MarqueeText(
                        text: todo.subtitle,
                        font: .system(size: 13),
                        color: secondaryText
                    )
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(todo.color.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Notebook row

    private var notebookRow: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .stroke(todo.color.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                Image(systemName: todo.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(todo.color)
            }
            .allowsHitTesting(false)

            Button { onAction(todo.action) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(todo.title)
                        .font(fontProvider(20, todo.title))
                        .foregroundColor(primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 1)
                        .background(HighlighterMark().fill(todo.color.opacity(0.28)))
                        .frame(minHeight: 28, alignment: .center)
                    // Single-line marquee — keeps the row height consistent
                    // even when subtitles vary in length.
                    MarqueeText(
                        text: todo.subtitle,
                        font: fontProvider(16, todo.subtitle),
                        color: secondaryText
                    )
                    .frame(minHeight: 22, alignment: .center)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button { onXDismiss(todo.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(chevronColor)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8).padding(.trailing, 8).padding(.vertical, 10)
    }
}

// MARK: - Marquee single-line text
//
// Renders the text on a single line. If the text is wider than the available
// container width, it auto-scrolls horizontally (ticker-style) so users can
// read it without wrapping the layout. Falls back to a static centered Text
// when the content fits — no animation overhead in the common case.

struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    /// Pixels per second the ticker moves. Slow enough to be readable.
    var speed: CGFloat = 26
    /// Visible gap between the end of one cycle and the start of the next.
    var gapBetweenCycles: CGFloat = 36

    @State private var textWidth: CGFloat = 0
    @State private var startTime: Date = Date()

    var body: some View {
        GeometryReader { geo in
            let needsScroll = textWidth > geo.size.width + 1

            ZStack(alignment: .leading) {
                if needsScroll && textWidth > 0 {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                        let elapsed = context.date.timeIntervalSince(startTime)
                        let cycle = textWidth + gapBetweenCycles
                        let raw = CGFloat(elapsed) * speed
                        let phase = raw.truncatingRemainder(dividingBy: cycle)
                        HStack(spacing: gapBetweenCycles) {
                            Text(text)
                                .font(font).foregroundColor(color)
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                            Text(text)
                                .font(font).foregroundColor(color)
                                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                        }
                        .offset(x: -phase)
                    }
                } else {
                    Text(text)
                        .font(font).foregroundColor(color)
                        .lineLimit(1)
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: estimatedHeight)
        // Hidden ruler measures the text's natural width without affecting
        // the visible layout.
        .background(
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(0)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MarqueeTextWidthKey.self,
                            value: proxy.size.width
                        )
                    }
                )
                .allowsHitTesting(false)
        )
        .onPreferenceChange(MarqueeTextWidthKey.self) { width in
            if abs(width - textWidth) > 0.5 {
                textWidth = width
                startTime = Date()
            }
        }
    }

    /// Rough height — enough for the body fonts the suggestion cards use
    /// (system 13–16pt). Intentionally fixed so the row's height never
    /// jitters when the text content changes.
    private var estimatedHeight: CGFloat { 22 }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
