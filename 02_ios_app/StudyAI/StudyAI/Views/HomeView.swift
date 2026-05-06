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

/// Carries the weakness data needed to present WeaknessPracticeView.
/// Using `.sheet(item:)` ensures a fresh @StateObject on every presentation.
private struct FeynmanSheetItem: Identifiable {
    let id = UUID()
    let weaknessKey: String
    let weaknessValue: WeaknessValue
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
    @StateObject private var usageService = UsageService.shared
    @StateObject private var familyService = FamilyService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @ObservedObject private var profileService = ProfileService.shared
    @ObservedObject private var appState = AppState.shared
    @AppStorage("daily_challenge_last_completed") private var dailyChallengeLastCompleted = ""
    @AppStorage("daily_challenge_points_claimed_date") private var dailyChallengePointsClaimedDate = ""
    @State private var userName = ""
    @State private var navigateToSession = false
    @State private var showingProfile = false
    @State private var showingSettings = false
    @State private var showingUpgrade = false
    @State private var showingGuestConversion = false
    @State private var showingMistakeReview = false
    @State private var showingQuestionGeneration = false
    // ── Practice todo shortcut configuration ──────────────────────────────
    /// Pre-selected subject for MistakeReviewView
    @State private var mistakeReviewInitialSubject: String? = nil
    /// Config passed to PracticeLibraryView → NewPracticeSheet (random or concept review shortcuts)
    @State private var practiceLibraryShortcutConfig: PracticeLibraryView.ShortcutConfig? = nil
    /// Direct navigation to QuestionSheetView for the practice retry shortcut
    @State private var practiceRetrySession: PracticeSession? = nil
    @State private var showingParentReports = false
    @State private var showingHomeworkAlbum = false
    @State private var showingFocusMode = false
    @State private var feynmanSheetItem: FeynmanSheetItem? = nil
    @State private var lottieRefreshID: Int = 0
    @State private var isMoreFeaturesExpanded: Bool = true
    @State private var showingPointsShop: Bool = false
    @State private var streakBonusClaimed: Int = 0
    @State private var showStreakBonusToast: Bool = false

    // ✅ Dark Mode Support: Detect current color scheme
    @Environment(\.colorScheme) var colorScheme
    // iPad vs iPhone layout
    @Environment(\.horizontalSizeClass) var sizeClass

    // Parent authentication modals
    @State private var showingParentAuthForChat = false
    @State private var showingParentAuthForGrader = false
    @State private var showingParentAuthForReports = false

    private let logger = Logger(subsystem: "com.studyai", category: "HomeView")

    private var todayString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private var unclaimedEarningsCount: Int {
        let today = todayString
        let streakBonus = pointsManager.hasClaimedStreakBonusToday ? 0 : 1
        let dailyChallenge = (dailyChallengeLastCompleted == today && dailyChallengePointsClaimedDate != today) ? 1 : 0
        return streakBonus + dailyChallenge
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Child session banner — shown when parent has switched to a child account
                    if familyService.isChildSession,
                       let childName = AuthenticationService.shared.currentUser?.name {
                        HStack(spacing: 10) {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(DesignTokens.Colors.Cute.blue)
                            Text(String(format: NSLocalizedString("family.childSessionBanner",
                                        value: "Viewing %@'s account", comment: ""), childName))
                                .font(.subheadline.bold())
                                .foregroundColor(themeManager.primaryText)
                            Spacer()
                            Button {
                                Task { await familyService.switchBackToParent() }
                            } label: {
                                Text(NSLocalizedString("family.switchBack", value: "Back to my account", comment: ""))
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(DesignTokens.Colors.Cute.blue)
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(DesignTokens.Colors.Cute.blue.opacity(0.1))
                        .padding(.bottom, 4)
                    }

                    // Engaging Hero Header with Animation, Avatar, Greeting & Stats
                    engagingHeroHeader
                        .padding(.bottom, DesignTokens.Spacing.xxl)

                    // Streak freeze used banner
                    if pointsManager.streakFreezeUsedToday {
                        HStack(spacing: 8) {
                            Image(systemName: "snowflake")
                                .foregroundColor(.cyan)
                            Text(String(format: NSLocalizedString("streak.freeze.used.banner", comment: ""),
                                        pointsManager.streakFreezeCards))
                                .font(.subheadline)
                                .foregroundColor(themeManager.primaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.cyan.opacity(0.1))
                        )
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                        .padding(.bottom, 8)
                    }


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
            .navigationBarHidden(UIDevice.current.userInterfaceIdiom != .pad)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                lottieRefreshID += 1
                todoEngine.fetchAndRefresh()
                updateUserName(from: profileService.currentProfile ?? profileService.loadCachedProfile())

                // Schedule streak protection notification if no activity today
                if pointsManager.todayProgress?.totalQuestions == 0 && pointsManager.currentStreak > 2 {
                    NotificationService.shared.scheduleStreakProtectionReminder(currentStreak: pointsManager.currentStreak)
                }
            }
            .onReceive(profileService.$currentProfile) { profile in
                updateUserName(from: profile)
            }
            .onReceive(usageService.$nudgeFeature) { feature in
                guard feature != nil else { return }
                usageService.nudgeFeature = nil
                showingUpgrade = true
            }
            .sheet(isPresented: $showingProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showingSettings) {
                ModernProfileView(onLogout: {
                    AuthenticationService.shared.signOut()
                    showingSettings = false
                })
            }
            .sheet(isPresented: $showingPointsShop) {
                PointsShopView()
            }
            .navigationDestination(isPresented: $showingMistakeReview) {
                MistakeReviewView(initialSubject: mistakeReviewInitialSubject)
            }
            .navigationDestination(isPresented: $showingQuestionGeneration) {
                PracticeLibraryView(shortcutConfig: practiceLibraryShortcutConfig)
            }
            // Direct navigation to QuestionSheetView for practice retry shortcut
            .navigationDestination(item: $practiceRetrySession) { session in
                QuestionSheetView(session: session)
            }
            .onChange(of: appState.homeNavResetToken) { _, newToken in
                debugPrint("🏠 [HomeView] homeNavResetToken fired (\(newToken)) → resetting nav. showingMistakeReview=\(showingMistakeReview), showingQuestionGeneration=\(showingQuestionGeneration), selectedTab=\(appState.selectedTab)")
                showingMistakeReview = false
                showingQuestionGeneration = false
                feynmanSheetItem = nil
                practiceRetrySession = nil
                mistakeReviewInitialSubject = nil
                practiceLibraryShortcutConfig = nil
            }
            // ── Track HomeView navigation state ──────────────────────────────────
            .onChange(of: showingMistakeReview) { _, v in
                debugPrint("🏠 [HomeView.nav] showingMistakeReview → \(v) | selectedTab=\(appState.selectedTab)")
            }
            .onChange(of: showingQuestionGeneration) { _, v in
                debugPrint("🏠 [HomeView.nav] showingQuestionGeneration → \(v) | selectedTab=\(appState.selectedTab)")
            }
            .onChange(of: showingFocusMode) { _, v in
                debugPrint("🏠 [HomeView.nav] showingFocusMode → \(v) | selectedTab=\(appState.selectedTab)")
            }
            .onChange(of: appState.shouldOpenFocusMode) { _, shouldOpen in
                if shouldOpen {
                    appState.shouldOpenFocusMode = false
                    showingFocusMode = true
                }
            }
            .onChange(of: appState.shouldOpenMistakeReview) { _, shouldOpen in
                if shouldOpen {
                    appState.shouldOpenMistakeReview = false
                    showingMistakeReview = true
                }
            }
            .onChange(of: appState.shouldOpenPracticeLibrary) { _, shouldOpen in
                if shouldOpen {
                    appState.shouldOpenPracticeLibrary = false
                    practiceLibraryShortcutConfig = nil
                    showingQuestionGeneration = true
                }
            }
            .onChange(of: appState.shouldOpenDailyChallenge) { _, shouldOpen in
                if shouldOpen {
                    practiceLibraryShortcutConfig = nil
                    showingQuestionGeneration = true
                }
            }
            .onChange(of: appState.shouldOpenPointsShop) { _, shouldOpen in
                if shouldOpen {
                    appState.shouldOpenPointsShop = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        showingPointsShop = true
                    }
                }
            }
            .onChange(of: showingHomeworkAlbum) { _, v in
                debugPrint("🏠 [HomeView.nav] showingHomeworkAlbum → \(v) | selectedTab=\(appState.selectedTab)")
            }
            .onChange(of: showingProfile) { _, v in
                debugPrint("🏠 [HomeView.nav] showingProfile → \(v) | selectedTab=\(appState.selectedTab)")
            }
            .sheet(isPresented: $showingParentReports) {
                NavigationStack {
                    ParentReportsContainerView()
                }
            }
            .sheet(isPresented: $showingUpgrade) {
                UpgradeComparisonView(
                    blockedFeature: "Live Tutor",
                    reason: .featureBlocked,
                    onDismiss: { showingUpgrade = false }
                )
            }
            .sheet(isPresented: $showingGuestConversion) {
                GuestConversionView(
                    blockedFeature: "voice_minutes",
                    onDismiss: { showingGuestConversion = false }
                )
            }
            .sheet(isPresented: $showingHomeworkAlbum) {
                HomeworkAlbumView()
            }
            .fullScreenCover(isPresented: $showingFocusMode) {
                FocusView()
            }
            .sheet(item: $feynmanSheetItem) { item in
                WeaknessPracticeView(
                    weaknessKey: item.weaknessKey,
                    weaknessValue: item.weaknessValue
                )
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
                    message: "Study Reports require parent permission",
                    onSuccess: { showingParentReports = true }
                )
            }
    }

    // MARK: - Engaging Hero Header
    private var engagingHeroHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            // Left: User profile avatar
            profileAvatarView(size: 46)
                .onTapGesture { showingProfile = true }

            // Center: Greeting text — ZCOOLKuaiLe for Chinese, IndieFlower for other languages
            HStack(spacing: 4) {
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
                if let tier = AuthenticationService.shared.currentUser?.tier {
                    if tier == .premiumPlus {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "D97706"))  // gold
                    } else if tier == .premium {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "A8A9AD"))  // silver
                    }
                }
            }
                .minimumScaleFactor(0.7)

            Spacer()

            // Right: Points star + Animation toggle + Settings
            HStack(spacing: 6) {
                // Points balance — tap to open points hub
                Button(action: { showingPointsShop = true }) {
                    HomePulsingStar(isActive: pointsManager.hasUnclaimedEarnings)
                        .overlay(alignment: .topTrailing) {
                            let count = unclaimedEarningsCount
                            if count > 0 {
                                Text("\(min(count, 99))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .padding(.horizontal, 3)
                                    .background(Color.red)
                                    .clipShape(Capsule())
                                    .offset(x: 6, y: -4)
                            }
                        }
                }
                .buttonStyle(PlainButtonStyle())

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

                Button(action: { showingSettings = true }) {
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
            if customUrl.hasPrefix("data:image/"),
               let commaIndex = customUrl.firstIndex(of: ","),
               let imageData = Data(base64Encoded: String(customUrl[customUrl.index(after: commaIndex)...])),
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
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
        case .openMistakeReview(let topSubject):
            mistakeReviewInitialSubject = topSubject
            showingMistakeReview = true
        case .startFeynmanPractice(let subjectKey):
            let topWeaknesses = ShortTermStatusService.shared.getTopActiveWeaknesses(limit: 20)
            // Prefer a weakness matching the todo's subject; fall back to the highest-value weakness overall
            let chosen = topWeaknesses.first(where: {
                $0.key.hasPrefix(subjectKey + "/") || $0.key == subjectKey
            }) ?? topWeaknesses.max(by: { $0.value.value < $1.value.value })
            if let match = chosen {
                feynmanSheetItem = FeynmanSheetItem(weaknessKey: match.key, weaknessValue: match.value)
            } else {
                // No tracked weaknesses yet — WeaknessPracticeView will generate generic questions
                feynmanSheetItem = FeynmanSheetItem(
                    weaknessKey: subjectKey + "/general",
                    weaknessValue: WeaknessValue(
                        value: 0.5, firstDetected: Date(), lastAttempt: Date(),
                        totalAttempts: 0, correctAttempts: 0
                    )
                )
            }
        case .startConceptReview(let recentSessionId, let subject):
            // Open PracticeLibraryView → NewPracticeSheet pre-opened in archive tab
            // with the specific conversation auto-selected once archives load
            practiceLibraryShortcutConfig = PracticeLibraryView.ShortcutConfig(
                tab: .archive,
                subject: subject,
                conversationId: recentSessionId
            )
            showingQuestionGeneration = true
        case .startRandomPractice(let subjects):
            // Open PracticeLibraryView → NewPracticeSheet pre-opened in random tab
            // with the worst subject pre-selected
            practiceLibraryShortcutConfig = PracticeLibraryView.ShortcutConfig(
                tab: .random,
                subject: subjects.first ?? "",
                conversationId: nil
            )
            showingQuestionGeneration = true
        case .retryPracticeSession(let sessionId, _):
            // Reset progress and navigate directly to the question sheet in redo state
            PracticeSessionManager.shared.resetSessionProgress(sessionId: sessionId)
            if let session = PracticeSessionManager.shared.getSession(id: sessionId) {
                practiceRetrySession = session
            } else {
                // Session not found — fall back to the practice library
                practiceLibraryShortcutConfig = nil
                showingQuestionGeneration = true
            }
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
            guard case .allowed = FeatureGate.check(.voiceChat, user: AuthenticationService.shared.currentUser) else {
                if AuthenticationService.shared.currentUser?.isAnonymous == true {
                    showingGuestConversion = true
                } else {
                    showingUpgrade = true
                }
                return
            }
            AppState.shared.pendingChatAction = .startLiveMode(starterPrompt: NSLocalizedString("chat.liveMode.oralPractice.starterPrompt", comment: ""))
            onSelectTab(.chat)
        case .startLiveScenario(let scenario):
            guard case .allowed = FeatureGate.check(.voiceChat, user: AuthenticationService.shared.currentUser) else {
                if AuthenticationService.shared.currentUser?.isAnonymous == true {
                    showingGuestConversion = true
                } else {
                    showingUpgrade = true
                }
                return
            }
            let profile = ProfileService.shared.currentProfile
            let grade   = profile?.gradeLevel ?? ""
            let name    = profile?.firstName ?? profile?.displayName ?? userName
            let lang    = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            let prompt  = scenario.buildPrompt(grade: grade, name: name, language: lang)
            AppState.shared.pendingChatAction = .startLiveMode(starterPrompt: prompt)
            onSelectTab(.chat)
        case .showDailyQuestion(let question):
            let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            let message: String
            switch lang {
            case "zh-Hans", "zh-Hant":
                message = "请介绍关于「\(question)」相关的信息"
            case "ja":
                message = "「\(question)」について詳しく教えてください"
            case "de":
                message = "Bitte erkläre mir mehr über: \(question)"
            case "fr":
                message = "Dis-moi en plus sur : \(question)"
            case "es":
                message = "Por favor, cuéntame más sobre: \(question)"
            default:
                message = "Please tell me more about: \(question)"
            }
            AppState.shared.pendingChatAction = .sendMessage(text: message, subject: nil, useDeepMode: false)
            onSelectTab(.chat)
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
                        .foregroundColor(colorScheme == .dark ? .white : themeManager.secondaryText)
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
                        .foregroundColor(colorScheme == .dark ? .white : themeManager.secondaryText)
                }

                // Card 3: Practice
                PracticeQuickActionCard(
                    isDailyCompleted: dailyChallengeLastCompleted == todayString,
                    action: { showingQuestionGeneration = true }
                )
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

            // Fire action immediately so navigation state is set in the current SwiftUI
            // render cycle — avoids conflicts with any ongoing sheet-dismissal animations.
            action()

            // Reset press animation after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
        }) {
            ZStack {
                // Full-card rounded rectangle background
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        themeManager.quickActionCardFill(
                            color: color, cuteCircleColor: cuteCircleColor,
                            isPressed: isPressed, colorScheme: colorScheme)
                    )
                    .overlay(
                        Group {
                            if let border = themeManager.quickActionCardBorder(color: color, isPressed: isPressed) {
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(border.color, lineWidth: border.width)
                            }
                        }
                    )
                    .shadow(
                        color: themeManager.quickActionCardShadow(color: color, isPressed: isPressed, colorScheme: colorScheme).color,
                        radius: themeManager.quickActionCardShadow(color: color, isPressed: isPressed, colorScheme: colorScheme).radius,
                        x: 0, y: 2
                    )

                // Lottie or SF Symbol
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
                    Circle()
                        .fill(themeManager.iconCircleFill(color: color, isPressed: isPressed))
                        .frame(width: 50, height: 50)
                        .scaleEffect(isPressed ? 0.9 : 1.0)

                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(themeManager.iconSymbolColor(color: color, isPressed: isPressed))
                        .rotationEffect(.degrees(rotationAngle))
                        .scaleEffect(scale)
                        .onAppear {
                            withAnimationIfNotPowerSaving(
                                Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
                            ) { scale = 1.05 }
                            withAnimationIfNotPowerSaving(
                                Animation.easeInOut(duration: 3.0).repeatForever(autoreverses: true)
                            ) { rotationAngle = 3 }
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 95)
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Practice Quick Action Card (with daily badge + sliding banner)

private struct PracticeQuickActionCard: View {
    let isDailyCompleted: Bool
    let action: () -> Void

    @State private var isPressed = false
    @Environment(\.lottieRefreshID) private var lottieRefreshID
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private let mintColor = DesignTokens.Colors.Cute.mint

    var body: some View {
        VStack(spacing: 6) {
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = true }
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isPressed = false }
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(themeManager.quickActionCardFill(
                            color: themeManager.featureCardColor("practice"),
                            cuteCircleColor: mintColor,
                            isPressed: isPressed,
                            colorScheme: colorScheme))
                        .overlay(Group {
                            if let border = themeManager.quickActionCardBorder(
                                color: themeManager.featureCardColor("practice"),
                                isPressed: isPressed) {
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(border.color, lineWidth: border.width)
                            }
                        })
                        .shadow(
                            color: themeManager.quickActionCardShadow(
                                color: themeManager.featureCardColor("practice"),
                                isPressed: isPressed,
                                colorScheme: colorScheme).color,
                            radius: themeManager.quickActionCardShadow(
                                color: themeManager.featureCardColor("practice"),
                                isPressed: isPressed,
                                colorScheme: colorScheme).radius,
                            x: 0, y: 2
                        )

                    LottieView(
                        animationName: "createquiz",
                        loopMode: .loop,
                        animationSpeed: 0.5,
                        powerSavingProgress: 0.8,
                        refreshID: lottieRefreshID
                    )
                    .frame(width: 50, height: 50)
                    .scaleEffect(isPressed ? 0.117 * 0.95 : 0.117)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !isDailyCompleted {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 20, height: 20)
                                .shadow(color: Color.red.opacity(0.5), radius: 4, x: 0, y: 1)
                            Text("3")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 7)
                        .padding(.trailing, 7)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 95)
                .contentShape(RoundedRectangle(cornerRadius: 22))
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            }
            .buttonStyle(.plain)

            Text(NSLocalizedString("home.quickAction.practice", value: "练习本", comment: ""))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white : themeManager.secondaryText)
        }
    }
}

// MARK: - Home Pulsing Star (Points icon on home screen)

/// Self-contained pulsing star that gently scales up/down when active.
/// Completely isolated — animation state is internal, cannot leak to other views.
private struct HomePulsingStar: View {
    let isActive: Bool
    @State private var isPulsing = false

    private let goldColor = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        ZStack {
            Circle()
                .fill(goldColor.opacity(0.12))
                .frame(width: 36, height: 36)

            Image(systemName: "star.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(goldColor)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
        }
        .frame(width: 36, height: 36)
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isActive) { _, active in
            if active {
                startPulseIfNeeded()
            } else {
                withAnimation(.easeOut(duration: 0.3)) { isPulsing = false }
            }
        }
    }

    private func startPulseIfNeeded() {
        guard isActive else { return }
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
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

            // Fire action immediately so navigation state is set in the current SwiftUI
            // render cycle — avoids conflicts with any ongoing sheet-dismissal animations.
            action()

            // Reset press animation after short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimationIfNotPowerSaving(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    if lottieAnimation == nil {
                        Circle()
                            .fill(themeManager.iconCircleFill(color: color, isPressed: isPressed))
                            .frame(width: 42, height: 42)
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
                        .frame(width: 34, height: 34)
                        .scaleEffect(isPressed ? lottieScale * 0.7 * 0.95 : lottieScale * 0.7)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22))
                            .foregroundColor(themeManager.iconSymbolColor(color: color, isPressed: isPressed))
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
                        .foregroundColor(themeManager.cardTextPrimary)
                        .fontWeight(.medium)

                    Text(subtitle)
                        .font(DesignTokens.Typography.caption1)
                        .foregroundColor(themeManager.cardTextSecondary)
                }
                .padding(.leading, 20)

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.cardTextSecondary)
                    .offset(x: isPressed ? 3 : 0)
            }
            .padding(12)
            .background(
                themeManager.horizontalCardFill(color: color, isPressed: isPressed, colorScheme: colorScheme)
            )
            .cornerRadius(16)
            .overlay(
                Group {
                    if let border = themeManager.horizontalCardBorder(color: color, isPressed: isPressed, colorScheme: colorScheme) {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(border.color, lineWidth: border.width)
                    }
                }
            )
            .shadow(
                color: themeManager.horizontalCardShadow(color: color, isPressed: isPressed, colorScheme: colorScheme).color,
                radius: themeManager.horizontalCardShadow(color: color, isPressed: isPressed, colorScheme: colorScheme).radius,
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
