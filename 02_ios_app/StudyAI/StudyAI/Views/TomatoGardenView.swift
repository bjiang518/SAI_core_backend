//
//  TomatoGardenView.swift
//  StudyAI
//
//  Tomato Garden - Display all collected tomatoes
//

import SwiftUI

struct TomatoGardenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var gardenService = TomatoGardenService.shared
    @StateObject private var themeManager = ThemeManager.shared

    @State private var selectedFilter: FilterOption = .all
    @State private var showDeleteConfirmation = false
    @State private var tomatoToDelete: Tomato?
    @State private var showPhysicsGarden = false
    @State private var showingGardenInfo = false

    enum FilterOption: String, CaseIterable {
        case all
        case today
        case week
        case classic
        case curly
        case cute

        var localizedTitle: String {
            switch self {
            case .all:
                return NSLocalizedString("tomato.garden.filter.all", comment: "All")
            case .today:
                return NSLocalizedString("tomato.garden.filter.today", comment: "Today")
            case .week:
                return NSLocalizedString("tomato.garden.filter.week", comment: "Week")
            case .classic:
                return NSLocalizedString("tomato.garden.type.classic", comment: "Classic")
            case .curly:
                return NSLocalizedString("tomato.garden.type.curly", comment: "Curly")
            case .cute:
                return NSLocalizedString("tomato.garden.type.cute", comment: "Cute")
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        statsCard
                        filterSection
                        tomatoGrid

                        if let milestone = gardenService.getNextMilestone() {
                            nextMilestoneCard(milestone: milestone)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(NSLocalizedString("tomato.garden.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(themeManager.secondaryText)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { showingGardenInfo = true }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(DesignTokens.Colors.Cute.blue)
                        }
                        Button(action: { showPhysicsGarden = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text(NSLocalizedString("tomato.garden.physics", comment: ""))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundColor(DesignTokens.Colors.Cute.lavender)
                        }
                    }
                }
            }
            .alert(NSLocalizedString("tomatoGarden.info.title", comment: ""), isPresented: $showingGardenInfo) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(NSLocalizedString("tomatoGarden.info.message", comment: ""))
            }
            .fullScreenCover(isPresented: $showPhysicsGarden) {
                PhysicsTomatoGardenView()
            }
            .alert(NSLocalizedString("tomato.garden.delete.title", comment: "Delete"), isPresented: $showDeleteConfirmation) {
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                    if let tomato = tomatoToDelete {
                        gardenService.removeTomato(id: tomato.id)
                    }
                }
            } message: {
                Text(NSLocalizedString("tomato.garden.delete.message", comment: ""))
            }
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(DesignTokens.Colors.Cute.peach)
                Text(NSLocalizedString("tomato.garden.stats", comment: ""))
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)
                Spacer()
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                TomatoStatItem(
                    icon: "🍅",
                    value: "\(gardenService.stats.totalTomatoes)",
                    label: NSLocalizedString("tomato.garden.total", comment: ""),
                    themeManager: themeManager
                )

                TomatoStatItem(
                    icon: "⏱️",
                    value: gardenService.stats.formattedTotalTime,
                    label: NSLocalizedString("tomato.garden.focusTime", comment: ""),
                    themeManager: themeManager
                )

                TomatoStatItem(
                    icon: "⭐️",
                    value: formatDuration(gardenService.stats.longestSession),
                    label: NSLocalizedString("tomato.garden.longestSession", comment: ""),
                    themeManager: themeManager
                )
            }

            HStack(spacing: 12) {
                TomatoTypeCount(type: .classic, count: gardenService.stats.classicCount, themeManager: themeManager)
                TomatoTypeCount(type: .curly, count: gardenService.stats.curlyCount, themeManager: themeManager)
                TomatoTypeCount(type: .cute, count: gardenService.stats.cuteCount, themeManager: themeManager)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    FilterChip(
                        title: option.localizedTitle,
                        isSelected: selectedFilter == option,
                        themeManager: themeManager,
                        action: { selectedFilter = option }
                    )
                }
            }
        }
    }

    // MARK: - Tomato Grid

    private var tomatoGrid: some View {
        let filteredTomatoes = getFilteredTomatoes()

        return VStack(alignment: .leading, spacing: 16) {
            if filteredTomatoes.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(filteredTomatoes) { tomato in
                        TomatoCard(tomato: tomato, themeManager: themeManager) {
                            tomatoToDelete = tomato
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 60))
                .foregroundColor(DesignTokens.Colors.Cute.mint.opacity(0.3))

            Text(NSLocalizedString("tomato.garden.emptyState", comment: ""))
                .font(.title3.weight(.medium))
                .foregroundColor(themeManager.secondaryText)

            Text(NSLocalizedString("tomato.garden.emptyMessage", comment: ""))
                .font(.body)
                .foregroundColor(themeManager.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Next Milestone Card

    private func nextMilestoneCard(milestone: (count: Int, description: String)) -> some View {
        let remaining = gardenService.tomatoesNeededForNextMilestone() ?? 0

        return HStack(spacing: 12) {
            Image(systemName: "flag.fill")
                .font(.system(size: 24))
                .foregroundColor(DesignTokens.Colors.Cute.yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("tomato.garden.nextMilestone", comment: ""))
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)

                Text(milestone.description)
                    .font(.body.weight(.semibold))
                    .foregroundColor(themeManager.primaryText)

                Text(String(format: NSLocalizedString("tomato.garden.remaining", comment: ""), remaining))
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(themeManager.secondaryText.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: CGFloat(gardenService.stats.totalTomatoes) / CGFloat(milestone.count))
                    .stroke(DesignTokens.Colors.Cute.yellow, lineWidth: 4)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                Text("\(Int((Double(gardenService.stats.totalTomatoes) / Double(milestone.count)) * 100))%")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(themeManager.primaryText)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Helper Functions

    private func getFilteredTomatoes() -> [Tomato] {
        let sorted = gardenService.getTomatoesSortedByDate()

        switch selectedFilter {
        case .all:
            return sorted
        case .today:
            return gardenService.getTodayTomatoes()
        case .week:
            return gardenService.getWeekTomatoes()
        case .classic:
            return sorted.filter { $0.type == .classic }
        case .curly:
            return sorted.filter { $0.type == .curly }
        case .cute:
            return sorted.filter { $0.type == .cute }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes)\(NSLocalizedString("tomato.garden.minutes", comment: "min"))"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h\(remainingMinutes)m"
        }
    }
}

// MARK: - Subviews

struct TomatoStatItem: View {
    let icon: String
    let value: String
    let label: String
    let themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 32))

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(themeManager.primaryText)

            Text(label)
                .font(.caption)
                .foregroundColor(themeManager.secondaryText)
        }
    }
}

struct TomatoTypeCount: View {
    let type: TomatoType
    let count: Int
    let themeManager: ThemeManager

    var body: some View {
        HStack(spacing: 8) {
            Image(type.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)

                Text(String(format: NSLocalizedString("tomato.garden.count", comment: ""), count))
                    .font(.body.weight(.semibold))
                    .foregroundColor(themeManager.primaryText)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(themeManager.cardBackground.opacity(0.5))
        )
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let themeManager: ThemeManager
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : themeManager.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? DesignTokens.Colors.Cute.peach : themeManager.cardBackground)
                )
        }
    }
}

struct TomatoCard: View {
    let tomato: Tomato
    let themeManager: ThemeManager
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(tomato.type.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            Text(tomato.type.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(themeManager.primaryText)

            VStack(spacing: 4) {
                Text(tomato.formattedDuration)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)

                Text(tomato.formattedDate)
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
            }
        }
    }
}

// MARK: - Preview

struct TomatoGardenView_Previews: PreviewProvider {
    static var previews: some View {
        TomatoGardenView()
    }
}
