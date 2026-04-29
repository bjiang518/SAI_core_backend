//
//  PracticeLibraryView.swift
//  StudyAI
//
//  Main screen for the Practice Library — shows all past sessions with filter/sort,
//  and allows creating new sessions via the nav-bar "+ New" button.
//

import SwiftUI

struct PracticeLibraryView: View {
    @StateObject private var sessionManager = PracticeSessionManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) var colorScheme

    // Filter & sort
    @State private var selectedSubject: String = "All"
    @State private var selectedStatus: StatusFilter = .all
    @State private var sortOrder: SortOrder = .newest

    // ── Shortcut pre-configuration ──────────────────────────────────────
    /// When set, the New Practice sheet opens immediately with this config.
    struct ShortcutConfig {
        let tab: NewPracticeSheet.Tab
        let subject: String
        let conversationId: String?
    }

    private let shortcutConfig: ShortcutConfig?

    init(initialSubjectFilter: String? = nil, shortcutConfig: ShortcutConfig? = nil) {
        self.shortcutConfig = shortcutConfig
        if let subj = initialSubjectFilter {
            _selectedSubject = State(initialValue: subj)
        }
    }

    enum StatusFilter: CaseIterable {
        case all, ongoing, completed

        var displayName: String {
            switch self {
            case .all:       return NSLocalizedString("practiceLibrary.filterAll", comment: "")
            case .ongoing:   return NSLocalizedString("practiceLibrary.statusOngoing", comment: "")
            case .completed: return NSLocalizedString("practiceLibrary.statusCompleted", comment: "")
            }
        }
    }

    // Navigation
    @State private var selectedSession: PracticeSession? = nil
    @State private var dailyChallengeSession: PracticeSession? = nil
    @State private var showingNewPractice: Bool = false

    // Daily Challenge
    @ObservedObject private var dailyChallengeService = QuestionGenerationService.shared
    @State private var isDailyChallengeLoading = false
    @AppStorage("daily_challenge_last_completed") private var dailyChallengeLastCompleted = ""
    @AppStorage("daily_challenge_session_id") private var dailyChallengeSessionId = ""
    @AppStorage("daily_challenge_session_date") private var dailyChallengeSessionDate = ""
    @State private var isDailyHistoryExpanded = false
    @State private var selectedHistoryDate: String? = nil
    @State private var historyEntries: [DailyChallengeHistory.Entry] = []
    @State private var dailyCardGlow = false
    @State private var dailyButtonShake: CGFloat = 0

    private var todayString: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private var isDailyChallengeCompletedToday: Bool {
        dailyChallengeLastCompleted == todayString
    }

    // Delete confirmation
    @State private var sessionToDelete: PracticeSession? = nil
    @State private var showingDeleteConfirm: Bool = false

    // Info alert
    @State private var showingPracticeInfo: Bool = false

    // Onboarding tutorial
    @AppStorage("practice_lib_onboarding_done") private var libOnboardingDone = false
    @State private var practiceOnboardingStep: PracticeLibOnboardingStep? = nil
    @State private var practiceOnboardingAnchors: [String: CGRect] = [:]

    @Namespace private var subjectAnimation

    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case scoreHigh = "Score ↓"
        case incompletFirst = "Incomplete First"

        var displayName: String {
            switch self {
            case .newest: return NSLocalizedString("practiceLibrary.sortNewest", comment: "")
            case .oldest: return NSLocalizedString("practiceLibrary.sortOldest", comment: "")
            case .scoreHigh: return NSLocalizedString("practiceLibrary.sortScore", comment: "")
            case .incompletFirst: return NSLocalizedString("practiceLibrary.sortIncomplete", comment: "")
            }
        }
    }

    private var allSessions: [PracticeSession] {
        sessionManager.allSessionsPublished
    }

    private var subjectList: [String] {
        var subjects = ["All"]
        let unique = Set(allSessions.map { PracticeSessionManager.normalizeSubject($0.subject) }).sorted()
        subjects.append(contentsOf: unique)
        return subjects
    }

    private var filteredSorted: [PracticeSession] {
        var list = allSessions

        if selectedSubject != "All" {
            list = list.filter { PracticeSessionManager.normalizeSubject($0.subject) == selectedSubject }
        }

        switch selectedStatus {
        case .ongoing:   list = list.filter { !$0.isCompleted }
        case .completed: list = list.filter {  $0.isCompleted }
        case .all: break
        }

        switch sortOrder {
        case .newest:
            list.sort { $0.createdDate > $1.createdDate }
        case .oldest:
            list.sort { $0.createdDate < $1.createdDate }
        case .scoreHigh:
            list.sort { scoreOf($0) > scoreOf($1) }
        case .incompletFirst:
            list.sort { !$0.isCompleted && $1.isCompleted }
        }

        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter section — warm paper background (no grid)
            VStack(spacing: 0) {
                subjectSelector
                statusFilterBar
                sortBar
            }
            .background(
                colorScheme == .dark ? Color(hex: "2C2A26") : Color(hex: "FAF6EE")
            )

            // Session list — grid paper background, extends to bottom safe area only
            sessionList
                .background(gridPaperBackground.ignoresSafeArea(.all, edges: .bottom))
        }
        .navigationTitle(NSLocalizedString("practiceLibrary.title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            sessionManager.updatePublishedState()
            historyEntries = DailyChallengeHistory.load()
            // Mark daily challenge completed if user has graded at least 1 question
            if dailyChallengeSessionDate == todayString && !dailyChallengeSessionId.isEmpty
                && dailyChallengeLastCompleted != todayString {
                if let s = PracticeSessionManager.shared.getSession(id: dailyChallengeSessionId),
                   !s.completedQuestionIds.isEmpty {
                    dailyChallengeLastCompleted = todayString
                }
            }
            // Open NewPracticeSheet immediately if a shortcut config was provided
            if shortcutConfig != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingNewPractice = true
                }
            }
            // Auto-start daily challenge if opened from notification
            if AppState.shared.shouldOpenDailyChallenge {
                AppState.shared.shouldOpenDailyChallenge = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    startDailyChallenge()
                }
            }
            // Auto-show onboarding for first-time users
            if !libOnboardingDone && shortcutConfig == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if practiceOnboardingStep == nil {
                        practiceOnboardingStep = .newButton
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingPracticeInfo = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingNewPractice = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                        Text(NSLocalizedString("common.new", comment: ""))
                            .font(.subheadline.bold())
                    }
                    .foregroundColor(themeManager.accentColor)
                }
            }
        }
        .sheet(isPresented: $showingNewPractice) {
            if let config = shortcutConfig {
                NewPracticeSheet(
                    onSessionCreated: { session in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            selectedSession = session
                        }
                    },
                    initialTab: config.tab,
                    initialSubject: config.subject,
                    initialConversationId: config.conversationId
                )
            } else {
                NewPracticeSheet { session in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedSession = session
                    }
                }
            }
        }
        .navigationDestination(item: $selectedSession) { session in
            QuestionSheetView(session: session)
        }
        .navigationDestination(item: $dailyChallengeSession) { session in
            DailyChallengeView(session: session)
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedHistoryDate != nil },
            set: { if !$0 { selectedHistoryDate = nil } }
        )) {
            if let dateStr = selectedHistoryDate,
               let entry = historyEntries.first(where: { $0.date == dateStr }),
               let session = PracticeSessionManager.shared.getSession(id: entry.sessionId) {
                DailyChallengeView(session: session)
            }
        }
        .alert(NSLocalizedString("practiceLibrary.info.title", comment: ""), isPresented: $showingPracticeInfo) {
            Button(NSLocalizedString("practiceLibrary.replayTutorial", value: "Replay Tutorial", comment: "")) {
                libOnboardingDone = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    practiceOnboardingStep = .newButton
                }
            }
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("practiceLibrary.info.message", comment: ""))
        }
        .alert(NSLocalizedString("practiceLibrary.deleteTitle", comment: ""), isPresented: $showingDeleteConfirm) {
            Button(NSLocalizedString("common.delete", comment: ""), role: .destructive) {
                if let s = sessionToDelete { sessionManager.deleteSession(id: s.id) }
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("practiceLibrary.deleteMessage", comment: ""))
        }
        .overlay {
            if let step = practiceOnboardingStep {
                PracticeLibOnboardingOverlayView(
                    step: step,
                    anchors: practiceOnboardingAnchors,
                    totalSteps: 4,
                    onNext: { advancePracticeLibOnboarding() },
                    onSkip: { dismissPracticeLibOnboarding() }
                )
            }
        }
        .onPreferenceChange(PracticeLibOnboardingAnchorKey.self) { practiceOnboardingAnchors = $0 }
    }

    // MARK: - Daily Challenge Card

    private var dailyChallengeCard: some View {
        Button(action: startDailyChallenge) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isDailyChallengeCompletedToday
                              ? Color.gray.opacity(0.15)
                              : DesignTokens.Colors.Cute.mint.opacity(0.2))
                        .frame(width: 44, height: 44)
                    if isDailyChallengeLoading {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else if isDailyChallengeCompletedToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(DesignTokens.Colors.Cute.mint)
                    } else {
                        Image(systemName: "star.fill")
                            .font(.title3)
                            .foregroundColor(DesignTokens.Colors.Cute.mint)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("dailyChallenge.title", value: "每日3题", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(themeManager.primaryText)
                    Text(isDailyChallengeLoading
                         ? NSLocalizedString("dailyChallenge.generating", value: "正在生成今日3题…", comment: "")
                         : isDailyChallengeCompletedToday
                             ? NSLocalizedString("dailyChallenge.doneReview", value: "今日已完成 · 点击回顾", comment: "")
                             : NSLocalizedString("dailyChallenge.subtitle", value: "基于你的薄弱点，每天3道精选题", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !isDailyChallengeLoading {
                    Text(isDailyChallengeCompletedToday
                         ? NSLocalizedString("dailyChallenge.review", value: "回顾", comment: "")
                         : NSLocalizedString("dailyChallenge.start", value: "开始", comment: ""))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isDailyChallengeCompletedToday ? Color.secondary : DesignTokens.Colors.Cute.mint)
                        .clipShape(Capsule())
                        .offset(x: isDailyChallengeCompletedToday ? 0 : dailyButtonShake)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(hex: "2C2A26") : Color.white)
                    .shadow(
                        color: isDailyChallengeCompletedToday
                            ? .black.opacity(0.06)
                            : DesignTokens.Colors.Cute.mint.opacity(dailyCardGlow ? 0.6 : 0.15),
                        radius: isDailyChallengeCompletedToday ? 6 : (dailyCardGlow ? 12 : 4),
                        x: 0, y: 2
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isDailyChallengeCompletedToday
                                    ? Color.clear
                                    : DesignTokens.Colors.Cute.mint.opacity(dailyCardGlow ? 0.7 : 0.2),
                                lineWidth: 1.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDailyChallengeLoading)
        .onAppear {
            guard !isDailyChallengeCompletedToday else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                dailyCardGlow = true
            }
            startShake()
        }
    }

    private func startShake() {
        let shakeSequence: [CGFloat] = [0, 3, -3, 2, -2, 1, -1, 0]
        var delay = 0.0
        for offset in shakeSequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.07)) { dailyButtonShake = offset }
            }
            delay += 0.07
        }
        // Repeat every 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            guard !isDailyChallengeCompletedToday else { return }
            startShake()
        }
    }

    private func startDailyChallenge() {
        // If we already generated a session today, just reopen it
        if dailyChallengeSessionDate == todayString && !dailyChallengeSessionId.isEmpty,
           let existing = PracticeSessionManager.shared.getSession(id: dailyChallengeSessionId) {
            dailyChallengeSession = existing
            return
        }

        guard !isDailyChallengeLoading else { return }
        isDailyChallengeLoading = true
        Task {
            let adapter = QuestionGenerationDataAdapter.shared
            let primary = adapter.getMostCommonSubjects().first ?? "Mathematics"
            let weaknessTopics = adapter.getWeaknessTopics(for: primary)
            let mixedTopics = adapter.getMixedTopicsWithMastery(for: primary, weaknessTopics: weaknessTopics)
            let config = QuestionGenerationService.RandomQuestionsConfig(
                topics: mixedTopics.isEmpty ? [primary] : mixedTopics,
                focusNotes: adapter.getPersonalizedFocusNotes(for: primary),
                difficulty: .adaptive,
                questionCount: 3,
                questionType: .any
            )
            let result = await dailyChallengeService.generateQuestionsV2(
                subject: primary,
                mode: 1,
                config: config,
                userProfile: adapter.createUserProfile(),
                shortTermContext: dailyChallengeService.buildShortTermContext(subject: primary)
            )
            await MainActor.run {
                isDailyChallengeLoading = false
                if case .success = result,
                   let sid = dailyChallengeService.currentSessionId,
                   let session = PracticeSessionManager.shared.getSession(id: sid) {
                    dailyChallengeSessionId = sid
                    dailyChallengeSessionDate = todayString
                    dailyChallengeSession = session
                }
            }
        }
    }

    // MARK: - Daily Challenge Expandable History

    private var dailyChallengeHistorySection: some View {
        VStack(spacing: 0) {
            // Expand/collapse toggle row
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isDailyHistoryExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.caption.bold())
                        .foregroundColor(DesignTokens.Colors.Cute.mint)
                    Text(NSLocalizedString("dailyChallenge.history", value: "历史记录", comment: ""))
                        .font(.caption.bold())
                        .foregroundColor(themeManager.primaryText)
                    Spacer()
                    Text(String(format: NSLocalizedString("dailyChallenge.totalCorrect", value: "累计答对 %d 题", comment: ""), historyTotalCorrect))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isDailyHistoryExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if isDailyHistoryExpanded {
                VStack(spacing: 12) {
                    // Mini accuracy bar chart (last 7 entries)
                    if historyEntries.count >= 2 {
                        accuracyBarChart
                            .padding(.horizontal, 16)
                    }
                    // Horizontal date scroll (last 30 calendar days)
                    dateScrollView
                        .padding(.bottom, 8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(colorScheme == .dark ? Color(hex: "2C2A26") : Color.white)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }

    private var accuracyBarChart: some View {
        let recent = historyEntries.prefix(7).reversed() as ReversedCollection
        let maxH: CGFloat = 36
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(recent), id: \.date) { entry in
                VStack(spacing: 2) {
                    let ratio = entry.total > 0 ? CGFloat(entry.correct) / CGFloat(entry.total) : 0
                    RoundedRectangle(cornerRadius: 3)
                        .fill(entry.scoreColor)
                        .frame(width: 14, height: max(4, ratio * maxH))
                    Text(shortDate(entry.date))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("3/3")
                    .font(.system(size: 9)).foregroundColor(.secondary)
                Spacer()
                Text("0/3")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
            .frame(height: maxH + 14)
        }
        .frame(height: maxH + 20)
    }

    private var dateScrollView: some View {
        let calendar = Calendar.current
        let today = Date()
        let days: [Date] = (0..<30).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.reversed()

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days, id: \.self) { day in
                        let dateStr = formatDate(day)
                        let entry = historyEntries.first(where: { $0.date == dateStr })
                        let isToday = dateStr == todayString
                        Button(action: {
                            guard let e = entry,
                                  PracticeSessionManager.shared.getSession(id: e.sessionId) != nil else { return }
                            selectedHistoryDate = dateStr
                        }) {
                            VStack(spacing: 3) {
                                Text(dayLabel(day))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(isToday ? .white : entry != nil ? .white : .secondary)
                                if let e = entry {
                                    Text("\(e.correct)/\(e.total)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                } else {
                                    Text("·")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 38, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isToday ? DesignTokens.Colors.Cute.mint
                                          : entry != nil ? entry!.scoreColor
                                          : Color.secondary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(entry == nil)
                        .id(dateStr)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo(todayString, anchor: .trailing)
                }
            }
        }
    }

    private var historyTotalCorrect: Int { historyEntries.reduce(0) { $0 + $1.correct } }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: date)
    }
    private func shortDate(_ str: String) -> String {
        let parts = str.split(separator: "-")
        guard parts.count == 3 else { return str }
        return "\(parts[1])/\(parts[2])"
    }
    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: date)
    }

    // MARK: - Subject Selector (CompactSubjectSelector style)

    private var subjectSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(subjectList, id: \.self) { subject in
                        let isSelected = selectedSubject == subject
                        let label = subject == "All"
                            ? NSLocalizedString("practiceLibrary.filterAll", comment: "")
                            : PracticeSessionManager.localizeSubject(subject)

                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedSubject = subject
                                proxy.scrollTo(subject, anchor: .center)
                            }
                        }) {
                            Text(label)
                                .font(isSelected ? .subheadline : .caption)
                                .fontWeight(isSelected ? .bold : .medium)
                                .foregroundColor(isSelected ? themeManager.accentColor : .secondary)
                                .padding(.horizontal, isSelected ? 16 : 12)
                                .padding(.vertical, isSelected ? 10 : 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isSelected ? themeManager.accentColor.opacity(0.1) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14)
                                                .stroke(isSelected ? themeManager.accentColor : Color.clear, lineWidth: 1.5)
                                        )
                                )
                                .scaleEffect(isSelected ? 1.05 : 0.9)
                                .opacity(isSelected ? 1.0 : 0.65)
                        }
                        .buttonStyle(.plain)
                        .id(subject)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedSubject) { _, newValue in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(selectedSubject, anchor: .center)
            }
            .practiceLibOnboardingAnchor("practice_lib_onboarding_subjectFilter")
        }
        .padding(.top, 4)
    }

    // MARK: - Status Filter Bar

    private var statusFilterBar: some View {
        HStack(spacing: 0) {
            ForEach(StatusFilter.allCases, id: \.self) { status in
                let isSelected = selectedStatus == status
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedStatus = status
                    }
                }) {
                    Text(status.displayName)
                        .font(.caption.bold())
                        .foregroundColor(isSelected ? themeManager.accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            isSelected
                                ? themeManager.accentColor.opacity(0.1)
                                : Color.clear
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .background(themeManager.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .practiceLibOnboardingAnchor("practice_lib_onboarding_statusFilter")
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var sortBar: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(action: { sortOrder = order }) {
                        Label(order.displayName, systemImage: sortOrder == order ? "checkmark" : "")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                    Text(sortOrder.displayName)
                        .font(.caption)
                }
                .foregroundColor(themeManager.accentColor)
            }
            .padding(.trailing)
        }
        .padding(.bottom, 4)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - Session List

    private var sessionList: some View {
        Group {
            if filteredSorted.isEmpty {
                VStack(spacing: 0) {
                    List {
                        dailyChallengeCard
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        dailyChallengeHistorySection
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(height: 180)

                    emptyState
                }
            } else {
                List {
                    dailyChallengeCard
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 4, trailing: 16))
                        .listRowBackground(Color.clear)
                    dailyChallengeHistorySection
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)

                    ForEach(filteredSorted) { session in
                        PracticeSessionCard(session: session)
                            .practiceLibOnboardingAnchor(
                                session.id == filteredSorted.first?.id
                                    ? "practice_lib_onboarding_sessionCard" : ""
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedSession = session }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    sessionToDelete = session
                                    showingDeleteConfirm = true
                                } label: {
                                    Label(NSLocalizedString("common.delete", comment: ""), systemImage: "trash")
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                    // Bottom padding row
                    Color.clear
                        .frame(height: 80)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    // MARK: - Grid Paper Background (matches SuggestedTodosSection style)

    private var gridPaperBackground: some View {
        ZStack {
            // Warm paper base
            colorScheme == .dark ? Color(hex: "27251F") : Color(hex: "FAF6EE")

            Canvas { ctx, size in
                let spacing: CGFloat = 24
                let lineColor: Color = colorScheme == .dark
                    ? Color(hex: "4A4640").opacity(0.55)
                    : Color(hex: "B8C4C0").opacity(0.55)
                let style = StrokeStyle(lineWidth: 0.5, lineCap: .round)

                // Horizontal lines
                var y: CGFloat = spacing
                while y < size.height {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(lineColor), style: style)
                    y += spacing
                }

                // Vertical lines
                var x: CGFloat = spacing
                while x < size.width {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(lineColor), style: style)
                    x += spacing
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.4))
            Text(NSLocalizedString("practiceLibrary.emptyTitle", comment: ""))
                .font(.headline)
                .foregroundColor(.secondary)
            Text(NSLocalizedString("practiceLibrary.emptySubtitle", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: { showingNewPractice = true }) {
                Label(NSLocalizedString("practiceLibrary.generateFirst", comment: ""), systemImage: "plus")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.accentColor)
                    .cornerRadius(12)
            }
            Spacer()
        }
    }

    // MARK: - Helper

    private func scoreOf(_ session: PracticeSession) -> Double {
        let correct = session.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        let total = session.completedQuestionIds.count
        guard total > 0 else { return 0 }
        return Double(correct) / Double(total)
    }

    // MARK: - Onboarding

    private func advancePracticeLibOnboarding() {
        guard let current = practiceOnboardingStep else { return }
        let librarySteps: [PracticeLibOnboardingStep] = [
            .newButton, .subjectFilter, .sortAndStatus, .swipeToDelete
        ]
        guard let idx = librarySteps.firstIndex(of: current) else {
            dismissPracticeLibOnboarding(); return
        }
        let nextIdx = idx + 1
        if nextIdx >= librarySteps.count {
            dismissPracticeLibOnboarding()
        } else {
            let nextStep = librarySteps[nextIdx]
            // Skip swipeToDelete if list is empty
            if nextStep == .swipeToDelete && filteredSorted.isEmpty {
                dismissPracticeLibOnboarding()
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    practiceOnboardingStep = nextStep
                }
            }
        }
    }

    private func dismissPracticeLibOnboarding() {
        SpotlightWindow.hide()
        practiceOnboardingStep = nil
        libOnboardingDone = true
    }
}
