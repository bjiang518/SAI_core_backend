//
//  SuggestedTodosSection.swift
//  StudyAI
//
//  Torn-notebook-paper style daily to-do list shown on the Home screen.
//  Visual design: white paper, faint blue ruled lines, red left margin,
//  grey binding strip, and an irregular torn-paper bottom edge.
//

import SwiftUI

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

// MARK: - Section View

struct SuggestedTodosSection: View {
    let todos: [SuggestedTodo]
    let onAction: (SuggestedTodo.TodoAction) -> Void
    let onDismiss: (String) -> Void
    let onRefresh: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isRefreshing = false

    // MARK: Theme colours

    private var paperColor: Color {
        colorScheme == .dark ? Color(hex: "28282C") : Color(hex: "FEFEFE")
    }
    private var lineColor: Color {
        colorScheme == .dark
            ? Color(hex: "3C3C48").opacity(0.7)
            : Color(hex: "DCDCF0").opacity(0.9)
    }
    private var bindingColor: Color {
        colorScheme == .dark ? Color(hex: "404048") : Color(hex: "D0D0D8")
    }
    private var marginColor: Color {
        colorScheme == .dark
            ? Color(hex: "D47070").opacity(0.45)
            : Color(hex: "E89090").opacity(0.6)
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

    private var headerFont: Font {
        Font.custom("MarkerFelt-Wide", size: 15)
    }
    private var itemFont: Font {
        Font.custom("MarkerFelt-Wide", size: 16)
    }
    private var subtitleFont: Font {
        Font.custom("MarkerFelt-Thin", size: 13)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if todos.isEmpty {
                emptyStateRow
            } else {
                ForEach(todos) { todo in
                    rowDivider
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
    }

    // MARK: – Paper background

    private var notebookBackground: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 1. Paper fill
                Color(hex: colorScheme == .dark ? "28282C" : "FEFEFE")

                // 2. Horizontal ruled lines (dashed, start below header)
                Canvas { ctx, size in
                    var y: CGFloat = 46
                    let spacing: CGFloat = 38
                    while y < size.height - 24 {
                        var p = Path()
                        p.move(to: CGPoint(x: 30, y: y))
                        p.addLine(to: CGPoint(x: size.width - 8, y: y))
                        ctx.stroke(p, with: .color(lineColor),
                                   style: StrokeStyle(lineWidth: 0.5,
                                                      lineCap: .round,
                                                      dash: [5, 4]))
                        y += spacing
                    }
                }

                // 3. Left binding strip
                Rectangle()
                    .fill(bindingColor)
                    .frame(width: 8)

                // 4. Red margin line
                Rectangle()
                    .fill(marginColor)
                    .frame(width: 1.5)
                    .padding(.leading, 22)
            }
            // Clip the whole background together with the torn edge
            .clipShape(TornEdgeShape())
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: – Header

    private var headerRow: some View {
        HStack(spacing: 5) {
            Text(NSLocalizedString("suggestedTodo.sectionTitle", value: "建议事项", comment: ""))
                .font(headerFont)
                .foregroundColor(secondaryText)
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
                onDismiss(todo.id)
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
    }
}
