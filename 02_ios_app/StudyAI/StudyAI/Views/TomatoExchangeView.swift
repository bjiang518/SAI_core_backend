//
//  TomatoExchangeView.swift
//  StudyAI
//
//  Enhanced tomato exchange interface with selection, animation, and haptics
//

import SwiftUI

struct TomatoExchangeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var gardenService = TomatoGardenService.shared

    @State private var selectedRarity: Int = 1  // 1=普通, 2=稀有, 3=超稀有
    @State private var selectedTomatoes: Set<String> = []
    @State private var showingExchangeAnimation = false
    @State private var showingRewardPopup = false
    @State private var rewardedTomato: Tomato?
    @State private var isExchanging = false

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
                        // Header
                        headerSection

                        // Rarity Selector
                        raritySelector

                        // Exchange Box
                        exchangeBox

                        // Tomato Selection Grid
                        tomatoSelectionGrid

                        Spacer(minLength: 20)
                    }
                    .padding()
                }

                // Exchange Animation Overlay
                if showingExchangeAnimation {
                    exchangeAnimationView
                }
            }
            .navigationTitle("番茄兑换")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingRewardPopup) {
                if let tomato = rewardedTomato {
                    TomatoRewardPopup(tomato: tomato) {
                        showingRewardPopup = false
                        rewardedTomato = nil
                        selectedTomatoes.removeAll()
                    }
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("番茄兑换工坊")
                .font(.title2.bold())
                .foregroundColor(colorScheme == .dark ? .white : .primary)

            Text("选择5个同等级番茄，兑换更高等级番茄")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    // MARK: - Rarity Selector

    private var raritySelector: some View {
        HStack(spacing: 12) {
            rarityButton(rarity: 1, icon: "R", label: "普通", color: .gray)
            rarityButton(rarity: 2, icon: "S", label: "稀有", color: .blue)
            rarityButton(rarity: 3, icon: "SS", label: "超稀有", color: .purple)
        }
        .padding(.horizontal)
    }

    private func rarityButton(rarity: Int, icon: String, label: String, color: Color) -> some View {
        Button(action: {
            selectedRarity = rarity
            selectedTomatoes.removeAll()
        }) {
            VStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(selectedRarity == rarity ? .white : color)

                Text(label)
                    .font(.caption.bold())
                    .foregroundColor(selectedRarity == rarity ? .white : (colorScheme == .dark ? .white.opacity(0.7) : .primary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedRarity == rarity ? color : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selectedRarity == rarity ? color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Exchange Box

    private var exchangeBox: some View {
        VStack(spacing: 20) {
            // Progress indicator
            HStack(spacing: 12) {
                ForEach(0..<5) { index in
                    ZStack {
                        Circle()
                            .fill(index < selectedTomatoes.count ? rarityColor(selectedRarity) : Color.gray.opacity(0.2))
                            .frame(width: 50, height: 50)

                        if index < selectedTomatoes.count {
                            Text(rarityIcon(selectedRarity))
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        } else {
                            Image(systemName: "plus")
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    }
                }
            }

            // Arrow
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            // Result preview
            ZStack {
                Circle()
                    .fill(selectedTomatoes.count == 5 ? rarityColor(selectedRarity + 1).opacity(0.2) : Color.gray.opacity(0.1))
                    .frame(width: 80, height: 80)

                if selectedTomatoes.count == 5 {
                    Text(rarityIcon(selectedRarity + 1))
                        .font(.system(size: 48, weight: .black, design: .rounded))
                        .foregroundColor(rarityColor(selectedRarity + 1))
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }

            // Exchange button
            Button(action: performExchange) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("兑换番茄")
                        .font(.headline)
                    Image(systemName: "sparkles")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(selectedTomatoes.count == 5 ?
                              LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing) :
                              LinearGradient(colors: [Color.gray.opacity(0.5)], startPoint: .leading, endPoint: .trailing))
                )
                .shadow(color: selectedTomatoes.count == 5 ? Color.orange.opacity(0.5) : Color.clear, radius: 10, x: 0, y: 5)
            }
            .disabled(selectedTomatoes.count != 5 || isExchanging)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white)
                .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
        )
    }

    // MARK: - Tomato Selection Grid

    private var tomatoSelectionGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选择要兑换的番茄（\(selectedTomatoes.count)/5）")
                .font(.headline)
                .foregroundColor(colorScheme == .dark ? .white : .primary)
                .padding(.horizontal, 4)

            let availableTomatoes = getAvailableTomatoes()

            if availableTomatoes.isEmpty {
                emptyStateView
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(availableTomatoes) { tomato in
                        SelectableTomatoCard(
                            tomato: tomato,
                            isSelected: selectedTomatoes.contains(tomato.id),
                            colorScheme: colorScheme
                        ) {
                            toggleSelection(tomato)
                        }
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))

            Text("没有可兑换的番茄")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("完成专注任务获得更多番茄")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Exchange Animation View

    private var exchangeAnimationView: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Spinning rarity icons
                HStack(spacing: -20) {
                    ForEach(0..<5) { _ in
                        Text(rarityIcon(selectedRarity))
                            .font(.system(size: 40, weight: .black, design: .rounded))
                            .foregroundColor(rarityColor(selectedRarity))
                            .rotationEffect(.degrees(isExchanging ? 360 : 0))
                            .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: isExchanging)
                    }
                }

                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .scaleEffect(isExchanging ? 1.2 : 1.0)
                    .animation(Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isExchanging)

                Text("✨ 正在兑换...")
                    .font(.title2.bold())
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Helper Methods

    private func getAvailableTomatoes() -> [Tomato] {
        return gardenService.tomatoes.filter { $0.type.rarity == selectedRarity }
    }

    private func toggleSelection(_ tomato: Tomato) {
        if selectedTomatoes.contains(tomato.id) {
            selectedTomatoes.remove(tomato.id)
        } else {
            if selectedTomatoes.count < 5 {
                selectedTomatoes.insert(tomato.id)
            }
        }
    }

    private func rarityIcon(_ rarity: Int) -> String {
        switch rarity {
        case 1: return "R"
        case 2: return "S"
        case 3: return "SS"
        case 4: return "SSS"
        default: return "R"
        }
    }

    private func rarityColor(_ rarity: Int) -> Color {
        switch rarity {
        case 1: return .gray
        case 2: return .blue
        case 3: return .purple
        case 4: return .orange
        default: return .gray
        }
    }

    private func performExchange() {
        guard selectedTomatoes.count == 5 else { return }

        isExchanging = true
        showingExchangeAnimation = true

        // Haptic feedback - heavy impact
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        // Perform exchange after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Get the tomatoes to remove
            let tomatoesToRemove = gardenService.tomatoes.filter { selectedTomatoes.contains($0.id) }

            // Remove selected tomatoes
            for tomato in tomatoesToRemove {
                gardenService.removeTomato(id: tomato.id)
            }

            // Determine new tomato type
            let newTomatoType: TomatoType
            switch selectedRarity {
            case 1:
                newTomatoType = TomatoType.randomRare()
            case 2:
                newTomatoType = TomatoType.randomSuperRare()
            case 3:
                newTomatoType = .diamond
            default:
                newTomatoType = .classic
            }

            // Create new tomato
            let newTomato = Tomato(
                type: newTomatoType,
                earnedDate: Date(),
                focusDuration: 0
            )

            // Add to garden
            gardenService.tomatoes.append(newTomato)
            gardenService.saveTomatoes()
            gardenService.updateStats()

            // Success haptic
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)

            // Show reward popup
            showingExchangeAnimation = false
            rewardedTomato = newTomato

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingRewardPopup = true
                isExchanging = false
            }
        }
    }
}

// MARK: - Selectable Tomato Card

struct SelectableTomatoCard: View {
    let tomato: Tomato
    let isSelected: Bool
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? rarityColor.opacity(0.3) : (colorScheme == .dark ? Color.white.opacity(0.05) : Color.gray.opacity(0.1)))
                        .frame(width: 70, height: 70)

                    Image(tomato.type.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 55, height: 55)

                    if isSelected {
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .background(Circle().fill(Color.white).padding(2))
                            }
                            Spacer()
                        }
                        .frame(width: 70, height: 70)
                    }
                }

                Text(tomato.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(isSelected ? 0.1 : 0.02) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(isSelected ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var rarityColor: Color {
        switch tomato.type.rarityColor {
        case "gray": return .gray
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        default: return .gray
        }
    }
}

// MARK: - Tomato Reward Popup

struct TomatoRewardPopup: View {
    let tomato: Tomato
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var rotation: Double = 0
    @State private var showingConfetti = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Reward content
                VStack(spacing: 24) {
                    Text("🎉")
                        .font(.system(size: 60))

                    Text("恭喜获得")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.8))

                    // Animated tomato
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [rarityColor.opacity(0.4), rarityColor.opacity(0.1)],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 100
                                )
                            )
                            .frame(width: 200, height: 200)
                            .blur(radius: 20)

                        Image(tomato.type.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(rotation))
                            .scaleEffect(scale)
                    }

                    VStack(spacing: 8) {
                        Text(tomato.type.displayName)
                            .font(.title.bold())
                            .foregroundColor(.white)

                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundColor(rarityColor)
                            Text(tomato.type.rarityLabel)
                                .font(.headline)
                                .foregroundColor(rarityColor)
                        }

                        Text(tomato.type.description)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                Spacer()

                // Close button
                Button(action: onDismiss) {
                    Text("太棒了！")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(rarityColor)
                        )
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }

            // Confetti effect
            if showingConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            // Haptic
            let successFeedback = UINotificationFeedbackGenerator()
            successFeedback.notificationOccurred(.success)

            // Animations
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                scale = 1.0
            }

            withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotation = 360
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingConfetti = true
            }
        }
    }

    private var rarityColor: Color {
        switch tomato.type.rarityColor {
        case "gray": return .gray
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        default: return .gray
        }
    }
}

// MARK: - Confetti View

struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confettiPieces) { piece in
                    Text(piece.emoji)
                        .font(.system(size: 24))
                        .position(piece.position)
                        .opacity(piece.opacity)
                }
            }
            .onAppear {
                generateConfetti(in: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func generateConfetti(in size: CGSize) {
        let emojis = ["🍅", "✨", "⭐️", "💫", "🎉", "🎊"]

        for _ in 0..<50 {
            let randomX = CGFloat.random(in: 0...size.width)
            let randomDelay = Double.random(in: 0...0.5)

            let piece = ConfettiPiece(
                id: UUID(),
                emoji: emojis.randomElement()!,
                position: CGPoint(x: randomX, y: -50),
                opacity: 1.0
            )

            confettiPieces.append(piece)

            withAnimation(Animation.linear(duration: 3).delay(randomDelay)) {
                if let index = confettiPieces.firstIndex(where: { $0.id == piece.id }) {
                    confettiPieces[index].position = CGPoint(
                        x: randomX + CGFloat.random(in: -50...50),
                        y: size.height + 50
                    )
                    confettiPieces[index].opacity = 0
                }
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id: UUID
    let emoji: String
    var position: CGPoint
    var opacity: Double
}

// MARK: - Preview

struct TomatoExchangeView_Previews: PreviewProvider {
    static var previews: some View {
        TomatoExchangeView()
    }
}
