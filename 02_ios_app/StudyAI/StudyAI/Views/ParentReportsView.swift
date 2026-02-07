//
//  ParentReportsView.swift
//  StudyAI
//
//  Main view for parent report generation and management
//  Provides date range selection and report display functionality
//

import SwiftUI
import Lottie

struct ParentReportsView: View {
    @StateObject private var reportService = ParentReportService.shared
    @StateObject private var authService = AuthenticationService.shared
    @State private var selectedReport: ParentReport?
    @State private var isGeneratingReport = false
    @State private var showingInstructions = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Actions
                    quickActionsSection

                    // Recent Reports
                    recentReportsSection
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("parentReport.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showingInstructions = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.body)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .alert(NSLocalizedString("parentReport.instructions.title", comment: ""), isPresented: $showingInstructions) {
                Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
            } message: {
                Text(NSLocalizedString("parentReport.instructions.message", comment: ""))
            }
            .fullScreenCover(item: $selectedReport) { report in
                ReportDetailView(report: report)
                    .onAppear {
                        print("🔍 ReportDetailView fullScreenCover appeared with report: \(report.id)")
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
                    Button(action: {
                        clearAllReports()
                    }) {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }

            if reportService.availableReports.isEmpty {
                RecentReportsEmptyState()
            } else {
                List {
                    ForEach(reportService.availableReports.prefix(3)) { report in
                        ReportListCard(report: report) {
                            Task {
                                await loadReportDetail(reportId: report.id)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteReport(reportId: report.id)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(min(reportService.availableReports.count, 3)) * 110)
                .scrollDisabled(true)
            }
        }
    }

    // MARK: - Actions
    private func loadRecentReports() {
        guard authService.currentUser?.id != nil else { return }

        Task {
            // Load from LOCAL storage only (no backend query)
            let localStorage = LocalReportStorage.shared
            let localReports = await localStorage.getAllCachedReports()

            await MainActor.run {
                reportService.availableReports = Array(localReports.prefix(5))
                print("📊 Loaded \(localReports.count) reports from local storage")
            }
        }
    }

    private func deleteReport(reportId: String) {
        Task {
            let success = await reportService.deleteReport(reportId: reportId)

            if success {
                print("✅ Report \(reportId) deleted successfully")
            } else {
                print("❌ Failed to delete report \(reportId)")
            }
        }
    }

    private func clearAllReports() {
        reportService.clearCache()
        print("🗑️ All reports cleared from cache")
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

            // Check LOCAL storage first (no backend query)
            let localStorage = LocalReportStorage.shared
            let localReports = await localStorage.getAllCachedReports()

            var cachedReportId: String? = nil

            // Look for a locally cached report that matches the requested type
            let cachedReport = localReports.first { report in
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

            if let cached = cachedReport {
                cachedReportId = cached.id
                print("✅ Found locally cached \(type.rawValue) report: \(cached.id)")
                print("📅 Cached report period: \(cached.startDate) - \(cached.endDate)")
            } else {
                print("🔄 No suitable cached report found locally, generating new report")
            }

            await MainActor.run {
                isGeneratingReport = false

                if cachedReportId != nil {
                    // Use the cached report directly
                    print("🎯 Using locally cached report")
                    if let report = cachedReport {
                        selectedReport = report
                    }
                } else {
                    // No suitable cached report found, proceed with generation
                    print("🔄 Generating new report from local data")
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(
            colorScheme == .dark
                ? Color(.systemGray5)
                : Color(.systemGray6)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    colorScheme == .dark
                        ? Color(.systemGray4)
                        : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

struct ReportListCard: View {
    let report: ParentReport
    let onTap: () -> Void
    @Environment(\.colorScheme) var colorScheme

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
                        Text(RelativeDateTimeFormatter().localizedString(for: report.generatedAt, relativeTo: Date()))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                colorScheme == .dark
                    ? Color(.systemGray6)
                    : Color(.systemBackground)
            )
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
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 48))
                .foregroundColor(colorScheme == .dark ? .gray : .secondary)

            VStack(spacing: 8) {
                Text(NSLocalizedString("parentReport.noReportsYet", comment: ""))
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(NSLocalizedString("parentReport.generateFirstReport", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(
            colorScheme == .dark
                ? Color(.systemGray6).opacity(0.3)
                : Color(.systemGray6).opacity(0.5)
        )
        .cornerRadius(12)
    }
}

struct ReportGenerationOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            // BACKGROUND OVERLAY: Semi-transparent dark background
            // Adjust opacity value (0.0 to 1.0) to make lighter or darker
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            GeometryReader { geometry in
                VStack {
                    Spacer()

                    // ============================================
                    // LOTTIE ANIMATION CONFIGURATION
                    // ============================================
                    // This displays while parent reports are being generated

                    LottieView(
                        // ANIMATION FILE: Name of the JSON file in Resources folder (without .json extension)
                        // Available animations: "Bubbles x2", "Fire_moving", "Loading_animation_blue"
                        animationName: "Loading_animation_blue",

                        // LOOP MODE: How the animation repeats
                        // Options: .loop (infinite repeat), .playOnce (plays once then stops),
                        //          .autoReverse (plays forward then backward), .repeat(count) (repeat N times)
                        loopMode: .loop,

                        // ANIMATION SPEED: Playback speed multiplier
                        // 1.0 = normal speed, 2.0 = twice as fast, 0.5 = half speed
                        // Range: 0.1 to 10.0 (recommended: 0.5 to 2.0 for smooth playback)
                        animationSpeed: 1.0,

                        // POWER SAVING PROGRESS: Where animation pauses in power saving mode
                        // 0.0 = start, 1.0 = end. This loading animation pauses at 70%
                        powerSavingProgress: 0.7
                    )
                    // FRAME SIZE: Dynamic sizing based on screen width
                    // - Uses minimum of (screen width - padding) or max size
                    // - geometry.size.width - 64 = screen width minus 32pt padding on each side
                    // - 400 = maximum size cap to prevent cropping on larger devices
                    // The animation adapts: 300x300 on iPhone 15 Pro, ~360x360 on Pro Max
                    .frame(
                        width: min(geometry.size.width - 64, 400),
                        height: min(geometry.size.width - 64, 400)
                    )

                    // CLIPPING: Prevents animation from rendering outside the frame bounds
                    // Remove .clipped() if you want overflow effects
//                    .clipped()

                    // ============================================
                    // ADDITIONAL MODIFIERS YOU CAN ADD:
                    // ============================================
//                     .scaleEffect(1.0)                     // Scale up/down (1.0 = original size, removed to prevent cropping)
                    // .opacity(0.9)                          // Transparency (0.0 = invisible, 1.0 = opaque)
                    // .rotationEffect(.degrees(0))          // Rotate animation
                    // .background(Color.white.opacity(0.1))  // Add background behind animation
                    // .cornerRadius(20)                      // Round corners
                    // .shadow(color: .blue, radius: 20)     // Add glow effect
                    // .padding()                             // Add padding around animation

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    ParentReportsView()
}
