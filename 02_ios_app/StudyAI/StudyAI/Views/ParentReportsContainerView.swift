//
//  ParentReportsContainerView.swift
//  StudyAI
//
//  Simple wrapper that shows PassiveReportsView and gates onboarding.
//  Onboarding shows when parentReportsEnabled == false (including after user declines and later returns).
//

import SwiftUI

struct ParentReportsContainerView: View {
    @State private var showingOnboarding = false
    @State private var hasCheckedOnboarding = false

    var body: some View {
        PassiveReportsView()
            .sheet(isPresented: $showingOnboarding) {
                ParentReportsOnboardingView(
                    onEnable: {
                        showingOnboarding = false
                    },
                    onDecline: {
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

        let settings = ParentReportSettings.load()

        // Only skip if user has actively enabled reports
        if settings.parentReportsEnabled {
            print("✅ [ParentReportsContainer] Reports already enabled, skipping onboarding")
            return
        }

        // Show onboarding (first-time or re-enable after declining)
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
