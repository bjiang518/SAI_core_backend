//
//  AchievementNotificationView.swift
//  StudyAI
//
//  Created by Claude Code on 9/18/25.
//

import SwiftUI

struct AchievementNotificationView: View {
    let achievement: [String: Any]
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var scale: CGFloat = 0.5
    @State private var rotation: Double = -10
    
    var body: some View {
        VStack(spacing: 16) {
            // Achievement Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.yellow.opacity(0.8), .orange.opacity(0.6)],
                            center: .center,
                            startRadius: 10,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .yellow.opacity(0.5), radius: 10, x: 0, y: 5)
                
                Image(systemName: achievement["icon"] as? String ?? "trophy.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(rotation))
            }
            
            // Achievement Text
            VStack(spacing: 8) {
                Text("🎉 Achievement Unlocked!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(achievement["achievement_name"] as? String ?? "New Achievement")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                if let description = achievement["description"] as? String {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                
                // XP Reward
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                    
                    Text("+\(achievement["xp_reward"] as? Int ?? 0) XP")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(16)
            }
            
            // Dismiss Button
            Button("Amazing!") {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    isVisible = false
                    scale = 0.1
                    rotation = 360
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        )
        .scaleEffect(isVisible ? 1.0 : 0.8)
        .opacity(isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                isVisible = true
                scale = 1.2
                rotation = 5
            }
            
            // Secondary animation for icon
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    scale = 1.0
                    rotation = 0
                }
            }
            
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if isVisible {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        isVisible = false
                        scale = 0.1
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Achievement Notification Overlay
struct AchievementNotificationOverlay: ViewModifier {
    @State private var achievements: [[String: Any]] = []
    @State private var currentAchievement: [String: Any]?
    @State private var showingNotification = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if showingNotification, let achievement = currentAchievement {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                dismissCurrentNotification()
                            }
                        
                        AchievementNotificationView(
                            achievement: achievement,
                            onDismiss: dismissCurrentNotification
                        )
                    }
                }
            )
            .onReceive(NotificationCenter.default.publisher(for: .achievementUnlocked)) { notification in
                if let achievement = notification.object as? [String: Any] {
                    showAchievement(achievement)
                }
            }
    }
    
    private func showAchievement(_ achievement: [String: Any]) {
        achievements.append(achievement)
        showNextAchievement()
    }
    
    private func showNextAchievement() {
        guard !showingNotification, !achievements.isEmpty else { return }
        
        currentAchievement = achievements.removeFirst()
        showingNotification = true
    }
    
    private func dismissCurrentNotification() {
        showingNotification = false
        currentAchievement = nil
        
        // Show next achievement if any
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            showNextAchievement()
        }
    }
}

// MARK: - View Extension
extension View {
    func achievementNotifications() -> some View {
        self.modifier(AchievementNotificationOverlay())
    }
}

// MARK: - Notification Extension
extension Notification.Name {
    static let achievementUnlocked = Notification.Name("AchievementUnlocked")
}

// MARK: - Achievement Manager
class AchievementManager: ObservableObject {
    static let shared = AchievementManager()
    
    private init() {}
    
    func showAchievement(_ achievement: [String: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .achievementUnlocked,
                object: achievement
            )
        }
    }
}

#Preview {
    let sampleAchievement: [String: Any] = [
        "achievement_name": "First Steps",
        "description": "Answer your first question",
        "icon": "questionmark.circle.fill",
        "xp_reward": 25,
        "rarity": "common"
    ]
    
    return ZStack {
        Color.blue.opacity(0.3)
            .ignoresSafeArea()
        
        AchievementNotificationView(
            achievement: sampleAchievement,
            onDismiss: {}
        )
    }
}