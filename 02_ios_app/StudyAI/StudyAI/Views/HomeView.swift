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
    @StateObject private var parentModeManager = ParentModeManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var todoEngine = SuggestedTodoEngine.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var appState = AppState.shared
    @State private var userName = ""
    @State private var navigateToSession = false
    @State private var showingProfile = false
    @State private var showingMistakeReview = false
    @State private var showingQuestionGeneration = false
    @State private var showingParentReports = false
    @State private var showingHomeworkAlbum = false
    @State private var showingFocusMode = false
    @State private var showingFeynmanPractice = false
    @State private var feynmanWeaknessKey: String = ""
    @State private var showingDailyQuestion = false
    @State private var dailyQuestionText: String = ""
    @State private var lottieRefreshID: Int = 0
    @State private var isMoreFeaturesExpanded: Bool = true

    // ✅ Dark Mode Support: Detect current color scheme
    @Environment(\.colorScheme) var colorScheme
    // iPad vs iPhone layout
    @Environment(\.horizontalSizeClass) var sizeClass

    // Parent authentication modals
    @State private var showingParentAuthForChat = false
    @State private var showingParentAuthForGrader = false
    @State private var showingParentAuthForReports = false

    private let logger = Logger(subsystem: "com.studyai", category: "HomeView")

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Engaging Hero Header with Animation, Avatar, Greeting & Stats
                    engagingHeroHeader
                        .padding(.bottom, DesignTokens.Spacing.xxl)

                    // Quick Actions
                    quickActionsSection
                        .padding(.bottom, DesignTokens.Spacing.xl)
                        .environment(\.lottieRefreshID, lottieRefreshID)

                    // Suggested daily to-do list (torn notebook style)
                    SuggestedTodosSection(
                        todos: todoEngine.todos,
                        onAction: { handleTodoAction($0) },
                        onDismiss: { todoEngine.dismiss(id: $0) },
                        onRefresh: { todoEngine.forceRefresh() }
                    )
                    .padding(.horizontal, DesignTokens.Spacing.sm)

                    // More features — sits flush below the suggestion card
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
                todoEngine.fetchAndRefresh()
                updateUserName(from: profileService.currentProfile ?? profileService.loadCachedProfile())
            }
            .onReceive(profileService.$currentProfile) { profile in
                updateUserName(from: profile)
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
                PracticeLibraryView()
            }
            .onChange(of: appState.homeNavResetToken) { _, _ in
                showingMistakeReview = false
                showingQuestionGeneration = false
                showingFeynmanPractice = false
                showingDailyQuestion = false
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
            .sheet(isPresented: $showingFeynmanPractice) {
                WeaknessPracticeView(
                    weaknessKey: feynmanWeaknessKey,
                    weaknessValue: WeaknessValue(
                        value: 0.5,
                        firstDetected: Date(),
                        lastAttempt: Date(),
                        totalAttempts: 0,
                        correctAttempts: 0
                    )
                )
            }
            .sheet(isPresented: $showingDailyQuestion) {
                DailyQuestionCard(question: dailyQuestionText)
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
        HStack(alignment: .center, spacing: 14) {
            // Left: User profile avatar
            profileAvatarView(size: 46)
                .onTapGesture { showingProfile = true }

            // Center: Greeting text — ZCOOLKuaiLe for Chinese, IndieFlower for other languages
            Text("\(greetingText), \(userName)")
                .font(
                    "\(greetingText) \(userName)".unicodeScalars.contains {
                        (0x4E00...0x9FFF ~= $0.value) || (0x3400...0x4DBF ~= $0.value)
                    }
                    ? Font.custom("ZCOOLKuaiLe-Regular", size: 24)
                    : Font.custom("IndieFlower", size: 24)
                )
                .foregroundColor(themeManager.primaryText)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            // Right: Animation toggle + Settings
            HStack(spacing: 6) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        appState.isPowerSavingMode.toggle()
                    }
                }) {
                    Image(systemName: appState.isPowerSavingMode ? "figure.stand" : "figure.run")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(appState.isPowerSavingMode ? .orange : .green)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(appState.isPowerSavingMode
                                      ? Color.orange.opacity(0.10)
                                      : Color.green.opacity(0.10))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { showingProfile = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(themeManager.secondaryText)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(colorScheme == .dark
                                      ? Color.white.opacity(0.08)
                                      : Color.black.opacity(0.06))
                        )
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.top, DesignTokens.Spacing.md)
        .padding(.bottom, 4)
    }

    // MARK: - Profile Avatar
    @ViewBuilder
    private func profileAvatarView(size: CGFloat) -> some View {
        let userId = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        let localAvatarKey = "localAvatarFilename_\(userId)"

        if let localFilename = UserDefaults.standard.string(forKey: localAvatarKey),
           let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let imageData = try? Data(contentsOf: documentsDirectory.appendingPathComponent(localFilename)),
           let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .id(localFilename)
        } else if let localAvatarId = UserDefaults.standard.object(forKey: "selectedAvatarId") as? Int,
                  let avatar = ProfileAvatar.from(id: localAvatarId) {
            Image(avatar.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let customUrl = profileService.currentProfile?.customAvatarUrl,
                  !customUrl.isEmpty {
            AsyncImage(url: URL(string: customUrl)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                default:
                    fallbackAvatarCircle(size: size)
                }
            }
        } else if let avatarId = profileService.currentProfile?.avatarId,
                  let avatar = ProfileAvatar.from(id: avatarId) {
            Image(avatar.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            fallbackAvatarCircle(size: size)
        }
    }

    @ViewBuilder
    private func fallbackAvatarCircle(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
            if let name = AuthenticationService.shared.currentUser?.name, !name.isEmpty {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundColor(.white)
            }
        }
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

    // MARK: - Suggested Todo Action Handler

    private func handleTodoAction(_ action: SuggestedTodo.TodoAction) {
        switch action {
        // ── Category 1: Practice ─────────────────────────────────────────────
        case .openMistakeReview:
            showingMistakeReview = true
        case .startFeynmanPractice(let weaknessKey):
            feynmanWeaknessKey = weaknessKey
            showingFeynmanPractice = true
        case .startConceptReview:
            // TODO: pass sessionId to QuestionGenerationView for auto-generation (Mode 3)
            showingQuestionGeneration = true
        case .startRandomPractice:
            // TODO: pre-configure QuestionGenerationView for random 5-Q practice
            showingQuestionGeneration = true
        // ── Category 2: Main Feature ─────────────────────────────────────────
        case .openGrader:
            if parentModeManager.requiresAuthentication(for: .homeworkGrader) {
                showingParentAuthForGrader = true
            } else {
                onSelectTab(.grader)
            }
        case .openChat:
            onSelectTab(.chat)
        // ── Category 3: Extended Features ────────────────────────────────────
        case .openFocus:
            showingFocusMode = true
        case .openHomeworkAlbum:
            showingHomeworkAlbum = true
        case .openParentReport:
            if parentModeManager.requiresAuthentication(for: .parentReports) {
                showingParentAuthForReports = true
            } else {
                showingParentReports = true
            }
        case .openProgress:
            todoEngine.markProgressViewed()
            onSelectTab(.progress)
        // ── Category 4: Deep Extension ────────────────────────────────────────
        case .startOralPractice:
            AppState.shared.pendingChatAction = .startLiveMode(starterPrompt: NSLocalizedString("chat.liveMode.oralPractice.starterPrompt", comment: ""))
            onSelectTab(.chat)
        case .showDailyQuestion(let question):
            dailyQuestionText = question
            showingDailyQuestion = true
        }
    }

    private func updateUserName(from profile: UserProfile?) {
        guard let profile = profile else {
            userName = NSLocalizedString("home.defaultStudentName", comment: "")
            return
        }
        if let displayName = profile.displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userName = displayName
        } else if let firstName = profile.firstName, !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userName = firstName
        } else {
            userName = NSLocalizedString("home.defaultStudentName", comment: "")
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
            HStack(spacing: DesignTokens.Spacing.md) {
                // Card 1: Chat
                VStack(spacing: 6) {
                    QuickActionCard_New(
                        icon: "message.fill",
                        title: NSLocalizedString("home.chat", comment: ""),
                        subtitle: "",
                        color: themeManager.featureCardColor("chat"),
                        lottieAnimation: "Chat_bot",
                        lottieScale: 0.117,
                        cuteCircleColor: DesignTokens.Colors.Cute.blue,
                        action: {
                            if parentModeManager.requiresAuthentication(for: .chatFunction) {
                                showingParentAuthForChat = true
                            } else {
                                onSelectTab(.chat)
                            }
                        }
                    )
                    Text(NSLocalizedString("home.quickAction.chat", value: "问AI", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(themeManager.secondaryText)
                }

                // Card 2: Homework Grader
                VStack(spacing: 6) {
                    QuickActionCard_New(
                        icon: "camera.fill",
                        title: NSLocalizedString("home.homeworkGrader", comment: ""),
                        subtitle: "",
                        color: themeManager.featureCardColor("homework"),
                        lottieAnimation: "Camera_black",
                        lottieScale: 0.117,
                        cuteCircleColor: DesignTokens.Colors.Cute.yellow,
                        action: {
                            if parentModeManager.requiresAuthentication(for: .homeworkGrader) {
                                showingParentAuthForGrader = true
                            } else {
                                onSelectTab(.grader)
                            }
                        }
                    )
                    Text(NSLocalizedString("home.quickAction.homework", value: "作业批改", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(themeManager.secondaryText)
                }

                // Card 3: Practice
                VStack(spacing: 6) {
                    QuickActionCard_New(
                        icon: "doc.text.fill",
                        title: NSLocalizedString("home.practice", comment: ""),
                        subtitle: "",
                        color: themeManager.featureCardColor("practice"),
                        lottieAnimation: "createquiz",
                        lottieScale: 0.117,
                        cuteCircleColor: DesignTokens.Colors.Cute.mint,
                        action: { showingQuestionGeneration = true }
                    )
                    Text(NSLocalizedString("home.quickAction.practice", value: "练习本", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(themeManager.secondaryText)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - Additional Actions Section
    private var additionalActionsSection: some View {
        VStack(spacing: 0) {
            // Centered divider + chevron toggle
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isMoreFeaturesExpanded.toggle()
                }
            }) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isMoreFeaturesExpanded ? 180 : 0))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.secondary.opacity(0.09)))
                        .padding(.horizontal, 10)

                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 1)
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, DesignTokens.Spacing.sm)

            if isMoreFeaturesExpanded {
                if sizeClass == .regular {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: DesignTokens.Spacing.md),
                        GridItem(.flexible(), spacing: DesignTokens.Spacing.md)
                    ], spacing: DesignTokens.Spacing.md) {
                        moreFeatureButtons
                    }
                    .padding(.horizontal, DesignTokens.Spacing.xl)
                } else {
                    VStack(spacing: DesignTokens.Spacing.md) {
                        moreFeatureButtons
                            .padding(.horizontal, DesignTokens.Spacing.xl)
                    }
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

        // Card 6: Mistake Review
        HorizontalActionButton(
            icon: "xmark.circle.fill",
            title: NSLocalizedString("home.mistakeReview", comment: ""),
            subtitle: NSLocalizedString("home.mistakeReviewDescription", comment: ""),
            color: colorScheme == .dark ? DesignTokens.Colors.rainbowIndigo.dark : DesignTokens.Colors.rainbowIndigo.light,
            lottieAnimation: "mistakeNotebook",
            lottieScale: 0.16,
            action: { showingMistakeReview = true }
        )

        // Card 7: Pomodoro Focus
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
            action: { onSelectTab(.progress); todoEngine.markProgressViewed() }
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
    let cuteCircleColor: Color  // Per-card fill color in Cute theme

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
        self.cuteCircleColor = .white
    }

    // Initializer with Lottie animation
    init(icon: String, title: String, subtitle: String, color: Color, lottieAnimation: String, lottieScale: CGFloat = 1.0, lottieOffset: CGPoint = .zero, cuteCircleColor: Color = .white, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.action = action
        self.lottieAnimation = lottieAnimation
        self.lottieScale = lottieScale
        self.lottieOffset = lottieOffset
        self.cuteCircleColor = cuteCircleColor
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
                        // Circular frame — cute: solid themed fill; iOS: white face + colored edge
                        Circle()
                            .fill(
                                themeManager.currentTheme == .cute
                                    ? cuteCircleColor.opacity(isPressed ? 0.45 : 0.55)
                                    : Color.white
                            )
                            .overlay(
                                themeManager.currentTheme == .cute
                                    ? nil
                                    : Circle().stroke(color.opacity(isPressed ? 0.60 : 0.40), lineWidth: 2)
                            )
                            .frame(width: 86, height: 86)
                            .offset(x: lottieOffset.x, y: lottieOffset.y - 16)
                            .scaleEffect(isPressed ? 0.92 : 1.0)
                        LottieView(
                            animationName: animationName,
                            loopMode: .loop,
                            animationSpeed: 0.5,
                            powerSavingProgress: 0.8,
                            refreshID: lottieRefreshID
                        )
                        .frame(width: 50, height: 50)
                        .scaleEffect(isPressed ? lottieScale * 0.95 : lottieScale)
                        .offset(x: lottieOffset.x, y: lottieOffset.y - 16)
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

            }
            .frame(maxWidth: .infinity)
            .frame(height: 95)
            .contentShape(Rectangle())
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
