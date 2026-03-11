//
//  SuggestedTodoEngine.swift
//  StudyAI
//
//  4-category daily-todo engine.
//
//  ┌─────────────────────────────────────────────────────────────────────┐
//  │  HOW TO ADD A NEW TODO ITEM                                         │
//  │  1. Create a struct conforming to SuggestedTodoItemProvider.        │
//  │  2. Pick the right TodoCategory and a meaningful priority (Int).    │
//  │  3. Implement evaluate() — return nil when the item is not timely.  │
//  │  4. Append an instance to SuggestedTodoEngine.allProviders.         │
//  │  No other files need changing for the engine logic itself.          │
//  └─────────────────────────────────────────────────────────────────────┘

import Foundation
import SwiftUI
import Combine

// MARK: - SuggestedTodo Model

struct SuggestedTodo: Identifiable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: TodoAction

    enum TodoAction {
        // ── Category 1 · Practice ──────────────────────────────────────────
        /// Open the mistake-review screen, optionally pre-filtered to a subject.
        case openMistakeReview(topSubject: String?)
        /// Jump directly into weakness-based Feynman practice questions.
        case startFeynmanPractice(weaknessKey: String)
        /// Generate questions from a recent archived AI conversation (Mode 3).
        case startConceptReview(recentSessionId: String, subject: String)
        /// Fallback: random 5-question MC/TF set using the user's subjects.
        case startRandomPractice(subjects: [String])
        /// Open a specific completed practice session in redo mode (reset answers, restart from Q1).
        case retryPracticeSession(sessionId: String, subject: String)

        // ── Category 2 · Main Feature ──────────────────────────────────────
        case openGrader
        case openChat

        // ── Category 3 · Extended Features ────────────────────────────────
        case openFocus
        case openHomeworkAlbum
        /// Placeholder — activated once APNs push infrastructure is ready.
        case openParentReport
        case openProgress

        // ── Category 4 · Deep Extension ────────────────────────────────────
        case startOralPractice
        /// Placeholder — activated once the backend daily-question endpoint is live.
        case showDailyQuestion(question: String)
        /// Launch Live Mode with a specific learning scenario.
        case startLiveScenario(LiveModeScenario)
    }
}

// MARK: - Category

/// The four daily sections. Each section contributes exactly one todo to the list
/// (or zero if no provider in that section is currently eligible).
enum TodoCategory: Int, CaseIterable {
    /// Highest-priority eligible item wins.
    case practice      = 0
    /// Highest-priority eligible item wins.
    case mainFeature   = 1
    /// One random eligible item, day-seeded — stable within a calendar day.
    case extended      = 2
    /// One random eligible item, day-seeded — stable within a calendar day.
    case deepExtension = 3
}

// MARK: - Provider Protocol

/// Conform to this protocol to introduce a new todo item.
/// All providers live in this file so the full menu is easy to audit in one place.
protocol SuggestedTodoItemProvider {
    /// Globally unique string — also the UserDefaults dismissal key fragment.
    var todoId: String { get }
    var category: TodoCategory { get }
    /// Intra-category priority; higher wins for `.practice` / `.mainFeature`.
    /// Ignored for `.extended` / `.deepExtension` (random selection).
    var priority: Int { get }
    /// Returns a built todo when the item is relevant, `nil` when it is not.
    /// Must be synchronous and cheap — runs on the main thread each refresh.
    func evaluate() -> SuggestedTodo?
}

// MARK: - Engine

@MainActor
final class SuggestedTodoEngine: ObservableObject {
    static let shared = SuggestedTodoEngine()
    private init() {}

    @Published var todos: [SuggestedTodo] = []

    // ── Provider Registry ───────────────────────────────────────────────────
    // To add a new todo: append its provider here — nothing else needs changing.
    private let allProviders: [SuggestedTodoItemProvider] = [
        // Category 1 — Practice
        MistakeReviewProvider(),
        PracticeRetryProvider(),         // priority 95 — low-score practice retry
        FeynmanPracticeProvider(),
        ConceptReviewProvider(),
        RandomPracticeProvider(),       // fallback — always eligible

        // Category 2 — Main Feature
        HomeworkGraderProvider(),
        OpenChatProvider(),             // fallback — always eligible
        OralPracticeProvider(),         // live mode fallback — same priority tier as scenarios
        LiveScenarioProvider(scenario: .oralComposition),
        LiveScenarioProvider(scenario: .debate),
        LiveScenarioProvider(scenario: .interview),
        LiveScenarioProvider(scenario: .classroomQA),
        LiveScenarioProvider(scenario: .presentation),
        LiveScenarioProvider(scenario: .historicalFigure),

        // Category 3 — Extended Features
        FocusSessionProvider(),
        HomeworkAlbumProvider(),
        ParentReportProvider(),         // placeholder — currently always nil
        ProgressCheckProvider(),

        // Category 4 — Deep Extension
        DailyQuestionProvider(),
    ]

    // MARK: Public API

    func refresh() {
        let seed = daySeed()
        var result: [SuggestedTodo] = []

        for category in TodoCategory.allCases {
            let eligible = allProviders
                .filter { $0.category == category }
                .compactMap { provider -> (priority: Int, todo: SuggestedTodo)? in
                    guard !isDismissedToday(provider.todoId),
                          let todo = provider.evaluate() else { return nil }
                    return (provider.priority, todo)
                }

            guard !eligible.isEmpty else { continue }

            let picked: SuggestedTodo
            switch category {
            case .practice, .mainFeature:
                // Deterministic: highest priority wins.
                // When multiple items share the top priority, use day-seed to rotate among them
                // so live mode scenarios cycle day-to-day instead of always showing the first one.
                let maxPriority = eligible.max(by: { $0.priority < $1.priority })!.priority
                let topTied = eligible.filter { $0.priority == maxPriority }
                if topTied.count == 1 {
                    picked = topTied[0].todo
                } else {
                    let categorySeed = abs(seed ^ (category.rawValue &* 7_919))
                    picked = topTied[categorySeed % topTied.count].todo
                }
            case .extended, .deepExtension:
                // Day-seeded random: consistent within a day, cycles across days.
                // XOR with a category-specific constant to avoid correlated picks.
                let categorySeed = abs(seed ^ (category.rawValue &* 7_919))
                picked = eligible[categorySeed % eligible.count].todo
            }

            result.append(picked)
        }

        todos = result
    }

    func forceRefresh() {
        clearTodayDismissals()
        refresh()
    }

    /// Fetch the daily question from the backend (if not cached yet today), then refresh.
    /// Call this from the view layer on appear — safe to call multiple times, the network
    /// request is skipped when today's question is already in UserDefaults.
    func fetchAndRefresh() {
        let lang    = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        let grade   = ProfileService.shared.currentProfile?.gradeLevel ?? "6"
        let date    = NetworkService.shared.todayUTCDateString()
        let slot    = NetworkService.shared.currentUTCSlot()
        let dateKey = "daily_question_\(date)_s\(slot)_\(lang)_\(grade)"

        // Already cached today → just refresh without a network call
        if UserDefaults.standard.string(forKey: dateKey) != nil {
            refresh()
            return
        }

        // Fetch in background; update todos when done
        Task {
            await NetworkService.shared.fetchDailyQuestion()
            await MainActor.run { self.refresh() }
        }

        // Render immediately with whatever we have while the fetch is in-flight
        refresh()
    }

    func dismiss(id: String) {
        UserDefaults.standard.set(true, forKey: dismissalKey(id))
        refresh()   // re-run engine so the dismissed slot is filled by the next eligible provider
    }

    func markProgressViewed() {
        let uid = AuthenticationService.shared.currentUser?.id ?? "anon"
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: "last_viewed_progress_\(uid)"
        )
        dismiss(id: ProgressCheckProvider.staticId)
    }

    // MARK: Private helpers

    private var todayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func dismissalKey(_ id: String) -> String {
        "todo_dismissed_\(todayString)_\(id)"
    }

    private func isDismissedToday(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: dismissalKey(id))
    }

    private func clearTodayDismissals() {
        let prefix = "todo_dismissed_\(todayString)_"
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    /// An integer unique per calendar day, used as the random seed.
    private func daySeed() -> Int {
        let c = Calendar.current
        let d = Date()
        let year = c.component(.year, from: d)
        let dayOfYear = c.ordinality(of: .day, in: .year, for: d) ?? 1
        return year * 1_000 + dayOfYear
    }
}

// MARK: - Category 1: Practice Providers

// ── 1b · Practice Retry (low score) ──────────────────────────────────────
// Fires when the user completed a practice session in the last 7 days with
// score < 60%. Surfaces the worst-performing subject so they can try again.

private struct PracticeRetryProvider: SuggestedTodoItemProvider {
    let todoId   = "practice_retry"
    let category = TodoCategory.practice
    let priority = 95   // just below MistakeReview (100), above Feynman (90)

    func evaluate() -> SuggestedTodo? {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let sessions = PracticeSessionManager.shared.allSessionsPublished
            .filter { $0.isCompleted && $0.lastAccessedDate > cutoff }

        guard !sessions.isEmpty else { return nil }

        // Find the single session with the lowest score (worst-performing)
        let worstSession = sessions
            .compactMap { s -> (session: PracticeSession, score: Double)? in
                guard let score = s.scorePercentage else { return nil }
                return score < 60 ? (s, score) : nil
            }
            .sorted { $0.score < $1.score }  // lowest score first
            .first

        guard let worst = worstSession else { return nil }

        let scoreStr = "\(Int(worst.score.rounded()))%"
        return SuggestedTodo(
            id:       todoId,
            icon:     "arrow.clockwise.circle",
            title:    String(format: NSLocalizedString("todo.practiceRetry.title", value: "再练一次 %@", comment: ""), worst.session.subject),
            subtitle: String(format: NSLocalizedString("todo.practiceRetry.subtitle", value: "上次得分 %@，继续加油！", comment: ""), scoreStr),
            color:    Color(hex: "FF6B6B"),
            action:   .retryPracticeSession(sessionId: worst.session.id, subject: worst.session.subject)
        )
    }
}

// ── 1c · Mistake Review ───────────────────────────────────────────────────

private struct MistakeReviewProvider: SuggestedTodoItemProvider {
    let todoId   = "mistake_review"
    let category = TodoCategory.practice
    let priority = 100

    func evaluate() -> SuggestedTodo? {
        let mistakes = todoQuestionStorage().getMistakeQuestions()
        guard !mistakes.isEmpty else { return nil }

        let top = topSubjectName(from: mistakes)
        let countFmt = mistakes.count == 1
            ? NSLocalizedString("todo.mistakeReview.count.one",  value: "1 道错题",      comment: "")
            : String(format: NSLocalizedString("todo.mistakeReview.count.many", value: "%d 道错题", comment: ""), mistakes.count)

        return SuggestedTodo(
            id:       todoId,
            icon:     "exclamationmark.circle",
            title:    NSLocalizedString("todo.mistakeReview.title",    value: "复习错题",        comment: ""),
            subtitle: top.map { "\($0) · \(countFmt)" } ?? countFmt,
            color:    Color(hex: "F26B50"),
            action:   .openMistakeReview(topSubject: top)
        )
    }
}

// ── 1b · Feynman Practice ─────────────────────────────────────────────────

private struct FeynmanPracticeProvider: SuggestedTodoItemProvider {
    let todoId   = "feynman_practice"
    let category = TodoCategory.practice
    let priority = 90

    func evaluate() -> SuggestedTodo? {
        let mistakes = todoQuestionStorage().getMistakeQuestions()
        guard let top = topSubjectName(from: mistakes) else { return nil }

        return SuggestedTodo(
            id:       todoId,
            icon:     "brain.head.profile",
            title:    NSLocalizedString("todo.feynman.title",    value: "费曼练习",             comment: ""),
            subtitle: String(format: NSLocalizedString("todo.feynman.subtitle", value: "针对「%@」生成专项习题", comment: ""), top),
            color:    Color(hex: "5B8EF0"),
            action:   .startFeynmanPractice(weaknessKey: top)
        )
    }
}

// ── 1c · Concept Review ───────────────────────────────────────────────────

private struct ConceptReviewProvider: SuggestedTodoItemProvider {
    let todoId   = "concept_review"
    let category = TodoCategory.practice
    let priority = 80

    func evaluate() -> SuggestedTodo? {
        let uid    = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let all    = ConversationLocalStorage.forUser(uid).getLocalConversations()

        // Find the most recently archived conversation within the last 7 days.
        let recent = all
            .filter { conv in
                if let ts = conv["archivedAt"] as? TimeInterval {
                    return Date(timeIntervalSince1970: ts) > cutoff
                }
                if let ts = conv["createdAt"] as? TimeInterval {
                    return Date(timeIntervalSince1970: ts) > cutoff
                }
                return false
            }
            .sorted {
                let a = ($0["archivedAt"] as? TimeInterval) ?? ($0["createdAt"] as? TimeInterval) ?? 0
                let b = ($1["archivedAt"] as? TimeInterval) ?? ($1["createdAt"] as? TimeInterval) ?? 0
                return a > b
            }
            .first

        guard let conv = recent else { return nil }

        let sessionId = (conv["sessionId"] as? String)
                     ?? (conv["id"]        as? String)
                     ?? ""
        guard !sessionId.isEmpty else { return nil }

        let subject = (conv["subject"] as? String)
                   ?? (conv["title"]   as? String)
                   ?? NSLocalizedString("todo.conceptReview.defaultSubject", value: "近期对话", comment: "")

        return SuggestedTodo(
            id:       todoId,
            icon:     "books.vertical",
            title:    NSLocalizedString("todo.conceptReview.title",    value: "概念复习",               comment: ""),
            subtitle: String(format: NSLocalizedString("todo.conceptReview.subtitle", value: "根据「%@」出题", comment: ""), subject),
            color:    Color(hex: "9C7EE8"),
            action:   .startConceptReview(recentSessionId: sessionId, subject: subject)
        )
    }
}

// ── 1d · Random Practice  (fallback — always eligible) ────────────────────

private struct RandomPracticeProvider: SuggestedTodoItemProvider {
    let todoId   = "random_practice"
    let category = TodoCategory.practice
    let priority = 70   // lowest in category — wins only when all others are nil

    func evaluate() -> SuggestedTodo? {
        let subjects = ProfileService.shared.currentProfile?.favoriteSubjects ?? []
        let display  = subjects.first
            ?? NSLocalizedString("todo.randomPractice.defaultSubject", value: "综合", comment: "")

        return SuggestedTodo(
            id:       todoId,
            icon:     "dice",
            title:    NSLocalizedString("todo.randomPractice.title",    value: "随机练习",            comment: ""),
            subtitle: String(format: NSLocalizedString("todo.randomPractice.subtitle", value: "%@ · 5 道选择/判断题", comment: ""), display),
            color:    Color(hex: "33C4B0"),
            action:   .startRandomPractice(subjects: subjects)
        )
    }
}

// MARK: - Category 2: Main Feature Providers

// ── 2a · Homework Grader ──────────────────────────────────────────────────

private struct HomeworkGraderProvider: SuggestedTodoItemProvider {
    let todoId   = "open_grader"
    let category = TodoCategory.mainFeature
    let priority = 100

    func evaluate() -> SuggestedTodo? {
        guard (PointsEarningManager.shared.todayProgress?.totalQuestions ?? 0) == 0 else { return nil }
        return SuggestedTodo(
            id:       todoId,
            icon:     "camera.viewfinder",
            title:    NSLocalizedString("todo.grader.title",    value: "批改今天的作业",      comment: ""),
            subtitle: NSLocalizedString("todo.grader.subtitle", value: "拍一张照片让 AI 分析", comment: ""),
            color:    Color(hex: "F5A033"),
            action:   .openGrader
        )
    }
}

// ── 2b · Open Chat  (fallback — always eligible) ──────────────────────────

private struct OpenChatProvider: SuggestedTodoItemProvider {
    let todoId   = "open_chat"
    let category = TodoCategory.mainFeature
    let priority = 90

    func evaluate() -> SuggestedTodo? {
        SuggestedTodo(
            id:       todoId,
            icon:     "bubble.left.and.bubble.right",
            title:    NSLocalizedString("todo.chat.title",    value: "问 AI 一个问题",      comment: ""),
            subtitle: NSLocalizedString("todo.chat.subtitle", value: "把今天的困惑说出来", comment: ""),
            color:    Color(hex: "4AAFDF"),
            action:   .openChat
        )
    }
}

// MARK: - Category 3: Extended Feature Providers

// ── 3a · Focus Session ────────────────────────────────────────────────────

private struct FocusSessionProvider: SuggestedTodoItemProvider {
    let todoId   = "open_focus"
    let category = TodoCategory.extended
    let priority = 0

    func evaluate() -> SuggestedTodo? {
        let done = FocusSessionService.shared.getTodaySessions().filter { $0.isCompleted }.count
        let subtitle = done == 0
            ? NSLocalizedString("todo.focus.subtitle.none", value: "今天还没有专注记录",        comment: "")
            : String(format: NSLocalizedString("todo.focus.subtitle.some", value: "今日已完成 %d 次，再来一次", comment: ""), done)
        return SuggestedTodo(
            id:       todoId,
            icon:     "timer",
            title:    NSLocalizedString("todo.focus.title",  value: "番茄专注 25 分钟", comment: ""),
            subtitle: subtitle,
            color:    Color(hex: "33C4B0"),
            action:   .openFocus
        )
    }
}

// ── 3b · Homework Album ───────────────────────────────────────────────────

private struct HomeworkAlbumProvider: SuggestedTodoItemProvider {
    let todoId   = "open_homework_album"
    let category = TodoCategory.extended
    let priority = 0

    func evaluate() -> SuggestedTodo? {
        let records = HomeworkImageStorageService.shared.getAllHomeworkImages()
        guard !records.isEmpty else { return nil }

        let subject = records.first?.subject ?? ""
        let subtitle = subject.isEmpty
            ? NSLocalizedString("todo.album.subtitle.generic", value: "查看保存的作业",   comment: "")
            : String(format: NSLocalizedString("todo.album.subtitle.subject", value: "最近：%@", comment: ""), subject)

        return SuggestedTodo(
            id:       todoId,
            icon:     "photo.on.rectangle.angled",
            title:    NSLocalizedString("todo.album.title",    value: "作业相册", comment: ""),
            subtitle: subtitle,
            color:    Color(hex: "FF85C1"),
            action:   .openHomeworkAlbum
        )
    }
}

// ── 3c · Parent Report  (placeholder) ────────────────────────────────────
// Enabled once APNs push infra is complete.
//
// 📌 WIRE-UP POINT — when push infra is ready:
//   1. Store a flag in UserDefaults when push payload arrives (e.g. "hasPendingParentReport").
//   2. Uncomment the guard and return below.

private struct ParentReportProvider: SuggestedTodoItemProvider {
    let todoId   = "parent_report_ready"
    let category = TodoCategory.extended
    let priority = 0

    func evaluate() -> SuggestedTodo? {
        // guard UserDefaults.standard.bool(forKey: "hasPendingParentReport") else { return nil }
        // return SuggestedTodo(id: todoId, icon: "doc.text.fill",
        //   title: "家长报告已就绪", subtitle: "查看本周学习报告",
        //   color: Color(hex: "5B8EF0"), action: .openParentReport)
        return nil
    }
}

// ── 3d · Progress Check ───────────────────────────────────────────────────

private struct ProgressCheckProvider: SuggestedTodoItemProvider {
    /// Exposed as `static` so `SuggestedTodoEngine.markProgressViewed()` can
    /// reference this ID without instantiating the struct.
    static let staticId = "open_progress"
    let todoId   = ProgressCheckProvider.staticId
    let category = TodoCategory.extended
    let priority = 0

    func evaluate() -> SuggestedTodo? {
        let uid        = AuthenticationService.shared.currentUser?.id ?? "anon"
        let lastViewed = UserDefaults.standard.double(forKey: "last_viewed_progress_\(uid)")
        let daysSince  = lastViewed == 0
            ? 999.0
            : (Date().timeIntervalSince1970 - lastViewed) / 86_400
        let subtitle = daysSince < 1
            ? NSLocalizedString("todo.progress.subtitle.today",   value: "了解今日学习成果", comment: "")
            : NSLocalizedString("todo.progress.subtitle.general", value: "掌握你的学习轨迹", comment: "")
        return SuggestedTodo(
            id:       todoId,
            icon:     "chart.bar.fill",
            title:    NSLocalizedString("todo.progress.title", value: "查看本周进度", comment: ""),
            subtitle: subtitle,
            color:    Color(hex: "8B6EE8"),
            action:   .openProgress
        )
    }
}

// MARK: - Category 4: Deep Extension Providers

// ── 4a · Oral Practice ────────────────────────────────────────────────────

private struct OralPracticeProvider: SuggestedTodoItemProvider {
    let todoId   = "oral_practice"
    let category = TodoCategory.mainFeature
    let priority = 75   // same tier as live scenarios — rotates daily via tie-breaking seed

    func evaluate() -> SuggestedTodo? {
        SuggestedTodo(
            id:       todoId,
            icon:     "waveform.and.mic",
            title:    NSLocalizedString("todo.oral.title",    value: "AI 口语练习",          comment: ""),
            subtitle: NSLocalizedString("todo.oral.subtitle", value: "和 AI 开口聊聊今天所学", comment: ""),
            color:    Color(hex: "FF9966"),
            action:   .startOralPractice
        )
    }
}

// ── 4b · Daily Question / Fallback ───────────────────────────────────────
// Shows today's "Did you know?" question when the backend has delivered one.
// Falls back to "Start an AI conversation" when nothing is cached yet.

private struct DailyQuestionProvider: SuggestedTodoItemProvider {
    let todoId   = "daily_question"
    let category = TodoCategory.deepExtension
    let priority = 0

    func evaluate() -> SuggestedTodo? {
        let lang    = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
        let grade   = ProfileService.shared.currentProfile?.gradeLevel ?? "6"
        let date    = NetworkService.shared.todayUTCDateString()
        let slot    = NetworkService.shared.currentUTCSlot()
        let dateKey = "daily_question_\(date)_s\(slot)_\(lang)_\(grade)"

        if let q = UserDefaults.standard.string(forKey: dateKey) {
            return SuggestedTodo(
                id:       todoId,
                icon:     "lightbulb.fill",
                title:    NSLocalizedString("todo.dailyQuestion.title",    value: "你知道吗？", comment: ""),
                subtitle: q,
                color:    Color(hex: "FFD700"),
                action:   .showDailyQuestion(question: q)
            )
        }

        // Fallback — backend hasn't delivered a question yet today
        return SuggestedTodo(
            id:       todoId,
            icon:     "bubble.left.and.bubble.right.fill",
            title:    NSLocalizedString("todo.dailyQuestion.fallback.title",    value: "开始一段 AI 对话",      comment: ""),
            subtitle: NSLocalizedString("todo.dailyQuestion.fallback.subtitle", value: "随时可以向 AI 提问",    comment: ""),
            color:    Color(hex: "4AAFDF"),
            action:   .openChat
        )
    }
}

// ── 4c · Live Mode Scenario ───────────────────────────────────────────────
// One scenario surfaces per day (day-seeded rotation across the 6 eligible providers).
// Uses the scenario's own icon, color, title, and subtitle from LiveModeScenario.

private struct LiveScenarioProvider: SuggestedTodoItemProvider {
    let scenario: LiveModeScenario
    var todoId: String { "live_scenario_\(scenario.rawValue)" }
    let category = TodoCategory.mainFeature
    let priority = 75

    func evaluate() -> SuggestedTodo? {
        // Hide scenarios that require a higher grade than the user's current level.
        // If grade level is not set on the profile, no restriction is applied.
        if let gl = ProfileService.shared.currentProfile?.gradeLevel,
           let grade = Int(gl),
           grade < scenario.minimumGrade {
            return nil
        }
        return SuggestedTodo(
            id:       todoId,
            icon:     scenario.icon,
            title:    scenario.title,
            subtitle: scenario.subtitle,
            color:    scenario.color,
            action:   .startLiveScenario(scenario)
        )
    }
}

// MARK: - Shared Free Functions
// Reused by multiple providers — avoids inheritance coupling.

private func todoQuestionStorage() -> QuestionLocalStorage {
    let uid = AuthenticationService.shared.currentUser?.id ?? "anonymous"
    return QuestionLocalStorage.forUser(uid)
}

private func topSubjectName(from mistakes: [[String: Any]]) -> String? {
    var counts: [String: Int] = [:]
    for m in mistakes {
        if let s = m["subject"] as? String, !s.isEmpty {
            counts[s, default: 0] += 1
        }
    }
    return counts.max(by: { $0.value < $1.value })?.key
}
