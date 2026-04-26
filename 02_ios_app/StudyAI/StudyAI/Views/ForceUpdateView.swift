//
//  ForceUpdateView.swift
//  StudyAI
//
//  Full-screen blocker shown when the backend returns 426 (App Update Required).
//  Non-dismissable — the only action is "Update Now" → App Store.
//

import SwiftUI

struct ForceUpdateView: View {
    let storeUrl: String?
    @StateObject private var themeManager = ThemeManager.shared

    private let defaultStoreUrl = "https://apps.apple.com/app/id6743428452"

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 72))
                .foregroundColor(themeManager.accentColor)

            VStack(spacing: 12) {
                Text(NSLocalizedString("forceUpdate.title", value: "Update Required", comment: ""))
                    .font(.title.bold())
                    .foregroundColor(themeManager.primaryText)

                Text(NSLocalizedString("forceUpdate.message", value: "A new version of StudyAgent is available. Please update to continue using the app.", comment: ""))
                    .font(.body)
                    .foregroundColor(themeManager.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(action: openAppStore) {
                Text(NSLocalizedString("forceUpdate.button", value: "Update Now", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(themeManager.accentColor)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(themeManager.cardBackground.ignoresSafeArea())
    }

    private func openAppStore() {
        let urlString = storeUrl ?? defaultStoreUrl
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
