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
    @StateObject private var greetingVoice = GreetingVoiceService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @ObservedObject private var profileService = ProfileService.shared
    @State private var userName = ""
    @State private var navigateToSession = false
    @State private var showingProfile = false
    @State private var showingMistakeReview = false
    @State private var showingQuestionGeneration = false
    @State private var showingParentReports = false
    @State private var blinkingOpacity: Double = 1.0  // For blinking animation during preload

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
                // Load user name from ProfileService - prefer displayName over fullName
                if let profile = profileService.currentProfile {
                    userName = profile.displayName ?? profile.fullName
                } else if let cachedProfile = profileService.loadCachedProfile() {
                    userName = cachedProfile.displayName ?? cachedProfile.fullName
                } else {
                    userName = "there"
                }
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
        VStack(spacing: DesignTokens.Spacing.md) {
            // Greeting card with gradient background - synced with voice type
            ZStack(alignment: .trailing) {
                // Dynamic gradient based on selected voice type
                // cornerRadius controls rounded corners (default: 24pt)
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: greetingVoice.currentVoiceType == .adam ? [
                                // Adam (blue): sky-400 -> blue-500 -> indigo-600
                                Color(hex: "38BDF8"),
                                Color(hex: "3B82F6"),
                                Color(hex: "4F46E5")
                            ] : [
                                // Eva (purple): fuchsia-300 -> purple-500 -> violet-600
                                Color(hex: "F0ABFC"),
                                Color(hex: "A855F7"),
                                Color(hex: "7C3AED")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(
                        color: (greetingVoice.currentVoiceType == .adam ?
                            DesignTokens.Colors.aiBlue : Color.purple).opacity(0.4),
                        radius: 12,
                        x: 0,
                        y: 6
                    )

                // Content inside the greeting card - only greeting now
                HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                    Spacer()
                        .frame(width: 8)  // Space before animation - adjust this value

                    // User Avatar - AI Spiral Loading animation - ENLARGED and INTERACTIVE
                    Button(action: {
                        // Don't allow tap if preloading
                        guard !greetingVoice.isPreloading else {
                            print("🎤 HomeView: Ignoring tap - still preloading")
                            return
                        }

                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()

                        // Speak random greeting
                        greetingVoice.speakRandomGreeting()
                    }) {
                        ZStack {
                            // Idle animation - AI Spiral Loading (slow, normal size)
                            if !greetingVoice.isSpeaking && !greetingVoice.isPreloading {
                                LottieView(
                                    animationName: "AI Spiral Loading",
                                    loopMode: .loop,
                                    animationSpeed: 0.5  // Slow when idle
                                )
                                .frame(width: 60, height: 60)
                                .scaleEffect(0.17)
                                .transition(.opacity)
                            }

                            // Preloading animation - AI Spiral Loading (fast, small, blinking)
                            if greetingVoice.isPreloading {
                                LottieView(
                                    animationName: "AI Spiral Loading",
                                    loopMode: .loop,
                                    animationSpeed: 2.5  // Fast when preloading/thinking
                                )
                                .frame(width: 60, height: 60)
                                .scaleEffect(0.12)  // Smaller during preloading
                                .opacity(blinkingOpacity)  // Blinking effect
                                .transition(.opacity)
                                .onAppear {
                                    // Start blinking animation
                                    withAnimation(
                                        Animation.easeInOut(duration: 0.6)
                                            .repeatForever(autoreverses: true)
                                    ) {
                                        blinkingOpacity = 0.3
                                    }
                                }
                                .onDisappear {
                                    // Reset opacity when preloading finishes
                                    blinkingOpacity = 1.0
                                }
                            }

                            // Speaking animation - Wave Animation (fast)
                            if greetingVoice.isSpeaking {
                                LottieView(
                                    animationName: "Wave Animation",
                                    loopMode: .loop,
                                    animationSpeed: 2.5  // Fast wave animation
                                )
                                .frame(width: 60, height: 60)
                                .scaleEffect(0.18)  // Much smaller - similar to idle spiral
                                .transition(.opacity)
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: greetingVoice.isSpeaking)
                        .animation(.easeInOut(duration: 0.3), value: greetingVoice.isPreloading)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(greetingVoice.isPreloading)  // Disable button during preload

                    // Greeting with larger fonts
                    VStack(alignment: .leading, spacing: 2) {
                        Text(greetingText)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))

                        Text(userName)
                            .font(.title2)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    }
                    .padding(.leading, 8)

                    Spacer()
                }
                .padding(DesignTokens.Spacing.md)  // Internal padding inside the card

                // Settings button - centered vertically on the right edge, enlarged
                Button(action: { showingProfile = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24))  // Enlarged from 18
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 48, height: 48)  // Enlarged from 36x36
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .padding(.trailing, DesignTokens.Spacing.md)
            }
            .frame(height: 90)  // Reduced height since we removed stats
            .padding(.top, DesignTokens.Spacing.md)  // Top spacing - reduced to move greeting up

            // Today's Progress - moved outside the gradient box
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(NSLocalizedString("home.todaysProgress", comment: ""))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                HStack(spacing: DesignTokens.Spacing.md) {
                    if let todayProgress = pointsManager.todayProgress {
                        StatBadge(
                            icon: "questionmark.circle.fill",
                            value: "\(todayProgress.totalQuestions)",
                            label: NSLocalizedString("home.questions", comment: ""),
                            color: DesignTokens.Colors.aiBlue
                        )

                        StatBadge(
                            icon: "target",
                            value: "\(Int(todayProgress.accuracy))%",
                            label: NSLocalizedString("home.accuracy", comment: ""),
                            color: DesignTokens.Colors.learningGreen
                        )

                        StatBadge(
                            icon: "flame.fill",
                            value: "\(pointsManager.currentStreak)",
                            label: NSLocalizedString("home.streak", comment: ""),
                            color: DesignTokens.Colors.reviewOrange
                        )
                    } else {
                        Text("Start learning to track progress")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(DesignTokens.Spacing.md)
                .background(DesignTokens.Colors.cardBackground)
                .cornerRadius(16)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            }
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
        case 0..<12: return NSLocalizedString("home.goodMorning", comment: "")
        case 12..<17: return NSLocalizedString("home.goodAfternoon", comment: "")
        default: return NSLocalizedString("home.goodEvening", comment: "")
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
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 16))

                Text(value)
                    .font(.title)
                    .foregroundColor(color)
                    .fontWeight(.bold)
            }

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
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
                    title: NSLocalizedString("home.homeworkGrader", comment: ""),
                    subtitle: NSLocalizedString("home.scanAndGrade", comment: ""),
                    color: DesignTokens.Colors.homeworkGraderCoral,
                    lottieAnimation: "Checklist",
                    lottieScale: 0.29,  // Adjust this value to change size (0.1 to 1.0)
                    action: { onSelectTab(.grader) }
                )

                QuickActionCard_New(
                    icon: "message.fill",
                    title: NSLocalizedString("home.chat", comment: ""),
                    subtitle: NSLocalizedString("home.conversationalAI", comment: ""),
                    color: DesignTokens.Colors.chatYellow,
                    lottieAnimation: "Chat",
                    lottieScale: 0.2,  // Adjust this value to change size (0.1 to 1.0)
                    action: { onSelectTab(.chat) }
                )

                QuickActionCard_New(
                    icon: "books.vertical.fill",
                    title: NSLocalizedString("home.library", comment: ""),
                    subtitle: NSLocalizedString("home.studySessions", comment: ""),
                    color: DesignTokens.Colors.libraryPurple,
                    lottieAnimation: "Books",
                    lottieScale: 0.12,  // Adjust this value to change size (0.1 to 1.0)
                    action: { onSelectTab(.library) }
                )

                QuickActionCard_New(
                    icon: "chart.bar.fill",
                    title: NSLocalizedString("home.progress", comment: ""),
                    subtitle: NSLocalizedString("home.trackLearning", comment: ""),
                    color: DesignTokens.Colors.progressGreen,
                    lottieAnimation: "Chart Graph",
                    lottieScale: 0.45,  // Adjust this value to change size (0.1 to 1.0)
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
                title: NSLocalizedString("home.practice", comment: ""),
                subtitle: NSLocalizedString("home.practiceDescription", comment: ""),
                color: DesignTokens.Colors.learningGreen,
                action: { showingQuestionGeneration = true }
            )

            HorizontalActionButton(
                icon: "arrow.uturn.backward.circle.fill",
                title: NSLocalizedString("home.mistakeReview", comment: ""),
                subtitle: NSLocalizedString("home.mistakeReviewDescription", comment: ""),
                color: DesignTokens.Colors.reviewOrange,
                action: { showingMistakeReview = true }
            )

            HorizontalActionButton(
                icon: "doc.text.fill",
                title: NSLocalizedString("home.parentReports", comment: ""),
                subtitle: NSLocalizedString("home.parentReportsDescription", comment: ""),
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
    let lottieAnimation: String?  // Optional Lottie animation name
    let lottieScale: CGFloat  // Scale for Lottie animation

    @State private var isPressed = false
    @State private var rotationAngle: Double = 0
    @State private var scale: CGFloat = 1.0

    // Default initializer without Lottie animation
    init(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
        self.lottieAnimation = nil
        self.lottieScale = 1.0
    }

    // Initializer with Lottie animation
    init(icon: String, title: String, subtitle: String, color: Color, lottieAnimation: String, lottieScale: CGFloat = 1.0, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
        self.lottieAnimation = lottieAnimation
        self.lottieScale = lottieScale
    }

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
                    // Only show circular background for SF Symbols, not Lottie
                    if lottieAnimation == nil {
                        Circle()
                            .fill(color.opacity(isPressed ? 0.3 : 0.15))
                            .frame(width: 50, height: 50)
                            .scaleEffect(isPressed ? 0.9 : 1.0)
                    }

                    // Use Lottie animation if provided, otherwise use SF Symbol
                    if let animationName = lottieAnimation {
                        LottieView(
                            animationName: animationName,
                            loopMode: .loop,
                            animationSpeed: 1.0
                        )
                        .frame(width: 50, height: 50)
                        .scaleEffect(isPressed ? lottieScale * 0.95 : lottieScale)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(isPressed ? color.opacity(0.7) : color)
                            .rotationEffect(.degrees(rotationAngle))
                            .scaleEffect(scale)
                    }
                }
                .onAppear {
                    // Only apply animations to SF Symbols, not Lottie animations
                    if lottieAnimation == nil {
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
            .background(
                ZStack {
                    // White card background
                    DesignTokens.Colors.cardBackground

                    // Subtle gradient overlay with the card's color
                    LinearGradient(
                        colors: [
                            color.opacity(0.12),
                            color.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .cornerRadius(18)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                color.opacity(isPressed ? 0.5 : 0.3),
                                color.opacity(isPressed ? 0.3 : 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isPressed ? 2.5 : 1.5
                    )
            )
            .shadow(
                color: color.opacity(isPressed ? 0.4 : 0.2),
                radius: isPressed ? 16 : 10,
                x: 0,
                y: isPressed ? 8 : 5
            )
            .shadow(
                color: Color.black.opacity(0.06),
                radius: 3,
                x: 0,
                y: 2
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
