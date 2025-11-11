//
//  TomatoPokedexView.swift
//  StudyAI
//
//  番茄图鉴 - 展示所有番茄类型的收集情况
//

import SwiftUI

struct TomatoPokedexView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var gardenService = TomatoGardenService.shared
    @State private var showPhysicsGarden = false
    @State private var showExchangeView = false

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark ? [
                        Color(red: 0.05, green: 0.05, blue: 0.1),
                        Color(red: 0.1, green: 0.1, blue: 0.15)
                    ] : [
                        Color(red: 0.95, green: 0.97, blue: 1.0),
                        Color(red: 0.90, green: 0.95, blue: 0.98)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Collection Progress Header
                        collectionProgressCard

                        // Exchange Section
                        exchangeSection

                        // Pokedex Grid
                        pokedexGrid

                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationTitle("🍅 番茄图鉴")
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
            .fullScreenCover(isPresented: $showExchangeView) {
                TomatoExchangeView()
            }
        }
    }

    // MARK: - Collection Progress Card

    private var collectionProgressCard: some View {
        VStack(spacing: 16) {
            // Progress Bar
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("收集进度")
                    .font(.headline)
                Spacer()
                Text("\(gardenService.stats.unlockedCount)/\(TomatoType.allCases.count)")
                    .font(.headline)
                    .foregroundColor(.blue)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 20)

                    // Progress
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(gardenService.stats.collectionProgress / 100), height: 20)
                }
            }
            .frame(height: 20)

            // Stats Row
            HStack(spacing: 20) {
                StatBubble(icon: "🍅", value: "\(gardenService.stats.totalTomatoes)", label: "总数量")
                StatBubble(icon: "⏱️", value: gardenService.stats.formattedTotalTime, label: "专注时长")
                StatBubble(icon: "🔥", value: String(format: "%.0f%%", gardenService.stats.collectionProgress), label: "完成度")
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }

    // MARK: - Exchange Section

    private var exchangeSection: some View {
        Button(action: { showExchangeView = true }) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.3), .red.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("番茄兑换工坊")
                        .font(.headline)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)

                    Text("5个番茄兑换更高级别")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                    .shadow(color: .orange.opacity(0.2), radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Pokedex Grid

    private var pokedexGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            ForEach(TomatoType.allCases, id: \.self) { type in
                PokedexCard(
                    tomatoType: type,
                    count: gardenService.stats.count(for: type),
                    isUnlocked: gardenService.stats.isUnlocked(type),
                    colorScheme: colorScheme
                )
            }
        }
    }
}

// MARK: - Pokedex Card

struct PokedexCard: View {
    let tomatoType: TomatoType
    let count: Int
    let isUnlocked: Bool
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 12) {
            // Tomato Image or Locked State
            ZStack {
                // Background Circle
                Circle()
                    .fill(isUnlocked ? AnyShapeStyle(rarityGradient) : AnyShapeStyle(Color.gray.opacity(0.2)))
                    .frame(width: 120, height: 120)

                if isUnlocked {
                    // Show actual tomato image
                    Image(tomatoType.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                } else {
                    // Show locked state
                    VStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text("未获得")
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }

                // Count Badge (top-right corner)
                if isUnlocked {
                    VStack {
                        HStack {
                            Spacer()
                            Text("×\(count)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.6))
                                )
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .frame(height: 120)

            // Name and Rarity
            VStack(spacing: 4) {
                Text(tomatoType.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .primary)

                if isUnlocked {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(rarityColor)
                        Text(tomatoType.rarityLabel)
                            .font(.caption)
                            .foregroundColor(rarityColor)
                    }
                } else {
                    Text("???")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.5))
                }
            }

            // Description
            if isUnlocked {
                Text(tomatoType.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isUnlocked ? rarityColor.opacity(0.3) : Color.clear, lineWidth: 2)
        )
    }

    private var rarityGradient: LinearGradient {
        LinearGradient(
            colors: [rarityColor.opacity(0.3), rarityColor.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var rarityColor: Color {
        switch tomatoType.rarityColor {
        case "gray":
            return .gray
        case "blue":
            return .blue
        case "purple":
            return .purple
        case "orange":
            return .orange
        default:
            return .gray
        }
    }
}

// MARK: - Exchange Card

struct ExchangeCard: View {
    let fromIcon: String
    let fromLabel: String
    let fromCount: Int
    let toIcon: String
    let toLabel: String
    let requirement: Int
    let canExchange: Bool
    let colorScheme: ColorScheme
    let onExchange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // From Tomato
            VStack(spacing: 4) {
                Text(fromIcon)
                    .font(.system(size: 32))
                Text(fromLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("×\(fromCount)")
                    .font(.caption2.bold())
                    .foregroundColor(canExchange ? .green : .red)
            }
            .frame(width: 80)

            // Arrow and Requirement
            VStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text("\(requirement)个兑换1个")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 100)

            // To Tomato
            VStack(spacing: 4) {
                Text(toIcon)
                    .font(.system(size: 32))
                Text(toLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80)

            Spacer()

            // Exchange Button
            Button(action: onExchange) {
                Text("兑换")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canExchange ? Color.orange : Color.gray)
                    )
            }
            .disabled(!canExchange)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(canExchange ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Stat Bubble

private struct StatBubble: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 24))
            Text(value)
                .font(.system(size: 14, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

struct TomatoPokedexView_Previews: PreviewProvider {
    static var previews: some View {
        TomatoPokedexView()
    }
}
