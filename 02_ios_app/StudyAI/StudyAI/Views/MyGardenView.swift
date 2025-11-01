//
//  MyGardenView.swift
//  StudyAI
//
//  Garden view displaying earned focus trees with dark mode support
//

import SwiftUI

struct MyGardenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var gardenService = FocusTreeGardenService.shared

    @State private var selectedFilter: TreeFilter = .all
    @State private var sortOption: SortOption = .recent
    @State private var showClearConfirmation = false

    enum TreeFilter: String, CaseIterable {
        case all = "All Trees"
        case sapling = "Saplings"
        case young = "Young Trees"
        case mature = "Mature Trees"
        case ancient = "Ancient Trees"

        var treeType: TreeType? {
            switch self {
            case .all: return nil
            case .sapling: return .sapling
            case .young: return .youngTree
            case .mature: return .matureTree
            case .ancient: return .ancientTree
            }
        }

        var localizedName: String {
            switch self {
            case .all: return NSLocalizedString("focus.garden.allTrees", comment: "All Trees")
            case .sapling: return NSLocalizedString("focus.tree.sapling", comment: "Saplings")
            case .young: return NSLocalizedString("focus.tree.youngTree", comment: "Young Trees")
            case .mature: return NSLocalizedString("focus.tree.matureTree", comment: "Mature Trees")
            case .ancient: return NSLocalizedString("focus.tree.ancientTree", comment: "Ancient Trees")
            }
        }
    }

    enum SortOption: String, CaseIterable {
        case recent = "Recent"
        case oldest = "Oldest"

        var localizedName: String {
            switch self {
            case .recent: return NSLocalizedString("focus.garden.recent", comment: "Recent")
            case .oldest: return NSLocalizedString("focus.garden.oldest", comment: "Oldest")
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Adaptive Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark ? [
                        Color(red: 0.05, green: 0.1, blue: 0.05),
                        Color(red: 0.1, green: 0.15, blue: 0.1)
                    ] : [
                        Color(red: 0.95, green: 0.98, blue: 0.95),
                        Color(red: 0.90, green: 0.96, blue: 0.92)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if gardenService.trees.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Statistics
                            statisticsSection
                                .padding(.horizontal, 20)
                                .padding(.top, 16)

                            // Filters
                            filterSection
                                .padding(.horizontal, 20)

                            // Trees Grid
                            treesGrid
                                .padding(.horizontal, 20)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .navigationTitle(NSLocalizedString("focus.garden.title", comment: "My Garden"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !gardenService.trees.isEmpty {
                        Menu {
                            Button(role: .destructive, action: { showClearConfirmation = true }) {
                                Label(NSLocalizedString("focus.garden.clearGarden", comment: "Clear Garden"), systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 24))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .primary)
                        }
                    }
                }
            }
            .alert(NSLocalizedString("focus.garden.clearGarden", comment: "Clear Garden"), isPresented: $showClearConfirmation) {
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
                Button(NSLocalizedString("common.delete", comment: "Delete"), role: .destructive) {
                    gardenService.clearGarden()
                }
            } message: {
                Text(NSLocalizedString("focus.garden.clearConfirmation", comment: "Clear all trees?"))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 80))
                .foregroundColor(colorScheme == .dark ? Color.green.opacity(0.4) : Color.green.opacity(0.3))

            VStack(spacing: 8) {
                Text(NSLocalizedString("focus.garden.emptyState", comment: "Your garden is empty"))
                    .font(.title2.weight(.semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                Text(NSLocalizedString("focus.garden.emptyStateMessage", comment: "Complete focus sessions to plant trees!"))
                    .font(.body)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(spacing: 16) {
            // Main Stats
            HStack(spacing: 12) {
                StatCard(
                    icon: "leaf.fill",
                    value: "\(gardenService.statistics.totalTrees)",
                    label: NSLocalizedString("focus.garden.totalTrees", comment: "Total Trees"),
                    color: .green,
                    colorScheme: colorScheme
                )

                StatCard(
                    icon: "clock.fill",
                    value: formatTotalTime(gardenService.statistics.totalFocusTime),
                    label: NSLocalizedString("focus.garden.totalFocusTime", comment: "Total Focus Time"),
                    color: .blue,
                    colorScheme: colorScheme
                )
            }

            HStack(spacing: 12) {
                StatCard(
                    icon: "trophy.fill",
                    value: formatDuration(gardenService.statistics.longestSession),
                    label: NSLocalizedString("focus.garden.longestSession", comment: "Longest Session"),
                    color: .orange,
                    colorScheme: colorScheme
                )

                StatCard(
                    icon: "flame.fill",
                    value: "\(gardenService.statistics.currentStreak)",
                    label: NSLocalizedString("focus.garden.currentStreak", comment: "Current Streak") + " " + NSLocalizedString("focus.garden.days", comment: "days"),
                    color: .red,
                    colorScheme: colorScheme
                )
            }
        }
    }

    private struct StatCard: View {
        let icon: String
        let value: String
        let label: String
        let color: Color
        let colorScheme: ColorScheme

        var body: some View {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)

                    Text(value)
                        .font(.title3.weight(.bold))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                }

                Text(label)
                    .font(.caption)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            .cornerRadius(12)
            .shadow(
                color: colorScheme == .dark ?
                    Color.white.opacity(0.05) :
                    Color.black.opacity(0.05),
                radius: 8,
                x: 0,
                y: 2
            )
        }
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(spacing: 12) {
            // Tree Type Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TreeFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            title: filter.localizedName,
                            isSelected: selectedFilter == filter,
                            colorScheme: colorScheme
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            // Sort Options
            HStack {
                Text(NSLocalizedString("focus.garden.sortBy", comment: "Sort by:"))
                    .font(.subheadline)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .secondary)

                Picker("", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.localizedName).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private struct FilterChip: View {
        let title: String
        let isSelected: Bool
        let colorScheme: ColorScheme
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : (colorScheme == .dark ? .white.opacity(0.8) : .primary))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        isSelected ?
                            Color.green :
                            (colorScheme == .dark ? Color.white.opacity(0.1) : Color.white)
                    )
                    .cornerRadius(20)
                    .shadow(
                        color: colorScheme == .dark ?
                            Color.white.opacity(0.05) :
                            Color.black.opacity(0.05),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            }
        }
    }

    // MARK: - Trees Grid

    private var treesGrid: some View {
        let columns = [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ]

        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredAndSortedTrees) { tree in
                TreeCard(tree: tree, colorScheme: colorScheme)
            }
        }
    }

    private struct TreeCard: View {
        let tree: FocusTree
        let colorScheme: ColorScheme

        var body: some View {
            VStack(spacing: 8) {
                // Tree Emoji
                Text(tree.type.emoji)
                    .font(.system(size: 48))

                // Tree Type
                Text(tree.type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                // Duration
                Text(formatDuration(tree.focusDuration))
                    .font(.caption2)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)

                // Date
                Text(formatDate(tree.earnedDate))
                    .font(.caption2)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.6) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
            .cornerRadius(12)
            .shadow(
                color: colorScheme == .dark ?
                    Color.white.opacity(0.05) :
                    Color.black.opacity(0.05),
                radius: 6,
                x: 0,
                y: 2
            )
        }

        private func formatDuration(_ duration: TimeInterval) -> String {
            let minutes = Int(duration / 60)
            if minutes < 60 {
                return "\(minutes)m"
            } else {
                let hours = minutes / 60
                let remainingMinutes = minutes % 60
                return "\(hours)h \(remainingMinutes)m"
            }
        }

        private func formatDate(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    // MARK: - Helper Methods

    private var filteredAndSortedTrees: [FocusTree] {
        var trees = gardenService.trees

        // Filter by type
        if let type = selectedFilter.treeType {
            trees = trees.filter { $0.type == type }
        }

        // Sort
        switch sortOption {
        case .recent:
            trees.sort { $0.earnedDate > $1.earnedDate }
        case .oldest:
            trees.sort { $0.earnedDate < $1.earnedDate }
        }

        return trees
    }

    private func formatTotalTime(_ duration: TimeInterval) -> String {
        let hours = Int(duration / 3600)
        if hours < 1 {
            return "\(Int(duration / 60))m"
        } else if hours < 100 {
            return "\(hours)h"
        } else {
            return "99h+"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

// MARK: - Preview

struct MyGardenView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MyGardenView()
                .preferredColorScheme(.light)

            MyGardenView()
                .preferredColorScheme(.dark)
        }
    }
}
