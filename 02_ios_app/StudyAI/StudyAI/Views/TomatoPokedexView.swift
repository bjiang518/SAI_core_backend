//
//  TomatoPokedexView.swift
//  StudyAI
//
//  番茄图鉴 - 展示所有番茄类型的收集情况
//

import SwiftUI

struct TomatoPokedexView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var gardenService = TomatoGardenService.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var showPhysicsGarden = false
    @State private var showExchangeView = false

    var body: some View {
        NavigationView {
            ZStack {
                themeManager.backgroundColor
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
            .navigationTitle(NSLocalizedString("tomato.garden.collection", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(themeManager.secondaryText)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
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
                    .foregroundColor(DesignTokens.Colors.Cute.yellow)
                Text(NSLocalizedString("tomato.garden.collectionProgress", comment: ""))
                    .font(.headline)
                    .foregroundColor(themeManager.primaryText)
                Spacer()
                Text("\(gardenService.stats.unlockedCount)/\(TomatoType.allCases.count)")
                    .font(.headline)
                    .foregroundColor(DesignTokens.Colors.Cute.blue)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(themeManager.secondaryText.opacity(0.2))
                        .frame(height: 20)

                    // Progress
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [DesignTokens.Colors.Cute.blue, DesignTokens.Colors.Cute.lavender],
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
                StatBubble(icon: "🍅", value: "\(gardenService.stats.totalTomatoes)", label: NSLocalizedString("tomato.garden.total", comment: ""), themeManager: themeManager)
                StatBubble(icon: "⏱️", value: gardenService.stats.formattedTotalTime, label: NSLocalizedString("tomato.garden.focusTime", comment: ""), themeManager: themeManager)
                StatBubble(icon: "🔥", value: String(format: "%.0f%%", gardenService.stats.collectionProgress), label: NSLocalizedString("tomato.garden.collectionProgress", comment: ""), themeManager: themeManager)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.cardBackground)
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
                                colors: [DesignTokens.Colors.Cute.peach.opacity(0.3), DesignTokens.Colors.Cute.pink.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 28))
                        .foregroundColor(DesignTokens.Colors.Cute.peach)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("tomato.garden.exchange.title", comment: ""))
                        .font(.headline)
                        .foregroundColor(themeManager.primaryText)

                    Text(NSLocalizedString("tomato.garden.exchange.5to1", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(themeManager.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignTokens.Colors.Cute.peach)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(themeManager.cardBackground)
                    .shadow(color: DesignTokens.Colors.Cute.peach.opacity(0.2), radius: 10, x: 0, y: 5)
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
                    themeManager: themeManager
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
    let themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 12) {
            // Tomato Image or Locked State
            ZStack {
                // Background Circle
                Circle()
                    .fill(isUnlocked ? AnyShapeStyle(rarityGradient) : AnyShapeStyle(themeManager.secondaryText.opacity(0.2)))
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
                            .foregroundColor(themeManager.secondaryText.opacity(0.5))
                        Text(NSLocalizedString("tomato.garden.locked", comment: ""))
                            .font(.caption)
                            .foregroundColor(themeManager.secondaryText.opacity(0.7))
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
                    .foregroundColor(themeManager.primaryText)

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
                        .foregroundColor(themeManager.secondaryText.opacity(0.5))
                }
            }

            // Description
            if isUnlocked {
                Text(tomatoType.description)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.cardBackground)
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
            return themeManager.secondaryText
        case "blue":
            return DesignTokens.Colors.Cute.blue
        case "purple":
            return DesignTokens.Colors.Cute.lavender
        case "orange":
            return DesignTokens.Colors.Cute.peach
        default:
            return themeManager.secondaryText
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
    let themeManager: ThemeManager
    let onExchange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // From Tomato
            VStack(spacing: 4) {
                Text(fromIcon)
                    .font(.system(size: 32))
                Text(fromLabel)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)
                Text("×\(fromCount)")
                    .font(.caption2.bold())
                    .foregroundColor(canExchange ? DesignTokens.Colors.Cute.mint : DesignTokens.Colors.Cute.peach)
            }
            .frame(width: 80)

            // Arrow and Requirement
            VStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundColor(DesignTokens.Colors.Cute.peach)
                Text(String(format: NSLocalizedString("tomato.garden.exchangeRequirement", comment: ""), requirement))
                    .font(.caption2)
                    .foregroundColor(themeManager.secondaryText)
            }
            .frame(width: 100)

            // To Tomato
            VStack(spacing: 4) {
                Text(toIcon)
                    .font(.system(size: 32))
                Text(toLabel)
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryText)
            }
            .frame(width: 80)

            Spacer()

            // Exchange Button
            Button(action: onExchange) {
                Text(NSLocalizedString("tomato.garden.exchange", comment: ""))
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canExchange ? DesignTokens.Colors.Cute.peach : themeManager.secondaryText)
                    )
            }
            .disabled(!canExchange)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(themeManager.cardBackground.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(canExchange ? DesignTokens.Colors.Cute.peach.opacity(0.3) : themeManager.secondaryText.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Stat Bubble

private struct StatBubble: View {
    let icon: String
    let value: String
    let label: String
    let themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 24))
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(themeManager.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundColor(themeManager.secondaryText)
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
