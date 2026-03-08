//
//  SuggestedTodoEngine.swift
//  StudyAI
//
//  Reads local user-activity signals and produces a daily prioritised list
//  of up to 4 suggested to-do items shown on the Home screen.
//  All signal reads are local (UserDefaults / in-memory) — no network calls.
//

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
        case openGrader
        case resumePractice
        case openMistakeReview(topSubject: String?)
        case openFocus
        case openProgress
    }
}

// MARK: - Engine

@MainActor
final class SuggestedTodoEngine: ObservableObject {
    static let shared = SuggestedTodoEngine()

    @Published var todos: [SuggestedTodo] = []

    private var uid: String {
        AuthenticationService.shared.currentUser?.id ?? "anonymous"
    }

    private var todayDateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private let logger = AppLogger.forFeature("SuggestedTodos")

    private init() {}

    // MARK: - Refresh  (call on HomeView.onAppear)

    func refresh() {
        var candidates: [(todo: SuggestedTodo, priority: Int)] = []

        // T04 · Incomplete practice session  (priority 100)
        let incomplete = PracticeSessionManager.shared.incompleteSessions
        if let first = incomplete.first {
            let remaining = first.questions.count - first.completedQuestionIds.count
            let subtitle: String = remaining > 0
                ? String(format: NSLocalizedString(
                    "suggestedTodo.resumePractice.subtitle",
                    value: "还剩 %d 题未完成",
                    comment: ""), remaining)
                : NSLocalizedString(
                    "suggestedTodo.resumePractice.subtitleGeneral",
                    value: "继续上次进度",
                    comment: "")
            candidates.append((SuggestedTodo(
                id: "resume_practice",
                icon: "arrow.clockwise",
                title: NSLocalizedString("suggestedTodo.resumePractice.title",
                                         value: "继续练习", comment: ""),
                subtitle: subtitle,
                color: Color(hex: "5B8EF0"),
                action: .resumePractice
            ), 100))
        }

        // T05 · Unreviewed mistakes  (priority 90)
        let mistakes = currentUserQuestionStorage().getMistakeQuestions()
        if !mistakes.isEmpty {
            let top = topSubject(from: mistakes)
            let subjectSuffix = top.map { " · \($0)" } ?? ""
            let subtitle = String(format: NSLocalizedString(
                "suggestedTodo.mistakeReview.subtitle",
                value: "%d 道错题待复习",
                comment: ""), mistakes.count) + subjectSuffix
            candidates.append((SuggestedTodo(
                id: "mistake_review",
                icon: "exclamationmark.circle",
                title: NSLocalizedString("suggestedTodo.mistakeReview.title",
                                         value: "复习错题", comment: ""),
                subtitle: subtitle,
                color: Color(hex: "F26B50"),
                action: .openMistakeReview(topSubject: top)
            ), 90))
        }

        // T01 · No questions answered today → suggest homework grader  (priority 80)
        if PointsEarningManager.shared.todayProgress?.totalQuestions ?? 0 == 0 {
            candidates.append((SuggestedTodo(
                id: "open_grader",
                icon: "camera.viewfinder",
                title: NSLocalizedString("suggestedTodo.homeworkGrader.title",
                                         value: "拍一张作业让 AI 分析", comment: ""),
                subtitle: NSLocalizedString("suggestedTodo.homeworkGrader.subtitle",
                                            value: "今天还没有评分记录", comment: ""),
                color: Color(hex: "F5A033"),
                action: .openGrader
            ), 80))
        }

        // T06 · Focus session today (priority 70, always a candidate)
        let completedFocusToday = FocusSessionService.shared
            .getTodaySessions()
            .filter { $0.isCompleted }
            .count
        let focusSubtitle = completedFocusToday == 0
            ? NSLocalizedString("suggestedTodo.focusMode.subtitle",
                                value: "今天还没有专注记录", comment: "")
            : String(format: NSLocalizedString("suggestedTodo.focusMode.subtitleDone",
                                               value: "今日已完成 %d 次，再来一次",
                                               comment: ""), completedFocusToday)
        candidates.append((SuggestedTodo(
            id: "open_focus",
            icon: "timer",
            title: NSLocalizedString("suggestedTodo.focusMode.title",
                                     value: "开始专注", comment: ""),
            subtitle: focusSubtitle,
            color: Color(hex: "33C4B0"),
            action: .openFocus
        ), 70))

        // T09 · Progress check (priority 60, always a candidate)
        let lastViewed = UserDefaults.standard.double(forKey: "last_viewed_progress_\(uid)")
        let daysSince: Double = lastViewed == 0
            ? 999
            : (Date().timeIntervalSince1970 - lastViewed) / 86400
        let progressSubtitle = daysSince < 1
            ? NSLocalizedString("suggestedTodo.progress.subtitleToday",
                                value: "了解今日学习成果", comment: "")
            : NSLocalizedString("suggestedTodo.progress.subtitle",
                                value: "掌握你的学习轨迹", comment: "")
        candidates.append((SuggestedTodo(
            id: "open_progress",
            icon: "chart.bar.fill",
            title: NSLocalizedString("suggestedTodo.progress.title",
                                     value: "查看本周学习进度", comment: ""),
            subtitle: progressSubtitle,
            color: Color(hex: "8B6EE8"),
            action: .openProgress
        ), 60))

        todos = candidates
            .filter { !isDismissedToday($0.todo.id) }
            .sorted { $0.priority > $1.priority }
            .prefix(5)
            .map { $0.todo }

        logger.info("📋 Suggested todos refreshed: \(todos.count) items")
    }

    // MARK: - Force-refresh (clears all today's dismissals then re-evaluates)

    func forceRefresh() {
        let prefix = "todo_dismissed_\(todayDateString)_"
        let keysToRemove = UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
        keysToRemove.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        refresh()
    }

    // MARK: - Dismiss a todo for the rest of today

    func dismiss(id: String) {
        UserDefaults.standard.set(true, forKey: "todo_dismissed_\(todayDateString)_\(id)")
        withAnimation(.easeInOut(duration: 0.2)) {
            todos.removeAll { $0.id == id }
        }
    }

    // MARK: - Mark the Progress tab as viewed (resets T09 cooldown)

    func markProgressViewed() {
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: "last_viewed_progress_\(uid)"
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            todos.removeAll { $0.id == "open_progress" }
        }
    }

    // MARK: - Helpers

    private func isDismissedToday(_ id: String) -> Bool {
        UserDefaults.standard.bool(forKey: "todo_dismissed_\(todayDateString)_\(id)")
    }

    private func topSubject(from mistakes: [[String: Any]]) -> String? {
        var counts: [String: Int] = [:]
        for m in mistakes {
            if let s = m["subject"] as? String, !s.isEmpty {
                counts[s, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
