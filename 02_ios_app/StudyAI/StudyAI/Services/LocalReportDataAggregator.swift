//
//  LocalReportDataAggregator.swift
//  StudyAI
//
//  Local-first report data aggregation service
//  Aggregates all report data from local storage (no server database queries)
//

import Foundation

/// Aggregates report data from local storage for parent reports
class LocalReportDataAggregator {
    static let shared = LocalReportDataAggregator()

    private let questionStorage = QuestionLocalStorage.shared
    private let conversationStorage = ConversationLocalStorage.shared
    private let progressService = LocalProgressService.shared

    private init() {}

    // MARK: - Main Aggregation Method

    /// Aggregate comprehensive report data from local storage
    /// This replaces the backend's database queries with local data
    func aggregateReportData(
        userId: String,
        startDate: Date,
        endDate: Date,
        options: ReportAggregationOptions = ReportAggregationOptions()
    ) async -> ReportData {

        let startTime = Date()

        // Fetch all local data
        let localQuestions = questionStorage.getLocalQuestions()
        let localConversations = conversationStorage.getLocalConversations()

        // Convert and filter questions by date range
        let questions = filterAndConvertQuestions(localQuestions, startDate: startDate, endDate: endDate)

        // Convert and filter conversations by date range
        let conversations = filterConversations(localConversations, startDate: startDate, endDate: endDate)

        // Calculate all metrics
        let academic = calculateAcademicMetrics(questions: questions, startDate: startDate, endDate: endDate)
        let activity = calculateActivityMetrics(questions: questions, conversations: conversations)
        let subjects = calculateSubjectBreakdown(questions: questions)
        let progress = await calculateProgressMetrics(questions: questions, startDate: startDate, endDate: endDate)
        let mistakes = analyzeMistakePatterns(questions: questions)

        let generationTime = Date().timeIntervalSince(startTime)

        return ReportData(
            userId: userId,
            reportPeriod: ReportPeriod(startDate: startDate, endDate: endDate),
            generatedAt: Date(),
            academic: academic,
            activity: activity,
            mentalHealth: nil, // Mental health not available from local storage
            subjects: subjects,
            progress: progress,
            mistakes: mistakes,
            metadata: ReportMetadata(
                generationTimeMs: Int(generationTime * 1000),
                dataPoints: DataPointsMetrics(
                    questions: questions.count,
                    sessions: calculateSessionCount(questions: questions),
                    conversations: conversations.count,
                    mentalHealthIndicators: 0
                )
            )
        )
    }

    // MARK: - Data Filtering

    private func filterAndConvertQuestions(_ localQuestions: [[String: Any]], startDate: Date, endDate: Date) -> [QuestionSummary] {
        var questions: [QuestionSummary] = []

        for questionData in localQuestions {
            // Parse archived date
            guard let archivedAtString = questionData["archivedAt"] as? String,
                  let archivedAt = parseDate(archivedAtString) else {
                continue
            }

            // Filter by date range
            guard archivedAt >= startDate && archivedAt <= endDate else {
                continue
            }

            // Convert to QuestionSummary
            if let question = try? questionStorage.convertLocalQuestionToSummary(questionData) {
                questions.append(question)
            }
        }

        return questions
    }

    private func filterConversations(_ localConversations: [[String: Any]], startDate: Date, endDate: Date) -> [[String: Any]] {
        return localConversations.filter { conversation in
            guard let archivedDateString = conversation["archived_date"] as? String,
                  let archivedDate = parseDate(archivedDateString) else {
                return false
            }
            return archivedDate >= startDate && archivedDate <= endDate
        }
    }

    // MARK: - Metric Calculations

    private func calculateAcademicMetrics(questions: [QuestionSummary], startDate: Date, endDate: Date) -> AcademicMetrics {
        let totalQuestions = questions.count
        let gradedQuestions = questions.filter { $0.isGraded }
        let correctAnswers = gradedQuestions.filter { $0.grade == .correct }.count

        // NEW: Calculate performance breakdown
        let incorrectAnswers = gradedQuestions.filter { $0.grade == .incorrect }.count
        let emptyAnswers = gradedQuestions.filter { $0.grade == .empty }.count
        let partialCreditAnswers = gradedQuestions.filter { $0.grade == .partialCredit }.count

        let accuracy = totalQuestions > 0 ? Double(correctAnswers) / Double(totalQuestions) : 0.0
        let averageConfidence = questions.compactMap { $0.confidence }.reduce(0, +) / Float(max(questions.count, 1))

        // Calculate trend by comparing first half vs second half
        let midpoint = questions.count / 2
        let firstHalf = questions.suffix(midpoint) // Older questions
        let secondHalf = questions.prefix(midpoint) // Newer questions

        let firstHalfAccuracy = calculateAccuracy(Array(firstHalf))
        let secondHalfAccuracy = calculateAccuracy(Array(secondHalf))
        let improvementTrend = secondHalfAccuracy > firstHalfAccuracy ? "improving" :
                              secondHalfAccuracy < firstHalfAccuracy ? "declining" : "stable"

        // Calculate time spent (estimate 2 minutes per question)
        let timeSpentMinutes = totalQuestions * 2

        // Calculate questions per day
        let daysDiff = max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
        let questionsPerDay = totalQuestions / daysDiff

        return AcademicMetrics(
            overallAccuracy: accuracy,
            averageConfidence: Double(averageConfidence),
            totalQuestions: totalQuestions,
            correctAnswers: correctAnswers,
            improvementTrend: improvementTrend,
            consistencyScore: Double(calculateConsistencyScore(questions: questions)),
            timeSpentMinutes: timeSpentMinutes,
            questionsPerDay: questionsPerDay,
            totalIncorrect: incorrectAnswers,
            totalEmpty: emptyAnswers,
            totalPartialCredit: partialCreditAnswers
        )
    }

    private func calculateActivityMetrics(questions: [QuestionSummary], conversations: [[String: Any]]) -> ActivityMetrics {
        // Calculate study time (estimate 2 minutes per question)
        let totalStudyMinutes = questions.count * 2

        // Calculate active days
        let calendar = Calendar.current
        let activeDays = Set(questions.map { calendar.startOfDay(for: $0.archivedAt) }).count

        // Calculate sessions per day (estimate 1 session per unique day)
        let sessionsPerDay = activeDays > 0 ? Double(questions.count) / Double(activeDays) : 0

        // Average session length (estimate)
        let averageSessionMinutes = activeDays > 0 ? totalStudyMinutes / activeDays : 0

        // Conversation engagement
        let totalConversations = conversations.count
        let totalMessages = totalConversations * 5 // Estimate 5 messages per conversation
        let averageMessagesPerConversation = totalConversations > 0 ? totalMessages / totalConversations : 0
        let conversationEngagementScore = min(1.0, Double(totalConversations) / 10.0) // 10+ conversations = 100% engagement

        // Study patterns
        let subjectPreferences = Array(Set(questions.map { $0.normalizedSubject }))
        let preferredStudyTimes = "afternoon" // Default, would need time data to calculate
        let sessionLengthTrend = "consistent" // Default

        return ActivityMetrics(
            studyTime: StudyTimeMetrics(
                totalMinutes: totalStudyMinutes,
                averageSessionMinutes: averageSessionMinutes,
                activeDays: activeDays,
                sessionsPerDay: sessionsPerDay
            ),
            engagement: EngagementMetrics(
                totalConversations: totalConversations,
                totalMessages: totalMessages,
                averageMessagesPerConversation: averageMessagesPerConversation,
                conversationEngagementScore: conversationEngagementScore
            ),
            patterns: StudyPatterns(
                preferredStudyTimes: preferredStudyTimes,
                sessionLengthTrend: sessionLengthTrend,
                subjectPreferences: subjectPreferences
            )
        )
    }

    private func calculateSubjectBreakdown(questions: [QuestionSummary]) -> [String: SubjectMetrics] {
        let questionsBySubject = Dictionary(grouping: questions) { $0.normalizedSubject }

        var subjectMetrics: [String: SubjectMetrics] = [:]

        for (subject, subjectQuestions) in questionsBySubject {
            let totalQuestions = subjectQuestions.count
            let correctAnswers = subjectQuestions.filter { $0.grade == .correct }.count
            let accuracy = totalQuestions > 0 ? Double(correctAnswers) / Double(totalQuestions) : 0.0
            let averageConfidence = subjectQuestions.compactMap { $0.confidence }.reduce(0, +) / Float(max(subjectQuestions.count, 1))

            // Estimate study time (2 minutes per question)
            let totalStudyTime = totalQuestions * 2

            // Estimate sessions (1 session per day of activity)
            let calendar = Calendar.current
            let totalSessions = Set(subjectQuestions.map { calendar.startOfDay(for: $0.archivedAt) }).count
            let averageSessionLength = totalSessions > 0 ? Double(totalStudyTime) / Double(totalSessions) : 0.0

            subjectMetrics[subject] = SubjectMetrics(
                performance: SubjectPerformance(
                    totalQuestions: totalQuestions,
                    correctAnswers: correctAnswers,
                    accuracy: accuracy,
                    averageConfidence: Double(averageConfidence)
                ),
                activity: SubjectActivity(
                    totalSessions: totalSessions,
                    totalStudyTime: totalStudyTime,
                    averageSessionLength: averageSessionLength
                )
            )
        }

        return subjectMetrics
    }

    private func calculateProgressMetrics(questions: [QuestionSummary], startDate: Date, endDate: Date) async -> ProgressMetrics {
        // Determine overall trend based on recent performance
        let trend = determineTrend(questions: questions)

        // Identify improvements
        let improvements = identifyImprovements(questions: questions)

        // Identify concerns
        let concerns = identifyConcerns(questions: questions)

        // Generate recommendations
        let recommendations = generateRecommendations(questions: questions)

        return ProgressMetrics(
            comparison: "Local report - no previous period comparison available",
            improvements: improvements,
            concerns: concerns,
            overallTrend: trend,
            progressScore: nil,
            detailedComparison: nil,
            recommendations: recommendations,
            previousPeriod: nil
        )
    }

    private func analyzeMistakePatterns(questions: [QuestionSummary]) -> MistakeAnalysis {
        let mistakes = questions.filter { $0.grade == .incorrect || $0.grade == .partialCredit }
        let totalQuestions = questions.count

        let mistakesBySubject = Dictionary(grouping: mistakes) { $0.normalizedSubject }
        let patterns = mistakesBySubject.map { subject, mistakeList -> MistakePattern in
            let count = mistakeList.count
            let percentage = totalQuestions > 0 ? Int((Double(count) / Double(totalQuestions)) * 100) : 0
            let averageConfidence = mistakeList.compactMap { $0.confidence }.reduce(0, +) / Float(max(mistakeList.count, 1))

            return MistakePattern(
                subject: subject,
                count: count,
                percentage: percentage,
                averageConfidence: Double(averageConfidence),
                commonIssues: ["Review needed for \(subject)"]
            )
        }

        let mistakeRate = totalQuestions > 0 ? Int((Double(mistakes.count) / Double(totalQuestions)) * 100) : 0
        let recommendations = mistakes.isEmpty ?
            ["Great job! Keep up the excellent work."] :
            ["Focus on subjects with lower accuracy", "Review mistakes to identify patterns"]

        return MistakeAnalysis(
            totalMistakes: mistakes.count,
            mistakeRate: mistakeRate,
            patterns: patterns,
            recommendations: recommendations
        )
    }

    // MARK: - Helper Methods

    private func calculateAccuracy(_ questions: [QuestionSummary]) -> Float {
        guard !questions.isEmpty else { return 0.0 }
        let correct = questions.filter { $0.grade == .correct }.count
        return Float(correct) / Float(questions.count)
    }

    private func calculateConsistencyScore(questions: [QuestionSummary]) -> Float {
        guard questions.count > 5 else { return 0.5 } // Not enough data

        // Calculate accuracy variance across time periods
        let chunkSize = max(5, questions.count / 5)
        var accuracies: [Float] = []

        for i in stride(from: 0, to: questions.count, by: chunkSize) {
            let chunk = Array(questions[i..<min(i + chunkSize, questions.count)])
            accuracies.append(calculateAccuracy(chunk))
        }

        // Lower variance = higher consistency
        let mean = accuracies.reduce(0, +) / Float(accuracies.count)
        let variance = accuracies.map { pow($0 - mean, 2) }.reduce(0, +) / Float(accuracies.count)

        return max(0.0, 1.0 - variance) // Convert variance to consistency score
    }

    private func calculateSessionCount(questions: [QuestionSummary]) -> Int {
        let calendar = Calendar.current
        return Set(questions.map { calendar.startOfDay(for: $0.archivedAt) }).count
    }

    private func determineTrend(questions: [QuestionSummary]) -> String {
        guard questions.count > 10 else { return "stable" }

        let midpoint = questions.count / 2
        let older = Array(questions.suffix(midpoint))
        let newer = Array(questions.prefix(midpoint))

        let olderAccuracy = calculateAccuracy(older)
        let newerAccuracy = calculateAccuracy(newer)

        if newerAccuracy > olderAccuracy + 0.1 {
            return "improving"
        } else if newerAccuracy < olderAccuracy - 0.1 {
            return "declining"
        }
        return "stable"
    }

    private func identifyImprovements(questions: [QuestionSummary]) -> [ProgressImprovement] {
        let subjectAccuracies = Dictionary(grouping: questions) { $0.normalizedSubject }
            .mapValues { calculateAccuracy($0) }
            .filter { $0.value >= 0.8 }

        return subjectAccuracies.map { subject, accuracy in
            ProgressImprovement(
                metric: "accuracy",
                change: Double(accuracy),
                message: "Strong performance in \(subject) (\(Int(accuracy * 100))% accuracy)",
                significance: accuracy >= 0.9 ? "major" : "minor"
            )
        }
    }

    private func identifyConcerns(questions: [QuestionSummary]) -> [ProgressConcern] {
        let subjectAccuracies = Dictionary(grouping: questions) { $0.normalizedSubject }
            .mapValues { calculateAccuracy($0) }
            .filter { $0.value < 0.6 }

        return subjectAccuracies.map { subject, accuracy in
            ProgressConcern(
                metric: "accuracy",
                change: Double(accuracy),
                message: "Needs practice in \(subject) (\(Int(accuracy * 100))% accuracy)",
                significance: accuracy < 0.4 ? "major" : "minor"
            )
        }
    }

    private func generateRecommendations(questions: [QuestionSummary]) -> [ProgressRecommendation] {
        var recommendations: [ProgressRecommendation] = []

        // Check for consistency
        if calculateConsistencyScore(questions: questions) < 0.5 {
            recommendations.append(ProgressRecommendation(
                category: "habits",
                priority: "high",
                title: "Improve Study Consistency",
                description: "Maintaining a regular study schedule will help improve learning outcomes",
                actionItems: ["Set a specific study time each day", "Track your daily progress"]
            ))
        }

        // Check for subject diversity
        let subjects = Set(questions.map { $0.normalizedSubject })
        if subjects.count < 3 {
            recommendations.append(ProgressRecommendation(
                category: "academic",
                priority: "medium",
                title: "Expand Subject Coverage",
                description: "Exploring more subject areas will help broaden your knowledge base",
                actionItems: ["Try studying a new subject", "Review different topics"]
            ))
        }

        return recommendations
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}

// MARK: - Data Models

struct ReportAggregationOptions {
    var includeAIInsights: Bool = false
    var forceRefresh: Bool = false
}
