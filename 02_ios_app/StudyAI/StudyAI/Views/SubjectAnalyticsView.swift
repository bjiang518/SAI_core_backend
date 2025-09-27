//
//  SubjectAnalyticsView.swift
//  StudyAI
//
//  Advanced subject analytics with filtering and comparison features
//

import SwiftUI
import Charts

struct SubjectAnalyticsView: View {
    let subjectBreakdownData: SubjectBreakdownData?
    let selectedTimeframe: TimeframeOption
    let onTimeframeChanged: (TimeframeOption) -> Void
    
    @State private var selectedAnalyticsTab: AnalyticsTab = .overview
    @Environment(\.dismiss) private var dismiss
    
    enum AnalyticsTab: String, CaseIterable {
        case overview = "Overview"
        case performance = "Performance"
        case trends = "Trends"
        case insights = "Insights"
        
        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .performance: return "target"
            case .trends: return "chart.line.uptrend.xyaxis"
            case .insights: return "lightbulb.fill"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Analytics Tab Selector
                analyticsTabSelector
                
                ScrollView {
                    LazyVStack(spacing: 20) {
                        switch selectedAnalyticsTab {
                        case .overview:
                            overviewContent
                        case .performance:
                            performanceContent
                        case .trends:
                            trendsContent
                        case .insights:
                            insightsContent
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Subject Analytics")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(TimeframeOption.allCases, id: \.self) { option in
                            Button(action: {
                                onTimeframeChanged(option)
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
                        HStack {
                            Text(selectedTimeframe.displayName)
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    // MARK: - Tab Selector
    
    private var analyticsTabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedAnalyticsTab = tab
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.title3)
                                .foregroundColor(selectedAnalyticsTab == tab ? .blue : .secondary)
                            
                            Text(tab.rawValue)
                                .font(.caption)
                                .fontWeight(selectedAnalyticsTab == tab ? .semibold : .regular)
                                .foregroundColor(selectedAnalyticsTab == tab ? .blue : .secondary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedAnalyticsTab == tab ? Color.blue.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var overviewContent: some View {
        if subjectBreakdownData != nil {
            VStack(spacing: 16) {
                Text("Overview")
                    .font(.headline)
                Text("Subject breakdown data available")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)
        } else {
            analyticsEmptyState
        }
    }
    
    @ViewBuilder
    private var performanceContent: some View {
        VStack(spacing: 16) {
            Text("Performance")
                .font(.headline)
            Text("Performance analytics coming soon")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var trendsContent: some View {
        VStack(spacing: 16) {
            Text("Trends")
                .font(.headline)
            Text("Trend analysis coming soon")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var insightsContent: some View {
        VStack(spacing: 16) {
            Text("Insights")
                .font(.headline)
            Text("AI insights coming soon")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Empty State
    
    private var analyticsEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Analytics Data")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Complete some study sessions to see detailed analytics and insights!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(40)
    }
}

#Preview {
    SubjectAnalyticsView(
        subjectBreakdownData: nil as SubjectBreakdownData?,
        selectedTimeframe: TimeframeOption.currentWeek,
        onTimeframeChanged: { _ in }
    )
}