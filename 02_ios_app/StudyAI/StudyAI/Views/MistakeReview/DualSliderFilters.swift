//
//  DualSliderFilters.swift
//  StudyAI
//
//  Dual slider filters for severity and time range
//

import SwiftUI

// MARK: - Severity Level Enum

enum SeverityLevel: String, CaseIterable {
    case all = "All"
    case mediumPlus = "Med+"
    case severe = "Severe"

    var color: Color {
        switch self {
        case .all: return .green
        case .mediumPlus: return .orange
        case .severe: return .red
        }
    }

    var displayName: String {
        switch self {
        case .all: return NSLocalizedString("mistakeReview.filter.severity.all", comment: "")
        case .mediumPlus: return NSLocalizedString("mistakeReview.filter.severity.medPlus", comment: "")
        case .severe: return NSLocalizedString("mistakeReview.filter.severity.severe", comment: "")
        }
    }

    /// Filter mistakes by severity
    /// - all: Show all mistakes
    /// - mediumPlus: Show execution_error + conceptual_gap (exclude needs_refinement)
    /// - severe: Show only conceptual_gap
    func matches(errorType: String?) -> Bool {
        guard let errorType = errorType else {
            // No error type means no analysis yet - show in "all" only
            return self == .all
        }

        switch self {
        case .all:
            return true
        case .mediumPlus:
            // Exclude "needs_refinement" (nearly there)
            return errorType != "needs_refinement"
        case .severe:
            // Only "conceptual_gap"
            return errorType == "conceptual_gap"
        }
    }
}

// MARK: - Time Range Enum

enum FilterTimeRange: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case allTime = "All"

    var displayName: String {
        switch self {
        case .week: return NSLocalizedString("mistakeReview.filter.time.week", comment: "")
        case .month: return NSLocalizedString("mistakeReview.filter.time.month", comment: "")
        case .allTime: return NSLocalizedString("mistakeReview.filter.time.all", comment: "")
        }
    }

    var mistakeTimeRange: MistakeTimeRange {
        switch self {
        case .week: return .thisWeek
        case .month: return .thisMonth
        case .allTime: return .allTime
        }
    }
}

// MARK: - Dual Slider Filters View

struct DualSliderFilters: View {
    @Binding var selectedSeverity: SeverityLevel
    @Binding var selectedTimeRange: FilterTimeRange

    var body: some View {
        HStack(spacing: 16) {
            // Left: Severity Filter
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("mistakeReview.filter.severityLabel", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                SliderDots(
                    options: SeverityLevel.allCases,
                    selected: $selectedSeverity,
                    colorProvider: { $0.color }
                )
            }
            .frame(maxWidth: .infinity)

            // Divider
            Rectangle()
                .fill(Color(UIColor.systemGray4))
                .frame(width: 1, height: 50)

            // Right: Time Range Filter
            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("mistakeReview.filter.timeLabel", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)

                SliderDots(
                    options: FilterTimeRange.allCases,
                    selected: $selectedTimeRange,
                    colorProvider: { _ in .blue }
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Slider Dots Component

struct SliderDots<T: RawRepresentable & CaseIterable & Equatable>: View where T.RawValue == String {
    let options: [T]
    @Binding var selected: T
    let colorProvider: (T) -> Color

    var body: some View {
        VStack(spacing: 8) {
            // Dots with track
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color(UIColor.systemGray4))
                        .frame(height: 4)

                    // Active track (from start to selected dot)
                    Capsule()
                        .fill(colorProvider(selected))
                        .frame(width: selectedOffset(geometry: geometry), height: 4)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)

                    // Dots
                    HStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            ZStack {
                                // Dot background
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 28, height: 28)
                                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                                // Dot fill
                                Circle()
                                    .fill(colorProvider(option))
                                    .frame(
                                        width: selected == option ? 20 : 14,
                                        height: selected == option ? 20 : 14
                                    )
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
                            }
                            .frame(maxWidth: .infinity)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selected = option
                                }

                                // Haptic feedback
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            }
                        }
                    }
                }
            }
            .frame(height: 28)

            // Labels
            HStack {
                ForEach(options, id: \.rawValue) { option in
                    if let displayable = option as? SeverityLevel {
                        Text(displayable.displayName)
                            .font(.caption2)
                            .fontWeight(selected == option ? .semibold : .regular)
                            .foregroundColor(selected == option ? colorProvider(option) : .secondary)
                            .frame(maxWidth: .infinity)
                    } else if let displayable = option as? FilterTimeRange {
                        Text(displayable.displayName)
                            .font(.caption2)
                            .fontWeight(selected == option ? .semibold : .regular)
                            .foregroundColor(selected == option ? colorProvider(option) : .secondary)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(option.rawValue)
                            .font(.caption2)
                            .fontWeight(selected == option ? .semibold : .regular)
                            .foregroundColor(selected == option ? colorProvider(option) : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func selectedOffset(geometry: GeometryProxy) -> CGFloat {
        guard let index = options.firstIndex(where: { $0 == selected }) else {
            return 0
        }
        let segmentWidth = geometry.size.width / CGFloat(options.count)
        return segmentWidth * CGFloat(index + 1)
    }
}

#Preview {
    VStack(spacing: 20) {
        DualSliderFilters(
            selectedSeverity: .constant(.all),
            selectedTimeRange: .constant(.week)
        )
        .padding()

        DualSliderFilters(
            selectedSeverity: .constant(.mediumPlus),
            selectedTimeRange: .constant(.month)
        )
        .padding()

        DualSliderFilters(
            selectedSeverity: .constant(.severe),
            selectedTimeRange: .constant(.allTime)
        )
        .padding()
    }
}
