//
//  PassiveReportsView.swift
//  StudyAI
//
//  Passive Reports List View
//  Shows scheduled weekly/monthly reports with visible button to manually trigger generation
//

import SwiftUI
import UIKit

struct PassiveReportsView: View {
    @StateObject private var viewModel = PassiveReportsViewModel()
    @State private var selectedPeriod: ReportPeriod = .weekly
    @State private var showTestingAlert = false
    @State private var batchToDelete: PassiveReportBatch?
    @State private var showDeleteConfirmation = false
    @State private var isEditMode = false
    @State private var selectedBatches: Set<String> = []
    @State private var showingReportsInfo = false

    enum ReportPeriod: String, CaseIterable {
        case weekly = "Weekly"
        case monthly = "Monthly"

        var localizedName: String {
            switch self {
            case .weekly:
                return NSLocalizedString("reports.passive.weekly", value: "Weekly", comment: "")
            case .monthly:
                return NSLocalizedString("reports.passive.monthly", value: "Monthly", comment: "")
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header section with subtitle
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly and monthly learning insights")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                    // Period Picker (Weekly/Monthly) - moved into scroll view
                    periodPicker

                    // Content based on loading state
                    if viewModel.isLoadingBatches {
                        loadingView
                    } else if batches.isEmpty {
                        emptyStateView
                    } else {
                        batchesContent
                    }
                }
            }
            .navigationTitle("Parent Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Info button
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isEditMode {
                        Button(action: { showingReportsInfo = true }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Generate button
                        Button {
                            showTestingAlert = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                        }

                        // Three-dot dropdown menu
                        Menu {
                            Button {
                                print("🔧 [EditMode] Entering edit mode")
                                isEditMode = true
                                print("🔧 [EditMode] isEditMode = \(isEditMode)")
                            } label: {
                                Label("Edit Reports", systemImage: "checkmark.circle")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Edit mode: Cancel button
                if isEditMode {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isEditMode = false
                            selectedBatches.removeAll()
                        }
                    }
                }
            }
            .alert(NSLocalizedString("passiveReports.info.title", comment: ""), isPresented: $showingReportsInfo) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(NSLocalizedString("passiveReports.info.message", comment: ""))
            }
            .alert("Testing Mode", isPresented: $showTestingAlert) {
                Button("Generate Weekly Report") {
                    Task {
                        await viewModel.triggerManualGeneration(period: "weekly")
                    }
                }
                Button("Generate Monthly Report") {
                    Task {
                        await viewModel.triggerManualGeneration(period: "monthly")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Manually trigger report generation for testing. This button will be removed in production.")
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                if let error = viewModel.errorMessage {
                    Text(error)
                }
            }
            .task {
                await viewModel.loadAllBatches()
                // Start monitoring for new reports
                viewModel.startReportMonitoring()
            }
            .refreshable {
                await viewModel.loadAllBatches()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Check for new reports when app comes to foreground
                Task {
                    await viewModel.checkForNewReportsNow()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenParentReports"))) { notification in
                // Handle notification tap to open specific report
                print("📊 [PassiveReports] Received notification tap - reloading reports")
                Task {
                    await viewModel.loadAllBatches()
                }
            }
        }
    }

    // MARK: - Subviews

    private var periodPicker: some View {
        HStack(spacing: 12) {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPeriod = period
                    }
                }) {
                    Text(period.localizedName)
                        .font(.system(size: 15, weight: selectedPeriod == period ? .semibold : .regular))
                        .foregroundColor(selectedPeriod == period ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selectedPeriod == period ?
                                Color.blue : Color(.secondarySystemBackground)
                        )
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var batchesContent: some View {
        VStack(spacing: 12) {
            LazyVStack(spacing: 12) {
                ForEach(batches) { batch in
                    if isEditMode {
                        // Edit mode: Checkbox + Card (not tappable)
                        HStack(spacing: 12) {
                            Button {
                                toggleSelection(batch)
                            } label: {
                                Image(systemName: selectedBatches.contains(batch.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedBatches.contains(batch.id) ? .blue : .gray)
                                    .font(.system(size: 24))
                            }

                            PassiveReportBatchCard(batch: batch)
                        }
                    } else {
                        // Normal mode: NavigationLink
                        NavigationLink(destination: PassiveReportDetailView(batch: batch)) {
                            PassiveReportBatchCard(batch: batch)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }

            // Delete button in edit mode
            if isEditMode && !selectedBatches.isEmpty {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete \(selectedBatches.count) Report\(selectedBatches.count > 1 ? "s" : "")")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .alert("Delete Reports?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedBatches()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedBatches.count) report\(selectedBatches.count > 1 ? "s" : "")? This action cannot be undone.")
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading reports...")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))

            VStack(spacing: 8) {
                Text("No Reports Available")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(selectedPeriod == .weekly ?
                    "Weekly reports are generated every Sunday at 10 PM. Check back soon!" :
                    "Monthly reports are generated on the 1st of each month.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private var batches: [PassiveReportBatch] {
        selectedPeriod == .weekly ? viewModel.weeklyBatches : viewModel.monthlyBatches
    }

    private func formatDateRange(_ batch: PassiveReportBatch) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: batch.startDate)
        let end = formatter.string(from: batch.endDate)
        return "\(start) - \(end)"
    }

    private func toggleSelection(_ batch: PassiveReportBatch) {
        if selectedBatches.contains(batch.id) {
            selectedBatches.remove(batch.id)
        } else {
            selectedBatches.insert(batch.id)
        }
    }

    private func deleteSelectedBatches() {
        Task {
            // Get batches to delete
            let batchesToDelete = batches.filter { selectedBatches.contains($0.id) }

            print("🗑️ [PassiveReportsView] Deleting \(batchesToDelete.count) selected batches")

            // Delete all batches atomically
            let (succeeded, failed) = await viewModel.deleteBatches(batchesToDelete)

            // Exit edit mode and clear selection
            isEditMode = false
            selectedBatches.removeAll()

            // Show result if there were failures
            if failed > 0 {
                print("⚠️ [PassiveReportsView] Batch delete partial success: \(succeeded) succeeded, \(failed) failed")
            } else {
                print("✅ [PassiveReportsView] All \(succeeded) batches deleted successfully")
            }
        }
    }
}

// MARK: - Batch Card Component

struct PassiveReportBatchCard: View {
    let batch: PassiveReportBatch

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with date range
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(periodText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(dateRangeText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()

                // Grade badge
                if let grade = batch.overallGrade {
                    Text(grade)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(gradeColor(grade))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(gradeColor(grade).opacity(0.1))
                        .cornerRadius(8)
                }
            }

            // Summary text
            if let summary = batch.oneLineSummary {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Metrics row
            HStack(spacing: 20) {
                if let accuracy = batch.overallAccuracy {
                    metricItem(icon: "chart.bar.fill", value: "\(Int(accuracy * 100))%", label: "Accuracy")
                }

                if let questions = batch.questionCount {
                    metricItem(icon: "questionmark.circle.fill", value: "\(questions)", label: "Questions")
                }

                if let time = batch.studyTimeMinutes {
                    metricItem(icon: "clock.fill", value: "\(time)m", label: "Study Time")
                }
            }

            // Trends (if available)
            HStack(spacing: 12) {
                if let accuracyTrend = batch.accuracyTrend {
                    trendBadge(trend: accuracyTrend, label: "Accuracy")
                }

                if let activityTrend = batch.activityTrend {
                    trendBadge(trend: activityTrend, label: "Activity")
                }
            }

            // Report count
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                Text("\(batch.reportCount ?? 0) reports available")
                    .font(.caption)
            }
            .foregroundColor(.blue)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    // MARK: - Helper Views

    private func metricItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.primary)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func trendBadge(trend: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: trendIcon(trend))
                .font(.caption2)
            Text("\(label): \(trend)")
                .font(.caption2)
        }
        .foregroundColor(trendColor(trend))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(trendColor(trend).opacity(0.1))
        .cornerRadius(6)
    }

    // MARK: - Helpers

    private var periodText: String {
        batch.period.capitalized
    }

    private var dateRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: batch.startDate)
        let end = formatter.string(from: batch.endDate)
        return "\(start) - \(end)"
    }

    private func gradeColor(_ grade: String) -> Color {
        let firstChar = grade.first?.uppercased() ?? "C"
        switch firstChar {
        case "A": return .green
        case "B": return .blue
        case "C": return .orange
        default: return .red
        }
    }

    private func trendIcon(_ trend: String) -> String {
        switch trend.lowercased() {
        case "improving", "increasing": return "arrow.up.right"
        case "declining", "decreasing": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    private func trendColor(_ trend: String) -> Color {
        switch trend.lowercased() {
        case "improving", "increasing": return .green
        case "declining", "decreasing": return .red
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    PassiveReportsView()
}
