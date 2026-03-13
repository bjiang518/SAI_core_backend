//
//  UpgradePromptView.swift
//  StudyAI
//

import SwiftUI

struct UpgradePromptView: View {
    let blockedFeature: GatedFeature
    let reason: FeatureGate.BlockReason
    var onDismiss: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var guestService = GuestSessionService.shared
    @State private var showingConversionLogin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 52))
                    .foregroundColor(themeManager.accentColor)

                // Title & message
                VStack(spacing: 8) {
                    Text(title)
                        .font(.title2.bold())
                        .foregroundColor(themeManager.primaryText)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(themeManager.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // CTA buttons
                VStack(spacing: 12) {
                    primaryButton
                    secondaryButton
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.dismiss", comment: "Dismiss")) {
                        onDismiss()
                    }
                    .foregroundColor(themeManager.secondaryText)
                }
            }
        }
        .sheet(isPresented: $showingConversionLogin) {
            ModernLoginView(conversionMode: true) {
                showingConversionLogin = false
                onDismiss()
            }
        }
    }

    // MARK: - Computed strings

    private var title: String {
        switch reason {
        case .notAuthenticated:
            return NSLocalizedString("upgrade.title", comment: "Upgrade title")
        case .upgradeRequired where authService.currentUser?.isAnonymous == true:
            return NSLocalizedString("upgrade.createFreeAccount", comment: "Create free account title")
        case .upgradeRequired:
            return NSLocalizedString("upgrade.upgradeToPremium", comment: "Upgrade to premium title")
        case .monthlyLimitReached:
            return NSLocalizedString("upgrade.monthlyLimitReached", comment: "Monthly limit reached title")
        case .coppaRestricted:
            return NSLocalizedString("upgrade.coppaRestricted", comment: "COPPA restricted title")
        }
    }

    private var subtitle: String {
        switch reason {
        case .notAuthenticated, .upgradeRequired where authService.currentUser?.isAnonymous == true:
            return NSLocalizedString("upgrade.createAccountSubtitle", comment: "Create account subtitle")
        case .upgradeRequired:
            return NSLocalizedString("upgrade.upgradeToPremiumSubtitle", comment: "Upgrade to premium subtitle")
        case .monthlyLimitReached:
            return NSLocalizedString("upgrade.monthlyLimitSubtitle", comment: "Monthly limit subtitle")
        case .coppaRestricted:
            return NSLocalizedString("upgrade.coppaRestrictedSubtitle", comment: "COPPA restricted subtitle")
        }
    }

    private var iconName: String {
        switch reason {
        case .coppaRestricted: return "lock.shield"
        case .monthlyLimitReached: return "chart.bar.fill"
        default: return "star.circle.fill"
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch reason {
        case .upgradeRequired where authService.currentUser?.isAnonymous == true:
            Button {
                showingConversionLogin = true
            } label: {
                Text(NSLocalizedString("upgrade.createFreeAccount", comment: "Create free account CTA"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        case .upgradeRequired, .monthlyLimitReached, .notAuthenticated:
            Button {
                // Phase 7: open StoreKit paywall
                onDismiss()
            } label: {
                Text(NSLocalizedString("upgrade.upgradeToPremium", comment: "Upgrade to premium CTA"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        case .coppaRestricted:
            EmptyView()
        }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        switch reason {
        case .upgradeRequired, .monthlyLimitReached:
            Button {
                onDismiss()
            } label: {
                Text(NSLocalizedString("upgrade.continueFree", comment: "Continue with free"))
                    .font(.subheadline)
                    .foregroundColor(themeManager.secondaryText)
            }
        default:
            EmptyView()
        }
    }
}
