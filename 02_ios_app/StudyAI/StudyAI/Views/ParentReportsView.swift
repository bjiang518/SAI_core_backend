//
//  ParentReportsView.swift
//  StudyAI
//
//  Main view for parent report generation and management
//  Provides date range selection and report display functionality
//

import SwiftUI

struct ParentReportsView: View {
    @StateObject private var reportService = ParentReportService.shared
    @StateObject private var authService = AuthenticationService.shared
    @State private var selectedReport: ParentReport?
    @State private var isGeneratingReport = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    headerSection

                    // Quick Actions
                    quickActionsSection

                    // Recent Reports
                    recentReportsSection
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("parentReport.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selectedReport) { report in
                ReportDetailView(report: report)
                    .onAppear {
                        print("🔍 ReportDetailView sheet appeared with report: \(report.id)")
                    }
            }
            .onAppear {
                loadRecentReports()
            }
            .overlay {
                if reportService.isGeneratingReport {
                    ReportGenerationOverlay(
                        progress: reportService.reportGenerationProgress
                    )
                }
            }
        }
    }

    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("parentReport.studyReports", comment: ""))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(NSLocalizedString("parentReport.trackProgress", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                    .opacity(0.7)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(16)
    }

    // MARK: - Quick Actions Section
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("parentReport.quickActions", comment: ""))
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                Button(action: {
                    generateWeeklyReport()
                }) {
                    ReportActionCard(
                        icon: "calendar.badge.clock",
                        title: NSLocalizedString("parentReport.weeklyReport", comment: ""),
                        subtitle: "",
                        color: .green
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isGeneratingReport)

                Button(action: {
                    generateMonthlyReport()
                }) {
                    ReportActionCard(
                        icon: "calendar",
                        title: NSLocalizedString("parentReport.monthlyReport", comment: ""),
                        subtitle: "",
                        color: .orange
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isGeneratingReport)

                Button(action: {
                    generateProgressReport()
                }) {
                    ReportActionCard(
                        icon: "chart.line.uptrend.xyaxis",
                        title: NSLocalizedString("parentReport.progressReport", comment: ""),
                        subtitle: "",
                        color: .blue
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isGeneratingReport)
            }
        }
    }

    // MARK: - Recent Reports Section
    private var recentReportsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("parentReport.recentReports", comment: ""))
                    .font(.headline)

                Spacer()

                if !reportService.availableReports.isEmpty {
                    Button(NSLocalizedString("parentReport.viewAll", comment: "")) {
                        // Navigate to full reports list
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }

            if reportService.availableReports.isEmpty {
                RecentReportsEmptyState()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(reportService.availableReports.prefix(3)) { report in
                        ReportListCard(report: report) {
                            Task {
                                await loadReportDetail(reportId: report.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions
    private func loadRecentReports() {
        guard let userId = authService.currentUser?.id else { return }

        Task {
            _ = await reportService.fetchStudentReports(
                studentId: userId,
                limit: 5
            )
        }
    }

    private func generateWeeklyReport() {
        generateQuickReport(type: .weekly, daysBack: 7)
    }

    private func generateMonthlyReport() {
        generateQuickReport(type: .monthly, daysBack: 30)
    }

    private func generateProgressReport() {
        generateQuickReport(type: .progress, daysBack: 14)
    }

    private func generateQuickReport(type: ReportType, daysBack: Int) {
        guard let userId = authService.currentUser?.id else { return }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: endDate) ?? endDate

        isGeneratingReport = true

        Task {
            print("🚀 Quick action for \(type.rawValue) report")

            // First, check if we have a recent cached report for this period
            let recentReports = await reportService.fetchStudentReports(studentId: userId, limit: 10, offset: 0)

            var cachedReportId: String? = nil

            switch recentReports {
            case .success(let reportsResponse):
                // Look for a report that matches the requested type and is still valid
                let cachedReportItem = reportsResponse.reports.first { report in
                    let isSameType = report.reportType == type
                    let isNotExpired = !report.isExpired

                    // For weekly/monthly reports, check if it covers a similar recent period
                    if type == .weekly || type == .monthly {
                        let daysDifference = abs(Calendar.current.dateComponents([.day], from: report.startDate, to: startDate).day ?? 999)
                        let isRecentPeriod = daysDifference <= (type == .weekly ? 3 : 15) // Allow some flexibility
                        return isSameType && isNotExpired && isRecentPeriod
                    } else {
                        // For custom/progress reports, use exact date matching
                        let sameStartDate = Calendar.current.isDate(report.startDate, inSameDayAs: startDate)
                        let sameEndDate = Calendar.current.isDate(report.endDate, inSameDayAs: endDate)
                        return isSameType && isNotExpired && sameStartDate && sameEndDate
                    }
                }

                if let cached = cachedReportItem {
                    cachedReportId = cached.id
                    print("✅ Found cached \(type.rawValue) report: \(cached.id)")
                    print("📅 Cached report period: \(cached.startDate) - \(cached.endDate)")
                }

            case .failure(let error):
                print("⚠️ Failed to check for cached reports: \(error.localizedDescription)")
            }

            await MainActor.run {
                isGeneratingReport = false

                if let reportId = cachedReportId {
                    // Fetch the cached report directly
                    print("🎯 Using cached report instead of generating new one")
                    loadCachedReport(reportId: reportId)
                } else {
                    // No suitable cached report found, proceed with generation
                    print("🔄 No suitable cached report found, generating new report")
                    generateNewReport(type: type, startDate: startDate, endDate: endDate, userId: userId)
                }
            }
        }
    }

    private func loadCachedReport(reportId: String) {
        isGeneratingReport = true

        Task {
            let result = await reportService.fetchReport(reportId: reportId)

            await MainActor.run {
                isGeneratingReport = false

                switch result {
                case .success(let report):
                    selectedReport = report
                    // No need to set showingReportDetail - sheet(item:) handles this automatically
                case .failure(let error):
                    print("Failed to load cached report: \(error.localizedDescription)")
                    // Handle error - could show alert or fallback to generation
                }
            }
        }
    }

    private func generateNewReport(type: ReportType, startDate: Date, endDate: Date, userId: String) {
        isGeneratingReport = true

        Task {
            let result = await reportService.generateReport(
                studentId: userId,
                startDate: startDate,
                endDate: endDate,
                reportType: type,
                includeAIAnalysis: true,
                compareWithPrevious: true
            )

            await MainActor.run {
                isGeneratingReport = false

                switch result {
                case .success(let report):
                    selectedReport = report
                    // No need to set showingReportDetail - sheet(item:) handles this automatically
                case .failure(let error):
                    print("Report generation failed: \(error.localizedDescription)")
                    // Handle error - could show alert
                }
            }
        }
    }

    private func loadReportDetail(reportId: String) async {
        let result = await reportService.fetchReport(reportId: reportId)

        await MainActor.run {
            switch result {
            case .success(let report):
                print("🔍 Setting selectedReport which will trigger sheet presentation")
                selectedReport = report
                // No need to set showingReportDetail - sheet(item:) handles this automatically
            case .failure(let error):
                print("Failed to load report: \(error.localizedDescription)")
                // Handle error
            }
        }
    }
}

// MARK: - Supporting Views

struct ReportActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ReportListCard: View {
    let report: ReportListItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: report.reportType.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(report.reportType.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(formatDateRange(start: report.startDate, end: report.endDate))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        if report.aiAnalysisIncluded {
                            Label(NSLocalizedString("parentReport.aiAnalysis", comment: ""), systemImage: "brain.head.profile")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }

                        Spacer()

                        Text(RelativeDateTimeFormatter().localizedString(for: report.generatedAt, relativeTo: Date()))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDateRange(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

struct RecentReportsEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(NSLocalizedString("parentReport.noReportsYet", comment: ""))
                    .font(.headline)
                    .fontWeight(.medium)

                Text(NSLocalizedString("parentReport.generateFirstReport", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

struct ReportGenerationOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)

                Text(NSLocalizedString("parentReport.generatingReport", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)

                ProgressView(value: progress)
                    .frame(width: 200)
                    .tint(.white)

                Text(String(format: NSLocalizedString("parentReport.percentComplete", comment: ""), Int(progress * 100)))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(30)
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
        }
    }
}

#Preview {
    ParentReportsView()
}