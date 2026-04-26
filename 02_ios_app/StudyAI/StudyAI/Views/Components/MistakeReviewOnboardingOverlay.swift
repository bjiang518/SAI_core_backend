//
//  MistakeReviewOnboardingOverlay.swift
//  StudyAI
//
//  5-step spotlight tutorial for MistakeReviewView.
//  Reuses SpotlightWindowOverlay + SpotlightWindow from ChatOnboardingOverlay.
//

import SwiftUI
import UIKit

// MARK: - Onboarding Steps

enum MistakeReviewOnboardingStep: Int, CaseIterable {
    case subjectSelector = 0
    case activeFilter    = 1
    case heatmap         = 2
    case taxonomy        = 3
    case startReview     = 4

    var anchorID: String {
        switch self {
        case .subjectSelector: return "mistake_review_onboarding_subjectSelector"
        case .activeFilter:    return "mistake_review_onboarding_activeFilter"
        case .heatmap:         return "mistake_review_onboarding_heatmap"
        case .taxonomy:        return "mistake_review_onboarding_taxonomy"
        case .startReview:     return "mistake_review_onboarding_startReview"
        }
    }

    var title: String {
        switch self {
        case .subjectSelector:
            return NSLocalizedString("mistakeReviewOnboarding.subject.title",
                value: "Choose a Subject", comment: "")
        case .activeFilter:
            return NSLocalizedString("mistakeReviewOnboarding.activeFilter.title",
                value: "Track Your Progress", comment: "")
        case .heatmap:
            return NSLocalizedString("mistakeReviewOnboarding.heatmap.title",
                value: "Weakness Heatmap", comment: "")
        case .taxonomy:
            return NSLocalizedString("mistakeReviewOnboarding.taxonomy.title",
                value: "Drill Into Topics", comment: "")
        case .startReview:
            return NSLocalizedString("mistakeReviewOnboarding.startReview.title",
                value: "Start Targeted Practice", comment: "")
        }
    }

    var description: String {
        switch self {
        case .subjectSelector:
            return NSLocalizedString("mistakeReviewOnboarding.subject.desc",
                value: "Select a subject to see your mistakes. The badge shows how many weak points need attention.",
                comment: "")
        case .activeFilter:
            return NSLocalizedString("mistakeReviewOnboarding.activeFilter.desc",
                value: "Active shows current weaknesses. Good At shows topics you\u{2019}ve mastered \u{2014} weaknesses you\u{2019}ve turned into strengths!",
                comment: "")
        case .heatmap:
            return NSLocalizedString("mistakeReviewOnboarding.heatmap.desc",
                value: "Inner arcs show your weakest topics. As you practice and improve, they move outward and turn green.",
                comment: "")
        case .taxonomy:
            return NSLocalizedString("mistakeReviewOnboarding.taxonomy.desc",
                value: "Tap a topic to expand it. Select specific concepts to focus your review on exactly what you need.",
                comment: "")
        case .startReview:
            return NSLocalizedString("mistakeReviewOnboarding.startReview.desc",
                value: "Tap to review your mistakes and generate practice questions. Turn your weaknesses into strengths!",
                comment: "")
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .subjectSelector: return 14
        case .activeFilter:    return 10
        case .heatmap:         return 16
        case .taxonomy:        return 16
        case .startReview:     return 12
        }
    }

    var isToolbarStep: Bool { false }

    /// Steps 2-4 require a subject to be selected (they're conditionally visible).
    var requiresSubject: Bool {
        rawValue >= 2
    }
}

// MARK: - PreferenceKey (anchor capture)

struct MistakeReviewOnboardingAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func mistakeReviewOnboardingAnchor(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: MistakeReviewOnboardingAnchorKey.self,
                                value: [id: geo.frame(in: .global)])
            }
        )
    }
}

// MARK: - UIKit sync (local to this overlay)

private struct MROnboardingUIKitSyncKey: PreferenceKey {
    static var defaultValue = UIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )
    static func reduce(value: inout UIKitSyncData, nextValue: () -> UIKitSyncData) {
        value = nextValue()
    }
}

// MARK: - Main Overlay View

struct MistakeReviewOnboardingOverlayView: View {
    let step: MistakeReviewOnboardingStep
    let anchors: [String: CGRect]
    let totalSteps: Int
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.85
    @State private var cachedSyncData: UIKitSyncData = UIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )

    var body: some View {
        GeometryReader { geo in
            let sRect = spotlightRect(in: geo)
            let cPos  = cardPosition(in: geo, spotlightRect: sRect)
            let cW: CGFloat = 290
            let cH: CGFloat = 170
            let cRect = CGRect(x: cPos.x - cW / 2, y: cPos.y - cH / 2,
                               width: cW, height: cH)

            ZStack {
                // Invisible tap layer — UIKit SpotlightWindow handles the dark overlay
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onNext() }

                // Pulsing ring around spotlight target
                if !sRect.isEmpty {
                    RoundedRectangle(cornerRadius: step.spotlightCornerRadius)
                        .strokeBorder(
                            DesignTokens.Colors.Cute.peach.opacity(pulseOpacity),
                            lineWidth: 2.5
                        )
                        .frame(width: sRect.width, height: sRect.height)
                        .scaleEffect(pulseScale)
                        .position(x: sRect.midX, y: sRect.midY)
                        .allowsHitTesting(false)
                }

                // Callout card
                calloutCard
                    .frame(width: cW)
                    .position(cPos)
            }
            .preference(key: MROnboardingUIKitSyncKey.self, value: UIKitSyncData(
                spotlightRect: sRect,
                cardRect: cRect,
                spotlightRadius: step.spotlightCornerRadius
            ))
        }
        .ignoresSafeArea()
        .onPreferenceChange(MROnboardingUIKitSyncKey.self) { data in
            cachedSyncData = data
            if SpotlightWindow.isShowing {
                SpotlightWindow.update(data: data)
            } else {
                SpotlightWindow.show(data: data)
            }
        }
        .onDisappear {
            SpotlightWindow.hide()
        }
        .onAppear {
            if !SpotlightWindow.isShowing, !cachedSyncData.spotlightRect.isEmpty {
                SpotlightWindow.show(data: cachedSyncData)
            }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseScale   = 1.10
                pulseOpacity = 0.30
            }
        }
        .onChange(of: step) { _ in
            pulseScale   = 1.0
            pulseOpacity = 0.85
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseScale   = 1.10
                pulseOpacity = 0.30
            }
        }
    }

    // MARK: - Spotlight rect

    private func spotlightRect(in geo: GeometryProxy) -> CGRect {
        let raw = anchors[step.anchorID] ?? .zero
        guard !raw.isEmpty else { return .zero }
        return raw
    }

    // MARK: - Card position

    private func cardPosition(in geo: GeometryProxy, spotlightRect rect: CGRect) -> CGPoint {
        let cardW: CGFloat = 290
        let cardH: CGFloat = 170
        let margin: CGFloat = 16
        let gap: CGFloat = 14

        let screenW = geo.size.width
        let screenH = geo.size.height

        let safeTop    = SpotlightWindow.safeAreaTop()
        let safeBottom = SpotlightWindow.safeAreaBottom()
        let navBottom  = safeTop + 44.0

        if rect.isEmpty {
            return CGPoint(x: screenW / 2, y: screenH / 2)
        }

        let spaceBelow = screenH - safeBottom - rect.maxY
        let spaceAbove = rect.minY - navBottom

        var y: CGFloat
        if spaceBelow >= cardH + gap + margin {
            y = rect.maxY + gap + cardH / 2
        } else if spaceAbove >= cardH + gap + margin {
            y = rect.minY - gap - cardH / 2
        } else {
            y = screenH / 2
        }

        var x = rect.midX
        x = max(cardW / 2 + margin, min(x, screenW - cardW / 2 - margin))
        y = max(cardH / 2 + margin, min(y, screenH - safeBottom - cardH / 2 - margin))

        return CGPoint(x: x, y: y)
    }

    // MARK: - Callout card

    @ViewBuilder
    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(DesignTokens.Colors.Cute.peach)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    Text(step.description)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 8)

            HStack {
                Button(action: onSkip) {
                    Text(NSLocalizedString("onboarding.skip", value: "Skip", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                        .padding(.vertical, 8)
                }

                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == step.rawValue
                                  ? DesignTokens.Colors.Cute.peach
                                  : Color(red: 0.4, green: 0.4, blue: 0.4))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    Text(step.rawValue >= totalSteps - 1
                         ? NSLocalizedString("onboarding.done", value: "Done", comment: "")
                         : NSLocalizedString("onboarding.next", value: "Next", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(DesignTokens.Colors.Cute.peach)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 5)
        )
    }
}
