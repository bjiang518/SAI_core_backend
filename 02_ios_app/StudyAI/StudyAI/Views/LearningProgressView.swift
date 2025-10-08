//
//  LearningProgressView.swift
//  StudyAI
//
//  Enhanced progress view with integrated subject breakdown
//

import SwiftUI
import Charts

struct LearningProgressView: View {
    @StateObject private var networkService = NetworkService.shared
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var progressData: [String: Any] = [:]
    @State private var subjectBreakdownData: SubjectBreakdownData?
    @State private var isLoading = true
    @State private var isLoadingSubjectBreakdown = false
    @State private var errorMessage = ""
    @State private var selectedSubject: SubjectCategory?
    @State private var showingSubjectDetail = false
    @State private var selectedTimeframe: TimeframeOption = .currentWeek
    @State private var selectedSubjectFilter: SubjectCategory? = nil
    @State private var loadingTask: Task<Void, Never>? = nil
    
    private let viewId = UUID().uuidString.prefix(8)
    
    // Get actual user ID from authentication service
    private var userId: String {




        if let user = AuthenticationService.shared.currentUser {



            return user.id
        }

        // Fallback: try UserDefaults (legacy support)
        if let userDataString = UserDefaults.standard.string(forKey: "user_data"),
           let userData = userDataString.data(using: .utf8),
           let userDict = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
           let id = userDict["id"] as? String {

            return id
        }

        // Check if we have stored auth token but no current user
        if let token = AuthenticationService.shared.getAuthToken() {
            print("⚠️ DEBUG: Auth token exists but no currentUser! Token: \(String(token.prefix(20)))...")
            print("⚠️ DEBUG: This suggests authentication state is inconsistent")

            // Try to fix the user UID issue
            Task {
                do {
                    try await AuthenticationService.shared.fixExistingUserUID()

                } catch {

                }
            }
        }

        print("⚠️ DEBUG: No authenticated user found, falling back to guest_user")

        return "guest_user" // Fallback for non-authenticated users
    }
    
    var body: some View {

        return ScrollView {
            LazyVStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading your progress...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                } else if !errorMessage.isEmpty {
                    ErrorStateView(message: errorMessage) {
                        loadProgressData()
                    }
                } else {
                    progressContent
                }
            }
            .padding()
        }
        .navigationTitle("📊 Progress")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Button(selectedSubjectFilter?.displayName ?? "All Subjects") {}
                        .disabled(true)

                    Divider()

                    Button("All Subjects") {
                        selectedSubjectFilter = nil
                        loadingTask?.cancel()
                        loadingTask = Task {
                            await loadSubjectBreakdown()
                        }
                    }

                    ForEach(SubjectCategory.allCases, id: \.self) { subject in
                        Button(action: {
                            selectedSubjectFilter = subject
                            loadingTask?.cancel()
                            loadingTask = Task {
                                await loadSubjectBreakdown()
                            }
                        }) {
                            HStack {
                                Image(systemName: subject.icon)
                                Text(subject.displayName)
                                if selectedSubjectFilter == subject {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        if let filter = selectedSubjectFilter {
                            Text(filter.displayName)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.blue)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(TimeframeOption.allCases, id: \.self) { option in
                        Button(action: {
                            selectedTimeframe = option
                            loadingTask?.cancel()
                            loadingTask = Task {
                                await loadSubjectBreakdown()
                            }
                        }) {
                            HStack {
                                Text(option.displayName)
                                if selectedTimeframe == option {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.blue)
                }
            }
        }
        .refreshable {

            // Cancel existing task and create new one
            loadingTask?.cancel()
            loadingTask = Task {
                await loadProgressDataAsync()
            }
            await loadingTask?.value
        }
        .onAppear {

            // Cancel any existing loading task
            loadingTask?.cancel()

            // Only load if we don't have data or it's stale
            if subjectBreakdownData == nil || errorMessage.isEmpty {
                loadingTask = Task {
                    await loadProgressDataAsync()
                }
            }
        }
        .onDisappear {

            // Cancel loading task when view disappears
            loadingTask?.cancel()
            loadingTask = nil
        }
        .sheet(isPresented: $showingSubjectDetail) {
            if let subject = selectedSubject {
                SubjectDetailView(subject: subject, timeframe: selectedTimeframe)
            }
        }
    }
    
    @ViewBuilder
    private var progressContent: some View {
        // Points and Streak Overview
        OverviewMetricsCard()

        // Today's Activity Section (moved to top)
        if let todayProgress = pointsManager.todayProgress {


            TodayActivitySection(todayProgress: todayProgress)
        } else {

        }

        // Weekly Progress Grid
        WeeklyProgressSection()

        // Subject Breakdown Section (Main Feature)
        SubjectBreakdownSection()

        // Learning Goals Progress
        LearningGoalsSection()

        // Recent Checkouts
        if !pointsManager.dailyCheckoutHistory.isEmpty {
            RecentCheckoutsSection()
        }
    }
    
    // MARK: - Overview Metrics Card
    
    @ViewBuilder
    private func OverviewMetricsCard() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Learning Journey")
                .font(.headline)
                .fontWeight(.bold)

            HStack(spacing: 20) {
                ProgressMetric(
                    title: "Points Today",
                    value: "\(calculateTodayPoints())",
                    icon: "star.fill",
                    color: .blue
                )

                ProgressMetric(
                    title: "Streak",
                    value: "\(pointsManager.currentStreak) days",
                    icon: "flame.fill",
                    color: .orange
                )

                ProgressMetric(
                    title: "Total Points",
                    value: "\(pointsManager.totalPointsEarned)",
                    icon: "star.circle.fill",
                    color: .green
                )
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Activity Progress Section (Weekly or Monthly)

    @ViewBuilder
    private func WeeklyProgressSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(selectedTimeframe == .currentWeek ? "Weekly Activity" : "Monthly Activity")
                .font(.headline)
                .fontWeight(.bold)

            if selectedTimeframe == .currentWeek {
                // Show weekly grid for current week
                WeeklyProgressGrid()
                    .onAppear {
                        // Force weekly progress initialization if needed
                        if pointsManager.currentWeeklyProgress == nil {
                            pointsManager.checkWeeklyReset()
                        }
                    }
            } else if selectedTimeframe == .lastMonth {
                // Show monthly calendar for last month
                MonthlyProgressGrid()
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Subject Breakdown Section (Main Feature)

    @ViewBuilder
    private func SubjectBreakdownSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📚 Subject Breakdown")
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                HStack(spacing: 4) {
                    if let filter = selectedSubjectFilter {
                        HStack(spacing: 4) {
                            Image(systemName: filter.icon)
                                .font(.caption)
                                .foregroundColor(filter.swiftUIColor)
                            Text(filter.displayName)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    } else {
                        Button(selectedTimeframe.displayName) {
                            // Timeframe selector could be expanded here
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }

            if let data = subjectBreakdownData {
                let filteredData = applySubjectFilter(data)

                // Overall Summary
                if filteredData.summary.totalSubjectsStudied > 0 {
                    SubjectSummaryCard(summary: filteredData.summary, filter: selectedSubjectFilter)
                }

                // Enhanced Visualizations with Charts
                if !filteredData.subjectProgress.isEmpty && selectedSubjectFilter == nil {
                    VStack(spacing: 16) {
                        // Horizontal bar chart for accuracy comparison only
                        SubjectAccuracyBarChart(subjectProgress: filteredData.subjectProgress)
                    }
                }

            } else {
                // Empty state for subject breakdown
                if selectedSubjectFilter != nil {
                    FilteredSubjectEmptyState(subject: selectedSubjectFilter!)
                } else {
                    SubjectBreakdownEmptyState()
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Learning Goals Section

    @ViewBuilder
    private func LearningGoalsSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learning Goals")
                .font(.headline)
                .fontWeight(.bold)

            // Filter out weekly streak goals to avoid duplication with WeeklyProgressGrid
            let filteredGoals = pointsManager.learningGoals.filter { $0.type != .weeklyStreak }

            if filteredGoals.isEmpty {
                Text("No active learning goals")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(filteredGoals) { goal in
                    LearningGoalProgressRow(goal: goal)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Today Activity Section
    
    private func TodayActivitySection(todayProgress: DailyProgress) -> some View {







        return VStack(alignment: .leading, spacing: 16) {
            Text("Today's Activity")
                .font(.headline)
                .fontWeight(.bold)

            HStack(spacing: 20) {
                ProgressMetric(
                    title: "Questions",
                    value: "\(todayProgress.totalQuestions)",
                    icon: "questionmark.circle.fill",
                    color: .blue
                )

                ProgressMetric(
                    title: "Correct",
                    value: "\(todayProgress.correctAnswers)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )

                ProgressMetric(
                    title: "Accuracy",
                    value: "\(Int(todayProgress.accuracy))%",
                    icon: "target",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Recent Checkouts Section
    
    @ViewBuilder
    private func RecentCheckoutsSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Checkouts")
                .font(.headline)
                .fontWeight(.bold)
            
            ForEach(pointsManager.dailyCheckoutHistory.suffix(5).reversed(), id: \.id) { checkout in
                CheckoutHistoryRow(checkout: checkout)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods

    private func calculateTodayPoints() -> Int {
        // Calculate points based on today's progress and checked out daily goals
        guard let todayProgress = pointsManager.todayProgress else { return 0 }

        var points = 0

        // Add points for questions answered (basic calculation)
        points += todayProgress.correctAnswers * 10 // 10 points per correct answer
        points += (todayProgress.totalQuestions - todayProgress.correctAnswers) * 5 // 5 points per wrong answer

        // Add points from checked out daily goals (this is what the user requested)
        let checkedOutDailyGoals = pointsManager.learningGoals.filter { $0.isDaily && $0.isCheckedOut }
        for goal in checkedOutDailyGoals {
            points += pointsManager.calculateAvailablePoints(for: goal)
        }

        // Apply daily maximum of 100 points as requested by user
        return min(points, 100)
    }

    // Helper method to apply subject filtering
    private func applySubjectFilter(_ data: SubjectBreakdownData) -> SubjectBreakdownData {
        guard let filter = selectedSubjectFilter else { return data }
        
        // Filter subject progress to only include the selected subject
        let filteredProgress = data.subjectProgress.filter { $0.subject == filter }
        
        // Update summary based on filtered data
        let filteredSummary = SubjectBreakdownSummary(
            totalSubjectsStudied: filteredProgress.isEmpty ? 0 : 1,
            mostStudiedSubject: filteredProgress.first?.subject,
            leastStudiedSubject: filteredProgress.first?.subject,
            highestPerformingSubject: filteredProgress.first?.subject,
            lowestPerformingSubject: filteredProgress.first?.subject,
            totalQuestionsAcrossSubjects: filteredProgress.first?.questionsAnswered ?? 0,
            overallAccuracy: filteredProgress.first?.averageAccuracy ?? 0.0,
            subjectDistribution: filteredProgress.isEmpty ? [:] : [filter: filteredProgress.first!.questionsAnswered],
            subjectPerformance: filteredProgress.isEmpty ? [:] : [filter: filteredProgress.first!.averageAccuracy],
            studyTimeDistribution: filteredProgress.isEmpty ? [:] : [filter: filteredProgress.first!.totalStudyTimeMinutes],
            lastUpdated: Date(),
            totalQuestionsAnswered: filteredProgress.first?.questionsAnswered ?? 0,
            totalStudyTime: filteredProgress.first?.totalStudyTime ?? 0,
            improvementRate: data.summary.improvementRate
        )
        
        // Filter insights to be relevant to the selected subject
        let filteredInsights = SubjectInsights(
            subjectToFocus: data.insights.subjectToFocus.filter { $0 == filter },
            subjectsToMaintain: data.insights.subjectsToMaintain.filter { $0 == filter },
            studyTimeRecommendations: data.insights.studyTimeRecommendations.filter { $0.key == filter },
            crossSubjectConnections: data.insights.crossSubjectConnections.filter { $0.primarySubject == filter || $0.relatedSubject == filter },
            achievementOpportunities: data.insights.achievementOpportunities.filter { $0.subject == filter },
            personalizedTips: data.insights.personalizedTips,
            optimalStudySchedule: data.insights.optimalStudySchedule
        )
        
        return SubjectBreakdownData(
            summary: filteredSummary,
            subjectProgress: filteredProgress,
            insights: filteredInsights,
            trends: data.trends.filter { $0.subject == filter },
            lastUpdated: data.lastUpdated,
            comparisons: [], // No comparisons when filtering
            recommendations: data.recommendations.filter { $0.targetSubject == filter }
        )
    }
    
    @ViewBuilder
    private func SubjectSummaryCard(summary: SubjectBreakdownSummary, filter: SubjectCategory?) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(summary.totalSubjectsStudied)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("Subjects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int(summary.overallAccuracy))%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text("Accuracy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let mostStudied = summary.mostStudiedSubject,
               let topPerforming = summary.highestPerformingSubject {
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Most Studied: \(mostStudied.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.gold)
                            .font(.caption)
                        Text("Top Performing: \(topPerforming.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func SubjectPerformanceSection(
        subjectProgress: [SubjectProgressData],
        onSubjectTap: @escaping (SubjectProgressData) -> Void
    ) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(subjectProgress.sorted(by: { $0.averageAccuracy > $1.averageAccuracy }).prefix(6)) { progress in
                CompactSubjectCard(progress: progress) {
                    onSubjectTap(progress)
                }
            }
        }
        
        if subjectProgress.count > 6 {
            Button("View All Subjects") {
                // Could navigate to full subject breakdown view
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.top, 8)
        }
    }
    
    @ViewBuilder
    private func CompactSubjectCard(progress: SubjectProgressData, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: progress.subject.icon)
                        .font(.title3)
                        .foregroundColor(progress.subject.swiftUIColor)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(progress.averageAccuracy))%")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(progress.performanceLevel.color)
                        
                        Image(systemName: progress.performanceLevel.icon)
                            .font(.caption2)
                            .foregroundColor(progress.performanceLevel.color)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.subject.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    
                    Text("\(progress.questionsAnswered) questions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(progress.performanceLevel.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private func QuickInsightsSection(insights: SubjectInsights, filter: SubjectCategory?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
                Text(filter != nil ? "Insights for \(filter!.displayName)" : "Quick Insights")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            if !insights.subjectToFocus.isEmpty {
                InsightRow(
                    icon: "exclamationmark.triangle.fill",
                    color: .orange,
                    text: "Focus on: \(insights.subjectToFocus.map { $0.displayName }.joined(separator: ", "))"
                )
            }
            
            if !insights.subjectsToMaintain.isEmpty {
                InsightRow(
                    icon: "checkmark.circle.fill",
                    color: .green,
                    text: "Keep up: \(insights.subjectsToMaintain.map { $0.displayName }.joined(separator: ", "))"
                )
            }
            
            if let tip = insights.personalizedTips.first {
                InsightRow(
                    icon: "quote.bubble.fill",
                    color: .blue,
                    text: tip
                )
            }
            
            // Add study time recommendations for filtered subject
            if let filter = filter,
               let recommendedTime = insights.studyTimeRecommendations[filter] {
                InsightRow(
                    icon: "clock.fill",
                    color: .purple,
                    text: "Recommended study time: \(recommendedTime) minutes per day"
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func InsightRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
                .frame(width: 16)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }
    
    @ViewBuilder
    private func FilteredSubjectEmptyState(subject: SubjectCategory) -> some View {
        VStack(spacing: 12) {
            Image(systemName: subject.icon)
                .font(.title2)
                .foregroundColor(subject.swiftUIColor)
            
            Text("No \(subject.displayName) Data Yet")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("Ask questions about \(subject.displayName) to see your progress here!")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func SubjectComparisonSection(subjectProgress: [SubjectProgressData]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("Subject Comparison")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            
            let topSubjects = subjectProgress.sorted { $0.averageAccuracy > $1.averageAccuracy }.prefix(3)
            let strugglingSubjects = subjectProgress.sorted { $0.averageAccuracy < $1.averageAccuracy }.prefix(2)
            
            VStack(alignment: .leading, spacing: 8) {
                if !topSubjects.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "trophy.fill")
                                .foregroundColor(.gold)
                                .font(.caption2)
                            Text("Top Performing")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach(Array(topSubjects), id: \.id) { subject in
                                SubjectPerformanceChip(
                                    subject: subject,
                                    showAccuracy: true
                                )
                            }
                        }
                    }
                }
                
                if !strugglingSubjects.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("Needs Attention")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        
                        HStack(spacing: 8) {
                            ForEach(Array(strugglingSubjects), id: \.id) { subject in
                                SubjectPerformanceChip(
                                    subject: subject,
                                    showAccuracy: true
                                )
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    @ViewBuilder
    private func SubjectPerformanceChip(subject: SubjectProgressData, showAccuracy: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: subject.subject.icon)
                .font(.caption2)
                .foregroundColor(subject.subject.swiftUIColor)
            
            Text(subject.subject.displayName)
                .font(.caption2)
                .fontWeight(.medium)
            
            if showAccuracy {
                Text("(\(Int(subject.averageAccuracy))%)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(subject.subject.swiftUIColor.opacity(0.1))
        .cornerRadius(4)
    }
    
    @ViewBuilder
    private func SubjectBreakdownEmptyState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No Subject Data Yet")
                .font(.subheadline)
                .fontWeight(.medium)
            
            Text("Answer questions across different subjects to see your breakdown!")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
    
    // MARK: - Data Loading
    
    private func loadProgressData() {
        print("🔄 ========================================")
        print("🔄 === LEARNING PROGRESS VIEW: LOAD START ===")
        print("🔄 === User ID: \(userId) ===")
        print("🔄 ========================================")
        isLoading = true
        errorMessage = ""

        Task {
            await loadProgressDataAsync()
        }
    }

    private func loadProgressDataAsync() async {
        print("📡 LearningProgressView: loadProgressDataAsync() started")
        // Check if task was cancelled before starting
        if Task.isCancelled {
            print("⚠️ LearningProgressView: Task cancelled before starting")
            return
        }


        await MainActor.run {
            isLoading = true
        }
        
        async let basicProgress = loadBasicProgress()
        async let subjectData = loadSubjectBreakdown()
        
        // Wait for both to complete (or be cancelled)
        let _ = await (basicProgress, subjectData)
        
        if !Task.isCancelled {
            await MainActor.run {
                isLoading = false

            }
        } else {

        }
    }
    
    private func loadBasicProgress() async {
        // Simulate basic progress loading
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await MainActor.run {
            // Basic progress is handled by PointsEarningManager

        }
    }
    
    private func loadSubjectBreakdown() async {
        print("📡 ========================================")
        print("📡 === LOAD SUBJECT BREAKDOWN START ===")
        print("📡 === LearningProgressView.loadSubjectBreakdown() ===")
        print("📡 ========================================")

        // Check if task was cancelled before starting
        if Task.isCancelled {
            print("⚠️ LearningProgressView: Task cancelled before loadSubjectBreakdown")
            return
        }

        // Avoid duplicate requests if already loading subject breakdown specifically
        guard !isLoadingSubjectBreakdown else {
            print("⚠️ LearningProgressView: Already loading subject breakdown, skipping duplicate request")
            return
        }

        await MainActor.run {
            isLoadingSubjectBreakdown = true
        }

        print("📡 Calling fetchSubjectBreakdown with:")
        print("📡   userId: \(userId)")
        print("📡   timeframe: \(selectedTimeframe.apiValue)")

        do {
            let response = try await networkService.fetchSubjectBreakdown(
                userId: userId,
                timeframe: selectedTimeframe.apiValue
            )

            print("📥 ========================================")
            print("📥 === RECEIVED SUBJECT BREAKDOWN RESPONSE ===")
            print("📥 Response success: \(response.success)")
            print("📥 Response message: \(response.message ?? "nil")")
            print("📥 Response data exists: \(response.data != nil)")

            if let data = response.data {
                print("📊 Subject breakdown data structure:")
                print("📊   - Subject count: \(data.subjectProgress.count)")
                print("📊   - Total subjects studied: \(data.summary.totalSubjectsStudied)")
                print("📊   - Total questions: \(data.summary.totalQuestionsAnswered)")
                print("📊   - Overall accuracy: \(data.summary.overallAccuracy)")
                print("📊   - Last updated: \(data.lastUpdated)")
            } else {
                print("❌ Response data is nil")
            }
            print("📥 ========================================")

            // Check if task was cancelled during network call
            if Task.isCancelled {
                print("⚠️ LearningProgressView: Task cancelled after network call")
                await MainActor.run {
                    isLoadingSubjectBreakdown = false
                }
                return
            }

            await MainActor.run {
                isLoadingSubjectBreakdown = false
                if response.success, let data = response.data {
                    print("✅ SUCCESS: Setting subjectBreakdownData")
                    self.subjectBreakdownData = data
                    print("✅ subjectBreakdownData now set with \(data.subjectProgress.count) subjects")
                } else {
                    print("❌ FAILURE: Cannot set subjectBreakdownData")
                    print("❌ Success: \(response.success)")
                    print("❌ Data exists: \(response.data != nil)")

                    if !Task.isCancelled {
                        let errorMsg = response.message ?? "Failed to load subject breakdown"
                        print("❌ Setting errorMessage: \(errorMsg)")
                        errorMessage = errorMsg
                    }
                }
            }
        } catch {
            print("❌ ========================================")
            print("❌ === EXCEPTION IN LOAD SUBJECT BREAKDOWN ===")
            print("❌ Error: \(error)")
            print("❌ Error description: \(error.localizedDescription)")
            print("❌ Is cancellation error: \(error.localizedDescription.contains("cancelled"))")
            print("❌ ========================================")

            await MainActor.run {
                isLoadingSubjectBreakdown = false

                // Only log as error if not cancelled (which is common during view changes)
                if !error.localizedDescription.contains("cancelled") && !Task.isCancelled {
                    let errorMsg = "Failed to load subject breakdown: \(error.localizedDescription)"
                    print("❌ Setting errorMessage: \(errorMsg)")
                    errorMessage = errorMsg
                } else {
                    print("⚠️ Cancelled error - not setting errorMessage")
                }
            }
        }
    }
}

// MARK: - Enhanced Chart Components for Progress View

struct SubjectAccuracyBarChart: View {
    let subjectProgress: [SubjectProgressData]

    private var chartData: [SubjectAccuracyChartData] {
        let data = subjectProgress.map { progress in
            SubjectAccuracyChartData(
                subject: progress.subject.displayName,
                accuracy: progress.averageAccuracy,
                color: getAccuracyColor(progress.averageAccuracy)
            )
        }.sorted { $0.accuracy > $1.accuracy }

        return data
    }

    private var averageAccuracy: Double {
        guard !subjectProgress.isEmpty else { return 0 }
        let total = subjectProgress.reduce(0) { $0 + $1.averageAccuracy }
        return total / Double(subjectProgress.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subject Accuracy Comparison")
                .font(.headline)
                .fontWeight(.bold)

            if !chartData.isEmpty {
                VStack(spacing: 12) {
                    // Average line indicator
                    HStack {
                        Rectangle()
                            .fill(Color.gray)
                            .frame(width: 20, height: 2)
                        Text("Average: \(String(format: "%.1f", averageAccuracy))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    // Horizontal Bar Chart
                    Chart(chartData, id: \.subject) { data in
                        BarMark(
                            x: .value("Accuracy", data.accuracy),
                            y: .value("Subject", data.subject),
                            height: .fixed(20)
                        )
                        .foregroundStyle(data.color.gradient)
                        .cornerRadius(4)

                        // Average reference line
                        RuleMark(x: .value("Average", averageAccuracy))
                            .foregroundStyle(Color.gray)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }
                    .frame(height: max(120, CGFloat(chartData.count * 35)))
                    .chartXScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let intValue = value.as(Int.self) {
                                    Text("\(intValue)%")
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let stringValue = value.as(String.self) {
                                    Text(stringValue)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("No accuracy data available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func getAccuracyColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case 90...: return .green
        case 80..<90: return .blue
        case 70..<80: return .yellow
        case 60..<70: return .orange
        default: return .red
        }
    }
}

// MARK: - Chart Data Models

struct SubjectAccuracyChartData {
    let subject: String
    let accuracy: Double
    let color: Color
}

// MARK: - Supporting Views

struct ProgressMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LearningGoalProgressRow: View {
    let goal: LearningGoal
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: goal.type.icon)
                    .foregroundColor(goal.type.color)
                    .frame(width: 24)

                Text(goal.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                // Progress info and checkout button
                HStack(spacing: 8) {
                    if goal.isCompleted && !goal.isCheckedOut {
                        // Show available points for checkout
                        let availablePoints = pointsManager.calculateAvailablePoints(for: goal)
                        if availablePoints > 0 {
                            Text("+\(availablePoints) pts")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    } else if goal.isCheckedOut {
                        // Show checked out status
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Checked out")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        // Show progress
                        Text("\(goal.currentProgress)/\(goal.targetValue)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Checkout button
                    CheckoutButton(
                        goal: goal,
                        isActive: goal.isCompleted && !goal.isCheckedOut,
                        onCheckout: {
                            performCheckout()
                        }
                    )
                }
            }

            // Animated progress bar
            ProgressView(value: Double(goal.currentProgress), total: Double(goal.targetValue))
                .progressViewStyle(LinearProgressViewStyle(tint: goal.type.color))
                .scaleEffect(x: isAnimating ? 1.05 : 1.0, y: 1.0, anchor: .leading)
                .animation(.easeInOut(duration: 0.3), value: isAnimating)
        }
    }

    private func performCheckout() {
        let pointsEarned = pointsManager.checkoutGoal(goal.id)

        // Trigger checkout animation
        withAnimation(.easeInOut(duration: 0.3)) {
            isAnimating = true
        }

        // Reset animation after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isAnimating = false
            }
        }


    }
}

struct CheckoutButton: View {
    let goal: LearningGoal
    let isActive: Bool
    let onCheckout: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            if isActive {
                // Button press animation
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = true
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                    onCheckout()
                }
            }
        }) {
            ZStack {
                // Button background
                Circle()
                    .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPressed ? 0.9 : 1.0)

                // Checkmark icon
                Image(systemName: goal.isCheckedOut ? "checkmark.circle.fill" : "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(goal.isCheckedOut ? .green : (isActive ? .white : .gray))
                    .scaleEffect(isPressed ? 0.8 : 1.0)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isActive)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
    }
}

struct CheckoutHistoryRow: View {
    let checkout: DailyCheckout
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(checkout.displayDate)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(checkout.goalsCompleted) goals completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(checkout.finalPoints) pts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                
                if checkout.isWeekend {
                    Text("Weekend 2x")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Unable to Load Data")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Supporting Types

enum TimeframeOption: String, CaseIterable {
    case currentWeek = "current_week"
    case lastMonth = "last_month"

    var displayName: String {
        switch self {
        case .currentWeek: return "This Week"
        case .lastMonth: return "Last Month"
        }
    }

    var apiValue: String {
        return self.rawValue
    }
}

// MARK: - Monthly Progress Grid Component

struct MonthlyProgressGrid: View {
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var monthlyActivities: [DailyActivity] = []
    @State private var isLoading = false

    private let calendar = Calendar.current
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            monthHeader
            monthlyCalendarGrid
            activityLegend
        }
        .onAppear {
            loadMonthlyData()
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Text(monthTitle)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text("\(totalQuestionsThisMonth)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
    }

    // MARK: - Monthly Calendar Grid

    private var monthlyCalendarGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return VStack(spacing: 8) {
            // Weekday headers
            HStack {
                ForEach(weekdayHeaders, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(calendarDays, id: \.id) { day in
                    DayActivityCell(
                        day: day,
                        isCurrentMonth: day.isCurrentMonth,
                        activity: getActivityForDay(day.date)
                    )
                }
            }
        }
    }

    // MARK: - Activity Legend

    private var activityLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Level")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text("Less")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack(spacing: 3) {
                    ForEach(ActivityIntensity.allCases, id: \.rawValue) { intensity in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(intensity.color)
                            .frame(width: 12, height: 12)
                    }
                }

                Text("More")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("questions this month")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var monthTitle: String {
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: lastMonth)
    }

    private var weekdayHeaders: [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.shortWeekdaySymbols.map { $0.prefix(1).uppercased() }
    }

    private var calendarDays: [CalendarDay] {
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()

        guard let monthInterval = calendar.dateInterval(of: .month, for: lastMonth),
              let firstOfMonth = calendar.dateInterval(of: .month, for: lastMonth)?.start else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let daysInMonth = calendar.range(of: .day, in: .month, for: lastMonth)?.count ?? 30

        var days: [CalendarDay] = []

        // Add empty cells for days before the first day of the month
        for _ in 1..<firstWeekday {
            days.append(CalendarDay(date: Date.distantPast, dayNumber: 0, isCurrentMonth: false))
        }

        // Add all days of the month
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(CalendarDay(date: date, dayNumber: day, isCurrentMonth: true))
            }
        }

        // Fill remaining cells to complete the grid (42 cells = 6 weeks × 7 days)
        while days.count < 42 {
            days.append(CalendarDay(date: Date.distantFuture, dayNumber: 0, isCurrentMonth: false))
        }

        return days
    }

    private var totalQuestionsThisMonth: Int {
        return monthlyActivities.reduce(0) { $0 + $1.questionCount }
    }

    // MARK: - Helper Methods

    private func loadMonthlyData() {
        // For now, use mock data. In production, this would fetch from server
        // or calculate from stored weekly progress data
        monthlyActivities = generateMockMonthlyData()
    }

    private func getActivityForDay(_ date: Date) -> DailyActivity? {
        let dateString = dateFormatter.string(from: date)
        return monthlyActivities.first { $0.date == dateString }
    }

    private func generateMockMonthlyData() -> [DailyActivity] {
        var activities: [DailyActivity] = []
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()

        guard let monthInterval = calendar.dateInterval(of: .month, for: lastMonth) else {
            return activities
        }

        var currentDate = monthInterval.start
        while currentDate < monthInterval.end {
            let questionCount = Int.random(in: 0...25) // Random activity for demo
            if questionCount > 0 {
                activities.append(DailyActivity(
                    date: dateFormatter.string(from: currentDate),
                    questionCount: questionCount
                ))
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return activities
    }
}

// MARK: - Monthly Calendar Supporting Types

struct CalendarDay {
    let id = UUID()
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool
}

struct DailyActivity {
    let date: String // yyyy-MM-dd format
    let questionCount: Int

    var intensityLevel: ActivityIntensity {
        switch questionCount {
        case 0: return .none
        case 1...5: return .light
        case 6...15: return .medium
        case 16...: return .high
        default: return .none
        }
    }
}

struct DayActivityCell: View {
    let day: CalendarDay
    let isCurrentMonth: Bool
    let activity: DailyActivity?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(activity?.intensityLevel.color ?? ActivityIntensity.none.color)
                .frame(width: 32, height: 32)

            if isCurrentMonth && day.dayNumber > 0 {
                Text("\(day.dayNumber)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(shouldUseWhiteText ? .white : .black)
            }
        }
        .opacity(isCurrentMonth ? 1.0 : 0.3)
    }

    private var shouldUseWhiteText: Bool {
        guard let activity = activity else { return false }
        switch activity.intensityLevel {
        case .medium, .high:
            return true
        case .none, .light:
            return false
        }
    }
}

// MARK: - Extensions

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}

#Preview {
    LearningProgressView()
}