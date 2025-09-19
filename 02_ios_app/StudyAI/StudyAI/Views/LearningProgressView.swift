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
    @State private var showingDailyCheckout = false
    @State private var selectedSubject: SubjectCategory?
    @State private var showingSubjectDetail = false
    @State private var selectedTimeframe: TimeframeOption = .currentWeek
    @State private var selectedSubjectFilter: SubjectCategory? = nil
    @State private var showingSubjectFilter = false
    @State private var subjectAnalytics: [String: Any] = [:]
    @State private var loadingTask: Task<Void, Never>? = nil
    
    private let viewId = UUID().uuidString.prefix(8)
    
    // Get actual user ID from authentication service
    private var userId: String {
        if let user = AuthenticationService.shared.currentUser {
            print("🎯 DEBUG: Got authenticated user ID: \(user.id)")
            return user.id
        }
        
        // Fallback: try UserDefaults (legacy support)
        if let userDataString = UserDefaults.standard.string(forKey: "user_data"),
           let userData = userDataString.data(using: .utf8),
           let userDict = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
           let id = userDict["id"] as? String {
            print("🎯 DEBUG: Got user ID from UserDefaults: \(id)")
            return id
        }
        
        print("⚠️ DEBUG: No authenticated user found, falling back to guest_user")
        return "guest_user" // Fallback for non-authenticated users
    }
    
    var body: some View {
        print("🎯 DEBUG: [View \(viewId)] LearningProgressView with SUBJECT BREAKDOWN body building")
        return NavigationView {
            ScrollView {
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
                        Button("Daily Checkout") {
                            showingDailyCheckout = true
                        }
                        
                        Divider()
                        
                        Button("Analytics View") {
                            showingSubjectFilter = true
                        }
                        
                        Divider()
                        
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
                print("🎯 DEBUG: Enhanced LearningProgressView manual refresh triggered")
                // Cancel existing task and create new one
                loadingTask?.cancel()
                loadingTask = Task {
                    await loadProgressDataAsync()
                }
                await loadingTask?.value
            }
            .onAppear {
                print("🎯 DEBUG: [View \(viewId)] Enhanced LearningProgressView onAppear called")
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
                print("🎯 DEBUG: [View \(viewId)] Enhanced LearningProgressView onDisappear called")
                // Cancel loading task when view disappears
                loadingTask?.cancel()
                loadingTask = nil
            }
            .sheet(isPresented: $showingDailyCheckout) {
                DailyCheckoutView()
            }
            .sheet(isPresented: $showingSubjectDetail) {
                if let subject = selectedSubject {
                    SubjectDetailView(subject: subject, timeframe: selectedTimeframe)
                }
            }
            .sheet(isPresented: $showingSubjectFilter) {
                SubjectAnalyticsView(
                    subjectBreakdownData: subjectBreakdownData,
                    selectedTimeframe: selectedTimeframe,
                    onTimeframeChanged: { timeframe in
                        selectedTimeframe = timeframe
                        loadingTask?.cancel()
                        loadingTask = Task {
                            await loadSubjectBreakdown()
                        }
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private var progressContent: some View {
        // Points and Streak Overview
        OverviewMetricsCard()
        
        // Weekly Progress Grid
        WeeklyProgressSection()
        
        // Subject Breakdown Section (Main Feature)
        SubjectBreakdownSection()
        
        // Learning Goals Progress
        LearningGoalsSection()
        
        // Recent Activity Summary
        if let todayProgress = pointsManager.todayProgress {
            TodayActivitySection(todayProgress: todayProgress)
        }
        
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
                    title: "Points",
                    value: "\(pointsManager.currentPoints)",
                    icon: "star.fill",
                    color: .blue
                )
                
                ProgressMetric(
                    title: "Streak",
                    value: "\(pointsManager.currentStreak)",
                    icon: "flame.fill",
                    color: .orange
                )
                
                ProgressMetric(
                    title: "Total Earned",
                    value: "\(pointsManager.totalPointsEarned)",
                    icon: "trophy.fill",
                    color: .green
                )
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Weekly Progress Section
    
    @ViewBuilder
    private func WeeklyProgressSection() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Activity")
                .font(.headline)
                .fontWeight(.bold)
            
            WeeklyProgressGrid()
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
                
                // Subject Performance Grid
                if !filteredData.subjectProgress.isEmpty {
                    SubjectPerformanceSection(
                        subjectProgress: filteredData.subjectProgress,
                        onSubjectTap: { subject in
                            selectedSubject = subject.subject
                            showingSubjectDetail = true
                        }
                    )
                }
                
                // Quick Insights
                if !filteredData.insights.personalizedTips.isEmpty {
                    QuickInsightsSection(insights: filteredData.insights, filter: selectedSubjectFilter)
                }
                
                // Comparative Analytics (when no filter is applied)
                if selectedSubjectFilter == nil && !filteredData.subjectProgress.isEmpty {
                    SubjectComparisonSection(subjectProgress: filteredData.subjectProgress)
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
            
            ForEach(pointsManager.learningGoals) { goal in
                LearningGoalProgressRow(goal: goal)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Today Activity Section
    
    @ViewBuilder
    private func TodayActivitySection(todayProgress: DailyProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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
    
    // MARK: - Subject Breakdown Components
    
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
        isLoading = true
        errorMessage = ""
        
        Task {
            await loadProgressDataAsync()
        }
    }
    
    private func loadProgressDataAsync() async {
        // Check if task was cancelled before starting
        if Task.isCancelled {
            print("🎯 DEBUG: Progress data load cancelled before starting")
            return
        }
        
        print("🎯 DEBUG: Starting loadProgressDataAsync")
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
                print("🎯 DEBUG: loadProgressDataAsync completed successfully")
            }
        } else {
            print("🎯 DEBUG: loadProgressDataAsync was cancelled")
        }
    }
    
    private func loadBasicProgress() async {
        // Simulate basic progress loading
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        await MainActor.run {
            // Basic progress is handled by PointsEarningManager
            print("🎯 DEBUG: Basic progress loaded")
        }
    }
    
    private func loadSubjectBreakdown() async {
        // Check if task was cancelled before starting
        if Task.isCancelled {
            print("🎯 DEBUG: Subject breakdown load cancelled before starting")
            return
        }
        
        // Avoid duplicate requests if already loading subject breakdown specifically
        guard !isLoadingSubjectBreakdown else { 
            print("🎯 DEBUG: Subject breakdown already loading, skipping")
            return 
        }
        
        await MainActor.run {
            isLoadingSubjectBreakdown = true
        }
        
        do {
            print("🔄 DEBUG: Starting subject breakdown load for user: \(userId)")
            let response = try await networkService.fetchSubjectBreakdown(
                userId: userId,
                timeframe: selectedTimeframe.apiValue
            )
            
            // Check if task was cancelled during network call
            if Task.isCancelled {
                print("🎯 DEBUG: Subject breakdown load cancelled during network call")
                await MainActor.run {
                    isLoadingSubjectBreakdown = false
                }
                return
            }
            
            await MainActor.run {
                isLoadingSubjectBreakdown = false
                if response.success, let data = response.data {
                    self.subjectBreakdownData = data
                    print("🎯 DEBUG: Subject breakdown loaded successfully: \(data.subjectProgress.count) subjects")
                } else {
                    print("🎯 DEBUG: Subject breakdown failed: \(response.message ?? "Unknown error")")
                }
            }
        } catch {
            await MainActor.run {
                isLoadingSubjectBreakdown = false
                print("🎯 DEBUG: Subject breakdown error: \(error.localizedDescription)")
                // Only log as error if not cancelled (which is common during view changes)
                if !error.localizedDescription.contains("cancelled") && !Task.isCancelled {
                    errorMessage = "Failed to load subject breakdown: \(error.localizedDescription)"
                } else {
                    print("🎯 DEBUG: Subject breakdown request was cancelled (expected during view changes)")
                }
            }
        }
    }
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
                
                if goal.isCompleted {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("+\(goal.pointsEarned) pts")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                } else {
                    Text("\(goal.currentProgress)/\(goal.targetValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            ProgressView(value: Double(goal.currentProgress), total: Double(goal.targetValue))
                .progressViewStyle(LinearProgressViewStyle(tint: goal.type.color))
        }
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
    case last3Months = "last_3_months"
    
    var displayName: String {
        switch self {
        case .currentWeek: return "This Week"
        case .lastMonth: return "Last Month"
        case .last3Months: return "Last 3 Months"
        }
    }
    
    var apiValue: String {
        return self.rawValue
    }
}

// MARK: - Extensions

extension Color {
    static let gold = Color(red: 1.0, green: 0.84, blue: 0.0)
}

#Preview {
    LearningProgressView()
}