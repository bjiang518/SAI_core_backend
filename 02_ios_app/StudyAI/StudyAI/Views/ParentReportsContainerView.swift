//
//  ParentReportsContainerView.swift
//  StudyAI
//
//  Simple wrapper that directly shows PassiveReportsView
//  Scheduled/On-Demand tabs removed per user request
//

import SwiftUI

struct ParentReportsContainerView: View {
    @State private var showingOnboarding = false
    @State private var hasCheckedOnboarding = false

    var body: some View {
        PassiveReportsView()
            .sheet(isPresented: $showingOnboarding) {
                ParentReportsOnboardingView(
                    onComplete: {
                        var settings = ParentReportSettings.load()
                        settings.hasSeenOnboarding = true
                        settings.save()
                        showingOnboarding = false
                    },
                    onSkip: {
                        var settings = ParentReportSettings.load()
                        settings.hasSeenOnboarding = true
                        settings.save()
                        showingOnboarding = false
                    }
                )
            }
            .onAppear {
                checkOnboarding()
            }
    }

    // MARK: - Helper Methods

    private func checkOnboarding() {
        guard !hasCheckedOnboarding else { return }
        hasCheckedOnboarding = true

        // Check if user has already seen the onboarding
        let settings = ParentReportSettings.load()
        if settings.hasSeenOnboarding {
            print("✅ [ParentReportsContainer] Onboarding already completed")
            return
        }

        // Check if reports are already enabled
        if settings.parentReportsEnabled {
            print("✅ [ParentReportsContainer] Reports already enabled, skipping onboarding")
            return
        }

        // Show onboarding
        print("📊 [ParentReportsContainer] Showing parent reports onboarding")
        showingOnboarding = true
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        ParentReportsContainerView()
    }
}
