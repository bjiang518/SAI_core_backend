//
//  HomeView.swift
//  StudyAI
//
//  Enhanced UI Implementation
//

import SwiftUI
import os.log
import Lottie

// Environment key to propagate lottieRefreshID down to card subviews
private struct LottieRefreshIDKey: EnvironmentKey {
    static let defaultValue: Int = 0
}
extension EnvironmentValues {
    var lottieRefreshID: Int {
        get { self[LottieRefreshIDKey.self] }
        set { self[LottieRefreshIDKey.self] = newValue }
    }
}

struct HomeView: View {
    let onSelectTab: (MainTab) -> Void
    @StateObject private var networkService = NetworkService.shared
    @StateObject private var voiceService = VoiceInteractionService.shared
    @StateObject private var greetingVoice = GreetingVoiceService.shared
    @StateObject private var parentModeManager = ParentModeManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var appState = AppState.shared
    @State private var userName = ""
    @State private var navigateToSession = false
    @State private var showingProfile = false
    @State private var showingMistakeReview = false
    @State private var showingQuestionGeneration = false
    @State private var showingParentReports = false
    @State private var showingHomeworkAlbum = false  // NEW: Homework Album
    @State private var showingFocusMode = false  // NEW: Focus Mode
    @State private var lottieRefreshID: Int = 0  // Incremented on appear to force LottieView re-sync

    // ✅ Dark Mode Support: Detect current color scheme
    @Environment(\.colorScheme) var colorScheme
    // iPad vs iPhone layout
    @Environment(\.horizontalSizeClass) var sizeClass

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
                        .padding(.bottom, DesignTokens.Spacing.xxl)
                        .environment(\.lottieRefreshID, lottieRefreshID)

                    // Additional Actions (Practice, Mistake Review, Parent Reports)
                    additionalActionsSection
                        .environment(\.lottieRefreshID, lottieRefreshID)

                    Spacer(minLength: 100)
                }
                .padding(.bottom, DesignTokens.Spacing.md)
            }
            .background(themeManager.backgroundColor.ignoresSafeArea())
            .navigationBarHidden(true)
            .onAppear {
                lottieRefreshID += 1
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
            .navigationDestination(isPresented: $showingMistakeReview) {
                MistakeReviewView()
            }
            .navigationDestination(isPresented: $showingQuestionGeneration) {
                QuestionGenerationView()
            }
            .sheet(isPresented: $showingParentReports) {
                NavigationView {
                    ParentReportsContainerView()
                }
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
        // iPad 上防止 NavigationView 变成双列拆分布局
        .navigationViewStyle(.stack)
    }

    // MARK: - Engaging Hero Header
    private var engagingHeroHeader: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            // Greeting card with gradient background - synced with voice type
            ZStack(alignment: .trailing) {
                // Dynamic gradient based on theme - Cute Mode uses solid color
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        themeManager.currentTheme == .cute ?
                            // Cute Mode: Fully solid color (no gradient)
                            AnyShapeStyle(themeManager.greetingCardBackground) :
                            // Day/Night Mode: Voice-based gradients
                            AnyShapeStyle(LinearGradient(
                                colors: {
                                    switch greetingVoice.currentVoiceType {
                                    case .adam:
                                        return colorScheme == .dark ? [
                                            Color(hex: "0C1844"),
                                            Color(hex: "1E3A8A"),
                                            Color(hex: "1E40AF")
                                        ] : [
                                            Color(hex: "38BDF8"),
                                            Color(hex: "3B82F6"),
                                            Color(hex: "4F46E5")
                                        ]
                                    case .eva:
                                        return colorScheme == .dark ? [
                                            Color(hex: "2D0A4E"),
                                            Color(hex: "581C87"),
                                            Color(hex: "6B21A8")
                                        ] : [
                                            Color(hex: "F0ABFC"),
                                            Color(hex: "A855F7"),
                                            Color(hex: "7C3AED")
                                        ]
                                    case .max:
                                        return colorScheme == .dark ? [
                                            Color(hex: "7C2D12"),
                                            Color(hex: "9A3412"),
                                            Color(hex: "C2410C")
                                        ] : [
                                            Color(hex: "FB923C"),
                                            Color(hex: "F97316"),
                                            Color(hex: "EA580C")
                                        ]
                                    case .mia:
                                        return colorScheme == .dark ? [
                                            Color(hex: "831843"),
                                            Color(hex: "9F1239"),
                                            Color(hex: "BE123C")
                                        ] : [
                                            Color(hex: "F9A8D4"),
                                            Color(hex: "EC4899"),
                                            Color(hex: "DB2777")
                                        ]
                                    }
                                }(),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    )
                    .shadow(
                        color: themeManager.currentTheme == .cute ?
                            Color.black.opacity(0.2) :
                            (colorScheme == .dark ?
                                Color.white.opacity(0.1) :
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
                                }()
                            ),
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
                            .font(.body)  // Slightly larger than callout
                            .foregroundColor(Color(white: 0.3))  // Dark grey
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(userName)
                            .font(.title)  // Slightly larger than title2
                            .foregroundColor(Color(white: 0.3))  // Dark grey
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
                    .foregroundColor(
                        themeManager.currentTheme == .cute ?
                            Color.gray :  // Grey in Cute mode
                            .primary
                    )

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
                        Text(NSLocalizedString("home.startLearningPrompt", comment: ""))
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
            // Section title row with animation toggle
            HStack {
                Text(NSLocalizedString("home.quickActions", comment: ""))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(
                        themeManager.currentTheme == .cute ?
                            Color.gray :
                            .primary
                    )

                Spacer()

                // Animation toggle button
                Button(action: {
                    print("🎛️ [HomeView] Animation toggle tapped | before=\(appState.isPowerSavingMode) → after=\(!appState.isPowerSavingMode)")
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        appState.isPowerSavingMode.toggle()
                    }
                    print("🎛️ [HomeView] AppState.isPowerSavingMode is now: \(appState.isPowerSavingMode)")
                }) {
                    Image(systemName: appState.isPowerSavingMode ? "figure.stand" : "figure.run")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(appState.isPowerSavingMode ? .orange : .green)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(appState.isPowerSavingMode
                                    ? Color.orange.opacity(0.12)
                                    : Color.green.opacity(0.12))
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)

            LazyVGrid(columns: Array(
                repeating: GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                count: sizeClass == .regular ? 4 : 2  // iPad: 4列, iPhone: 2列
            ), spacing: DesignTokens.Spacing.md) {

                // Card 1: Snap & Ask (top-left)
                QuickActionCard_New(
                    icon: "message.fill",
                    title: NSLocalizedString("home.chat", comment: ""),
                    subtitle: NSLocalizedString("home.conversationalAI", comment: ""),
                    color: themeManager.featureCardColor("chat"),
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

                // Card 2: Homework Grader (top-right)
                QuickActionCard_New(
                    icon: "camera.fill",
                    title: NSLocalizedString("home.homeworkGrader", comment: ""),
                    subtitle: NSLocalizedString("home.scanAndGrade", comment: ""),
                    color: themeManager.featureCardColor("homework"),
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

                // Card 3: Mistake Review (bottom-left)
                QuickActionCard_New(
                    icon: "xmark.circle.fill",
                    title: NSLocalizedString("home.mistakeReview", comment: ""),
                    subtitle: NSLocalizedString("home.mistakeReviewDescription", comment: ""),
                    color: colorScheme == .dark ? DesignTokens.Colors.rainbowIndigo.dark : DesignTokens.Colors.rainbowIndigo.light,
                    lottieAnimation: "mistakeNotebook",
                    lottieScale: 0.16,
                    lottieOffset: CGPoint(x: 0, y: 5),
                    action: { showingMistakeReview = true }
                )

                // Card 4: Practice (bottom-right)
                QuickActionCard_New(
                    icon: "doc.text.fill",
                    title: NSLocalizedString("home.practice", comment: ""),
                    subtitle: NSLocalizedString("home.practiceDescription", comment: ""),
                    color: themeManager.featureCardColor("practice"),
                    lottieAnimation: "createquiz",
                    lottieScale: 0.14,
                    lottieOffset: CGPoint(x: 0, y: 10),
                    action: { showingQuestionGeneration = true }
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
                .foregroundColor(
                    themeManager.currentTheme == .cute ?
                        Color.gray :  // Grey in Cute mode
                        .primary
                )
                .padding(.horizontal, DesignTokens.Spacing.xl)

            if sizeClass == .regular {
                // iPad: 2列网格布局
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                    GridItem(.flexible(), spacing: DesignTokens.Spacing.md)
                ], spacing: DesignTokens.Spacing.md) {
                    moreFeatureButtons
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
            } else {
                // iPhone: 现有竖排布局（零改动）
                VStack(spacing: DesignTokens.Spacing.md) {
                    moreFeatureButtons
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                }
            }
        }
    }

    // 5 个 More Features 按钮（内容零改动，仅提取复用）
    @ViewBuilder
    private var moreFeatureButtons: some View {
        // Card 5: Library
        HorizontalActionButton(
            icon: "books.vertical.fill",
            title: NSLocalizedString("home.library", comment: ""),
            subtitle: NSLocalizedString("home.studySessions", comment: ""),
            color: themeManager.featureCardColor("library"),
            lottieAnimation: "Books",
            lottieScale: 0.12,
            action: { onSelectTab(.library) }
        )

        // Card 6: Pomodoro Focus
        HorizontalActionButton(
            icon: "brain.head.profile",
            title: NSLocalizedString("pomodoro.focusMode", comment: ""),
            subtitle: NSLocalizedString("home.focusModeDescription", comment: ""),
            color: Color(red: 0.2, green: 0.8, blue: 0.7),
            lottieAnimation: "loadingtomato",
            lottieScale: 0.21,
            action: { showingFocusMode = true }
        )

        // Card 7: Homework Album
        HorizontalActionButton(
            icon: "photo.on.rectangle.angled",
            title: NSLocalizedString("home.homeworkAlbum", comment: ""),
            subtitle: NSLocalizedString("home.homeworkAlbumDescription", comment: ""),
            color: colorScheme == .dark ? DesignTokens.Colors.rainbowPink.dark : DesignTokens.Colors.rainbowPink.light,
            lottieAnimation: "Imageicontadah",
            lottieScale: 0.16,
            action: { showingHomeworkAlbum = true }
        )

        // Card 8: Parent Reports
        HorizontalActionButton(
            icon: "figure.2.and.child.holdinghands",
            title: NSLocalizedString("home.parentReports", comment: ""),
            subtitle: NSLocalizedString("home.parentReportsDescription", comment: ""),
            color: themeManager.featureCardColor("reports"),
            lottieAnimation: "Report",
            lottieScale: 0.1,
            lottiePowerSavingProgress: 0.5,
            action: {
                if parentModeManager.requiresAuthentication(for: .parentReports) {
                    showingParentAuthForReports = true
                } else {
                    showingParentReports = true
                }
            }
        )

        // Card 9: Progress
        HorizontalActionButton(
            icon: "chart.bar.fill",
            title: NSLocalizedString("home.progress", comment: ""),
            subtitle: NSLocalizedString("home.trackLearning", comment: ""),
            color: themeManager.featureCardColor("progress"),
            lottieAnimation: "Chart Graph",
            lottieScale: 0.45,
            action: { onSelectTab(.progress) }
        )
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
    let lottieOffset: CGPoint  // Offset for Lottie animation position

    @State private var isPressed = false
    @State private var rotationAngle: Double = 0
    @State private var scale: CGFloat = 1.0
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.lottieRefreshID) var lottieRefreshID
    @StateObject private var themeManager = ThemeManager.shared

    // Default initializer without Lottie animation
    init(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
        self.lottieAnimation = nil
        self.lottieScale = 1.0
        self.lottieOffset = .zero
    }

    // Initializer with Lottie animation
    init(icon: String, title: String, subtitle: String, color: Color, lottieAnimation: String, lottieScale: CGFloat = 1.0, lottieOffset: CGPoint = .zero, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
        self.lottieAnimation = lottieAnimation
        self.lottieScale = lottieScale
        self.lottieOffset = lottieOffset
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
                            .fill(
                                themeManager.currentTheme == .cute ?
                                    Color.white.opacity(0.3) :  // White circle in Cute mode
                                    color.opacity(isPressed ? 0.3 : 0.15)
                            )
                            .frame(width: 50, height: 50)
                            .scaleEffect(isPressed ? 0.9 : 1.0)
                    }

                    // Use Lottie animation if provided, otherwise use SF Symbol
                    if let animationName = lottieAnimation {
                        LottieView(
                            animationName: animationName,
                            loopMode: .loop,
                            animationSpeed: 0.5,
                            powerSavingProgress: 0.8,
                            refreshID: lottieRefreshID
                        )
                        .frame(width: 50, height: 50)
                        .scaleEffect(isPressed ? lottieScale * 0.95 : lottieScale)
                        .offset(x: lottieOffset.x, y: lottieOffset.y)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(
                                themeManager.currentTheme == .cute ?
                                    DesignTokens.Colors.Cute.textPrimary :  // Soft black icon in Cute mode
                                    (isPressed ? color.opacity(0.7) : color)
                            )
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
                        .foregroundColor(
                            themeManager.currentTheme == .cute ?
                                DesignTokens.Colors.Cute.textPrimary :  // Soft black in Cute mode
                                .primary
                        )
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(
                            themeManager.currentTheme == .cute ?
                                DesignTokens.Colors.Cute.textSecondary :  // Grey in Cute mode
                                .secondary
                        )
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                Group {
                    // Cute Mode: Lighter solid color (30% opacity - similar to More Features)
                    // Day/Night Mode: Gradient overlay
                    if themeManager.currentTheme == .cute {
                        color.opacity(0.3)  // Much lighter (30% opacity)
                    } else {
                        ZStack {
                            // Brighter card background for light mode
                            colorScheme == .dark ?
                                DesignTokens.Colors.cardBackground :
                                Color.white

                            // More vibrant gradient overlay with increased opacity for light mode
                            LinearGradient(
                                colors: [
                                    color.opacity(colorScheme == .dark ? 0.12 : 0.25),
                                    color.opacity(colorScheme == .dark ? 0.05 : 0.15),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                }
            )
            .cornerRadius(18)
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
    let lottieAnimation: String?
    let lottieScale: CGFloat
    let lottiePowerSavingProgress: CGFloat

    @State private var isPressed = false
    @State private var iconScale: CGFloat = 1.0
    @State private var iconRotation: Double = 0
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.lottieRefreshID) var lottieRefreshID
    @StateObject private var themeManager = ThemeManager.shared

    init(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
        self.lottieAnimation = nil
        self.lottieScale = 1.0
        self.lottiePowerSavingProgress = 0.8
    }

    init(icon: String, title: String, subtitle: String, color: Color, lottieAnimation: String, lottieScale: CGFloat = 1.0, lottiePowerSavingProgress: CGFloat = 0.8, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
        self.lottieAnimation = lottieAnimation
        self.lottieScale = lottieScale
        self.lottiePowerSavingProgress = lottiePowerSavingProgress
    }

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
                    if lottieAnimation == nil {
                        Circle()
                            .fill(
                                themeManager.currentTheme == .cute ?
                                    Color.white.opacity(0.5) :  // White circle in Cute mode
                                    color.opacity(isPressed ? 0.3 : 0.15)
                            )
                            .frame(width: 50, height: 50)
                            .scaleEffect(isPressed ? 0.9 : 1.0)
                    }

                    if let animationName = lottieAnimation {
                        LottieView(
                            animationName: animationName,
                            loopMode: .loop,
                            animationSpeed: 0.5,
                            powerSavingProgress: lottiePowerSavingProgress,
                            refreshID: lottieRefreshID
                        )
                        .frame(width: 50, height: 50)
                        .scaleEffect(isPressed ? lottieScale * 0.95 : lottieScale)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(
                                themeManager.currentTheme == .cute ?
                                    DesignTokens.Colors.Cute.textPrimary :  // Soft black in Cute mode
                                    (isPressed ? color.opacity(0.7) : color)
                            )
                            .scaleEffect(iconScale)
                            .rotationEffect(.degrees(iconRotation))
                    }
                }
                .onAppear {
                    // Only animate SF Symbols, not Lottie
                    guard lottieAnimation == nil else { return }
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
                        .foregroundColor(
                            themeManager.currentTheme == .cute ?
                                DesignTokens.Colors.Cute.textPrimary :  // Soft black in Cute mode
                                .primary
                        )
                        .fontWeight(.medium)

                    Text(subtitle)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(
                            themeManager.currentTheme == .cute ?
                                DesignTokens.Colors.Cute.textSecondary :  // Grey in Cute mode
                                .secondary
                        )
                }
                .padding(.leading, 20)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(
                        themeManager.currentTheme == .cute ?
                            DesignTokens.Colors.Cute.textSecondary :  // Grey in Cute mode
                            .secondary
                    )
                    .offset(x: isPressed ? 3 : 0)
            }
            .padding(16)
            .background(
                // Cute Mode: LIGHTER solid color (much lighter than Quick Actions)
                // Day/Night Mode: White/card background with border
                themeManager.currentTheme == .cute ?
                    color.opacity(0.25) :  // Lighter version (25% opacity) in Cute mode
                    (isPressed ?
                        color.opacity(colorScheme == .dark ? 0.05 : 0.1) :
                        (colorScheme == .dark ? DesignTokens.Colors.cardBackground : Color.white))
            )
            .cornerRadius(16)
            .overlay(
                Group {
                    if themeManager.currentTheme != .cute {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isPressed ? color.opacity(colorScheme == .dark ? 0.6 : 0.7) : color.opacity(colorScheme == .dark ? 0.3 : 0.4),
                                lineWidth: isPressed ? 2.0 : 1.5
                            )
                    }
                }
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
