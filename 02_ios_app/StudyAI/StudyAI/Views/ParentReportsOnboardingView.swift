//
//  ParentReportsOnboardingView.swift
//  StudyAI
//
//  Agreement screen for enabling parent reports.
//  Sync happens at report generation time, not during onboarding.
//

import SwiftUI

struct ParentReportsOnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    let onEnable: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)
                    .padding(.bottom, 32)

                // Title
                VStack(spacing: 8) {
                    Text("Get Weekly Learning Insights")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("AI-generated reports for parents, every week")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 32)

                // Features
                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Progress Tracking",
                        description: "See how your child improves each week"
                    )
                    FeatureRow(
                        icon: "lightbulb.fill",
                        title: "AI-Powered Insights",
                        description: "Personalized recommendations based on homework data"
                    )
                    FeatureRow(
                        icon: "heart.text.square.fill",
                        title: "Mental Wellbeing",
                        description: "Monitor engagement and confidence signals"
                    )
                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Private & Secure",
                        description: "Data is encrypted and never shared with third parties"
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 32)

                // Data note
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Homework data syncs to server automatically when you generate a report")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        var settings = ParentReportSettings.load()
                        settings.parentReportsEnabled = true
                        settings.autoSyncEnabled = true
                        settings.save()
                        onEnable()
                        dismiss()
                    }) {
                        Text("Enable Parent Reports")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button(action: {
                        var settings = ParentReportSettings.load()
                        settings.parentReportsEnabled = false
                        settings.autoSyncEnabled = false
                        settings.save()
                        onDecline()
                        dismiss()
                    }) {
                        Text("No Thanks")
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Supporting Views (reused from original)

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ParentReportsOnboardingView(
        onEnable: {},
        onDecline: {}
    )
}
