//
//  HomeworkOnboardingOverlay.swift
//  StudyAI
//
//  4-step spotlight tutorial overlay for DigitalHomeworkView.
//  Reuses SpotlightWindowOverlay + SpotlightWindow from ChatOnboardingOverlay.
//

import SwiftUI
import UIKit

// MARK: - Onboarding Steps

enum HomeworkOnboardingStep: Int, CaseIterable {
    case editImage    = 0
    case gradingMode  = 1
    case reparse      = 2
    case moreOptions  = 3

    var isLast: Bool { rawValue == HomeworkOnboardingStep.allCases.count - 1 }

    var anchorID: String {
        switch self {
        case .editImage:    return "hw_onboarding_editImage"
        case .gradingMode:  return "hw_onboarding_gradingMode"
        case .reparse:      return "hw_onboarding_reparse"
        case .moreOptions:  return "hw_onboarding_moreOptions"
        }
    }

    var title: String {
        switch self {
        case .editImage:
            return NSLocalizedString("hwOnboarding.editImage.title",
                value: "Edit Image", comment: "")
        case .gradingMode:
            return NSLocalizedString("hwOnboarding.gradingMode.title",
                value: "Grading Mode", comment: "")
        case .reparse:
            return NSLocalizedString("hwOnboarding.reparse.title",
                value: "Re-analyze", comment: "")
        case .moreOptions:
            return NSLocalizedString("hwOnboarding.moreOptions.title",
                value: "More Options", comment: "")
        }
    }

    var description: String {
        switch self {
        case .editImage:
            return NSLocalizedString("hwOnboarding.editImage.desc",
                value: "1. Tap the shaking photo icon to select a question's image\n2. Tap the Edit Image section or the image to edit the selected crop",
                comment: "")
        case .gradingMode:
            return NSLocalizedString("hwOnboarding.gradingMode.desc",
                value: "Fast mode for quick grading. Deep mode uses extended thinking \u{2014} more accurate for complex problems.",
                comment: "")
        case .reparse:
            return NSLocalizedString("hwOnboarding.reparse.desc",
                value: "Tap to re-parse this question from the image if the AI misread something.",
                comment: "")
        case .moreOptions:
            return NSLocalizedString("hwOnboarding.moreOptions.desc",
                value: "View the original image, reset annotations, delete questions, or replay this tutorial.",
                comment: "")
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .editImage:    return 12
        case .gradingMode:  return 12
        case .reparse:      return 14
        case .moreOptions:  return 20
        }
    }

    /// Whether this step targets a toolbar item (above safe area).
    var isToolbarStep: Bool {
        switch self {
        case .moreOptions: return true
        default: return false
        }
    }
}

// MARK: - PreferenceKey (anchor capture)

struct HomeworkOnboardingAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func hwOnboardingAnchor(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: HomeworkOnboardingAnchorKey.self,
                                value: [id: geo.frame(in: .global)])
            }
        )
    }
}

// MARK: - UIKit sync (local to this overlay)

private struct CardSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private struct HWUIKitSyncKey: PreferenceKey {
    static var defaultValue = UIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )
    static func reduce(value: inout UIKitSyncData, nextValue: () -> UIKitSyncData) {
        value = nextValue()
    }
}

// MARK: - Main Overlay View

struct HomeworkOnboardingOverlayView: View {
    let step: HomeworkOnboardingStep
    let anchors: [String: CGRect]
    let onNext: () -> Void
    let onSkip: () -> Void

    @StateObject private var themeManager = ThemeManager.shared
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.85
    @State private var measuredCardSize: CGSize = CGSize(width: 290, height: 170)
    @State private var cachedSyncData: UIKitSyncData = UIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )

    var body: some View {
        GeometryReader { geo in
            let sRect = spotlightRect(in: geo)
            let cPos  = cardPosition(in: geo, spotlightRect: sRect)
            let cW: CGFloat = 290
            let cH: CGFloat = measuredCardSize.height
            let cRect = CGRect(x: cPos.x - cW / 2, y: cPos.y - cH / 2,
                               width: cW, height: cH)

            ZStack {
                // Tap-through layer
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
            .preference(key: HWUIKitSyncKey.self, value: UIKitSyncData(
                spotlightRect: sRect,
                cardRect: cRect,
                spotlightRadius: step.spotlightCornerRadius
            ))
        }
        .ignoresSafeArea()
        .onPreferenceChange(CardSizeKey.self) { size in
            if size != .zero { measuredCardSize = size }
        }
        .onPreferenceChange(HWUIKitSyncKey.self) { data in
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
            // Reset pulse for new step
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
        let pad: CGFloat = 8
        let raw = anchors[step.anchorID] ?? .zero
        guard !raw.isEmpty else {
            return toolbarFallback(for: step, screenWidth: geo.size.width)
        }
        return raw.insetBy(dx: -pad, dy: -pad)
    }

    private func toolbarFallback(for step: HomeworkOnboardingStep, screenWidth w: CGFloat) -> CGRect {
        guard step == .moreOptions else { return .zero }
        let safeTop = SpotlightWindow.safeAreaTop()
        let navY: CGFloat = safeTop + 2
        let btnH: CGFloat = 40
        return CGRect(x: w - 65, y: navY, width: 44, height: btnH)
    }

    // MARK: - Card position

    private func cardPosition(in geo: GeometryProxy, spotlightRect rect: CGRect) -> CGPoint {
        let cardW: CGFloat = 290
        let cardH: CGFloat = 170
        let margin: CGFloat = 16
        let gap: CGFloat = 14

        let safeTop    = SpotlightWindow.safeAreaTop()
        let safeBottom = SpotlightWindow.safeAreaBottom()
        let screenW    = geo.size.width
        let screenH    = geo.size.height
        let navBottom  = safeTop + 44.0

        if rect.isEmpty {
            return CGPoint(x: screenW / 2, y: screenH / 2)
        }

        // Decide: place card below or above the spotlight
        let spaceBelow = screenH - safeBottom - rect.maxY
        let spaceAbove = rect.minY - navBottom

        var y: CGFloat
        if step.isToolbarStep {
            // Below toolbar
            y = navBottom + gap + cardH / 2
        } else if spaceBelow >= cardH + gap + margin {
            // Below spotlight
            y = rect.maxY + gap + cardH / 2
        } else if spaceAbove >= cardH + gap + margin {
            // Above spotlight
            y = rect.minY - gap - cardH / 2
        } else {
            // Center on screen
            y = screenH / 2
        }

        var x = rect.midX
        x = max(cardW / 2 + margin, min(x, screenW - cardW / 2 - margin))
        y = max(safeTop + cardH / 2 + margin, min(y, screenH - safeBottom - cardH / 2 - margin))

        return CGPoint(x: x, y: y)
    }

    // MARK: - Step description with inline SF Symbols

    @ViewBuilder
    private var stepDescriptionView: some View {
        if step == .editImage {
            VStack(alignment: .leading, spacing: 3) {
                (Text("1. Tap the shaking ")
                 + Text(Image(systemName: "photo.on.rectangle.angled"))
                 + Text(" icon to select a question's image"))
                (Text("2. Tap the Edit Image section or the image to edit the selected crop"))
            }
        } else {
            Text(step.description)
        }
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
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(red: 0, green: 0, blue: 0))
                    stepDescriptionView
                        .font(.system(size: 13, weight: .medium))
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
                    ForEach(0..<HomeworkOnboardingStep.allCases.count, id: \.self) { i in
                        Circle()
                            .fill(i == step.rawValue
                                  ? DesignTokens.Colors.Cute.peach
                                  : Color(red: 0.4, green: 0.4, blue: 0.4))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    Text(step.isLast
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
        .background(Color.white)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 5)
        .overlay(
            GeometryReader { cardGeo in
                Color.clear
                    .preference(key: CardSizeKey.self, value: cardGeo.size)
            }
        )
    }
}
