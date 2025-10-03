//
//  HomeView.swift
//  StudyAI
//
//  Enhanced UI Implementation
//

import SwiftUI
import os.log
import Lottie

struct HomeView: View {
    let onSelectTab: (MainTab) -> Void
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var userName = UserDefaults.standard.string(forKey: "user_name") ?? "Student"
    @State private var navigateToSession = false
    @State private var showingProfile = false
    @State private var showingMistakeReview = false
    @State private var showingQuestionGeneration = false
    @State private var showingParentReports = false

    private let logger = Logger(subsystem: "com.studyai", category: "HomeView")

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Engaging Hero Header with Animation, Avatar, Greeting & Stats
                    engagingHeroHeader
                        .padding(.bottom, DesignTokens.Spacing.cardSpacing)

                    // Quick Actions Grid (2x2) - now includes Homework Grader
                    quickActionsSection
                        .padding(.bottom, DesignTokens.Spacing.xxl)  // Increased spacing before horizontal buttons

                    // Additional Actions (Practice, Mistake Review, Parent Reports)
                    additionalActionsSection

                    Spacer(minLength: 100)
                }
                .padding(.vertical, DesignTokens.Spacing.md)
            }
            .background(
                // Holographic gradient background - as a background layer
                LottieView(
                    animationName: "Holographic gradient",
                    loopMode: .loop,
                    animationSpeed: 1.5
                )
                .scaleEffect(1.5)  // Scale factor - adjust this value
                .opacity(0.8)
                .ignoresSafeArea()
            )
            .background(DesignTokens.Colors.surface.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                // HomeView appeared
            }
            .sheet(isPresented: $showingProfile) {
                ModernProfileView(onLogout: {
                    AuthenticationService.shared.signOut()
                    showingProfile = false
                })
            }
            .sheet(isPresented: $showingMistakeReview) {
                MistakeReviewView()
            }
            .sheet(isPresented: $showingQuestionGeneration) {
                QuestionGenerationView()
            }
            .sheet(isPresented: $showingParentReports) {
                ParentReportsView()
            }
        }
    }

    // MARK: - Engaging Hero Header
    private var engagingHeroHeader: some View {
        VStack(spacing: 0) {
            // Greeting card with gradient background
            ZStack(alignment: .topTrailing) {
                // Brighter gradient background card
                // cornerRadius controls rounded corners (default: 24pt)
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            // New gradient: sky-400 -> blue-500 -> indigo-600
                            colors: [
                                Color(hex: "38BDF8"),  // sky-400
                                Color(hex: "3B82F6"),  // blue-500
                                Color(hex: "4F46E5")   // indigo-600
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )

                        // Original gradient (commented out for easy recovery)
                        // LinearGradient(
                        //     colors: [Color(hex: "60A5FA"), Color(hex: "3B82F6")],
                        //     startPoint: .topLeading,
                        //     endPoint: .bottomTrailing
                        // )
                    )
                    .shadow(color: DesignTokens.Colors.aiBlue.opacity(0.4), radius: 12, x: 0, y: 6)

                // Content inside the greeting card
                // VStack spacing controls gap between greeting and stats
                VStack(spacing: DesignTokens.Spacing.sm) {
                    // Compact greeting section
                    HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
                        Spacer()
                            .frame(width: 8)  // Space before animation - adjust this value

                        // User Avatar - AI Spiral Loading animation
                        LottieView(
                            animationName: "AI Spiral Loading",
                            loopMode: .loop,
                            animationSpeed: 1.0
                        )
                        .frame(width: 10, height: 10)  // Avatar size (default: 40pt)
                        .scaleEffect(0.1)

                        // Original white circle avatar (commented out for easy recovery)
                        // Circle()
                        //     .fill(Color.white)
                        //     .frame(width: 40, height: 40)
                        //     .overlay(
                        //         Text(String(userName.prefix(1)).uppercased())
                        //             .font(DesignTokens.Typography.subheadline)
                        //             .foregroundColor(DesignTokens.Colors.aiBlue)
                        //             .fontWeight(.bold)
                        //     )

                        // Compact Greeting
                        // Font sizes: .caption2 (smaller), .subheadline (medium), .title3 (larger)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(greetingText)
                                .font(DesignTokens.Typography.caption2)
                                .foregroundColor(.white.opacity(0.9))

                            Text(userName)
                                .font(DesignTokens.Typography.subheadline)
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        .padding(.leading, 26)  // Move text to the right - adjust this value

                        Spacer()
                    }

                    // Today's Progress Stats inside the card
                    HStack(spacing: DesignTokens.Spacing.md) {
                        if let todayProgress = pointsManager.todayProgress {
                            StatBadge(
                                icon: "questionmark.circle.fill",
                                value: "\(todayProgress.totalQuestions)",
                                label: "Questions",
                                color: .white
                            )

                            StatBadge(
                                icon: "target",
                                value: "\(Int(todayProgress.accuracy))%",
                                label: "Accuracy",
                                color: .white
                            )

                            StatBadge(
                                icon: "flame.fill",
                                value: "\(pointsManager.currentStreak)",
                                label: "Streak",
                                color: .white
                            )
                        } else {
                            Text("Start learning to track progress")
                                .font(DesignTokens.Typography.caption2)
                                .foregroundColor(.white.opacity(0.8))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xs)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(10)
                }
                .padding(DesignTokens.Spacing.md)  // Internal padding inside the card

                // Settings button in top-right corner
                Button(action: { showingProfile = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .padding(DesignTokens.Spacing.sm)
            }
            .frame(height: 110)  // Total height of the greeting card (adjust if needed)
            .padding(.top, DesignTokens.Spacing.md)  // Top spacing - reduced to move greeting up
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)  // Left and right margins
    }

    // MARK: - Motivational Message
    private var motivationalMessage: String {
        let messages = [
            "Let's make today count! 💪",
            "Ready to learn something new? 🌟",
            "Keep up the great work! 🎯",
            "You're doing amazing! ⭐",
            "Time to shine! ✨"
        ]
        let hour = Calendar.current.component(.hour, from: Date())
        let index = hour % messages.count
        return messages[index]
    }

    // MARK: - Helper Properties
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - StatBadge Component
struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 12))

                Text(value)
                    .font(DesignTokens.Typography.title3)
                    .foregroundColor(color)
                    .fontWeight(.bold)
            }

            Text(label)
                .font(DesignTokens.Typography.caption2)
                .foregroundColor(color.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quick Actions Section
extension HomeView {
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md)
            ], spacing: DesignTokens.Spacing.md) {

                QuickActionCard_New(
                    icon: "camera.fill",
                    title: "Homework Grader",
                    subtitle: "Scan & grade",
                    color: DesignTokens.Colors.aiBlue,
                    action: { onSelectTab(.grader) }
                )

                QuickActionCard_New(
                    icon: "message.fill",
                    title: "Chat Session",
                    subtitle: "Conversational AI",
                    color: DesignTokens.Colors.aiBlue,
                    action: { onSelectTab(.chat) }
                )

                QuickActionCard_New(
                    icon: "books.vertical.fill",
                    title: "Library",
                    subtitle: "Study sessions",
                    color: DesignTokens.Colors.libraryTeal,
                    action: { onSelectTab(.library) }
                )

                QuickActionCard_New(
                    icon: "chart.bar.fill",
                    title: "Progress",
                    subtitle: "Track learning",
                    color: DesignTokens.Colors.analyticsPlum,
                    action: { onSelectTab(.progress) }
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - Additional Actions Section
    private var additionalActionsSection: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            HorizontalActionButton(
                icon: "brain.head.profile.fill",
                title: "Practice",
                subtitle: "Generate questions & test yourself",
                color: DesignTokens.Colors.learningGreen,
                action: { showingQuestionGeneration = true }
            )

            HorizontalActionButton(
                icon: "arrow.uturn.backward.circle.fill",
                title: "Mistake Review",
                subtitle: "Learn from past errors",
                color: DesignTokens.Colors.reviewOrange,
                action: { showingMistakeReview = true }
            )

            HorizontalActionButton(
                icon: "doc.text.fill",
                title: "Parent Reports",
                subtitle: "Study progress & insights",
                color: DesignTokens.Colors.analyticsPlum,
                action: { showingParentReports = true }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
    }
}

// MARK: - Quick Action Card New
struct QuickActionCard_New: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false
    @State private var rotationAngle: Double = 0
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Button(action: {
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Trigger press animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(isPressed ? 0.3 : 0.15))
                        .frame(width: 50, height: 50)
                        .scaleEffect(isPressed ? 0.9 : 1.0)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(isPressed ? color.opacity(0.7) : color)
                        .rotationEffect(.degrees(rotationAngle))
                        .scaleEffect(scale)
                }
                .onAppear {
                    // Gentle floating animation
                    withAnimation(
                        Animation.easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                    ) {
                        scale = 1.05
                    }

                    // Slight rotation animation for some visual interest
                    withAnimation(
                        Animation.easeInOut(duration: 3.0)
                            .repeatForever(autoreverses: true)
                    ) {
                        rotationAngle = 3
                    }
                }

                VStack(spacing: 4) {
                    Text(title)
                        .font(DesignTokens.Typography.title3)
                        .foregroundColor(.primary)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(isPressed ? color.opacity(0.05) : DesignTokens.Colors.cardBackground)
            .cornerRadius(16)
            .shadow(
                color: isPressed ? color.opacity(0.3) : Color.black.opacity(0.05),
                radius: isPressed ? 8 : 4,
                x: 0,
                y: isPressed ? 4 : 2
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Horizontal Action Button
struct HorizontalActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    @State private var isPressed = false
    @State private var iconScale: CGFloat = 1.0
    @State private var iconRotation: Double = 0

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Trigger press animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(color.opacity(isPressed ? 0.3 : 0.15))
                        .frame(width: 50, height: 50)
                        .scaleEffect(isPressed ? 0.9 : 1.0)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(isPressed ? color.opacity(0.7) : color)
                        .scaleEffect(iconScale)
                        .rotationEffect(.degrees(iconRotation))
                }
                .onAppear {
                    // Gentle pulse animation
                    withAnimation(
                        Animation.easeInOut(duration: 2.5)
                            .repeatForever(autoreverses: true)
                    ) {
                        iconScale = 1.08
                    }

                    // Slight rotation animation
                    withAnimation(
                        Animation.easeInOut(duration: 3.5)
                            .repeatForever(autoreverses: true)
                    ) {
                        iconRotation = 4
                    }
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DesignTokens.Typography.title3)
                        .foregroundColor(.primary)
                        .fontWeight(.medium)

                    Text(subtitle)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .offset(x: isPressed ? 3 : 0)
            }
            .padding(16)
            .background(isPressed ? color.opacity(0.05) : DesignTokens.Colors.cardBackground)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: isPressed ? 2.0 : 1.5, dash: [5, 3])
                    )
                    .foregroundColor(isPressed ? color.opacity(0.6) : color.opacity(0.3))
            )
            .shadow(
                color: isPressed ? color.opacity(0.2) : Color.black.opacity(0.03),
                radius: isPressed ? 6 : 2,
                x: 0,
                y: isPressed ? 3 : 1
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    HomeView(onSelectTab: { _ in })
}