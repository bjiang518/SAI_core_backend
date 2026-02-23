//
//  TaxonomyFilter.swift
//  StudyAI
//
//  Taxonomy filter with two visualization modes: Chips (default) and Tree
//

import SwiftUI

// MARK: - Visualization Mode

enum TaxonomyVisualizationMode: String, CaseIterable {
    case chips = "Chips"
    case tree = "Tree"

    var icon: String {
        switch self {
        case .chips: return "square.grid.2x2.fill"
        case .tree: return "line.3.horizontal.decrease"
        }
    }
}

// MARK: - Taxonomy Filter View

struct TaxonomyFilterView: View {
    let subject: String
    let taxonomyData: [BaseBranchCount]
    @Binding var selectedDetailedBranches: Set<String>
    @State private var expandedBaseBranches: Set<String> = []
    @State private var visualizationMode: TaxonomyVisualizationMode = .chips

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with mode switcher
            HStack {
                Text(NSLocalizedString("mistakeReview.filter.filterByTopic", comment: ""))
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                // Liquid glass visualization mode toggle
                visualizationModeSwitcher

                if !selectedDetailedBranches.isEmpty {
                    clearButton
                }
            }

            // Content based on visualization mode
            if taxonomyData.isEmpty {
                Text(NSLocalizedString("mistakeReview.filter.noTaxonomyData", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                switch visualizationMode {
                case .chips:
                    ChipBasedTaxonomyView(
                        taxonomyData: taxonomyData,
                        selectedDetailedBranches: $selectedDetailedBranches,
                        expandedBaseBranches: $expandedBaseBranches
                    )
                case .tree:
                    TreeBasedTaxonomyView(
                        taxonomyData: taxonomyData,
                        selectedDetailedBranches: $selectedDetailedBranches,
                        expandedBaseBranches: $expandedBaseBranches
                    )
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Subviews

    private var visualizationModeSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(TaxonomyVisualizationMode.allCases, id: \.self) { mode in
                modeButton(for: mode)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
    }

    private func modeButton(for mode: TaxonomyVisualizationMode) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                visualizationMode = mode
            }
        }) {
            Image(systemName: mode.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(visualizationMode == mode ? .white : .secondary)
                .frame(width: 44, height: 32)
                .background(
                    Group {
                        if visualizationMode == mode {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                                .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                        }
                    }
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var clearButton: some View {
        Button(action: {
            selectedDetailedBranches.removeAll()
        }) {
            Text(String(format: NSLocalizedString("mistakeReview.filter.clearCount", comment: ""), selectedDetailedBranches.count))
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}

// MARK: - Chip-Based Taxonomy View

struct ChipBasedTaxonomyView: View {
    let taxonomyData: [BaseBranchCount]
    @Binding var selectedDetailedBranches: Set<String>
    @Binding var expandedBaseBranches: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(taxonomyData) { baseGroup in
                VStack(alignment: .leading, spacing: 8) {
                    let displayBaseBranch = baseGroup.baseBranch == MistakeReviewService.uncategorizedKey
                        ? NSLocalizedString("mistakeReview.filter.uncategorized", comment: "")
                        : baseGroup.baseBranch

                    // Base branch header (tap to expand/collapse)
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if expandedBaseBranches.contains(baseGroup.baseBranch) {
                                expandedBaseBranches.remove(baseGroup.baseBranch)
                            } else {
                                expandedBaseBranches.insert(baseGroup.baseBranch)
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: expandedBaseBranches.contains(baseGroup.baseBranch)
                                    ? "chevron.down"
                                    : "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 16)

                            Text(displayBaseBranch)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(baseGroup.baseBranch == MistakeReviewService.uncategorizedKey ? .secondary : .primary)

                            Spacer()

                            // Badge with mistake count
                            Text("\(baseGroup.mistakeCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(baseGroup.baseBranch == MistakeReviewService.uncategorizedKey ? Color.gray : Color.red)
                                .cornerRadius(12)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color(uiColor: .systemGray6))
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Detailed branches as chips (shown when expanded)
                    if expandedBaseBranches.contains(baseGroup.baseBranch) {
                        ChipFlowLayout(spacing: 8) {
                            ForEach(baseGroup.detailedBranches) { detail in
                                let displayDetailedBranch = detail.detailedBranch == MistakeReviewService.uncategorizedKey
                                    ? NSLocalizedString("mistakeReview.filter.uncategorized", comment: "")
                                    : detail.detailedBranch
                                ChipButton(
                                    title: displayDetailedBranch,
                                    count: detail.mistakeCount,
                                    isSelected: selectedDetailedBranches.contains(detail.detailedBranch),
                                    action: {
                                        if selectedDetailedBranches.contains(detail.detailedBranch) {
                                            selectedDetailedBranches.remove(detail.detailedBranch)
                                        } else {
                                            selectedDetailedBranches.insert(detail.detailedBranch)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.leading, 28)  // Indent to show hierarchy
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

// MARK: - Tree-Based Taxonomy View

struct TreeBasedTaxonomyView: View {
    let taxonomyData: [BaseBranchCount]
    @Binding var selectedDetailedBranches: Set<String>
    @Binding var expandedBaseBranches: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Root node
            TreeNode(
                icon: "circle.fill",
                title: NSLocalizedString("mistakeReview.filter.allTopics", comment: ""),
                level: 0,
                isExpanded: true,
                onTap: nil
            )

            // Base branches
            ForEach(taxonomyData) { baseGroup in
                let displayBaseBranch = baseGroup.baseBranch == MistakeReviewService.uncategorizedKey
                    ? NSLocalizedString("mistakeReview.filter.uncategorized", comment: "")
                    : baseGroup.baseBranch

                TreeNode(
                    icon: baseGroup.baseBranch == MistakeReviewService.uncategorizedKey ? "questionmark.folder.fill" : "folder.fill",
                    title: displayBaseBranch,
                    count: baseGroup.mistakeCount,
                    level: 1,
                    isExpanded: expandedBaseBranches.contains(baseGroup.baseBranch),
                    onTap: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if expandedBaseBranches.contains(baseGroup.baseBranch) {
                                expandedBaseBranches.remove(baseGroup.baseBranch)
                            } else {
                                expandedBaseBranches.insert(baseGroup.baseBranch)
                            }
                        }
                    }
                )

                // Detailed branches (leafs)
                if expandedBaseBranches.contains(baseGroup.baseBranch) {
                    ForEach(baseGroup.detailedBranches) { detail in
                        let displayDetailedBranch = detail.detailedBranch == MistakeReviewService.uncategorizedKey
                            ? NSLocalizedString("mistakeReview.filter.uncategorized", comment: "")
                            : detail.detailedBranch
                        TreeNode(
                            icon: "doc.fill",
                            title: displayDetailedBranch,
                            count: detail.mistakeCount,
                            level: 2,
                            isSelected: selectedDetailedBranches.contains(detail.detailedBranch),
                            onTap: {
                                if selectedDetailedBranches.contains(detail.detailedBranch) {
                                    selectedDetailedBranches.remove(detail.detailedBranch)
                                } else {
                                    selectedDetailedBranches.insert(detail.detailedBranch)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Components

struct ChipButton: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.3) : Color.red)
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue : Color(uiColor: .systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TreeNode: View {
    let icon: String
    let title: String
    var count: Int?
    let level: Int
    var isExpanded: Bool = false
    var isSelected: Bool = false
    let onTap: (() -> Void)?

    var body: some View {
        Button(action: {
            onTap?()
        }) {
            HStack(spacing: 8) {
                // Indentation based on level
                ForEach(0..<level, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 20)
                }

                // Tree connector lines
                if level > 0 {
                    VStack {
                        Rectangle()
                            .fill(Color(uiColor: .systemGray4))
                            .frame(width: 1, height: 20)
                        Spacer()
                    }

                    Rectangle()
                        .fill(Color(uiColor: .systemGray4))
                        .frame(width: 12, height: 1)
                }

                // Chevron (for expandable nodes)
                if onTap != nil && level < 2 {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                }

                // Icon
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)

                // Title
                Text(title)
                    .font(level == 0 ? .headline : .subheadline)
                    .foregroundColor(isSelected ? .blue : .primary)

                Spacer()

                // Count badge
                if let count = count {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.blue : Color.red)
                        .clipShape(Circle())
                }

                // Selection indicator
                if level == 2 {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }

    var iconColor: Color {
        switch level {
        case 0: return .gray
        case 1: return .orange
        case 2: return .blue
        default: return .gray
        }
    }
}

// MARK: - Flow Layout for Chip Wrapping

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
