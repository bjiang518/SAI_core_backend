//
//  DeepGradingExplanationView.swift
//  StudyAI
//
//  Renders deep-mode grading output:
//  - detailedExplanation with 「bold」 marker-pen highlight effect
//  - step_breakdown: per-step ✓ / △ / ✗ with explanations
//  - method_analysis: complexity badge + alternative method card
//

import SwiftUI

// MARK: - Main view

struct DeepGradingExplanationView: View {
    let grade: ProgressiveGradeResult

    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showStepBreakdown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            deepModeLabel

            if let explanation = grade.detailedExplanation, !explanation.isEmpty {
                MarkerHighlightText(explanation)
            }

            if let steps = grade.stepBreakdown, !steps.isEmpty {
                stepBreakdownSection(steps)
            }

            if let method = grade.methodAnalysis {
                methodAnalysisCard(method)
            }
        }
    }

    // MARK: - Deep Mode Label

    private var deepModeLabel: some View {
        HStack(spacing: 5) {
            Image(systemName: "brain.head.profile")
                .font(.caption2)
            Text(NSLocalizedString("grading.deepMode.label", value: "深度批改", comment: ""))
                .font(.caption2.weight(.semibold))
        }
        .foregroundColor(Color(hex: "8B5CF6"))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(hex: "8B5CF6").opacity(0.1))
        .clipShape(Capsule())
    }

    // MARK: - Step Breakdown

    private func stepBreakdownSection(_ steps: [StepBreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showStepBreakdown.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "list.number")
                        .font(.caption2)
                    Text(NSLocalizedString("grading.stepBreakdown.title", value: "步骤分析", comment: ""))
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: showStepBreakdown ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundColor(themeManager.primaryText)
            }
            .buttonStyle(.plain)

            if showStepBreakdown {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, item in
                        stepRow(index: idx, item: item)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.05)
                      : Color.black.opacity(0.03))
        )
    }

    private func stepRow(index: Int, item: StepBreakdownItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Status icon
            ZStack {
                Circle()
                    .fill(stepStatusColor(item.status).opacity(0.15))
                    .frame(width: 22, height: 22)
                Image(systemName: stepStatusIcon(item.status))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(stepStatusColor(item.status))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("grading.step.label", value: "Step", comment: "") + " \(index + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(stepStatusColor(item.status))
                Text(item.explanation)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Method Analysis

    private func methodAnalysisCard(_ method: MethodAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row
            HStack(spacing: 5) {
                Image(systemName: "function")
                    .font(.caption2)
                Text(NSLocalizedString("grading.methodAnalysis.title", value: "方法分析", comment: ""))
                    .font(.caption.weight(.semibold))
                Spacer()
                if let complexity = method.complexity, !complexity.isEmpty {
                    Text(complexity)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(hex: "0891B2"))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(hex: "0891B2").opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(themeManager.primaryText)

            if let approach = method.approachDescription, !approach.isEmpty {
                Text(approach)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }

            // Alternative method — only show if present
            if let alt = method.alternativeMethod, !alt.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("grading.methodAnalysis.alternative", value: "更优方法", comment: ""))
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.orange)
                        Text(alt)
                            .font(.caption2)
                            .foregroundColor(themeManager.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = method.efficiencyNote, !note.isEmpty {
                            Text(note)
                                .font(.caption2.italic())
                                .foregroundColor(themeManager.secondaryText.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.05)
                      : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "8B5CF6").opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func stepStatusColor(_ status: String) -> Color {
        switch status {
        case "correct":    return .green
        case "suboptimal": return .orange
        default:           return .red
        }
    }

    private func stepStatusIcon(_ status: String) -> String {
        switch status {
        case "correct":    return "checkmark"
        case "suboptimal": return "exclamationmark"
        default:           return "xmark"
        }
    }
}

// MARK: - MarkerHighlightText
// Parses 「bold text」 markers and renders them with a yellow highlighter stroke.

struct MarkerHighlightText: View {
    private let segments: [Segment]
    @Environment(\.colorScheme) private var colorScheme

    init(_ text: String) {
        self.segments = Self.parse(text)
    }

    var body: some View {
        segments.reduce(Text("")) { result, segment in
            result + segment.text(colorScheme: colorScheme)
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(3)
    }

    // MARK: - Parsing

    private struct Segment {
        let content: String
        let isHighlighted: Bool

        func text(colorScheme: ColorScheme) -> Text {
            if isHighlighted {
                return Text(content)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(colorScheme == .dark ? Color(hex: "FDE68A") : Color(hex: "92400E"))
            } else {
                return Text(content)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.85) : .primary)
            }
        }
    }

    private static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var remaining = text

        while !remaining.isEmpty {
            if let openRange = remaining.range(of: "「"),
               let closeRange = remaining.range(of: "」", range: openRange.upperBound..<remaining.endIndex) {
                // Text before the marker
                let before = String(remaining[remaining.startIndex..<openRange.lowerBound])
                if !before.isEmpty {
                    segments.append(Segment(content: before, isHighlighted: false))
                }
                // Highlighted content
                let highlighted = String(remaining[openRange.upperBound..<closeRange.lowerBound])
                if !highlighted.isEmpty {
                    segments.append(Segment(content: highlighted, isHighlighted: true))
                }
                remaining = String(remaining[closeRange.upperBound...])
            } else {
                segments.append(Segment(content: remaining, isHighlighted: false))
                break
            }
        }
        return segments
    }
}
