//
//  TomatoGardenView.swift
//  StudyAI
//
//  我的番茄园 - 展示用户收集的所有番茄
//

import SwiftUI

struct TomatoGardenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var gardenService = TomatoGardenService.shared

    @State private var selectedFilter: FilterOption = .all
    @State private var showDeleteConfirmation = false
    @State private var tomatoToDelete: Tomato?
    @State private var showPhysicsGarden = false

    enum FilterOption: String, CaseIterable {
        case all = "全部"
        case today = "今天"
        case week = "本周"
        case classic = "经典番茄"
        case curly = "卷藤番茄"
        case cute = "萌萌番茄"
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(colorScheme == .dark ? .systemGroupedBackground : .systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // 统计卡片
                        statsCard

                        // 筛选器
                        filterSection

                        // 番茄网格
                        tomatoGrid

                        // 成就提示
                        if let milestone = gardenService.getNextMilestone() {
                            nextMilestoneCard(milestone: milestone)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("我的番茄园")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showPhysicsGarden = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("物理模式")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.purple)
                    }
                }
            }
            .fullScreenCover(isPresented: $showPhysicsGarden) {
                PhysicsTomatoGardenView()
            }
            .alert("删除番茄", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let tomato = tomatoToDelete {
                        gardenService.removeTomato(id: tomato.id)
                    }
                }
            } message: {
                Text("确定要删除这个番茄吗？")
            }
        }
    }

    // MARK: - Stats Card

    private var statsCard: some View {
        VStack(spacing: 16) {
            // 标题
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.red)
                Text("番茄园统计")
                    .font(.headline)
                Spacer()
            }

            // 统计网格
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                TomatoStatItem(
                    icon: "🍅",
                    value: "\(gardenService.stats.totalTomatoes)",
                    label: "总番茄数"
                )

                TomatoStatItem(
                    icon: "⏱️",
                    value: gardenService.stats.formattedTotalTime,
                    label: "总专注时间"
                )

                TomatoStatItem(
                    icon: "⭐️",
                    value: formatDuration(gardenService.stats.longestSession),
                    label: "最长专注"
                )
            }

            // 番茄类型分布
            HStack(spacing: 12) {
                TomatoTypeCount(type: .classic, count: gardenService.stats.classicCount)
                TomatoTypeCount(type: .curly, count: gardenService.stats.curlyCount)
                TomatoTypeCount(type: .cute, count: gardenService.stats.cuteCount)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FilterOption.allCases, id: \.self) { option in
                    FilterChip(
                        title: option.rawValue,
                        isSelected: selectedFilter == option,
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
                        TomatoCard(tomato: tomato) {
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
                .foregroundColor(.gray.opacity(0.3))

            Text("还没有番茄")
                .font(.title3.weight(.medium))
                .foregroundColor(.secondary)

            Text("完成专注即可获得可爱的番茄奖励")
                .font(.body)
                .foregroundColor(.secondary)
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
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text("下一个里程碑")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(milestone.description)
                    .font(.body.weight(.semibold))

                Text("还需要 \(remaining) 个番茄")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 进度环
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                    .frame(width: 50, height: 50)

                Circle()
                    .trim(from: 0, to: CGFloat(gardenService.stats.totalTomatoes) / CGFloat(milestone.count))
                    .stroke(Color.orange, lineWidth: 4)
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                Text("\(Int((Double(gardenService.stats.totalTomatoes) / Double(milestone.count)) * 100))%")
                    .font(.caption2.weight(.bold))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
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
            return "\(minutes)分"
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

    var body: some View {
        VStack(spacing: 8) {
            Text(icon)
                .font(.system(size: 32))

            Text(value)
                .font(.title3.weight(.bold))

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TomatoTypeCount: View {
    let type: TomatoType
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(type.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(count)个")
                    .font(.body.weight(.semibold))
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? Color.red : Color.gray.opacity(0.1))
                )
        }
    }
}

struct TomatoCard: View {
    let tomato: Tomato
    let onDelete: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            // 番茄图片
            Image(tomato.type.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)

            // 类型名称
            Text(tomato.type.displayName)
                .font(.caption.weight(.medium))

            // 时间和日期
            VStack(spacing: 4) {
                Text(tomato.formattedDuration)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(tomato.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
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
