//
//  GuestConversionView.swift
//  StudyAI
//

import SwiftUI

struct GuestConversionView: View {
    let blockedFeature: String?
    let onDismiss: () -> Void

    @State private var showingSignUp   = false
    @State private var showingLogin    = false
    @State private var loginSucceeded  = false
    @StateObject private var themeManager = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private let accentBlue = Color(hex: "7EC8E3")
    private let cardBg     = Color(.systemBackground)
    private let pageBg     = Color(.systemGroupedBackground)

    // Column widths — guest col is narrower, free col wider for the longer header
    private let guestColW: CGFloat = 76
    private let freeColW:  CGFloat = 100

    private struct BenefitRow: Identifiable {
        let id = UUID()
        let icon: String
        let labelKey: String
        let guestValue: String   // "3", "✗", "—"
        let freeValue: String    // "10", "✓", "30"
        let featureKey: String
    }

    // 9 rows — quota + unlocked features + persistence features
    private let rows: [BenefitRow] = [
        BenefitRow(icon: "camera.fill",              labelKey: "guestConversion.homework",  guestValue: "3",  freeValue: "10", featureKey: "homework_single"),
        BenefitRow(icon: "message.fill",             labelKey: "guestConversion.chat",      guestValue: "10", freeValue: "50", featureKey: "chat_messages"),
        BenefitRow(icon: "pencil.and.list.clipboard",labelKey: "guestConversion.practice",  guestValue: "—",  freeValue: "30", featureKey: "questions"),
        BenefitRow(icon: "chart.bar.doc.horizontal", labelKey: "guestConversion.analysis",  guestValue: "—",  freeValue: "5",  featureKey: "error_analysis"),
        BenefitRow(icon: "brain.head.profile",       labelKey: "guestConversion.weakness",  guestValue: "✗",  freeValue: "✓",  featureKey: "weakness_tracking"),
        BenefitRow(icon: "icloud.and.arrow.up",      labelKey: "guestConversion.save",      guestValue: "✗",  freeValue: "✓",  featureKey: "save_progress"),
        BenefitRow(icon: "books.vertical",           labelKey: "guestConversion.library",   guestValue: "✗",  freeValue: "✓",  featureKey: "library"),
        BenefitRow(icon: "clock.arrow.circlepath",   labelKey: "guestConversion.history",   guestValue: "✗",  freeValue: "✓",  featureKey: "history"),
        BenefitRow(icon: "flame.fill",               labelKey: "guestConversion.streak",    guestValue: "✗",  freeValue: "✓",  featureKey: "streak"),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            pageBg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    benefitTable
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                    ctaSection
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 36)
                }
            }

            // Dismiss — top-left, same style as UpgradeComparisonView
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(white: colorScheme == .dark ? 1.0 : 0.0, opacity: 0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.leading, 20)
        }
        .sheet(isPresented: $showingSignUp) {
            ModernSignUpView(
                onSignUpSuccess: { showingSignUp = false; onDismiss() },
                conversionMode: true
            )
        }
        .sheet(isPresented: $showingLogin) {
            ModernLoginView(onLoginSuccess: {
                // 1. Close the login sheet
                showingLogin = false
                // 2. After the sheet dismiss animation completes, show success banner
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        loginSucceeded = true
                    }
                    // 3. Auto-dismiss GuestConversionView after user sees the success state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        onDismiss()
                    }
                }
            })
        }
        .overlay(alignment: .top) {
            if loginSucceeded {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                    Text(NSLocalizedString("guestConversion.loginSuccess", value: "Signed in successfully!", comment: ""))
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.green)
                .cornerRadius(14)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 52)

            ZStack {
                Circle()
                    .fill(accentBlue.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(accentBlue)
            }
            .padding(.bottom, 4)

            Text(NSLocalizedString("guestConversion.title", comment: ""))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("guestConversion.subtitle", comment: ""))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Benefit Table

    private var benefitTable: some View {
        VStack(spacing: 0) {
            columnHeaderRow
            Divider().padding(.horizontal, 4)
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                dataRow(row: row, idx: idx)
                if idx < rows.count - 1 {
                    Divider().padding(.horizontal, 4).opacity(0.3)
                }
            }
        }
        .background(cardBg)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 3)
    }

    // Column header row — feature col grows, each value col uses fixed width
    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            // Feature name spacer
            Spacer()

            // Guest column header
            Text(NSLocalizedString("guestConversion.guestCol", comment: ""))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: guestColW, alignment: .center)

            // Free column header — highlighted
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(accentBlue.opacity(0.12))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                Text(NSLocalizedString("guestConversion.freeCol", comment: ""))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(accentBlue)
            }
            .frame(width: freeColW)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func dataRow(row: BenefitRow, idx: Int) -> some View {
        let isHighlighted = row.featureKey == blockedFeature
        return HStack(spacing: 0) {
            // Feature label
            HStack(spacing: 8) {
                Image(systemName: row.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isHighlighted ? accentBlue : .secondary)
                    .frame(width: 20, alignment: .center)
                Text(NSLocalizedString(row.labelKey, comment: ""))
                    .font(.system(size: 13, weight: isHighlighted ? .semibold : .regular))
                    .foregroundColor(isHighlighted ? accentBlue : .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Guest value
            valueCell(row.guestValue, isGuest: true, highlighted: false)
                .frame(width: guestColW, alignment: .center)

            // Free value
            valueCell(row.freeValue, isGuest: false, highlighted: isHighlighted)
                .frame(width: freeColW, alignment: .center)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(idx % 2 == 1 ? Color(.systemFill).opacity(0.2) : Color.clear)
    }

    @ViewBuilder
    private func valueCell(_ value: String, isGuest: Bool, highlighted: Bool) -> some View {
        switch value {
        case "✓":
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(accentBlue)
        case "✗":
            Image(systemName: "xmark.circle")
                .font(.system(size: 15))
                .foregroundColor(Color(.systemGray3))
        case "—":
            Text("—")
                .font(.system(size: 13))
                .foregroundColor(Color(.systemGray3))
        default:
            // Numeric: "3", "10", etc.
            VStack(spacing: 1) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(highlighted ? accentBlue : (isGuest ? .secondary : accentBlue))
                Text(isGuest
                     ? NSLocalizedString("guestConversion.lifetime", comment: "")
                     : NSLocalizedString("guestConversion.perMonth", comment: ""))
                    .font(.system(size: 10))
                    .foregroundColor(isGuest ? Color(.systemGray3) : accentBlue.opacity(0.7))
            }
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button(action: { showingSignUp = true }) {
                Text(NSLocalizedString("guestConversion.createAccount", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(accentBlue)
                    .cornerRadius(14)
                    .shadow(color: accentBlue.opacity(0.35), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            Button(action: { showingLogin = true }) {
                Text(NSLocalizedString("guestConversion.signIn", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(accentBlue)
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Text(NSLocalizedString("guestConversion.continueGuest", comment: ""))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }
}
