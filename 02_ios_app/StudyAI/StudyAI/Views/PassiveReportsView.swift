//
//  PassiveReportsView.swift
//  StudyAI
//
//  Passive Reports List View
//  Shows scheduled weekly/monthly reports with visible button to manually trigger generation
//

import SwiftUI

struct PassiveReportsView: View {
    @StateObject private var viewModel = PassiveReportsViewModel()
    @State private var selectedPeriod: ReportPeriod = .weekly
    @State private var showTestingAlert = false
    @State private var batchToDelete: PassiveReportBatch?
    @State private var showDeleteConfirmation = false

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
            }
            .refreshable {
                await viewModel.loadAllBatches()
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
        LazyVStack(spacing: 12) {
            ForEach(batches) { batch in
                NavigationLink(destination: PassiveReportDetailView(batch: batch)) {
                    PassiveReportBatchCard(batch: batch)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 20)
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
