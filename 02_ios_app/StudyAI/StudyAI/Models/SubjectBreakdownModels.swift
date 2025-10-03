//
//  SubjectBreakdownModels.swift
//  StudyAI
//
//  Enhanced subject breakdown and analytics models
//

import Foundation
import SwiftUI

// MARK: - Subject Progress Analytics

struct SubjectProgressData: Codable, Identifiable {
    var id: UUID
    let subject: SubjectCategory
    var questionsAnswered: Int
    var correctAnswers: Int
    var totalStudyTimeMinutes: Int
    var streakDays: Int
    var lastStudiedDate: String // "2024-01-15"
    var recentActivity: [DailySubjectActivity]
    var weakAreas: [String]
    var strongAreas: [String]
    var difficultyProgression: [DifficultyLevel: Int]
    var topicBreakdown: [String: Int] // topic -> question count
    
    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.subject = try container.decode(SubjectCategory.self, forKey: .subject)
        self.questionsAnswered = try container.decode(Int.self, forKey: .questionsAnswered)
        self.correctAnswers = try container.decode(Int.self, forKey: .correctAnswers)
        self.totalStudyTimeMinutes = try container.decode(Int.self, forKey: .totalStudyTimeMinutes)
        self.streakDays = try container.decode(Int.self, forKey: .streakDays)
        self.lastStudiedDate = try container.decode(String.self, forKey: .lastStudiedDate)
        self.recentActivity = try container.decode([DailySubjectActivity].self, forKey: .recentActivity)
        self.weakAreas = try container.decode([String].self, forKey: .weakAreas)
        self.strongAreas = try container.decode([String].self, forKey: .strongAreas)
        self.difficultyProgression = (try? container.decode([DifficultyLevel: Int].self, forKey: .difficultyProgression)) ?? [:]
        self.topicBreakdown = (try? container.decode([String: Int].self, forKey: .topicBreakdown)) ?? [:]
    }
    
    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        subject: SubjectCategory,
        questionsAnswered: Int,
        correctAnswers: Int,
        totalStudyTimeMinutes: Int,
        streakDays: Int,
        lastStudiedDate: String,
        recentActivity: [DailySubjectActivity] = [],
        weakAreas: [String] = [],
        strongAreas: [String] = [],
        difficultyProgression: [DifficultyLevel: Int] = [:],
        topicBreakdown: [String: Int] = [:]
    ) {
        self.id = id
        self.subject = subject
        self.questionsAnswered = questionsAnswered
        self.correctAnswers = correctAnswers
        self.totalStudyTimeMinutes = totalStudyTimeMinutes
        self.streakDays = streakDays
        self.lastStudiedDate = lastStudiedDate
        self.recentActivity = recentActivity
        self.weakAreas = weakAreas
        self.strongAreas = strongAreas
        self.difficultyProgression = difficultyProgression
        self.topicBreakdown = topicBreakdown
    }
    
    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case subject, questionsAnswered, correctAnswers, totalStudyTimeMinutes
        case streakDays, lastStudiedDate, recentActivity, weakAreas, strongAreas
        case difficultyProgression, topicBreakdown
    }
    
    // Computed analytics
    var averageAccuracy: Double {
        guard questionsAnswered > 0 else { return 0.0 }
        return Double(correctAnswers) / Double(questionsAnswered) * 100.0
    }
    
    var totalStudyTime: TimeInterval {
        return TimeInterval(totalStudyTimeMinutes * 60)
    }
    
    var averageQuestionsPerDay: Double {
        guard !recentActivity.isEmpty else { return 0.0 }
        let totalQuestions = recentActivity.reduce(0) { $0 + $1.questionCount }
        return Double(totalQuestions) / Double(recentActivity.count)
    }
    
    var performanceLevel: PerformanceLevel {
        switch averageAccuracy {
        case 90...: return .excellent
        case 75..<90: return .good
        case 60..<75: return .average
        case 40..<60: return .needsImprovement
        default: return .beginner
        }
    }
    
    var isActivelyStudied: Bool {
        guard let lastDate = dateFromString(lastStudiedDate) else { return false }
        return Calendar.current.dateInterval(of: .day, for: Date())?.contains(lastDate) ?? false
    }
    
    private func dateFromString(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

struct DailySubjectActivity: Codable, Identifiable {
    var id: UUID
    let date: String // "2024-01-15"
    let subject: SubjectCategory
    var questionCount: Int
    var correctAnswers: Int
    var studyDurationMinutes: Int
    let timezone: String
    
    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.date = try container.decode(String.self, forKey: .date)
        self.subject = try container.decode(SubjectCategory.self, forKey: .subject)
        self.questionCount = try container.decode(Int.self, forKey: .questionCount)
        self.correctAnswers = try container.decode(Int.self, forKey: .correctAnswers)
        self.studyDurationMinutes = try container.decode(Int.self, forKey: .studyDurationMinutes)
        self.timezone = try container.decode(String.self, forKey: .timezone)
    }
    
    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        date: String,
        subject: SubjectCategory,
        questionCount: Int,
        correctAnswers: Int,
        studyDurationMinutes: Int,
        timezone: String
    ) {
        self.id = id
        self.date = date
        self.subject = subject
        self.questionCount = questionCount
        self.correctAnswers = correctAnswers
        self.studyDurationMinutes = studyDurationMinutes
        self.timezone = timezone
    }
    
    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case date, subject, questionCount, correctAnswers, studyDurationMinutes, timezone
    }
    
    var accuracy: Double {
        guard questionCount > 0 else { return 0.0 }
        return Double(correctAnswers) / Double(questionCount) * 100.0
    }
    
    var studyDuration: TimeInterval {
        return TimeInterval(studyDurationMinutes * 60)
    }
    
    var intensityLevel: StudyIntensity {
        switch questionCount {
        case 0: return .none
        case 1...5: return .light
        case 6...15: return .moderate
        case 16...30: return .intense
        case 31...: return .extreme
        default: return .none
        }
    }
}

// MARK: - Subject Breakdown Summary

struct SubjectBreakdownSummary: Codable {
    let totalSubjectsStudied: Int
    let mostStudiedSubject: SubjectCategory?
    let leastStudiedSubject: SubjectCategory?
    let highestPerformingSubject: SubjectCategory?
    let lowestPerformingSubject: SubjectCategory?
    let totalQuestionsAcrossSubjects: Int
    let overallAccuracy: Double
    let subjectDistribution: [SubjectCategory: Int]
    let subjectPerformance: [SubjectCategory: Double]
    let studyTimeDistribution: [SubjectCategory: Int] // minutes
    let lastUpdated: Date
    let totalQuestionsAnswered: Int
    let totalStudyTime: TimeInterval
    let improvementRate: Double
    
    // Custom initializer for JSON decoding - handles empty dictionaries
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.totalSubjectsStudied = try container.decode(Int.self, forKey: .totalSubjectsStudied)
        self.mostStudiedSubject = try container.decodeIfPresent(SubjectCategory.self, forKey: .mostStudiedSubject)
        self.leastStudiedSubject = try container.decodeIfPresent(SubjectCategory.self, forKey: .leastStudiedSubject)
        self.highestPerformingSubject = try container.decodeIfPresent(SubjectCategory.self, forKey: .highestPerformingSubject)
        self.lowestPerformingSubject = try container.decodeIfPresent(SubjectCategory.self, forKey: .lowestPerformingSubject)
        self.totalQuestionsAcrossSubjects = try container.decode(Int.self, forKey: .totalQuestionsAcrossSubjects)
        self.overallAccuracy = try container.decode(Double.self, forKey: .overallAccuracy)

        // Handle empty dictionaries that can't be decoded as specific types
        self.subjectDistribution = (try? container.decode([SubjectCategory: Int].self, forKey: .subjectDistribution)) ?? [:]
        self.subjectPerformance = (try? container.decode([SubjectCategory: Double].self, forKey: .subjectPerformance)) ?? [:]
        self.studyTimeDistribution = (try? container.decode([SubjectCategory: Int].self, forKey: .studyTimeDistribution)) ?? [:]

        // Handle lastUpdated as ISO string
        let lastUpdatedString = try container.decode(String.self, forKey: .lastUpdated)
        let formatter = ISO8601DateFormatter()
        self.lastUpdated = formatter.date(from: lastUpdatedString) ?? Date()

        self.totalQuestionsAnswered = try container.decode(Int.self, forKey: .totalQuestionsAnswered)
        self.totalStudyTime = TimeInterval(try container.decode(Int.self, forKey: .totalStudyTime))
        self.improvementRate = try container.decode(Double.self, forKey: .improvementRate)
    }
    
    // Regular initializer for programmatic creation
    init(
        totalSubjectsStudied: Int,
        mostStudiedSubject: SubjectCategory? = nil,
        leastStudiedSubject: SubjectCategory? = nil,
        highestPerformingSubject: SubjectCategory? = nil,
        lowestPerformingSubject: SubjectCategory? = nil,
        totalQuestionsAcrossSubjects: Int,
        overallAccuracy: Double,
        subjectDistribution: [SubjectCategory: Int] = [:],
        subjectPerformance: [SubjectCategory: Double] = [:],
        studyTimeDistribution: [SubjectCategory: Int] = [:],
        lastUpdated: Date = Date(),
        totalQuestionsAnswered: Int,
        totalStudyTime: TimeInterval,
        improvementRate: Double
    ) {
        self.totalSubjectsStudied = totalSubjectsStudied
        self.mostStudiedSubject = mostStudiedSubject
        self.leastStudiedSubject = leastStudiedSubject
        self.highestPerformingSubject = highestPerformingSubject
        self.lowestPerformingSubject = lowestPerformingSubject
        self.totalQuestionsAcrossSubjects = totalQuestionsAcrossSubjects
        self.overallAccuracy = overallAccuracy
        self.subjectDistribution = subjectDistribution
        self.subjectPerformance = subjectPerformance
        self.studyTimeDistribution = studyTimeDistribution
        self.lastUpdated = lastUpdated
        self.totalQuestionsAnswered = totalQuestionsAnswered
        self.totalStudyTime = totalStudyTime
        self.improvementRate = improvementRate
    }
    
    // Coding keys for JSON encoding/decoding
    enum CodingKeys: String, CodingKey {
        case totalSubjectsStudied, mostStudiedSubject, leastStudiedSubject
        case highestPerformingSubject, lowestPerformingSubject, totalQuestionsAcrossSubjects
        case overallAccuracy, subjectDistribution, subjectPerformance, studyTimeDistribution
        case lastUpdated, totalQuestionsAnswered, totalStudyTime, improvementRate
    }
    
    var diversityScore: Double {
        // Calculate how evenly distributed study time is across subjects
        guard !subjectDistribution.isEmpty else { return 0.0 }
        let values = Array(subjectDistribution.values)
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        let variance = values.reduce(0.0) { sum, value in
            sum + pow(Double(value) - mean, 2)
        } / Double(values.count)
        let stdDev = sqrt(variance)
        return max(0.0, 100.0 - (stdDev / mean * 100.0)) // Higher score = more diverse
    }
}

// MARK: - Subject Insights & Recommendations

struct SubjectInsights: Codable {
    let subjectToFocus: [SubjectCategory] // Subjects needing attention
    let subjectsToMaintain: [SubjectCategory] // Strong subjects to keep up
    let studyTimeRecommendations: [SubjectCategory: Int] // Recommended minutes per day
    let crossSubjectConnections: [SubjectConnection]
    let achievementOpportunities: [SubjectAchievement]
    let personalizedTips: [String]
    let optimalStudySchedule: WeeklyStudySchedule
    
    // Custom initializer for JSON decoding - handles empty dictionaries and arrays
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.subjectToFocus = (try? container.decode([SubjectCategory].self, forKey: .subjectToFocus)) ?? []
        self.subjectsToMaintain = (try? container.decode([SubjectCategory].self, forKey: .subjectsToMaintain)) ?? []
        self.studyTimeRecommendations = (try? container.decode([SubjectCategory: Int].self, forKey: .studyTimeRecommendations)) ?? [:]
        self.crossSubjectConnections = (try? container.decode([SubjectConnection].self, forKey: .crossSubjectConnections)) ?? []
        self.achievementOpportunities = (try? container.decode([SubjectAchievement].self, forKey: .achievementOpportunities)) ?? []
        self.personalizedTips = (try? container.decode([String].self, forKey: .personalizedTips)) ?? []
        self.optimalStudySchedule = (try? container.decode(WeeklyStudySchedule.self, forKey: .optimalStudySchedule)) ?? WeeklyStudySchedule(
            monday: [], tuesday: [], wednesday: [], thursday: [],
            friday: [], saturday: [], sunday: []
        )
    }
    
    // Regular initializer for programmatic creation
    init(
        subjectToFocus: [SubjectCategory],
        subjectsToMaintain: [SubjectCategory],
        studyTimeRecommendations: [SubjectCategory: Int],
        crossSubjectConnections: [SubjectConnection],
        achievementOpportunities: [SubjectAchievement],
        personalizedTips: [String],
        optimalStudySchedule: WeeklyStudySchedule
    ) {
        self.subjectToFocus = subjectToFocus
        self.subjectsToMaintain = subjectsToMaintain
        self.studyTimeRecommendations = studyTimeRecommendations
        self.crossSubjectConnections = crossSubjectConnections
        self.achievementOpportunities = achievementOpportunities
        self.personalizedTips = personalizedTips
        self.optimalStudySchedule = optimalStudySchedule
    }
    
    // Coding keys for JSON encoding/decoding
    enum CodingKeys: String, CodingKey {
        case subjectToFocus, subjectsToMaintain, studyTimeRecommendations
        case crossSubjectConnections, achievementOpportunities, personalizedTips, optimalStudySchedule
    }
}

struct SubjectConnection: Codable, Identifiable {
    var id: UUID
    let primarySubject: SubjectCategory
    let relatedSubject: SubjectCategory
    let connectionStrength: Double // 0.0 - 1.0
    let description: String
    let suggestedApproach: String
    
    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.primarySubject = try container.decode(SubjectCategory.self, forKey: .primarySubject)
        self.relatedSubject = try container.decode(SubjectCategory.self, forKey: .relatedSubject)
        self.connectionStrength = try container.decode(Double.self, forKey: .connectionStrength)
        self.description = try container.decode(String.self, forKey: .description)
        self.suggestedApproach = try container.decode(String.self, forKey: .suggestedApproach)
    }
    
    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        primarySubject: SubjectCategory,
        relatedSubject: SubjectCategory,
        connectionStrength: Double,
        description: String,
        suggestedApproach: String
    ) {
        self.id = id
        self.primarySubject = primarySubject
        self.relatedSubject = relatedSubject
        self.connectionStrength = connectionStrength
        self.description = description
        self.suggestedApproach = suggestedApproach
    }
    
    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case primarySubject, relatedSubject, connectionStrength, description, suggestedApproach
    }
}

struct SubjectAchievement: Codable, Identifiable {
    var id: UUID
    let subject: SubjectCategory
    let title: String
    let description: String
    let progressRequired: Int
    let currentProgress: Int
    let achievementType: AchievementType
    let reward: String
    
    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.subject = try container.decode(SubjectCategory.self, forKey: .subject)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decode(String.self, forKey: .description)
        self.progressRequired = try container.decode(Int.self, forKey: .progressRequired)
        self.currentProgress = try container.decode(Int.self, forKey: .currentProgress)
        self.achievementType = try container.decode(AchievementType.self, forKey: .achievementType)
        self.reward = try container.decode(String.self, forKey: .reward)
    }
    
    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        subject: SubjectCategory,
        title: String,
        description: String,
        progressRequired: Int,
        currentProgress: Int,
        achievementType: AchievementType,
        reward: String
    ) {
        self.id = id
        self.subject = subject
        self.title = title
        self.description = description
        self.progressRequired = progressRequired
        self.currentProgress = currentProgress
        self.achievementType = achievementType
        self.reward = reward
    }
    
    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case subject, title, description, progressRequired, currentProgress, achievementType, reward
    }
    
    var progressPercentage: Double {
        guard progressRequired > 0 else { return 0.0 }
        return min(Double(currentProgress) / Double(progressRequired) * 100.0, 100.0)
    }
    
    var isCompleted: Bool {
        return currentProgress >= progressRequired
    }
}

struct WeeklyStudySchedule: Codable {
    let monday: [SubjectStudySlot]
    let tuesday: [SubjectStudySlot]
    let wednesday: [SubjectStudySlot]
    let thursday: [SubjectStudySlot]
    let friday: [SubjectStudySlot]
    let saturday: [SubjectStudySlot]
    let sunday: [SubjectStudySlot]
    
    var allSlots: [SubjectStudySlot] {
        return monday + tuesday + wednesday + thursday + friday + saturday + sunday
    }
}

struct SubjectStudySlot: Codable, Identifiable {
    var id: UUID
    let subject: SubjectCategory
    let startTime: String // "09:00"
    let durationMinutes: Int
    let priority: StudyPriority
    let focusArea: String
    
    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.subject = try container.decode(SubjectCategory.self, forKey: .subject)
        self.startTime = try container.decode(String.self, forKey: .startTime)
        self.durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        self.priority = try container.decode(StudyPriority.self, forKey: .priority)
        self.focusArea = try container.decode(String.self, forKey: .focusArea)
    }
    
    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        subject: SubjectCategory,
        startTime: String,
        durationMinutes: Int,
        priority: StudyPriority,
        focusArea: String
    ) {
        self.id = id
        self.subject = subject
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.priority = priority
        self.focusArea = focusArea
    }
    
    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case subject, startTime, durationMinutes, priority, focusArea
    }
}

// MARK: - Supporting Enums

enum PerformanceLevel: String, CaseIterable, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case average = "Average"
    case needsImprovement = "Needs Improvement"
    case beginner = "Beginner"
    
    var color: Color {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .average: return .orange
        case .needsImprovement: return .red
        case .beginner: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .excellent: return "star.fill"
        case .good: return "checkmark.circle.fill"
        case .average: return "minus.circle.fill"
        case .needsImprovement: return "exclamationmark.triangle.fill"
        case .beginner: return "questionmark.circle.fill"
        }
    }
}

enum StudyIntensity: String, CaseIterable, Codable {
    case none = "None"
    case light = "Light"
    case moderate = "Moderate"
    case intense = "Intense"
    case extreme = "Extreme"
    
    var color: Color {
        switch self {
        case .none: return Color.gray.opacity(0.1)
        case .light: return Color.green.opacity(0.3)
        case .moderate: return Color.green.opacity(0.6)
        case .intense: return Color.orange.opacity(0.8)
        case .extreme: return Color.red.opacity(0.9)
        }
    }
}

enum DifficultyLevel: String, CaseIterable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case expert = "Expert"
    
    var numericValue: Int {
        switch self {
        case .beginner: return 1
        case .intermediate: return 2
        case .advanced: return 3
        case .expert: return 4
        }
    }
}

enum AchievementType: String, CaseIterable, Codable {
    case consistency = "Consistency"
    case accuracy = "Accuracy"
    case volume = "Volume"
    case improvement = "Improvement"
    case mastery = "Mastery"
    case discovery = "Discovery"
    
    var icon: String {
        switch self {
        case .consistency: return "calendar.badge.checkmark"
        case .accuracy: return "target"
        case .volume: return "chart.bar.fill"
        case .improvement: return "chart.line.uptrend.xyaxis"
        case .mastery: return "graduationcap.fill"
        case .discovery: return "lightbulb.fill"
        }
    }
}

enum StudyPriority: String, CaseIterable, Codable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case maintenance = "Maintenance"
    
    var color: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        case .maintenance: return .green
        }
    }
}

// MARK: - Subject Trend Analysis

struct SubjectTrendData: Codable, Identifiable {
    var id: UUID
    let subject: SubjectCategory
    let weeklyTrends: [WeeklySubjectTrend]
    let monthlyTrends: [MonthlySubjectTrend]
    let trendDirection: TrendDirection
    let projectedPerformance: Double
    let seasonalPattern: SeasonalPattern?

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.subject = try container.decode(SubjectCategory.self, forKey: .subject)
        self.weeklyTrends = try container.decode([WeeklySubjectTrend].self, forKey: .weeklyTrends)
        self.monthlyTrends = try container.decode([MonthlySubjectTrend].self, forKey: .monthlyTrends)
        self.trendDirection = try container.decode(TrendDirection.self, forKey: .trendDirection)
        self.projectedPerformance = try container.decode(Double.self, forKey: .projectedPerformance)
        self.seasonalPattern = try container.decodeIfPresent(SeasonalPattern.self, forKey: .seasonalPattern)
    }

    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        subject: SubjectCategory,
        weeklyTrends: [WeeklySubjectTrend],
        monthlyTrends: [MonthlySubjectTrend],
        trendDirection: TrendDirection,
        projectedPerformance: Double,
        seasonalPattern: SeasonalPattern?
    ) {
        self.id = id
        self.subject = subject
        self.weeklyTrends = weeklyTrends
        self.monthlyTrends = monthlyTrends
        self.trendDirection = trendDirection
        self.projectedPerformance = projectedPerformance
        self.seasonalPattern = seasonalPattern
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case subject, weeklyTrends, monthlyTrends, trendDirection, projectedPerformance, seasonalPattern
    }
}

struct WeeklySubjectTrend: Codable, Identifiable {
    var id: UUID
    let weekStart: String // "2024-01-15"
    let weekEnd: String // "2024-01-21"
    let questionCount: Int
    let accuracy: Double
    let studyTimeMinutes: Int
    let improvementScore: Double // -100 to +100

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.weekStart = try container.decode(String.self, forKey: .weekStart)
        self.weekEnd = try container.decode(String.self, forKey: .weekEnd)
        self.questionCount = try container.decode(Int.self, forKey: .questionCount)
        self.accuracy = try container.decode(Double.self, forKey: .accuracy)
        self.studyTimeMinutes = try container.decode(Int.self, forKey: .studyTimeMinutes)
        self.improvementScore = try container.decode(Double.self, forKey: .improvementScore)
    }

    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        weekStart: String,
        weekEnd: String,
        questionCount: Int,
        accuracy: Double,
        studyTimeMinutes: Int,
        improvementScore: Double
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.questionCount = questionCount
        self.accuracy = accuracy
        self.studyTimeMinutes = studyTimeMinutes
        self.improvementScore = improvementScore
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case weekStart, weekEnd, questionCount, accuracy, studyTimeMinutes, improvementScore
    }
}

struct MonthlySubjectTrend: Codable, Identifiable {
    var id: UUID
    let month: String // "2024-01"
    let questionCount: Int
    let accuracy: Double
    let studyTimeHours: Double
    let masteryLevel: Double // 0.0 - 1.0

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.month = try container.decode(String.self, forKey: .month)
        self.questionCount = try container.decode(Int.self, forKey: .questionCount)
        self.accuracy = try container.decode(Double.self, forKey: .accuracy)
        self.studyTimeHours = try container.decode(Double.self, forKey: .studyTimeHours)
        self.masteryLevel = try container.decode(Double.self, forKey: .masteryLevel)
    }

    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        month: String,
        questionCount: Int,
        accuracy: Double,
        studyTimeHours: Double,
        masteryLevel: Double
    ) {
        self.id = id
        self.month = month
        self.questionCount = questionCount
        self.accuracy = accuracy
        self.studyTimeHours = studyTimeHours
        self.masteryLevel = masteryLevel
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case month, questionCount, accuracy, studyTimeHours, masteryLevel
    }
}

enum TrendDirection: String, CaseIterable, Codable {
    case improving = "Improving"
    case declining = "Declining"
    case stable = "Stable"
    case volatile = "Volatile"
    
    var color: Color {
        switch self {
        case .improving: return .green
        case .declining: return .red
        case .stable: return .blue
        case .volatile: return .orange
        }
    }
    
    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .volatile: return "waveform"
        }
    }
}

enum SeasonalPattern: String, CaseIterable, Codable {
    case weekendFocused = "Weekend Focused"
    case weekdayFocused = "Weekday Focused"
    case morningPeak = "Morning Peak"
    case eveningPeak = "Evening Peak"
    case consistent = "Consistent"
    
    var description: String {
        switch self {
        case .weekendFocused: return "You study this subject more on weekends"
        case .weekdayFocused: return "You prefer studying this subject on weekdays"
        case .morningPeak: return "You're most productive with this subject in the morning"
        case .eveningPeak: return "You perform best with this subject in the evening"
        case .consistent: return "You maintain consistent study patterns for this subject"
        }
    }
}

// MARK: - API Response Models

struct SubjectBreakdownResponse: Codable {
    let success: Bool
    let data: SubjectBreakdownData?
    let message: String?
}

struct SubjectBreakdownData: Codable {
    let summary: SubjectBreakdownSummary
    let subjectProgress: [SubjectProgressData]
    let insights: SubjectInsights
    let trends: [SubjectTrendData]
    let lastUpdated: String
    let comparisons: [SubjectComparison]
    let recommendations: [SubjectRecommendation]
}

// MARK: - Helper Extensions

extension Array where Element == SubjectProgressData {
    func sortedByPerformance(ascending: Bool = false) -> [SubjectProgressData] {
        return sorted { lhs, rhs in
            ascending ? lhs.averageAccuracy < rhs.averageAccuracy : lhs.averageAccuracy > rhs.averageAccuracy
        }
    }
    
    func sortedByActivity(ascending: Bool = false) -> [SubjectProgressData] {
        return sorted { lhs, rhs in
            ascending ? lhs.questionsAnswered < rhs.questionsAnswered : lhs.questionsAnswered > rhs.questionsAnswered
        }
    }
    
    func filteredByPerformanceLevel(_ level: PerformanceLevel) -> [SubjectProgressData] {
        return filter { $0.performanceLevel == level }
    }
}

extension SubjectCategory {
    var learningTips: [String] {
        switch self {
        case .mathematics:
            return [
                "Practice problems daily to build muscle memory",
                "Focus on understanding concepts before memorizing formulas",
                "Work through examples step-by-step",
                "Use visual aids and diagrams when possible"
            ]
        case .physics:
            return [
                "Connect mathematical concepts to real-world phenomena",
                "Practice unit conversions regularly",
                "Draw diagrams for every problem",
                "Understand the physics intuition behind equations"
            ]
        case .chemistry:
            return [
                "Master the periodic table relationships",
                "Practice balancing equations daily",
                "Visualize molecular structures",
                "Connect microscopic behavior to macroscopic properties"
            ]
        case .biology:
            return [
                "Use mnemonics for complex processes",
                "Create concept maps to show relationships",
                "Practice identifying structures in diagrams",
                "Connect different biological levels (cell, tissue, organ, system)"
            ]
        case .english:
            return [
                "Read diverse texts to expand vocabulary",
                "Practice writing in different styles",
                "Analyze literary devices in your reading",
                "Discuss ideas with others to deepen understanding"
            ]
        case .history:
            return [
                "Create timelines to visualize chronology",
                "Connect historical events to their consequences",
                "Use primary sources when possible",
                "Consider multiple perspectives on events"
            ]
        case .geography:
            return [
                "Use maps regularly to build spatial awareness",
                "Connect physical and human geography",
                "Study current events in geographical context",
                "Practice identifying locations and patterns"
            ]
        case .computerScience:
            return [
                "Code regularly to build programming skills",
                "Break complex problems into smaller parts",
                "Practice debugging systematically",
                "Learn by building projects, not just reading"
            ]
        case .foreignLanguage:
            return [
                "Practice speaking and listening daily",
                "Immerse yourself in the language through media",
                "Focus on common vocabulary and phrases first",
                "Don't fear making mistakes - they're part of learning"
            ]
        case .arts:
            return [
                "Practice regularly to develop technique",
                "Study works by masters in your field",
                "Experiment with different styles and mediums",
                "Seek feedback from others to improve"
            ]
        case .other:
            return [
                "Set clear learning objectives",
                "Break complex topics into manageable parts",
                "Use multiple learning methods (visual, auditory, kinesthetic)",
                "Regular review and practice are key to retention"
            ]
        }
    }
    
    /// SwiftUI Color based on the string color property
    var swiftUIColor: Color {
        switch self {
        case .mathematics: return .blue
        case .physics: return .purple
        case .chemistry: return .green
        case .biology: return .orange
        case .english: return .pink
        case .history: return .brown
        case .geography: return .teal
        case .computerScience: return .indigo
        case .foreignLanguage: return .cyan
        case .arts: return .red
        case .other: return .gray
        }
    }
}

// MARK: - Subject Comparison Model

struct SubjectComparison: Codable, Identifiable {
    var id: UUID
    let primarySubject: SubjectCategory
    let comparedToSubject: SubjectCategory
    let accuracyDifference: Double
    let studyTimeDifference: Int // in minutes
    let comparisonType: ComparisonType

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.primarySubject = try container.decode(SubjectCategory.self, forKey: .primarySubject)
        self.comparedToSubject = try container.decode(SubjectCategory.self, forKey: .comparedToSubject)
        self.accuracyDifference = try container.decode(Double.self, forKey: .accuracyDifference)
        self.studyTimeDifference = try container.decode(Int.self, forKey: .studyTimeDifference)
        self.comparisonType = try container.decode(ComparisonType.self, forKey: .comparisonType)
    }

    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        primarySubject: SubjectCategory,
        comparedToSubject: SubjectCategory,
        accuracyDifference: Double,
        studyTimeDifference: Int,
        comparisonType: ComparisonType
    ) {
        self.id = id
        self.primarySubject = primarySubject
        self.comparedToSubject = comparedToSubject
        self.accuracyDifference = accuracyDifference
        self.studyTimeDifference = studyTimeDifference
        self.comparisonType = comparisonType
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case primarySubject, comparedToSubject, accuracyDifference, studyTimeDifference, comparisonType
    }
    
    enum ComparisonType: String, Codable, CaseIterable {
        case better = "better"
        case worse = "worse"
        case similar = "similar"
        
        var displayName: String {
            switch self {
            case .better: return "Better"
            case .worse: return "Worse"
            case .similar: return "Similar"
            }
        }
        
        var color: Color {
            switch self {
            case .better: return .green
            case .worse: return .red
            case .similar: return .blue
            }
        }
    }
}

// MARK: - Subject Recommendation Model

struct SubjectRecommendation: Codable, Identifiable {
    var id: UUID
    let targetSubject: SubjectCategory
    let title: String
    let description: String
    let priority: RecommendationPriority
    let estimatedTimeToComplete: Int // in minutes
    let category: RecommendationCategory

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.targetSubject = try container.decode(SubjectCategory.self, forKey: .targetSubject)
        self.title = try container.decode(String.self, forKey: .title)
        self.description = try container.decode(String.self, forKey: .description)
        self.priority = try container.decode(RecommendationPriority.self, forKey: .priority)
        self.estimatedTimeToComplete = try container.decode(Int.self, forKey: .estimatedTimeToComplete)
        self.category = try container.decode(RecommendationCategory.self, forKey: .category)
    }

    // Regular initializer for programmatic creation
    init(
        id: UUID = UUID(),
        targetSubject: SubjectCategory,
        title: String,
        description: String,
        priority: RecommendationPriority,
        estimatedTimeToComplete: Int,
        category: RecommendationCategory
    ) {
        self.id = id
        self.targetSubject = targetSubject
        self.title = title
        self.description = description
        self.priority = priority
        self.estimatedTimeToComplete = estimatedTimeToComplete
        self.category = category
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case targetSubject, title, description, priority, estimatedTimeToComplete, category
    }
    
    enum RecommendationPriority: String, Codable, CaseIterable {
        case high = "high"
        case medium = "medium"
        case low = "low"
        
        var icon: String {
            switch self {
            case .high: return "exclamationmark.circle.fill"
            case .medium: return "info.circle.fill"
            case .low: return "lightbulb.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .high: return .red
            case .medium: return .orange
            case .low: return .blue
            }
        }
    }
    
    enum RecommendationCategory: String, Codable, CaseIterable {
        case studyTime = "study_time"
        case practiceMore = "practice_more"
        case reviewWeak = "review_weak"
        case improveTechnique = "improve_technique"
        case crossSubject = "cross_subject"
        
        var displayName: String {
            switch self {
            case .studyTime: return "Study Time"
            case .practiceMore: return "Practice More"
            case .reviewWeak: return "Review Weak Areas"
            case .improveTechnique: return "Improve Technique"
            case .crossSubject: return "Cross-Subject"
            }
        }
    }
}