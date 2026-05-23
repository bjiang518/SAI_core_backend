//
//  WeakPointHeatmapView.swift
//  StudyAI
//
//  Semicircular arc heatmap. All data shown on the arcs — no list rows.
//  Most-weak branch = innermost arc (red). Least-weak = outermost.
//  Tap a chip below the arcs to drill into sub-topics.
//

import SwiftUI

struct WeakPointHeatmapView: View {
    let subject: String
    let mistakeService: MistakeReviewService

    // Re-renders when weakness data changes after practice sessions
    @ObservedObject private var statusService = ShortTermStatusService.shared

    @State private var selectedBaseBranch: String? = nil
    @State private var appeared = false

    // Arc geometry
    private let chartHeight: CGFloat = 160
    private let maxOuterRadius: CGFloat = 96
    private let arcSpacing: CGFloat = 26
    private let arcThickness: CGFloat = 20

    private var displayBranches: [BranchAccuracyData] {
        if let base = selectedBaseBranch {
            return mistakeService.getDetailedBranchAccuracy(for: subject, baseBranch: base)
        }
        return mistakeService.getBaseBranchAccuracy(for: subject)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow

            if displayBranches.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    arcCanvas(width: geo.size.width)
                }
                .frame(height: chartHeight)
                .opacity(appeared ? 1 : 0)
                .animation(.easeIn(duration: 0.5), value: appeared)
                .onAppear {
                    appeared = false
                    // Slight delay so initial render fires before fade-in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        appeared = true
                    }
                }
                .onChange(of: selectedBaseBranch) { _ in
                    appeared = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        appeared = true
                    }
                }
                .onChange(of: subject) { _ in
                    selectedBaseBranch = nil
                    appeared = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        appeared = true
                    }
                }

                drillDownChips
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 3)
    }

    // MARK: - Arc Canvas

    private func arcColor(for branch: BranchAccuracyData) -> Color {
        if branch.accuracy >= 0.75 { return .green }
        if branch.accuracy >= 0.55 { return Color(hue: 0.14, saturation: 0.9, brightness: 0.85) }
        if branch.accuracy >= 0.35 { return .orange }
        return .red
    }

    private func arcCanvas(width: CGFloat) -> some View {
        // Snapshot branches so Canvas closure sees a consistent set
        let branches = displayBranches
        let radii = computeRadii(width: width, count: branches.count)

        return Canvas { ctx, size in
            guard !branches.isEmpty else { return }

            let cx = size.width / 2
            let cy = size.height          // arc center sits at the bottom of the frame
            let center = CGPoint(x: cx, y: cy)

            for idx in 0 ..< branches.count {
                guard idx < radii.count else { break }
                let branch = branches[idx]
                let r = radii[idx]

                // ── Layer 1: Full arc in red = incorrect territory ──
                var fullPath = Path()
                fullPath.addArc(center: center, radius: r,
                                startAngle: .degrees(180), endAngle: .degrees(0),
                                clockwise: false)
                ctx.stroke(fullPath,
                           with: .color(Color.red.opacity(0.75)),
                           style: StrokeStyle(lineWidth: arcThickness, lineCap: .round))

                // ── Layer 2: Green from left = correct territory, proportional to accuracy ──
                // Left side (180°→endDeg) = correct count ratio; right remainder = incorrect.
                if branch.accuracy > 0.001 {
                    let endDeg = 180.0 - branch.accuracy * 180.0
                    var greenPath = Path()
                    greenPath.addArc(center: center, radius: r,
                                     startAngle: .degrees(180), endAngle: .degrees(endDeg),
                                     clockwise: false)
                    ctx.stroke(greenPath,
                               with: .color(.green),
                               style: StrokeStyle(lineWidth: arcThickness, lineCap: .round))
                }
            }
        }
    }

    // MARK: - Radii

    /// i=0 → innermost (most-weak, smallest radius)
    /// i=count-1 → outermost (least-weak, largest radius)
    private func computeRadii(width: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let outerR = min(width / 2 - 16, maxOuterRadius)
        return (0 ..< count).map { i in
            outerR - CGFloat(count - 1 - i) * arcSpacing
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            if let base = selectedBaseBranch {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedBaseBranch = nil
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.blue)
                }
                Text(base)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                Text(NSLocalizedString("heatmap.subTopics", value: "· Sub-topics", comment: ""))
                    .font(.caption).foregroundColor(.secondary)
            } else {
                Image(systemName: "flame.fill")
                    .font(.caption).foregroundColor(.orange)
                Text(NSLocalizedString("heatmap.title", value: "Weak Point Heatmap", comment: ""))
                    .font(.subheadline).fontWeight(.semibold)
            }
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text(selectedBaseBranch != nil
             ? NSLocalizedString("heatmap.noDetailedData", value: "No detailed data yet for this branch.", comment: "")
             : NSLocalizedString("heatmap.noPracticeData", value: "No practice data yet. Answer some questions to see your weak areas here.", comment: ""))
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: - Drill-down Chips (no numbered list — compact pills)

    private var drillDownChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if selectedBaseBranch != nil {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedBaseBranch = nil
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.caption2.weight(.semibold))
                            Text(NSLocalizedString("heatmap.back", value: "Back", comment: ""))
                        }
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.blue.opacity(0.1)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                ForEach(Array(displayBranches.enumerated()), id: \.element.id) { idx, branch in
                    let color = arcColor(for: branch)
                    Button {
                        guard selectedBaseBranch == nil else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            selectedBaseBranch = branch.name
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(color)
                                .frame(width: 6, height: 6)
                            Text(branch.name)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(color.opacity(0.08))
                                .overlay(
                                    Capsule()
                                        .stroke(color.opacity(0.35), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedBaseBranch != nil)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
