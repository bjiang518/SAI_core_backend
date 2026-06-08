//
//  HomeView.swift
//  StudyAI
//
//  Enhanced UI Implementation
//

import SwiftUI
import UIKit
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
    /// Pre-open knowledge tree tab in MistakeReviewView
    @State private var mistakeReviewShowKnowledgeTree: Bool = false
    /// Config passed to PracticeLibraryView → NewPracticeSheet (random or concept review shortcuts)
    @State private var practiceLibraryShortcutConfig: PracticeLibraryView.ShortcutConfig? = nil
    /// Direct navigation to QuestionSheetView for the practice retry shortcut
    @State private var practiceRetrySession: PracticeSession? = nil
    @State private var showingParentReports = false
    @State private var showingHomeworkAlbum = false
    @State private var showingFocusMode = false
    @State private var feynmanSheetItem: FeynmanSheetItem? = nil
    @State private var showingVideoLearning = false
    @State private var videoLearningSubject: String = ""
    @State private var videoLearningTopic: String = ""
    @State private var videoLearningBranch: String = ""
    @State private var lottieRefreshID: Int = 0
    @State private var isMoreFeaturesExpanded: Bool = true
    @State private var showingPointsShop: Bool = false
    @State private var streakBonusClaimed: Int = 0
    @State private var showStreakBonusToast: Bool = false

    // Home onboarding (coach-mark tour). Plays once per user, immediately
    // after FirstTimeOnboardingView completes on initial signup. Persisted
    // via @AppStorage("homeOnboardingCompleted"); never replays once the
    // user reaches the last step or taps Skip.
    @AppStorage("homeOnboardingCompleted") private var homeOnboardingCompleted = false
    @State private var homeOnboardingStep: HomeOnboardingStep = .askAI
    @State private var homeOnboardingAnchors: [String: CGRect] = [:]
    @State private var homeOnboardingActive: Bool = false
    // In-session re-entrancy guard. `tryStartHomeOnboarding` may be called
    // from multiple lifecycle hooks (onAppear, profile-loaded onChange);
    // this flag ensures only the first call actually fires the tour, even
    // if the gates pass several times in a row.
    @State private var homeOnboardingShownThisSession: Bool = false

    // ✅ Dark Mode Support: Detect current color scheme
    @Environment(\.colorScheme) var colorScheme
    // iPad vs iPhone layout
    @Environment(\.horizontalSizeClass) var sizeClass
    // Lifecycle phase — used to clear the SpotlightWindow scrim if the user
    // backgrounds the app mid-onboarding (otherwise the dark layer can
    // bleed into the next foreground transition).
    @Environment(\.scenePhase) private var scenePhase

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
        mainBody.modifier(HomeOnboardingHostModifier(
            active: homeOnboardingActive,
            scenePhase: scenePhase,
            anchors: $homeOnboardingAnchors,
            overlay: { homeOnboardingOverlayLayer }
        ))
    }

    /// Renamed from `body` so its enormous modifier chain (10+ .onChange,
    /// 8+ .sheet/.fullScreenCover, multiple .navigationDestination) is
    /// type-checked in isolation. Adding the onboarding overlay's
    /// .onPreferenceChange + .overlay directly to this chain pushed Swift's
    /// type-checker past its complexity threshold.
    private var mainBody: some View {
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
                    .homeOnboardingAnchor("home_suggestedTodos")

                    // More features — sits flush below the suggestion card
                    additionalActionsSection
                        .padding(.top, DesignTokens.Spacing.lg)
                        .environment(\.lottieRefreshID, lottieRefreshID)

                    Spacer(minLength: 100)
                }
                .padding(.bottom, DesignTokens.Spacing.md)
            }
            .background(themeManager.backgroundColor.ignoresSafeArea())
            .navigationBarHidden(UIDevice.current.userInterfaceIdiom != .pad)
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(Screen.home)
            .onAppear {
                lottieRefreshID += 1
                todoEngine.fetchAndRefresh()
                updateUserName(from: profileService.currentProfile ?? profileService.loadCachedProfile())

                // Schedule streak protection notification if no activity today
                if pointsManager.todayProgress?.totalQuestions == 0 && pointsManager.currentStreak > 2 {
                    NotificationService.shared.scheduleStreakProtectionReminder(currentStreak: pointsManager.currentStreak)
                }

                // Warm the chat empty-state suggested-prompts cache so the chat
                // marquee renders instantly when the user enters chat. Fire and
                // forget — failure simply means the chat falls back to the
                // network call on enter.
                Task.detached(priority: .background) {
                    let grade = await ProfileService.shared.currentProfile?.gradeLevel
                    let lang  = await NetworkService.shared.currentLanguage
                    _ = await NetworkService.shared.fetchSuggestedPrompts(
                        subject: "General",
                        gradeLevel: grade,
                        language: lang
                    )
                }

                // Kick off the home onboarding tour — first-time-only.
                // Plays once after the user finishes FirstTimeOnboardingView
                // (full-screen profile setup) on initial signup. The tour is
                // gated on `homeOnboardingCompleted` (AppStorage), so once
                // shown or skipped it never re-appears.
                //
                // Two trigger points handle SwiftUI's lifecycle:
                //   1) onAppear here — for users who finished
                //      FirstTimeOnboardingView in a previous session but
                //      somehow didn't complete the home tour.
                //   2) `onChange(of: profileService.currentProfile)` below —
                //      for the canonical first-time path: HomeView is
                //      mounted under the FirstTimeOnboardingView cover, its
                //      onAppear fires BEFORE the profile is loaded, then
                //      the user finishes the cover and the profile arrives.
                tryStartHomeOnboarding()
            }
            .onReceive(profileService.$currentProfile) { profile in
                updateUserName(from: profile)
                // First-time-login path: HomeView's onAppear fires under
                // the FirstTimeOnboardingView cover before the profile
                // exists, so the home tour can't start there. The profile
                // arriving (FirstTimeOnboardingView wrote it, or the user
                // just signed in and we fetched it) is the canonical signal
                // that "the user is now ready to see the home tour".
                if profile != nil {
                    tryStartHomeOnboarding()
                }
            }
            // Third trigger — the launch-loading splash dismissing. If
            // onAppear / the profile change fired while the splash was up,
            // the gate rejected the start. Catching the splash transition
            // false → done means we don't lose the tour.
            .onReceive(appState.$isLoadingAnimationActive) { isShowing in
                if !isShowing {
                    tryStartHomeOnboarding()
                }
            }
            // Fourth trigger — the FirstTimeOnboardingView fullScreenCover
            // dismissing. Same idea: HomeView's onAppear / profile-change
            // fire while the cover is up; we need to catch the moment the
            // user actually finishes the trial pitch and lands on home.
            .onReceive(appState.$isFirstTimeOnboardingActive) { isShowing in
                if !isShowing {
                    tryStartHomeOnboarding()
                }
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
                MistakeReviewView(initialSubject: mistakeReviewInitialSubject,
                                  initialShowKnowledgeTree: mistakeReviewShowKnowledgeTree)
            }
            .navigationDestination(isPresented: $showingQuestionGeneration) {
                PracticeLibraryView(shortcutConfig: practiceLibraryShortcutConfig)
            }
            // Direct navigation to QuestionSheetView for practice retry shortcut
            .navigationDestination(item: $practiceRetrySession) { session in
                QuestionSheetView(session: session)
            }
            // 8 routing `.onChange` handlers (homeNavResetToken + 7
            // appState.shouldOpen* flags) bundled into a single modifier
            // application. SwiftUI generates a `ModifiedContent<...>`
            // generic layer per chained modifier; mainBody already has
            // 8+ sheets/navigation destinations, so leaving these as a
            // chain pushed Xcode IDE's incremental type-checker over its
            // budget ("compiler unable to type-check in reasonable time").
            // Encapsulating them collapses the inferred type to a single
            // concrete-modifier application.
            .modifier(HomeViewAppStateRouting(
                appState: appState,
                showingMistakeReview: $showingMistakeReview,
                showingQuestionGeneration: $showingQuestionGeneration,
                showingFocusMode: $showingFocusMode,
                showingPointsShop: $showingPointsShop,
                feynmanSheetItem: $feynmanSheetItem,
                practiceRetrySession: $practiceRetrySession,
                mistakeReviewInitialSubject: $mistakeReviewInitialSubject,
                mistakeReviewShowKnowledgeTree: $mistakeReviewShowKnowledgeTree,
                practiceLibraryShortcutConfig: $practiceLibraryShortcutConfig
            ))
            .sheet(isPresented: $showingParentReports) {
                NavigationStack {
                    ParentReportsContainerView()
                }
            }
            .modifier(HomeViewBottomPresentations(
                showingUpgrade: $showingUpgrade,
                showingGuestConversion: $showingGuestConversion,
                showingHomeworkAlbum: $showingHomeworkAlbum,
                showingFocusMode: $showingFocusMode,
                showingVideoLearning: $showingVideoLearning,
                videoLearningTopic: videoLearningTopic,
                videoLearningBranch: videoLearningBranch,
                videoLearningSubject: videoLearningSubject,
                feynmanSheetItem: $feynmanSheetItem,
                showingParentAuthForChat: $showingParentAuthForChat,
                showingParentAuthForGrader: $showingParentAuthForGrader,
                showingParentAuthForReports: $showingParentAuthForReports,
                showingParentReports: $showingParentReports,
                onSelectTab: onSelectTab
            ))
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
                .homeOnboardingAnchor("home_pointsShop")

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
            mistakeReviewShowKnowledgeTree = false
            showingMistakeReview = true
        case .openKnowledgeTree(let subject):
            mistakeReviewInitialSubject = subject
            mistakeReviewShowKnowledgeTree = true
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
        case .openVideoLearning(let subject, let topicName, let branchName):
            videoLearningSubject = subject
            videoLearningTopic   = topicName
            videoLearningBranch  = branchName
            showingVideoLearning = true
        case .continueIncompleteSession(let sessionId, _):
            AppState.shared.pendingPracticeSessionId = sessionId
            AppState.shared.shouldOpenIncompleteSession = true
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

    // MARK: - Home Onboarding Helpers

    /// Extracted into its own @ViewBuilder so the body's modifier chain stays
    /// short — inlining this triggered "type-check too complex" on body.
    @ViewBuilder
    private var homeOnboardingOverlayLayer: some View {
        if homeOnboardingActive {
            HomeOnboardingOverlayView(
                step: homeOnboardingStep,
                anchors: homeOnboardingAnchors,
                onNext: advanceHomeOnboarding,
                onSkip: dismissHomeOnboarding
            )
            .transition(.opacity)
            .zIndex(999)
        }
    }

    /// Tap "Next" — either advance to the next step or finish if last.
    private func advanceHomeOnboarding() {
        let next = homeOnboardingStep.rawValue + 1
        if next >= HomeOnboardingStep.allCases.count {
            dismissHomeOnboarding()
            return
        }
        if let nextStep = HomeOnboardingStep(rawValue: next) {
            withAnimation(.easeInOut(duration: 0.25)) {
                homeOnboardingStep = nextStep
            }
        }
    }

    /// Tap "Skip" or finish last step — hide the overlay and persist the flag.
    private func dismissHomeOnboarding() {
        // Classify before tearing down: if the user is on the LAST step when
        // dismiss fires, it's because advanceHomeOnboarding tapped Next past
        // the end → "completed". Anything earlier is the Skip button →
        // "skipped". Distinguishing these lets the dashboard see real
        // completion rate vs. drop-off step distribution.
        let total = HomeOnboardingStep.allCases.count
        let currentStep = homeOnboardingStep.rawValue
        if currentStep == total - 1 {
            JourneyTracker.shared.track("onboarding_tour_completed", [
                "total_steps": total,
            ])
        } else {
            JourneyTracker.shared.track("onboarding_tour_skipped", [
                "at_step":      currentStep,
                "at_step_name": String(describing: homeOnboardingStep),
                "total_steps":  total,
            ])
        }

        // Synchronously hide the UIKit scrim BEFORE the SwiftUI animation
        // runs. The animation flips homeOnboardingActive → false, which
        // unmounts HomeOnboardingOverlayView, but its onDisappear races with
        // the next view's render — sometimes the scrim survives the
        // transition and bleeds into the loading splash. Hiding here closes
        // that window.
        SpotlightWindow.hide()
        withAnimation(.easeInOut(duration: 0.25)) {
            homeOnboardingActive = false
            // Restore the CuteTabBar.
            appState.isHomeOnboardingActive = false
        }
        homeOnboardingCompleted = true
    }

    /// Idempotent gate for the home tour. Safe to call from any trigger
    /// point (onAppear, profile-loaded change). Only the first call that
    /// passes all gates actually starts the tour; subsequent calls no-op
    /// because `homeOnboardingShownThisSession` flips on first success.
    private func tryStartHomeOnboarding() {
        guard !homeOnboardingCompleted else { return }
        guard !homeOnboardingShownThisSession else { return }
        guard !homeOnboardingActive else { return }
        let profile = profileService.currentProfile ?? profileService.loadCachedProfile()
        guard profile != nil else { return }
        // Hold off while the launch loading splash is on screen — the UIKit
        // scrim is added directly to the window and would otherwise leak
        // above the splash, leaving a dimmed/cutout look on top of the
        // "loading…" view.
        guard !appState.isLoadingAnimationActive else { return }
        // Same problem with the FirstTimeOnboardingView fullScreenCover —
        // HomeView is mounted underneath it, so its lifecycle hooks fire
        // before the user has dismissed the trial pitch. The window-level
        // scrim would dim the trial pitch instead of the home screen.
        guard !appState.isFirstTimeOnboardingActive else { return }

        homeOnboardingShownThisSession = true
        isMoreFeaturesExpanded = true

        // Fire BEFORE the 0.6s delay so we see the start event even if the
        // user immediately backgrounds the app. Pairs with the completed /
        // skipped events emitted by dismissHomeOnboarding() to form the
        // "Onboarding Tour" funnel on the Insights dashboard.
        JourneyTracker.shared.track("onboarding_tour_started", [
            "total_steps": HomeOnboardingStep.allCases.count,
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            // Re-check at fire-time. Loading splashes / fullScreenCovers
            // can race with the 0.6s timer. If a blocker is still up,
            // roll back the session flag so the next trigger retries.
            guard !appState.isLoadingAnimationActive,
                  !appState.isFirstTimeOnboardingActive else {
                homeOnboardingShownThisSession = false
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                homeOnboardingActive = true
                // Hide CuteTabBar so the spotlight isn't blocked at the
                // bottom of the screen.
                appState.isHomeOnboardingActive = true
            }
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
                    .homeOnboardingAnchor("home_askAI")
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
                    .homeOnboardingAnchor("home_snapHomework")
                    Text(NSLocalizedString("home.quickAction.homework", value: "作业批改", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : themeManager.secondaryText)
                }

                // Card 3: Practice
                PracticeQuickActionCard(
                    isDailyCompleted: dailyChallengeLastCompleted == todayString,
                    action: { showingQuestionGeneration = true }
                )
                .homeOnboardingAnchor("home_practice")
            }
            .padding(.horizontal, DesignTokens.Spacing.xl)
        }
    }

    // MARK: - Additional Actions Section
    private var additionalActionsSection: some View {
        VStack(spacing: 0) {
            // Cards expand FIRST so the chevron sits at the bottom of the whole block —
            // avoids the awkward "two stacked chevrons" look between this section and
            // the SuggestedTodos section above.
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

            // Centered divider + chevron toggle — now anchored at the bottom of the cards.
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
            .padding(.top, isMoreFeaturesExpanded ? DesignTokens.Spacing.md : DesignTokens.Spacing.sm)
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
            action: {
                mistakeReviewShowKnowledgeTree = false
                showingMistakeReview = true
            }
        )
        .homeOnboardingAnchor("home_mistakeReview")

        // Card 6b: Knowledge & Learning (knowledge tree)
        HorizontalActionButton(
            icon: "leaf.fill",
            title: NSLocalizedString("home.knowledgeLearning", value: "Knowledge & Learning", comment: ""),
            subtitle: NSLocalizedString("home.knowledgeLearningDescription", value: "Explore your knowledge tree", comment: ""),
            color: DesignTokens.Colors.Cute.mint,
            lottieAnimation: "Tree",
            lottieScale: 0.06,
            action: {
                mistakeReviewShowKnowledgeTree = true
                showingMistakeReview = true
            }
        )
        .homeOnboardingAnchor("home_knowledgeTree")

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
        .homeOnboardingAnchor("home_focusMode")

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
        .homeOnboardingAnchor("home_parentReports")

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
        .homeOnboardingAnchor("home_progress")
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

// MARK: - HomeOnboardingOverlay
//
// Coach-mark tour for HomeView, shown once on first home appearance.
// Walks the user through every primary button on the home screen with
// rich descriptions that highlight headline use cases AND hidden features
// (Live Mode, Deep grading, archive-driven practice generation, etc.)
//
// Mirrors ChatOnboardingOverlay's pattern: each highlighted button is
// tagged with `.homeOnboardingAnchor(id)`. The overlay reads anchors via
// a PreferenceKey and dims the screen with the existing UIKit-level
// SpotlightWindowOverlay (declared in ChatOnboardingOverlay.swift),
// punching a transparent hole at the target button + a hole for the
// SwiftUI callout card.

enum HomeOnboardingStep: Int, CaseIterable {
    case askAI          = 0
    case snapHomework   = 1
    case practice       = 2
    case suggestedTodos = 3
    case mistakeReview  = 4
    case knowledgeTree  = 5
    case focusMode      = 6
    case parentReports  = 7
    case progress       = 8
    case pointsShop     = 9    // moved to end of tour

    var isLast: Bool { rawValue == HomeOnboardingStep.allCases.count - 1 }

    var anchorID: String {
        switch self {
        case .askAI:          return "home_askAI"
        case .snapHomework:   return "home_snapHomework"
        case .practice:       return "home_practice"
        case .suggestedTodos: return "home_suggestedTodos"
        case .mistakeReview:  return "home_mistakeReview"
        case .knowledgeTree:  return "home_knowledgeTree"
        case .focusMode:      return "home_focusMode"
        case .parentReports:  return "home_parentReports"
        case .progress:       return "home_progress"
        case .pointsShop:     return "home_pointsShop"
        }
    }

    /// SF Symbol shown next to the step's title in the callout card.
    /// Reuses the home button's existing icon — no new icons added.
    var sfSymbol: String {
        switch self {
        case .askAI:          return "message.fill"
        case .snapHomework:   return "camera.fill"
        case .practice:       return "pencil.and.list.clipboard"
        case .suggestedTodos: return "list.bullet.rectangle"
        case .mistakeReview:  return "xmark.circle.fill"
        case .knowledgeTree:  return "leaf.fill"
        case .focusMode:      return "brain.head.profile"
        case .parentReports:  return "figure.2.and.child.holdinghands"
        case .progress:       return "chart.bar.fill"
        case .pointsShop:     return "star.fill"
        }
    }

    /// Whether the highlighted button sits in the top half of the screen
    /// (Quick Actions row + the points-shop badge in the header). Cards for
    /// these go BELOW the spotlight; everything else gets the card ABOVE.
    var isTopRow: Bool {
        switch self {
        case .askAI, .snapHomework, .practice, .pointsShop: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .askAI:
            return NSLocalizedString("homeOnboarding.askAI.title",
                value: "Ask AI — your real-time tutor", comment: "")
        case .snapHomework:
            return NSLocalizedString("homeOnboarding.snapHomework.title",
                value: "Snap homework — graded in seconds", comment: "")
        case .practice:
            return NSLocalizedString("homeOnboarding.practice.title",
                value: "Practice that targets you", comment: "")
        case .suggestedTodos:
            return NSLocalizedString("homeOnboarding.suggestedTodos.title",
                value: "Your daily plan, AI-curated", comment: "")
        case .mistakeReview:
            return NSLocalizedString("homeOnboarding.mistakeReview.title",
                value: "Every mistake, organized", comment: "")
        case .knowledgeTree:
            return NSLocalizedString("homeOnboarding.knowledgeTree.title",
                value: "Learn + practice, on a living tree", comment: "")
        case .focusMode:
            return NSLocalizedString("homeOnboarding.focusMode.title",
                value: "Focus 25 min, grow tomatoes", comment: "")
        case .parentReports:
            return NSLocalizedString("homeOnboarding.parentReports.title",
                value: "Weekly reports, AI-written", comment: "")
        case .progress:
            return NSLocalizedString("homeOnboarding.progress.title",
                value: "Your study story, over time", comment: "")
        case .pointsShop:
            return NSLocalizedString("homeOnboarding.pointsShop.title",
                value: "Earn points, redeem rewards", comment: "")
        }
    }

    /// Rich, scannable copy. Uses two inline tokens:
    ///   • {sfsymbol:name} — renders as an SF Symbol, e.g. {sfsymbol:ellipsis.circle}
    ///   • {hl}word{/hl}    — marker-pen highlight (color cycles through palette)
    /// Source-of-truth: Docs/HomeOnboarding.md
    var description: String {
        switch self {
        case .askAI:
            return NSLocalizedString("homeOnboarding.askAI.desc",
                value: "Type, voice, or photo. Answers in seconds.\n\n• {hl}Practice on the spot{/hl} from any chat topic.\n\n• {hl}Smart Learning{/hl} → AI video lessons.\n\n• Ask for {hl}diagrams{/hl} — visuals for hard concepts.\n\n• {sfsymbol:ellipsis.circle} menu → {hl}Live Mode{/hl} voice + scenarios.\n\n• {sfsymbol:archivebox.fill} {hl}Archive{/hl} chats — only saved ones train your tutor.",
                comment: "")

        case .snapHomework:
            return NSLocalizedString("homeOnboarding.snapHomework.desc",
                value: "Photo any worksheet (1–5 pages) → step-by-step solutions.\n\n• Toggle {hl}Deep{/hl} for hard problems — thinking-tier reasoning.\n\n• Wrong answers auto-flow to {hl}Mistake Review{/hl}, smart-organized.\n\n• Tap any question to {hl}ask a follow-up{/hl}.\n\n• Save as a {hl}digital workbook{/hl} — long-lived, sharable.",
                comment: "")

        case .practice:
            return NSLocalizedString("homeOnboarding.practice.desc",
                value: "Built for your grade, style, and weak spots — never generic.\n\n• {hl}Daily Challenge{/hl} — 3 fresh questions every day.\n\n• {hl}Real question banks{/hl} from textbooks, AMC, curated sets.\n\n• 3 modes: Random · From Mistakes · From a Saved Chat.\n\n• All sessions live here — auto-saved as {hl}sharable PDFs{/hl}.",
                comment: "")

        case .suggestedTodos:
            return NSLocalizedString("homeOnboarding.suggestedTodos.desc",
                value: "Daily AI-curated plan — what's most useful right now.\n\n• Built from {hl}your real data{/hl}: weak topics, expiring streaks.\n\n• {hl}One tap{/hl} → straight to the right place.\n\n• Swipe to dismiss; tap refresh to regenerate.\n\n• Smarter every day you use it.",
                comment: "")

        case .mistakeReview:
            return NSLocalizedString("homeOnboarding.mistakeReview.desc",
                value: "Every wrong answer, auto-grouped by subject and topic.\n\n• AI labels each {hl}error type{/hl} — know what to fix.\n\n• Tap to retry, or {hl}\"Practice these\"{/hl} for a whole batch.\n\n• Filter by subject / error / time.\n\n• Powers {hl}\"From Mistakes\"{/hl} practice — smarter as you review.",
                comment: "")

        case .knowledgeTree:
            return NSLocalizedString("homeOnboarding.knowledgeTree.desc",
                value: "Every concept = a leaf. {hl}Green = mastered{/hl}, gray = unexplored.\n\n• {hl}Learn{/hl} → tap any leaf for an AI video lesson.\n\n• {hl}Practice{/hl} → questions from the video or your tree position.\n\n• {hl}\"Light up the tree\"{/hl} auto-fills gray leaves.\n\n• Watch branches grow over weeks.",
                comment: "")

        case .focusMode:
            return NSLocalizedString("homeOnboarding.focusMode.desc",
                value: "25-min Pomodoro = 1 collectible tomato. 13 types · 4 tiers.\n\n• {hl}5 same-tier{/hl} → exchange for a rarer one (Diamond is end-game).\n\n• Real physics garden — pile up, roll, settle.\n\n• Pair with {hl}focus music{/hl} for deep work.\n\n• Daily streak grows your garden.",
                comment: "")

        case .parentReports:
            return NSLocalizedString("homeOnboarding.parentReports.desc",
                value: "AI-written weekly report of what your child actually studied.\n\n• {hl}Subject-by-subject{/hl}: time, accuracy, weak areas, recommendations.\n\n• Plain language — no jargon, real advice.\n\n• {hl}Multi-child support{/hl} for siblings.\n\n• Tap any past week to compare progress.",
                comment: "")

        case .progress:
            return NSLocalizedString("homeOnboarding.progress.desc",
                value: "Weeks of study → a single picture.\n\n• {hl}Subject breakdown{/hl}: time, accuracy, mastery growth.\n\n• {hl}Streak calendar{/hl} — every active day at a glance.\n\n• {hl}AI insights{/hl} — 3 weekly tips from your real data.\n\n• Tap any chart to drill into questions and chats.",
                comment: "")

        case .pointsShop:
            return NSLocalizedString("homeOnboarding.pointsShop.desc",
                value: "Every answer, mistake corrected, Pomodoro = points.\n\n• Stacks: {hl}streak bonus + daily challenge + milestones{/hl}.\n\n• Spend on {hl}streak freezes{/hl} and rare tomato unlocks.\n\n• {sfsymbol:star.fill} badge = today's unclaimed bonuses.",
                comment: "")
        }
    }

    /// Step-specific accent — matches the home button's tint when possible.
    var accent: Color {
        switch self {
        case .askAI:          return DesignTokens.Colors.Cute.blue
        case .snapHomework:   return DesignTokens.Colors.Cute.yellow
        case .practice:       return DesignTokens.Colors.Cute.peach
        case .suggestedTodos: return DesignTokens.Colors.Cute.pink
        case .mistakeReview:  return Color(red: 0.45, green: 0.40, blue: 0.95)
        case .knowledgeTree:  return DesignTokens.Colors.Cute.mint
        case .focusMode:      return Color(red: 0.20, green: 0.80, blue: 0.70)
        case .parentReports:  return DesignTokens.Colors.Cute.lavender
        case .progress:       return DesignTokens.Colors.Cute.blue
        case .pointsShop:     return DesignTokens.Colors.Cute.yellow
        }
    }

    var spotlightCornerRadius: CGFloat { isTopRow ? 22 : 18 }
}

/// Bundles the home onboarding host view's lifecycle modifiers into one
/// `ViewModifier`. Without this, the chain of `.toolbar` + `.overlay` +
/// `.onPreferenceChange` + multiple `.onChange` modifiers applied directly
/// to `mainBody` (which already has 8+ sheets and a few navigation
/// destinations) blew past Swift's incremental type-check budget — Xcode
/// reported "compiler is unable to type-check this expression in reasonable
/// time" on the body. Encapsulating them collapses the inferred generic
/// chain into a single application of a concrete modifier.
private struct HomeOnboardingHostModifier<Overlay: View>: ViewModifier {
    let active: Bool
    let scenePhase: ScenePhase
    @Binding var anchors: [String: CGRect]
    let overlay: () -> Overlay

    func body(content: Content) -> some View {
        content
            .toolbar(active ? .hidden : .visible, for: .tabBar)
            .onPreferenceChange(HomeOnboardingAnchorKey.self) { dict in
                anchors = dict
            }
            .overlay { overlay() }
            // SwiftUI's removal-timing isn't guaranteed when a parent
            // (tab switch, mid-session relaunch) unmounts the overlay
            // before its onDisappear fires. The leftover dark scrim
            // bleeds into the next view. Explicitly hide here when the
            // active flag flips off so no orphan scrim survives.
            .onChange(of: active) { _, isActive in
                if !isActive { SpotlightWindow.hide() }
            }
            // Same defense on backgrounding — clear the scrim before the
            // next foreground transition can flash it.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { SpotlightWindow.hide() }
            }
    }
}

/// Bundles all 8 routing `.onChange` handlers (homeNavResetToken +
/// `appState.shouldOpen*` flags) into a single `ViewModifier`. Same
/// rationale as the other Home modifiers: keeps mainBody's modifier chain
/// short enough for Xcode's incremental type-checker. No behavioral change.
private struct HomeViewAppStateRouting: ViewModifier {
    @ObservedObject var appState: AppState
    @Binding var showingMistakeReview: Bool
    @Binding var showingQuestionGeneration: Bool
    @Binding var showingFocusMode: Bool
    @Binding var showingPointsShop: Bool
    @Binding var feynmanSheetItem: FeynmanSheetItem?
    @Binding var practiceRetrySession: PracticeSession?
    @Binding var mistakeReviewInitialSubject: String?
    @Binding var mistakeReviewShowKnowledgeTree: Bool
    @Binding var practiceLibraryShortcutConfig: PracticeLibraryView.ShortcutConfig?

    func body(content: Content) -> some View {
        content
            .onChange(of: appState.homeNavResetToken) { _, newToken in
                debugPrint("🏠 [HomeView] homeNavResetToken fired (\(newToken)) → resetting nav. showingMistakeReview=\(showingMistakeReview), showingQuestionGeneration=\(showingQuestionGeneration), selectedTab=\(appState.selectedTab)")
                showingMistakeReview = false
                showingQuestionGeneration = false
                feynmanSheetItem = nil
                practiceRetrySession = nil
                mistakeReviewInitialSubject = nil
                mistakeReviewShowKnowledgeTree = false
                practiceLibraryShortcutConfig = nil
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
                    mistakeReviewInitialSubject = appState.pendingMistakeReviewSubject
                    mistakeReviewShowKnowledgeTree = appState.pendingMistakeReviewShowKnowledgeTree
                    appState.pendingMistakeReviewSubject = nil
                    appState.pendingMistakeReviewShowKnowledgeTree = false
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
            .onChange(of: appState.shouldOpenWeaknessPractice) { _, shouldOpen in
                guard shouldOpen else { return }
                appState.shouldOpenWeaknessPractice = false
                if let key = appState.pendingWeaknessKey,
                   let weaknessValue = ShortTermStatusService.shared.status.activeWeaknesses[key] {
                    appState.pendingWeaknessKey = nil
                    feynmanSheetItem = FeynmanSheetItem(weaknessKey: key, weaknessValue: weaknessValue)
                } else {
                    // Weakness was resolved — fall back to Mistake Review
                    appState.pendingWeaknessKey = nil
                    showingMistakeReview = true
                }
            }
            .onChange(of: appState.shouldOpenIncompleteSession) { _, shouldOpen in
                guard shouldOpen else { return }
                appState.shouldOpenIncompleteSession = false
                if let sessionId = appState.pendingPracticeSessionId,
                   let session = PracticeSessionManager.shared.getSession(id: sessionId) {
                    appState.pendingPracticeSessionId = nil
                    practiceRetrySession = session
                } else {
                    // Session completed or expired — fall back to practice library
                    appState.pendingPracticeSessionId = nil
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
    }
}

/// Tail of `mainBody` — sheets/full-screen covers / parent-auth gates that
/// don't fit on the Home screen but need to live inside HomeView's view
/// hierarchy. Extracted into a modifier so the type-checker sees ONE
/// concrete modifier application rather than 9 chained generic
/// `ModifiedContent<...>` layers; without this, mainBody trips Xcode IDE's
/// incremental type-check budget ("compiler unable to type-check in
/// reasonable time").
private struct HomeViewBottomPresentations: ViewModifier {
    @Binding var showingUpgrade: Bool
    @Binding var showingGuestConversion: Bool
    @Binding var showingHomeworkAlbum: Bool
    @Binding var showingFocusMode: Bool
    @Binding var showingVideoLearning: Bool
    let videoLearningTopic: String
    let videoLearningBranch: String
    let videoLearningSubject: String
    @Binding var feynmanSheetItem: FeynmanSheetItem?
    @Binding var showingParentAuthForChat: Bool
    @Binding var showingParentAuthForGrader: Bool
    @Binding var showingParentAuthForReports: Bool
    @Binding var showingParentReports: Bool
    let onSelectTab: (MainTab) -> Void

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $showingUpgrade) {
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
            .fullScreenCover(isPresented: $showingVideoLearning) {
                LearningView(
                    topicName: videoLearningTopic,
                    branchName: videoLearningBranch,
                    subject: videoLearningSubject,
                    unlitLeafKey: nil
                )
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
}

struct HomeOnboardingAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func homeOnboardingAnchor(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: HomeOnboardingAnchorKey.self,
                                value: [id: geo.frame(in: .global)])
            }
        )
    }
}

// We own our own UIKit-sync key so we don't collide with ChatOnboarding's
// fileprivate equivalent. The shape is identical — converted to UIKitSyncData
// (declared in ChatOnboardingOverlay.swift) before pushing to SpotlightWindow.
private struct HomeUIKitSyncData: Equatable {
    var spotlightRect: CGRect
    var cardRect: CGRect
    var spotlightRadius: CGFloat
    var cardRadius: CGFloat = 18
}

private struct HomeUIKitSyncKey: PreferenceKey {
    static var defaultValue = HomeUIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )
    static func reduce(value: inout HomeUIKitSyncData, nextValue: () -> HomeUIKitSyncData) {
        value = nextValue()
    }
}

/// Captures the natural rendered height of the callout card so the UIKit
/// scrim's transparent hole matches it exactly. Without this the card
/// overflows or gets cropped when descriptions wrap.
private struct HomeCardSizeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HomeOnboardingOverlayView: View {
    let step: HomeOnboardingStep
    let anchors: [String: CGRect]
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.85
    @State private var cachedSync = HomeUIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )
    // Measured card height — captured via .onPreferenceChange so the UIKit
    // cutout always matches the SwiftUI card's natural rendered size, even
    // when descriptions wrap to extra lines.
    @State private var measuredCardHeight: CGFloat = 0

    // Card sizing — wider/taller than ChatOnboarding's because each step has
    // a multi-paragraph description that surfaces hidden features.
    private let cardW: CGFloat = 340
    /// Fallback height before the card has been measured for the first time.
    private let cardHFallback: CGFloat = 380

    var body: some View {
        GeometryReader { geo in
            // Use the measured card height once available; fall back to a
            // generous default until the first render captures it.
            let cardH = max(measuredCardHeight, cardHFallback)
            let sRect = spotlightRect(in: geo)
            let cPos  = cardPosition(in: geo, spotlightRect: sRect, cardH: cardH)
            let cRect = CGRect(
                x: cPos.x - cardW / 2, y: cPos.y - cardH / 2,
                width: cardW, height: cardH
            )

            ZStack {
                // Tap-through hit layer — UIKit handles the actual dimming.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onNext() }

                // Pulsing ring around the highlighted button.
                if !sRect.isEmpty {
                    RoundedRectangle(cornerRadius: step.spotlightCornerRadius)
                        .strokeBorder(step.accent.opacity(pulseOpacity), lineWidth: 2.5)
                        .frame(width: sRect.width, height: sRect.height)
                        .scaleEffect(pulseScale)
                        .position(x: sRect.midX, y: sRect.midY)
                        .allowsHitTesting(false)
                }

                calloutCard
                    .frame(width: cardW)
                    // Capture the rendered height so the UIKit cutout matches
                    // exactly — fixes overlap/clip issues when content wraps.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HomeCardSizeKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    .position(cPos)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            .preference(key: HomeUIKitSyncKey.self, value: HomeUIKitSyncData(
                spotlightRect: sRect,
                cardRect: cRect,
                spotlightRadius: step.spotlightCornerRadius
            ))
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.28), value: step)
        .onPreferenceChange(HomeCardSizeKey.self) { h in
            // Match the cutout exactly to the card. Any extra pad here shows
            // up as a thin un-dimmed strip above/below the card (the home
            // content peeks through), which reads as a "gap".
            if abs(h - measuredCardHeight) > 0.5 {
                measuredCardHeight = h
            }
        }
        .onPreferenceChange(HomeUIKitSyncKey.self) { data in
            cachedSync = data
            if SpotlightWindow.isShowing {
                SpotlightWindow.update(data: convert(data))
            } else {
                SpotlightWindow.show(data: convert(data))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                // Pulse stays subtle — a 10% scale-up read as the ring
                // overshooting the cutout edge by 5pt+ at peak, which looked
                // like a "gap" between the highlighted card and the ring.
                pulseScale   = 1.04
                pulseOpacity = 0.30
            }
            if !SpotlightWindow.isShowing, !cachedSync.spotlightRect.isEmpty {
                SpotlightWindow.show(data: convert(cachedSync))
            }
        }
        .onDisappear { SpotlightWindow.hide() }
    }

    private func spotlightRect(in geo: GeometryProxy) -> CGRect {
        // Halo around the highlighted view. The horizontal halo gives the
        // cutout a small cushion around button edges; the vertical halo is
        // intentionally near-zero because most highlighted controls already
        // ship with their own visual padding (rounded card frames, button
        // chrome) — adding 8pt on top of that read as a gap, especially
        // visible in Chinese where glyphs are tighter than English.
        let padX: CGFloat = 8
        let padY: CGFloat = 2
        guard let raw = anchors[step.anchorID], !raw.isEmpty else { return .zero }
        return raw.insetBy(dx: -padX, dy: -padY)
    }

    private func cardPosition(in geo: GeometryProxy, spotlightRect rect: CGRect, cardH: CGFloat) -> CGPoint {
        let safeTop    = SpotlightWindow.safeAreaTop()
        let safeBottom = SpotlightWindow.safeAreaBottom()
        let screenW    = geo.size.width
        let screenH    = geo.size.height
        let margin: CGFloat = 16
        let gap: CGFloat    = 16

        if rect.isEmpty {
            return CGPoint(x: screenW / 2, y: screenH / 2)
        }

        let belowY = rect.maxY + gap + cardH / 2
        let aboveY = rect.minY - gap - cardH / 2
        var y: CGFloat = step.isTopRow ? belowY : aboveY

        let topLimit    = safeTop + cardH / 2 + margin
        let bottomLimit = screenH - safeBottom - cardH / 2 - margin

        if y < topLimit {
            y = min(belowY, bottomLimit)
        } else if y > bottomLimit {
            y = max(aboveY, topLimit)
        }
        y = max(topLimit, min(y, bottomLimit))

        var x = rect.midX
        x = max(cardW / 2 + margin, min(x, screenW - cardW / 2 - margin))
        return CGPoint(x: x, y: y)
    }

    private func convert(_ d: HomeUIKitSyncData) -> UIKitSyncData {
        UIKitSyncData(
            spotlightRect: d.spotlightRect,
            cardRect: d.cardRect,
            spotlightRadius: d.spotlightRadius,
            cardRadius: d.cardRadius
        )
    }

    @ViewBuilder
    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(alignment: .center, spacing: 10) {
                // Feature icon — uses the home button's existing SF Symbol so
                // the callout reads as a continuation of the spotlit button.
                Image(systemName: step.sfSymbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(step.accent)
                    .frame(width: 24, height: 24)
                Text(step.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(step.rawValue + 1) / \(HomeOnboardingStep.allCases.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.45))
                // Prominent skip — a tappable × in the top-right corner so
                // users always have an obvious exit (the bottom "Skip" link
                // is too subtle on its own).
                Button(action: onSkip) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.black.opacity(0.35))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("onboarding.skip",
                    value: "Skip", comment: ""))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            // Body — renders inline SF Symbols where the description includes
            // {sfsymbol:name} tokens (so "⋯" becomes the real ellipsis icon
            // and "📥" becomes the real archive icon, matching what the user
            // sees in the chat UI). {hl}…{/hl} tokens render as marker-pen
            // highlights cycling through the palette.
            renderRichText(step.description)
                .font(.system(size: 15))
                .foregroundColor(Color.black.opacity(0.78))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 8)

            HStack(spacing: 0) {
                Button(action: onSkip) {
                    Text(NSLocalizedString("onboarding.skip", value: "Skip", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.black.opacity(0.5))
                        .padding(.vertical, 9)
                        .padding(.horizontal, 4)
                }

                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<HomeOnboardingStep.allCases.count, id: \.self) { i in
                        Circle()
                            .fill(i == step.rawValue
                                  ? step.accent
                                  : Color.black.opacity(0.18))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    HStack(spacing: 4) {
                        Text(step.isLast
                             ? NSLocalizedString("onboarding.done", value: "Got it", comment: "")
                             : NSLocalizedString("onboarding.next", value: "Next", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                        if !step.isLast {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(step.accent)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 6)
        )
    }

    /// Cycling palette for marker-pen highlights — different colors so multiple
    /// highlights in one card feel like real, varied marker strokes.
    private static let highlightPalette: [Color] = [
        Color(hex: "FFE066").opacity(0.55),  // yellow
        Color(hex: "FFB3D9").opacity(0.55),  // pink
        Color(hex: "B8E6D5").opacity(0.55),  // mint
        Color(hex: "E1D4F5").opacity(0.55),  // lavender
        Color(hex: "FFD6BA").opacity(0.55),  // peach
    ]

    /// Parses {sfsymbol:name} and {hl}word{/hl} tokens out of a description
    /// string and rebuilds it as a Text composition. SF Symbols render inline;
    /// {hl}…{/hl} fragments get a marker-pen-style background that cycles
    /// through the palette so each highlight in a card stands out distinctly.
    private func renderRichText(_ raw: String) -> Text {
        var result = Text("")
        var remaining = raw[...]
        var hlIndex = 0

        while !remaining.isEmpty {
            // Find the earliest of `{sfsymbol:` or `{hl}`.
            let symbolRange = remaining.range(of: "{sfsymbol:")
            let hlRange     = remaining.range(of: "{hl}")
            let nextRange: Range<Substring.Index>?
            let isSymbol: Bool
            switch (symbolRange, hlRange) {
            case let (s?, h?):
                if s.lowerBound < h.lowerBound { nextRange = s; isSymbol = true }
                else                            { nextRange = h; isSymbol = false }
            case let (s?, nil): nextRange = s; isSymbol = true
            case let (nil, h?): nextRange = h; isSymbol = false
            case (nil, nil):
                result = result + Text(String(remaining))
                return result
            }
            guard let range = nextRange else { return result }

            // Append text before the token.
            let before = remaining[..<range.lowerBound]
            if !before.isEmpty { result = result + Text(String(before)) }

            if isSymbol {
                let after = remaining[range.upperBound...]
                if let close = after.firstIndex(of: "}") {
                    let symbol = String(after[..<close])
                    result = result + Text(Image(systemName: symbol))
                    remaining = after[after.index(after: close)...]
                } else {
                    result = result + Text(String(remaining))
                    return result
                }
            } else {
                let after = remaining[range.upperBound...]
                if let close = after.range(of: "{/hl}") {
                    let highlighted = String(after[..<close.lowerBound])
                    let color = Self.highlightPalette[hlIndex % Self.highlightPalette.count]
                    hlIndex += 1
                    var attr = AttributedString(highlighted)
                    attr.backgroundColor = color
                    attr.foregroundColor = .black
                    // Bold inside the highlight gives the marker-pen pop.
                    result = result + Text(attr).fontWeight(.semibold)
                    remaining = after[close.upperBound...]
                } else {
                    result = result + Text(String(remaining))
                    return result
                }
            }
        }
        return result
    }
}
