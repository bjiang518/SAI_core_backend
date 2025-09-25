//
//  ReportDateRangeSelector.swift
//  StudyAI
//
//  Date range selection component for parent report generation
//  Provides intuitive date picking with validation and presets
//

import SwiftUI

struct ReportDateRangeSelector: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var reportService = ParentReportService.shared
    @StateObject private var authService = AuthenticationService.shared

    let onReportGenerated: (ParentReport) -> Void

    // Date selection state
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var reportType: ReportType = .custom
    @State private var includeAIAnalysis = true
    @State private var compareWithPrevious = true

    // UI state
    @State private var isGenerating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var selectedPreset: DatePreset?

    var body: some View {
        NavigationView {
            Form {
                // Date Presets Section
                datePresetsSection

                // Custom Date Range Section
                customDateSection

                // Report Options Section
                reportOptionsSection

                // Preview Section
                previewSection
            }
            .navigationTitle("Generate Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isGenerating)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Generate") {
                        generateReport()
                    }
                    .fontWeight(.semibold)
                    .disabled(isGenerating || !isValidDateRange)
                }
            }
            .overlay {
                if isGenerating {
                    ReportGenerationOverlay(
                        progress: reportService.reportGenerationProgress
                    )
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Date Presets Section
    private var datePresetsSection: some View {
        Section("Quick Presets") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(DatePreset.allCases, id: \.self) { preset in
                    DatePresetCard(
                        preset: preset,
                        isSelected: selectedPreset == preset
                    ) {
                        selectPreset(preset)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Custom Date Section
    private var customDateSection: some View {
        Section("Custom Date Range") {
            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                .onChange(of: startDate) { _, _ in
                    selectedPreset = nil
                    validateDateRange()
                }

            DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                .onChange(of: endDate) { _, _ in
                    selectedPreset = nil
                    validateDateRange()
                }

            if !isValidDateRange {
                Label("End date must be after start date", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Duration Info
            HStack {
                Text("Duration:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(durationText)
                    .fontWeight(.medium)
            }
        }
    }

    // MARK: - Report Options Section
    private var reportOptionsSection: some View {
        Section("Report Options") {
            Picker("Report Type", selection: $reportType) {
                ForEach(ReportType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }

            Toggle("Include AI Analysis", isOn: $includeAIAnalysis)

            Toggle("Compare with Previous", isOn: $compareWithPrevious)

            if includeAIAnalysis {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                    Text("AI will analyze study patterns and provide personalized insights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Preview Section
    private var previewSection: some View {
        Section("Report Preview") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: reportType.icon)
                        .foregroundColor(.blue)
                    Text(reportType.displayName)
                        .fontWeight(.medium)
                    Spacer()
                }

                Text("Date Range: \(formatDateRange())")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    if includeAIAnalysis {
                        Label("AI Analysis", systemImage: "brain.head.profile")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }

                    if compareWithPrevious {
                        Label("Progress Comparison", systemImage: "chart.line.uptrend.xyaxis")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Computed Properties
    private var isValidDateRange: Bool {
        startDate <= endDate && endDate <= Date()
    }

    private var durationText: String {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    // MARK: - Methods
    private func selectPreset(_ preset: DatePreset) {
        selectedPreset = preset
        let dates = preset.dateRange
        startDate = dates.start
        endDate = dates.end
        reportType = preset.recommendedType
    }

    private func validateDateRange() {
        // Additional validation can be added here
    }

    private func formatDateRange() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
    }

    private func generateReport() {
        guard let userId = authService.currentUser?.id else {
            showError("Authentication required")
            return
        }

        guard isValidDateRange else {
            showError("Please select a valid date range")
            return
        }

        isGenerating = true

        Task {
            let result = await reportService.generateReport(
                studentId: userId,
                startDate: startDate,
                endDate: endDate,
                reportType: reportType,
                includeAIAnalysis: includeAIAnalysis,
                compareWithPrevious: compareWithPrevious
            )

            await MainActor.run {
                isGenerating = false

                switch result {
                case .success(let report):
                    onReportGenerated(report)
                    dismiss()
                case .failure(let error):
                    showError(error.localizedDescription)
                }
            }
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
    }
}

// MARK: - Date Presets

enum DatePreset: CaseIterable {
    case lastWeek
    case lastTwoWeeks
    case lastMonth
    case lastQuarter
    case currentMonth
    case customRange

    var title: String {
        switch self {
        case .lastWeek: return "Last 7 Days"
        case .lastTwoWeeks: return "Last 2 Weeks"
        case .lastMonth: return "Last 30 Days"
        case .lastQuarter: return "Last 3 Months"
        case .currentMonth: return "This Month"
        case .customRange: return "Custom Range"
        }
    }

    var icon: String {
        switch self {
        case .lastWeek: return "calendar.badge.clock"
        case .lastTwoWeeks: return "calendar.badge.plus"
        case .lastMonth: return "calendar"
        case .lastQuarter: return "calendar.badge.exclamationmark"
        case .currentMonth: return "calendar.circle"
        case .customRange: return "slider.horizontal.3"
        }
    }

    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .lastWeek:
            let start = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (start, now)
        case .lastTwoWeeks:
            let start = calendar.date(byAdding: .day, value: -14, to: now) ?? now
            return (start, now)
        case .lastMonth:
            let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (start, now)
        case .lastQuarter:
            let start = calendar.date(byAdding: .month, value: -3, to: now) ?? now
            return (start, now)
        case .currentMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (start, now)
        case .customRange:
            return (now, now) // Placeholder
        }
    }

    var recommendedType: ReportType {
        switch self {
        case .lastWeek: return .weekly
        case .lastTwoWeeks: return .custom
        case .lastMonth: return .monthly
        case .lastQuarter: return .progress
        case .currentMonth: return .monthly
        case .customRange: return .custom
        }
    }
}

// MARK: - Date Preset Card

struct DatePresetCard: View {
    let preset: DatePreset
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .white : .blue)

                Text(preset.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isSelected ? .white : .primary)

                if preset != .customRange {
                    Text(formatDuration(preset.dateRange))
                        .font(.caption2)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func formatDuration(_ dateRange: (start: Date, end: Date)) -> String {
        let days = Calendar.current.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 0
        return "\(days) days"
    }
}

#Preview {
    ReportDateRangeSelector { _ in }
}