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
            VStack(spacing: 0) {
                // Period Picker (Weekly/Monthly)
                periodPicker

                // Content based on loading state
                if viewModel.isLoadingBatches {
                    loadingView
                } else if batches.isEmpty {
                    emptyStateView
                } else {
                    batchListView
                }
            }
            .navigationTitle(NSLocalizedString("reports.passive.title", value: "Scheduled Reports", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showTestingAlert = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("Generate")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    .disabled(viewModel.isGenerating)
                    .opacity(viewModel.isGenerating ? 0.6 : 1.0)
                }
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
            }
            .refreshable {
                await viewModel.loadAllBatches()
            }
        }
    }

    // MARK: - Subviews

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Text(period.localizedName).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding()
    }

    private var batchListView: some View {
        List {
            ForEach(batches) { batch in
                NavigationLink(destination: PassiveReportDetailView(batch: batch)) {
                    PassiveReportBatchCard(batch: batch)
                }
                .buttonStyle(PlainButtonStyle())
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onDelete(perform: { indexSet in
                for index in indexSet {
                    let batch = batches[index]
                    batchToDelete = batch
                    showDeleteConfirmation = true
                }
            })
        }
        .listStyle(.plain)
        .confirmationDialog(
            "Delete Report",
            isPresented: $showDeleteConfirmation,
            presenting: batchToDelete
        ) { batch in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteBatch(batch)
                    batchToDelete = nil
                }
            }
        } message: { batch in
            let periodText = batch.period.capitalized
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"
            let startDate = dateFormatter.string(from: batch.startDate)
            let endDate = dateFormatter.string(from: batch.endDate)

            return Text("Are you sure you want to delete the \(periodText) report for \(startDate) - \(endDate)? This action cannot be undone.")
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
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 70))
                .foregroundColor(.gray.opacity(0.5))

            VStack(spacing: 8) {
                Text(NSLocalizedString("reports.passive.empty.title", value: "No Reports Yet", comment: ""))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(selectedPeriod == .weekly ?
                    NSLocalizedString("reports.passive.empty.weekly", value: "Weekly reports are generated every Sunday at 10 PM", comment: "") :
                    NSLocalizedString("reports.passive.empty.monthly", value: "Monthly reports are generated on the 1st of each month", comment: ""))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            // Test generation button (will be visible during development)
            if showTestingAlert {
                Button(action: {
                    Task {
                        await viewModel.triggerManualGeneration(period: selectedPeriod.rawValue.lowercased())
                    }
                }) {
                    HStack {
                        if viewModel.isGenerating {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("Generate Test Report")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .disabled(viewModel.isGenerating)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
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
