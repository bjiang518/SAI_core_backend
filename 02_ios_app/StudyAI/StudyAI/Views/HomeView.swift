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
    @StateObject private var parentModeManager = ParentModeManager.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @ObservedObject private var profileService = ProfileService.shared
    @State private var userName = ""
    @State private var navigateToSession = false
    @State private var showingProfile = false
    @State private var showingMistakeReview = false
    @State private var showingQuestionGeneration = false
    @State private var showingParentReports = false
    @State private var showingHomeworkAlbum = false  // NEW: Homework Album
    @State private var showingFocusMode = false  // NEW: Focus Mode

    // ✅ Dark Mode Support: Detect current color scheme
    @Environment(\.colorScheme) var colorScheme

    // Parent authentication modals
    @State private var showingParentAuthForChat = false
    @State private var showingParentAuthForGrader = false
    @State private var showingParentAuthForReports = false

    // ✅ Computed properties for today's activity - read directly from PointsEarningManager (matching Progress tab)
    private var todayTotalQuestions: Int {
        pointsManager.todayProgress?.totalQuestions ?? 0
    }

    private var todayCorrectAnswers: Int {
        pointsManager.todayProgress?.correctAnswers ?? 0
    }

    private var todayAccuracy: Double {
        guard let todayProgress = pointsManager.todayProgress else { return 0.0 }
        return todayProgress.accuracy
    }

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
                // Holographic gradient background - adaptive for dark mode
                LottieView(
                    animationName: "Holographic gradient",
                    loopMode: .loop,
                    animationSpeed: 1.5,
                    powerSavingProgress: 0.8  // Background animation pauses at 80%
                )
                .scaleEffect(1.5)
                .opacity(colorScheme == .dark ? 0.25 : 0.8)  // Much dimmer in dark mode
                .blendMode(colorScheme == .dark ? .screen : .normal)  // Screen blend for dark mode
                .ignoresSafeArea()
            )
            .background(DesignTokens.Colors.surface.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                // Load user name from ProfileService - always show display name or first name
                if let profile = profileService.currentProfile {
                    // Determine display name
                    if let displayName = profile.displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        userName = displayName
                    } else if let firstName = profile.firstName, !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        userName = firstName
                    } else {
                        userName = NSLocalizedString("home.defaultStudentName", comment: "")
                    }
                } else if let cachedProfile = profileService.loadCachedProfile() {
                    // Determine display name
                    if let displayName = cachedProfile.displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        userName = displayName
                    } else if let firstName = cachedProfile.firstName, !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        userName = firstName
                    } else {
                        userName = NSLocalizedString("home.defaultStudentName", comment: "")
                    }
                } else {
                    userName = NSLocalizedString("home.defaultStudentName", comment: "")
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
            .sheet(isPresented: $showingHomeworkAlbum) {
                HomeworkAlbumView()
            }
            .sheet(isPresented: $showingFocusMode) {
                FocusView()
            }
            .sheet(isPresented: $showingParentAuthForChat) {
                ParentAuthenticationView(
                    title: "Parent Verification",
                    message: "Chat function requires parent permission",
                    onSuccess: { onSelectTab(.chat) }
                )
            }
            .sheet(isPresented: $showingParentAuthForGrader) {
                ParentAuthenticationView(
                    title: "Parent Verification",
                    message: "Homework Grader requires parent permission",
                    onSuccess: { onSelectTab(.grader) }
                )
            }
            .sheet(isPresented: $showingParentAuthForReports) {
                ParentAuthenticationView(
                    title: "Parent Verification",
                    message: "Parent Reports require parent permission",
                    onSuccess: { showingParentReports = true }
                )
            }
        }
    }

    // MARK: - Engaging Hero Header
    private var engagingHeroHeader: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // Greeting card with gradient background - synced with voice type
            ZStack(alignment: .trailing) {
                // Dynamic gradient based on selected voice type - adaptive for dark mode
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: {
                                switch greetingVoice.currentVoiceType {
                                case .adam:
                                    return colorScheme == .dark ? [
                                        // Adam Dark Mode - much darker, muted blues
                                        Color(hex: "0C1844"),  // Very dark navy (custom)
                                        Color(hex: "1E3A8A"),  // navy-900
                                        Color(hex: "1E40AF")   // blue-800
                                    ] : [
                                        // Adam Light Mode - original bright blues
                                        Color(hex: "38BDF8"),  // sky-400
                                        Color(hex: "3B82F6"),  // blue-500
                                        Color(hex: "4F46E5")   // indigo-600
                                    ]
                                case .eva:
                                    return colorScheme == .dark ? [
                                        // Eva Dark Mode - much darker, richer purples
                                        Color(hex: "2D0A4E"),  // Very dark purple (custom)
                                        Color(hex: "581C87"),  // purple-900
                                        Color(hex: "6B21A8")   // purple-800
                                    ] : [
                                        // Eva Light Mode - original bright purples
                                        Color(hex: "F0ABFC"),  // fuchsia-300
                                        Color(hex: "A855F7"),  // purple-500
                                        Color(hex: "7C3AED")   // violet-600
                                    ]
                                case .max:
                                    return colorScheme == .dark ? [
                                        // Max Dark Mode - darker oranges
                                        Color(hex: "7C2D12"),  // orange-900
                                        Color(hex: "9A3412"),  // orange-800
                                        Color(hex: "C2410C")   // orange-700
                                    ] : [
                                        // Max Light Mode - bright oranges
                                        Color(hex: "FB923C"),  // orange-400
                                        Color(hex: "F97316"),  // orange-500
                                        Color(hex: "EA580C")   // orange-600
                                    ]
                                case .mia:
                                    return colorScheme == .dark ? [
                                        // Mia Dark Mode - darker pinks
                                        Color(hex: "831843"),  // pink-900
                                        Color(hex: "9F1239"),  // pink-800
                                        Color(hex: "BE123C")   // pink-700
                                    ] : [
                                        // Mia Light Mode - bright pinks
                                        Color(hex: "F9A8D4"),  // pink-300
                                        Color(hex: "EC4899"),  // pink-500
                                        Color(hex: "DB2777")   // pink-600
                                    ]
                                }
                            }(),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(
                        color: colorScheme == .dark ?
                            Color.white.opacity(0.1) :  // Subtle light shadow in dark mode
                            {
                                switch greetingVoice.currentVoiceType {
                                case .adam:
                                    return DesignTokens.Colors.aiBlue.opacity(0.4)
                                case .eva:
                                    return Color.purple.opacity(0.4)
                                case .max:
                                    return Color.orange.opacity(0.4)
                                case .mia:
                                    return Color.pink.opacity(0.4)
                                }
                            }(),
                        radius: 12,
                        x: 0,
                        y: 6
                    )

                // Content inside the greeting card - three-column layout
                HStack(alignment: .center, spacing: 8) {
                    // Left: AI Avatar Animation - moved further to the left
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
                        AIAvatarAnimation(
                            state: greetingVoice.isSpeaking ? .speaking : (greetingVoice.isPreloading ? .waiting : .idle),
                            voiceType: greetingVoice.currentVoiceType
                        )
                        .frame(width: 90, height: 90)
                        .id(greetingVoice.currentVoiceType.rawValue)  // Force recreation when voice type changes
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(greetingVoice.isPreloading)
                    .frame(width: 90, alignment: .leading)  // Align to leading edge
                    .offset(x: -8, y: -8)  // Move further left and up

                    // Center: Greeting text - wider central area
                    VStack(spacing: 2) {
                        Text(greetingText)
                            .font(.callout)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(userName)
                            .font(.title2)
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .frame(maxWidth: .infinity)

                    // Right: Settings button - moved back to the left a bit
                    Button(action: { showingProfile = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .frame(width: 70, alignment: .trailing)  // Wider frame, aligned right
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .frame(height: 110)  // Compact height
            .padding(.top, DesignTokens.Spacing.md)

            // Today's Progress - moved outside the gradient box
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text(NSLocalizedString("home.todaysProgress", comment: ""))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                HStack(spacing: DesignTokens.Spacing.md) {
                    if todayTotalQuestions > 0 {
                        StatBadge(
                            icon: "questionmark.circle.fill",
                            value: "\(todayTotalQuestions)",
                            label: NSLocalizedString("home.questions", comment: ""),
                            color: DesignTokens.Colors.aiBlue
                        )

                        StatBadge(
                            icon: "target",
                            value: "\(Int(todayAccuracy))%",
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
            // Section title
            Text(NSLocalizedString("home.quickActions", comment: ""))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.horizontal, DesignTokens.Spacing.xl)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                GridItem(.flexible(), spacing: DesignTokens.Spacing.md)
            ], spacing: DesignTokens.Spacing.md) {

                // Rainbow Card 1: Red (Adaptive)
                QuickActionCard_New(
                    icon: "camera.fill",
                    title: NSLocalizedString("home.homeworkGrader", comment: ""),
                    subtitle: NSLocalizedString("home.scanAndGrade", comment: ""),
                    color: colorScheme == .dark ? DesignTokens.Colors.rainbowRed.dark : DesignTokens.Colors.rainbowRed.light,
                    lottieAnimation: "Checklist",
                    lottieScale: 0.29,
                    action: {
                        if parentModeManager.requiresAuthentication(for: .homeworkGrader) {
                            showingParentAuthForGrader = true
                        } else {
                            onSelectTab(.grader)
                        }
                    }
                )

                // Rainbow Card 2: Orange (Adaptive)
                QuickActionCard_New(
                    icon: "message.fill",
                    title: NSLocalizedString("home.chat", comment: ""),
                    subtitle: NSLocalizedString("home.conversationalAI", comment: ""),
                    color: colorScheme == .dark ? DesignTokens.Colors.rainbowOrange.dark : DesignTokens.Colors.rainbowOrange.light,
                    lottieAnimation: "Chat",
                    lottieScale: 0.2,
                    action: {
                        if parentModeManager.requiresAuthentication(for: .chatFunction) {
                            showingParentAuthForChat = true
                        } else {
                            onSelectTab(.chat)
                        }
                    }
                )

                // Rainbow Card 3: Yellow (Adaptive)
                QuickActionCard_New(
                    icon: "books.vertical.fill",
                    title: NSLocalizedString("home.library", comment: ""),
                    subtitle: NSLocalizedString("home.studySessions", comment: ""),
                    color: colorScheme == .dark ? DesignTokens.Colors.rainbowYellow.dark : DesignTokens.Colors.rainbowYellow.light,
                    lottieAnimation: "Books",
                    lottieScale: 0.12,
                    action: { onSelectTab(.library) }
                )

                // Rainbow Card 4: Green (Adaptive)
                QuickActionCard_New(
                    icon: "chart.bar.fill",
                    title: NSLocalizedString("home.progress", comment: ""),
                    subtitle: NSLocalizedString("home.trackLearning", comment: ""),
                    color: colorScheme == .dark ? DesignTokens.Colors.rainbowGreen.dark : DesignTokens.Colors.rainbowGreen.light,
                    lottieAnimation: "Chart Graph",
                    lottieScale: 0.45,
                    action: { onSelectTab(.progress) }
                )
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - Additional Actions Section
    private var additionalActionsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            // Section title - aligned with Quick Actions title
            Text(NSLocalizedString("home.moreFeatures", comment: ""))
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.horizontal, DesignTokens.Spacing.xl)

            // Rainbow Card 5: Blue (Adaptive)
            HorizontalActionButton(
                icon: "doc.text.fill",
                title: NSLocalizedString("home.practice", comment: ""),
                subtitle: NSLocalizedString("home.practiceDescription", comment: ""),
                color: colorScheme == .dark ? DesignTokens.Colors.rainbowBlue.dark : DesignTokens.Colors.rainbowBlue.light,
                action: { showingQuestionGeneration = true }
            )
            .padding(.horizontal, DesignTokens.Spacing.xl)

            // Rainbow Card 6: Indigo (Adaptive)
            HorizontalActionButton(
                icon: "xmark.circle.fill",
                title: NSLocalizedString("home.mistakeReview", comment: ""),
                subtitle: NSLocalizedString("home.mistakeReviewDescription", comment: ""),
                color: colorScheme == .dark ? DesignTokens.Colors.rainbowIndigo.dark : DesignTokens.Colors.rainbowIndigo.light,
                action: { showingMistakeReview = true }
            )
            .padding(.horizontal, DesignTokens.Spacing.xl)

            // Rainbow Card 7: Violet (Adaptive)
            HorizontalActionButton(
                icon: "figure.2.and.child.holdinghands",
                title: NSLocalizedString("home.parentReports", comment: ""),
                subtitle: NSLocalizedString("home.parentReportsDescription", comment: ""),
                color: colorScheme == .dark ? DesignTokens.Colors.rainbowViolet.dark : DesignTokens.Colors.rainbowViolet.light,
                action: {
                    if parentModeManager.requiresAuthentication(for: .parentReports) {
                        showingParentAuthForReports = true
                    } else {
                        showingParentReports = true
                    }
                }
            )
            .padding(.horizontal, DesignTokens.Spacing.xl)

            // Rainbow Card 8: Pink/Magenta (Adaptive) - Homework Album
            HorizontalActionButton(
                icon: "photo.on.rectangle.angled",
                title: NSLocalizedString("home.homeworkAlbum", comment: ""),
                subtitle: NSLocalizedString("home.homeworkAlbumDescription", comment: ""),
                color: colorScheme == .dark ? DesignTokens.Colors.rainbowPink.dark : DesignTokens.Colors.rainbowPink.light,
                action: { showingHomeworkAlbum = true }
            )
            .padding(.horizontal, DesignTokens.Spacing.xl)

            // Rainbow Card 9: Teal (Adaptive) - Focus Mode
            HorizontalActionButton(
                icon: "brain.head.profile",
                title: NSLocalizedString("home.focusMode", comment: ""),
                subtitle: NSLocalizedString("home.focusModeDescription", comment: ""),
                color: Color(red: 0.2, green: 0.8, blue: 0.7),
                action: { showingFocusMode = true }
            )
            .padding(.horizontal, DesignTokens.Spacing.xl)
        }
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
    @Environment(\.colorScheme) var colorScheme  // ✅ Detect dark mode

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
            withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                            animationSpeed: 0.5
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
                        withAnimationIfNotPowerSaving(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true)
                        ) {
                            scale = 1.05
                        }

                        // Slight rotation animation for some visual interest
                        withAnimationIfNotPowerSaving(
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
                color: colorScheme == .dark ?
                    Color.white.opacity(isPressed ? 0.15 : 0.08) :  // Light shadow in dark mode
                    color.opacity(isPressed ? 0.4 : 0.2),           // Colored shadow in light mode
                radius: isPressed ? 16 : 10,
                x: 0,
                y: isPressed ? 8 : 5
            )
            .shadow(
                color: colorScheme == .dark ?
                    Color.clear :                           // No secondary shadow in dark mode
                    Color.black.opacity(0.06),              // Subtle shadow in light mode
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
            .animationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
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
    @Environment(\.colorScheme) var colorScheme  // ✅ Detect dark mode

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Trigger press animation
            withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
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
                    withAnimationIfNotPowerSaving(
                        Animation.easeInOut(duration: 2.5)
                            .repeatForever(autoreverses: true)
                    ) {
                        iconScale = 1.08
                    }

                    // Slight rotation animation
                    withAnimationIfNotPowerSaving(
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
                color: colorScheme == .dark ?
                    Color.white.opacity(isPressed ? 0.1 : 0.05) :  // Light shadow in dark mode
                    (isPressed ? color.opacity(0.2) : Color.black.opacity(0.03)),  // Colored/black shadow in light mode
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
