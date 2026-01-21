//
//  ParentReportsContainerView.swift
//  StudyAI
//
//  Container view with two tabs:
//  1. On-Demand Reports (legacy system)
//  2. Scheduled Reports (new passive system)
//
//  Migration strategy: Keep both tabs during testing phase,
//  then eventually remove on-demand tab after validation
//

import SwiftUI

struct ParentReportsContainerView: View {
    @State private var selectedTab: ReportTab = .scheduled
    @AppStorage("enable_passive_reports") private var enablePassiveReports = true

    enum ReportTab: String, CaseIterable {
        case scheduled = "Scheduled"
        case onDemand = "On-Demand"

        var displayName: String {
            switch self {
            case .scheduled:
                return NSLocalizedString("reports.tab.scheduled", value: "Scheduled", comment: "")
            case .onDemand:
                return NSLocalizedString("reports.tab.ondemand", value: "On-Demand", comment: "")
            }
        }

        var icon: String {
            switch self {
            case .scheduled: return "calendar.badge.clock"
            case .onDemand: return "play.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            customTabPicker

            // Content based on selected tab
            Group {
                switch selectedTab {
                case .scheduled:
                    PassiveReportsView()

                case .onDemand:
                    LegacyOnDemandReportsView()
                }
            }
            .transition(.opacity)
        }
        .navigationTitle("Parent Reports")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Custom Tab Picker

    private var customTabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ReportTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }) {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16))

                            Text(tab.displayName)
                                .font(.system(size: 15, weight: .semibold))
                        }

                        // Beta badge for scheduled tab
                        if tab == .scheduled && enablePassiveReports {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .cornerRadius(4)
                        }
                    }
                    .foregroundColor(selectedTab == tab ? .blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        selectedTab == tab ?
                            Color.blue.opacity(0.1) :
                            Color.clear
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Legacy On-Demand Reports View

/// Wrapper for the existing on-demand report system
/// This is kept during migration for comparison and gradual rollout
struct LegacyOnDemandReportsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))

            VStack(spacing: 12) {
                Text("Legacy On-Demand Reports")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This is the previous report generation system. It has been replaced by the new Scheduled Reports system.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Text("Switch to the Scheduled tab to view automatically generated weekly and monthly reports.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }

            // Note: In production, this view will be removed entirely
            // For now, it shows a deprecation message
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ParentReportsContainerView()
    }
}
