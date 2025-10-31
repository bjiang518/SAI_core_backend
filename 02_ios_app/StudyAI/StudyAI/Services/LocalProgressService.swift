//
//  LocalProgressService.swift
//  StudyAI
//
//  Created by Claude Code on 10/16/25.
//

import Foundation
import SwiftUI

/// Service to calculate progress data from local storage only (no server calls)
class LocalProgressService {
    static let shared = LocalProgressService()

    private let questionLocalStorage = QuestionLocalStorage.shared
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private init() {}

    // MARK: - Public API

    /// Calculate subject breakdown from local questions (replaces NetworkService.fetchSubjectBreakdown)
    func calculateSubjectBreakdown(timeframe: String = "current_week") async -> SubjectBreakdownData {
        // Get all local questions
        let localQuestions = questionLocalStorage.getLocalQuestions()

        // Convert to QuestionSummary objects
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? questionLocalStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        // Filter by timeframe
        let filteredQuestions = filterQuestionsByTimeframe(questions, timeframe: timeframe)

        // Group by normalized subject
        var questionsBySubject = Dictionary(grouping: filteredQuestions) { $0.normalizedSubject }

        // ✅ ENHANCEMENT: Include today's manually marked progress from PointsEarningManager
        // This ensures that progress marked via "Mark Progress" button shows up in subject breakdown
        let pointsManager = await MainActor.run { PointsEarningManager.shared }
        let todayProgress = await MainActor.run { pointsManager.todayProgress }

        if let todayProgress = todayProgress, timeframe == "today" || timeframe == "current_week" {
            // For each subject in today's progress, add synthetic questions to reflect the marked progress
            for (subject, subjectProgress) in todayProgress.subjectProgress {
                let normalized = normalizeSubjectName(subject)

                // Create synthetic questions to represent manually marked progress
                // This allows the subject breakdown to display manually marked data
                let syntheticQuestions = (0..<subjectProgress.numberOfQuestions).map { index in
                    let isCorrect = index < subjectProgress.numberOfCorrectQuestions
                    return QuestionSummary(
                        id: UUID().uuidString,
                        questionText: "Manually marked question \(index + 1)",
                        correctAnswer: isCorrect ? "Correct" : "Incorrect",
                        subject: subject,
                        grade: isCorrect ? .correct : .incorrect,
                        pointsEarned: isCorrect ? 10.0 : 0.0,
                        pointsPossible: 10.0,
                        archivedAt: Date(), // Today's date
                        studentAnswer: nil,
                        feedback: nil
                    )
                }

                // Merge with existing questions for this subject
                var existingQuestions = questionsBySubject[normalized] ?? []
                existingQuestions.append(contentsOf: syntheticQuestions)
                questionsBySubject[normalized] = existingQuestions

                print("📊 [LocalProgressService] Added \(syntheticQuestions.count) synthetic questions for \(subject) from marked progress")
            }
        }

        // Calculate subject progress data
        let subjectProgress = calculateSubjectProgress(questionsBySubject: questionsBySubject, allQuestions: filteredQuestions)

        // Calculate summary
        let summary = calculateSummary(subjectProgress: subjectProgress, allQuestions: filteredQuestions)

        // Calculate insights
        let insights = calculateInsights(subjectProgress: subjectProgress)

        // Calculate trends
        let trends = calculateTrends(questionsBySubject: questionsBySubject)

        // Calculate comparisons and recommendations
        let comparisons = calculateComparisons(subjectProgress: subjectProgress)
        let recommendations = generateRecommendations(subjectProgress: subjectProgress, insights: insights)

        let result = SubjectBreakdownData(
            summary: summary,
            subjectProgress: subjectProgress,
            insights: insights,
            trends: trends,
            lastUpdated: dateFormatter.string(from: Date()),
            comparisons: comparisons,
            recommendations: recommendations
        )

        return result
    }

    /// Calculate today's activity from local questions
    func calculateTodayActivity() async -> (totalQuestions: Int, correctAnswers: Int, accuracy: Double) {
        // Get all local questions
        let localQuestions = questionLocalStorage.getLocalQuestions()

        // Convert to QuestionSummary objects
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? questionLocalStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        // Filter for today's questions
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayQuestions = questions.filter { question in
            let questionDay = calendar.startOfDay(for: question.archivedAt)
            return questionDay == today
        }

        // Calculate stats
        let totalQuestions = todayQuestions.count
        let correctAnswers = todayQuestions.filter { $0.grade == .correct }.count
        let accuracy = totalQuestions > 0 ? Double(correctAnswers) / Double(totalQuestions) * 100.0 : 0.0

        return (totalQuestions, correctAnswers, accuracy)
    }

    /// Calculate monthly activity from local questions (replaces NetworkService.fetchMonthlyActivity)
    func calculateMonthlyActivity(year: Int, month: Int) async -> [DailyActivity] {
        // Get all local questions
        let localQuestions = questionLocalStorage.getLocalQuestions()

        // Convert to QuestionSummary objects
        var questions: [QuestionSummary] = []
        for questionData in localQuestions {
            if let question = try? questionLocalStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        // Filter questions for the specified month
        let calendar = Calendar.current
        let filteredQuestions = questions.filter { question in
            let components = calendar.dateComponents([.year, .month], from: question.archivedAt)
            return components.year == year && components.month == month
        }

        // Group by date and count questions per day
        let questionsByDate = Dictionary(grouping: filteredQuestions) { question in
            calendar.startOfDay(for: question.archivedAt)
        }

        // Create DailyActivity objects
        let activities = questionsByDate.map { date, dayQuestions in
            DailyActivity(
                date: dateFormatter.string(from: date),
                questionCount: dayQuestions.count
            )
        }.sorted { $0.date < $1.date }

        return activities
    }

    // MARK: - Timeframe Filtering

    private func filterQuestionsByTimeframe(_ questions: [QuestionSummary], timeframe: String) -> [QuestionSummary] {
        let calendar = Calendar.current
        let now = Date()

        let startDate: Date
        switch timeframe {
        case "today":
            startDate = calendar.startOfDay(for: now)
        case "current_week":
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case "current_month":
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case "all_time":
            return questions // No filtering
        default:
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        }

        return questions.filter { $0.archivedAt >= startDate }
    }

    // MARK: - Subject Progress Calculation

    private func calculateSubjectProgress(questionsBySubject: [String: [QuestionSummary]], allQuestions: [QuestionSummary]) -> [SubjectProgressData] {
        var result: [SubjectProgressData] = []

        for (subjectName, questions) in questionsBySubject {
            let subjectCategory = mapSubjectToCategory(subjectName)

            // Calculate metrics
            let questionsAnswered = questions.count
            let correctAnswers = questions.filter { $0.grade == .correct }.count

            // Estimate study time (2 minutes per question)
            let totalStudyTimeMinutes = questionsAnswered * 2

            // Calculate streak days
            let streakDays = calculateStreakDays(questions: questions)

            // Get last studied date
            let lastStudiedDate = questions.max(by: { $0.archivedAt < $1.archivedAt })?.archivedAt ?? Date()

            // Calculate recent activity
            let recentActivity = calculateRecentActivity(questions: questions, subject: subjectCategory)

            // Identify weak and strong areas (based on tags if available)
            let weakAreas = identifyWeakAreas(questions: questions)
            let strongAreas = identifyStrongAreas(questions: questions)

            // Difficulty progression (not available in current data, use empty)
            let difficultyProgression: [DifficultyLevel: Int] = [:]

            // Topic breakdown (not available in current data, use empty)
            let topicBreakdown: [String: Int] = [:]

            let progress = SubjectProgressData(
                subject: subjectCategory,
                questionsAnswered: questionsAnswered,
                correctAnswers: correctAnswers,
                totalStudyTimeMinutes: totalStudyTimeMinutes,
                streakDays: streakDays,
                lastStudiedDate: dateFormatter.string(from: lastStudiedDate),
                recentActivity: recentActivity,
                weakAreas: weakAreas,
                strongAreas: strongAreas,
                difficultyProgression: difficultyProgression,
                topicBreakdown: topicBreakdown
            )

            result.append(progress)
        }

        return result.sorted { $0.questionsAnswered > $1.questionsAnswered }
    }

    private func calculateStreakDays(questions: [QuestionSummary]) -> Int {
        guard !questions.isEmpty else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Get unique study dates, sorted descending
        let studyDates = Set(questions.map { calendar.startOfDay(for: $0.archivedAt) })
            .sorted(by: >)

        // Count consecutive days from today backwards
        var streak = 0
        var checkDate = today

        for date in studyDates {
            if calendar.isDate(date, inSameDayAs: checkDate) {
                streak += 1
                checkDate = calendar.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
            } else if date < checkDate {
                // Gap found, stop counting
                break
            }
        }

        return streak
    }

    private func calculateRecentActivity(questions: [QuestionSummary], subject: SubjectCategory) -> [DailySubjectActivity] {
        let calendar = Calendar.current
        let questionsByDate = Dictionary(grouping: questions) { question in
            calendar.startOfDay(for: question.archivedAt)
        }

        let timezone = TimeZone.current.identifier

        return questionsByDate.map { date, dayQuestions in
            let questionCount = dayQuestions.count
            let correctAnswers = dayQuestions.filter { $0.grade == .correct }.count
            let studyDurationMinutes = questionCount * 2 // 2 min per question

            return DailySubjectActivity(
                date: dateFormatter.string(from: date),
                subject: subject,
                questionCount: questionCount,
                correctAnswers: correctAnswers,
                studyDurationMinutes: studyDurationMinutes,
                timezone: timezone
            )
        }.sorted { $0.date > $1.date }
    }

    private func identifyWeakAreas(questions: [QuestionSummary]) -> [String] {
        let incorrectQuestions = questions.filter { $0.grade == .incorrect || $0.grade == .empty }

        // Group by tags if available
        var tagCounts: [String: Int] = [:]
        for question in incorrectQuestions {
            if let tags = question.tags {
                for tag in tags {
                    tagCounts[tag, default: 0] += 1
                }
            }
        }

        // Return top 3 most common tags in incorrect questions
        return tagCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    private func identifyStrongAreas(questions: [QuestionSummary]) -> [String] {
        let correctQuestions = questions.filter { $0.grade == .correct }

        // Group by tags if available
        var tagCounts: [String: Int] = [:]
        for question in correctQuestions {
            if let tags = question.tags {
                for tag in tags {
                    tagCounts[tag, default: 0] += 1
                }
            }
        }

        // Return top 3 most common tags in correct questions
        return tagCounts.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }
    }

    // MARK: - Summary Calculation

    private func calculateSummary(subjectProgress: [SubjectProgressData], allQuestions: [QuestionSummary]) -> SubjectBreakdownSummary {
        let totalSubjectsStudied = subjectProgress.count

        let mostStudiedSubject = subjectProgress.max(by: { $0.questionsAnswered < $1.questionsAnswered })?.subject
        let leastStudiedSubject = subjectProgress.min(by: { $0.questionsAnswered < $1.questionsAnswered })?.subject

        let highestPerformingSubject = subjectProgress.max(by: { $0.averageAccuracy < $1.averageAccuracy })?.subject
        let lowestPerformingSubject = subjectProgress.min(by: { $0.averageAccuracy < $1.averageAccuracy })?.subject

        let totalQuestionsAcrossSubjects = allQuestions.count
        let totalCorrect = allQuestions.filter { $0.grade == .correct }.count
        let overallAccuracy = totalQuestionsAcrossSubjects > 0 ? Double(totalCorrect) / Double(totalQuestionsAcrossSubjects) * 100.0 : 0.0

        // Subject distribution
        var subjectDistribution: [SubjectCategory: Int] = [:]
        for progress in subjectProgress {
            subjectDistribution[progress.subject] = progress.questionsAnswered
        }

        // Subject performance
        var subjectPerformance: [SubjectCategory: Double] = [:]
        for progress in subjectProgress {
            subjectPerformance[progress.subject] = progress.averageAccuracy
        }

        // Study time distribution
        var studyTimeDistribution: [SubjectCategory: Int] = [:]
        for progress in subjectProgress {
            studyTimeDistribution[progress.subject] = progress.totalStudyTimeMinutes
        }

        let totalStudyTime = TimeInterval(subjectProgress.reduce(0) { $0 + $1.totalStudyTimeMinutes } * 60)
        let improvementRate = 0.0 // Would need historical data to calculate

        return SubjectBreakdownSummary(
            totalSubjectsStudied: totalSubjectsStudied,
            mostStudiedSubject: mostStudiedSubject,
            leastStudiedSubject: leastStudiedSubject,
            highestPerformingSubject: highestPerformingSubject,
            lowestPerformingSubject: lowestPerformingSubject,
            totalQuestionsAcrossSubjects: totalQuestionsAcrossSubjects,
            overallAccuracy: overallAccuracy,
            subjectDistribution: subjectDistribution,
            subjectPerformance: subjectPerformance,
            studyTimeDistribution: studyTimeDistribution,
            lastUpdated: Date(),
            totalQuestionsAnswered: totalQuestionsAcrossSubjects,
            totalStudyTime: totalStudyTime,
            improvementRate: improvementRate
        )
    }

    // MARK: - Insights Calculation

    private func calculateInsights(subjectProgress: [SubjectProgressData]) -> SubjectInsights {
        // Subjects needing attention (accuracy < 70%)
        let subjectToFocus = subjectProgress
            .filter { $0.averageAccuracy < 70.0 }
            .map { $0.subject }

        // Strong subjects to maintain (accuracy >= 80%)
        let subjectsToMaintain = subjectProgress
            .filter { $0.averageAccuracy >= 80.0 }
            .map { $0.subject }

        // Study time recommendations (more time for low-performing subjects)
        var studyTimeRecommendations: [SubjectCategory: Int] = [:]
        for progress in subjectProgress {
            let recommendedMinutes: Int
            if progress.averageAccuracy < 60 {
                recommendedMinutes = 30 // 30 min/day for struggling subjects
            } else if progress.averageAccuracy < 75 {
                recommendedMinutes = 20 // 20 min/day for average subjects
            } else {
                recommendedMinutes = 15 // 15 min/day for strong subjects
            }
            studyTimeRecommendations[progress.subject] = recommendedMinutes
        }

        // Cross-subject connections (not available without more data)
        let crossSubjectConnections: [SubjectConnection] = []

        // Achievement opportunities (not available without more data)
        let achievementOpportunities: [SubjectAchievement] = []

        // Personalized tips
        let personalizedTips = generatePersonalizedTips(subjectProgress: subjectProgress)

        // Optimal study schedule (empty for now)
        let optimalStudySchedule = WeeklyStudySchedule(
            monday: [],
            tuesday: [],
            wednesday: [],
            thursday: [],
            friday: [],
            saturday: [],
            sunday: []
        )

        return SubjectInsights(
            subjectToFocus: subjectToFocus,
            subjectsToMaintain: subjectsToMaintain,
            studyTimeRecommendations: studyTimeRecommendations,
            crossSubjectConnections: crossSubjectConnections,
            achievementOpportunities: achievementOpportunities,
            personalizedTips: personalizedTips,
            optimalStudySchedule: optimalStudySchedule
        )
    }

    private func generatePersonalizedTips(subjectProgress: [SubjectProgressData]) -> [String] {
        var tips: [String] = []

        // Tip based on overall activity
        let totalQuestions = subjectProgress.reduce(0) { $0 + $1.questionsAnswered }
        if totalQuestions < 10 {
            tips.append("Try to answer at least 10 questions per day to build consistent study habits")
        }

        // Tip for low-performing subjects
        if let weakestSubject = subjectProgress.min(by: { $0.averageAccuracy < $1.averageAccuracy }),
           weakestSubject.averageAccuracy < 70 {
            tips.append("Focus extra time on \(weakestSubject.subject.rawValue) to improve your accuracy")
        }

        // Tip for streak
        if let bestStreak = subjectProgress.max(by: { $0.streakDays < $1.streakDays }),
           bestStreak.streakDays >= 3 {
            tips.append("Great \(bestStreak.streakDays)-day streak in \(bestStreak.subject.rawValue)! Keep it up!")
        }

        return tips
    }

    // MARK: - Trends Calculation

    private func calculateTrends(questionsBySubject: [String: [QuestionSummary]]) -> [SubjectTrendData] {
        var result: [SubjectTrendData] = []

        for (subjectName, questions) in questionsBySubject {
            let subjectCategory = mapSubjectToCategory(subjectName)

            // Calculate weekly trends (last 4 weeks)
            let weeklyTrends = calculateWeeklyTrends(questions: questions)

            // Calculate monthly trends (last 3 months)
            let monthlyTrends = calculateMonthlyTrends(questions: questions)

            // Determine trend direction
            let trendDirection = determineTrendDirection(weeklyTrends: weeklyTrends)

            // Project performance (based on recent trend)
            let projectedPerformance = weeklyTrends.last?.accuracy ?? 0.0

            let trend = SubjectTrendData(
                subject: subjectCategory,
                weeklyTrends: weeklyTrends,
                monthlyTrends: monthlyTrends,
                trendDirection: trendDirection,
                projectedPerformance: projectedPerformance,
                seasonalPattern: nil
            )

            result.append(trend)
        }

        return result
    }

    private func calculateWeeklyTrends(questions: [QuestionSummary]) -> [WeeklySubjectTrend] {
        let calendar = Calendar.current
        var trends: [WeeklySubjectTrend] = []

        // Group questions by week
        let questionsByWeek = Dictionary(grouping: questions) { question in
            calendar.dateInterval(of: .weekOfYear, for: question.archivedAt)?.start ?? question.archivedAt
        }

        // Calculate metrics for each week
        for (weekStart, weekQuestions) in questionsByWeek.sorted(by: { $0.key > $1.key }).prefix(4) {
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            let questionCount = weekQuestions.count
            let correctCount = weekQuestions.filter { $0.grade == .correct }.count
            let accuracy = questionCount > 0 ? Double(correctCount) / Double(questionCount) * 100.0 : 0.0
            let studyTimeMinutes = questionCount * 2

            let trend = WeeklySubjectTrend(
                weekStart: dateFormatter.string(from: weekStart),
                weekEnd: dateFormatter.string(from: weekEnd),
                questionCount: questionCount,
                accuracy: accuracy,
                studyTimeMinutes: studyTimeMinutes,
                improvementScore: 0.0 // Would need historical comparison
            )

            trends.append(trend)
        }

        return trends.sorted { $0.weekStart < $1.weekStart }
    }

    private func calculateMonthlyTrends(questions: [QuestionSummary]) -> [MonthlySubjectTrend] {
        let calendar = Calendar.current
        var trends: [MonthlySubjectTrend] = []

        // Group questions by month
        let questionsByMonth = Dictionary(grouping: questions) { question in
            let components = calendar.dateComponents([.year, .month], from: question.archivedAt)
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy-MM"
            return monthFormatter.string(from: calendar.date(from: components) ?? question.archivedAt)
        }

        // Calculate metrics for each month
        for (month, monthQuestions) in questionsByMonth.sorted(by: { $0.key > $1.key }).prefix(3) {
            let questionCount = monthQuestions.count
            let correctCount = monthQuestions.filter { $0.grade == .correct }.count
            let accuracy = questionCount > 0 ? Double(correctCount) / Double(questionCount) * 100.0 : 0.0
            let studyTimeHours = Double(questionCount * 2) / 60.0
            let masteryLevel = accuracy / 100.0

            let trend = MonthlySubjectTrend(
                month: month,
                questionCount: questionCount,
                accuracy: accuracy,
                studyTimeHours: studyTimeHours,
                masteryLevel: masteryLevel
            )

            trends.append(trend)
        }

        return trends.sorted { $0.month < $1.month }
    }

    private func determineTrendDirection(weeklyTrends: [WeeklySubjectTrend]) -> TrendDirection {
        guard weeklyTrends.count >= 2 else { return .stable }

        let recentWeeks = weeklyTrends.suffix(2)
        let oldAccuracy = recentWeeks.first?.accuracy ?? 0
        let newAccuracy = recentWeeks.last?.accuracy ?? 0

        let change = newAccuracy - oldAccuracy

        if change > 10 {
            return .improving
        } else if change < -10 {
            return .declining
        } else if abs(change) < 5 {
            return .stable
        } else {
            return .volatile
        }
    }

    // MARK: - Comparisons Calculation

    private func calculateComparisons(subjectProgress: [SubjectProgressData]) -> [SubjectComparison] {
        var comparisons: [SubjectComparison] = []

        // Compare each subject with the overall average
        let overallAvgAccuracy = subjectProgress.isEmpty ? 0 : subjectProgress.reduce(0.0) { $0 + $1.averageAccuracy } / Double(subjectProgress.count)

        for progress in subjectProgress {
            let accuracyDifference = progress.averageAccuracy - overallAvgAccuracy
            let comparisonType: SubjectComparison.ComparisonType

            if accuracyDifference > 5 {
                comparisonType = .better
            } else if accuracyDifference < -5 {
                comparisonType = .worse
            } else {
                comparisonType = .similar
            }

            // Compare with a "reference subject" (highest performing)
            if let bestSubject = subjectProgress.max(by: { $0.averageAccuracy < $1.averageAccuracy }),
               progress.subject != bestSubject.subject {
                let comparison = SubjectComparison(
                    primarySubject: progress.subject,
                    comparedToSubject: bestSubject.subject,
                    accuracyDifference: progress.averageAccuracy - bestSubject.averageAccuracy,
                    studyTimeDifference: progress.totalStudyTimeMinutes - bestSubject.totalStudyTimeMinutes,
                    comparisonType: comparisonType
                )
                comparisons.append(comparison)
            }
        }

        return comparisons
    }

    // MARK: - Recommendations Generation

    private func generateRecommendations(subjectProgress: [SubjectProgressData], insights: SubjectInsights) -> [SubjectRecommendation] {
        var recommendations: [SubjectRecommendation] = []

        // Recommend practice for low-performing subjects
        for subject in insights.subjectToFocus {
            if let progress = subjectProgress.first(where: { $0.subject == subject }) {
                let recommendation = SubjectRecommendation(
                    targetSubject: subject,
                    title: "Improve \(subject.rawValue) Performance",
                    description: "Your accuracy in \(subject.rawValue) is \(String(format: "%.1f%%", progress.averageAccuracy)). Practice more questions to improve.",
                    priority: .high,
                    estimatedTimeToComplete: 30,
                    category: .practiceMore
                )
                recommendations.append(recommendation)
            }
        }

        // Recommend maintenance for strong subjects
        for subject in insights.subjectsToMaintain {
            if let progress = subjectProgress.first(where: { $0.subject == subject }) {
                let recommendation = SubjectRecommendation(
                    targetSubject: subject,
                    title: "Maintain \(subject.rawValue) Strength",
                    description: "You're doing great in \(subject.rawValue) with \(String(format: "%.1f%%", progress.averageAccuracy)) accuracy. Keep practicing regularly.",
                    priority: .low,
                    estimatedTimeToComplete: 15,
                    category: .studyTime
                )
                recommendations.append(recommendation)
            }
        }

        return recommendations
    }

    // MARK: - Subject Mapping

    private func mapSubjectToCategory(_ subjectName: String) -> SubjectCategory {
        let normalized = subjectName.lowercased().trimmingCharacters(in: .whitespaces)

        switch normalized {
        case "math", "mathematics", "algebra", "geometry", "calculus":
            return .mathematics
        case "physics":
            return .physics
        case "chemistry":
            return .chemistry
        case "biology":
            return .biology
        case "english", "literature", "writing":
            return .english
        case "history":
            return .history
        case "geography":
            return .geography
        case "computer science", "programming", "cs", "coding":
            return .computerScience
        case "spanish", "french", "german", "chinese", "language":
            return .foreignLanguage
        case "art", "arts", "music", "drama":
            return .arts
        default:
            return .other
        }
    }
}
