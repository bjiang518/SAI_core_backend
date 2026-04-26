//
//  PracticeLibraryOnboardingOverlay.swift
//  StudyAI
//
//  5-step spotlight tutorial for PracticeLibraryView + NewPracticeSheet.
//  Steps 0-3 run on the library; step 4 runs inside the sheet.
//  Reuses SpotlightWindowOverlay + SpotlightWindow from ChatOnboardingOverlay.
//

import SwiftUI
import UIKit

// MARK: - Onboarding Steps

enum PracticeLibOnboardingStep: Int, CaseIterable {
    // Library steps (0-3)
    case newButton       = 0
    case subjectFilter   = 1
    case sortAndStatus   = 2
    case swipeToDelete   = 3
    // Sheet steps (4-7)
    case randomPractice  = 4
    case archivePractice = 5
    case questionConfig  = 6
    case difficultyBar   = 7

    var anchorID: String {
        switch self {
        case .newButton:       return "practice_lib_onboarding_newBtn"
        case .subjectFilter:   return "practice_lib_onboarding_subjectFilter"
        case .sortAndStatus:   return "practice_lib_onboarding_statusFilter"
        case .swipeToDelete:   return "practice_lib_onboarding_sessionCard"
        case .randomPractice:  return "practice_sheet_onboarding_randomPractice"
        case .archivePractice: return "practice_sheet_onboarding_archivePractice"
        case .questionConfig:  return "practice_sheet_onboarding_questionConfig"
        case .difficultyBar:   return "practice_sheet_onboarding_difficultyBar"
        }
    }

    var title: String {
        switch self {
        case .newButton:
            return NSLocalizedString("practiceLibOnboarding.newBtn.title",
                value: "Create Your First Practice", comment: "")
        case .subjectFilter:
            return NSLocalizedString("practiceLibOnboarding.subjectFilter.title",
                value: "Filter by Subject", comment: "")
        case .sortAndStatus:
            return NSLocalizedString("practiceLibOnboarding.sortStatus.title",
                value: "Sort & Filter", comment: "")
        case .swipeToDelete:
            return NSLocalizedString("practiceLibOnboarding.swipeDelete.title",
                value: "Delete a Session", comment: "")
        case .randomPractice:
            return NSLocalizedString("practiceSheetOnboarding.random.title",
                value: "Random Practice", comment: "")
        case .archivePractice:
            return NSLocalizedString("practiceSheetOnboarding.archive.title",
                value: "From Archives", comment: "")
        case .questionConfig:
            return NSLocalizedString("practiceSheetOnboarding.config.title",
                value: "Customize Questions", comment: "")
        case .difficultyBar:
            return NSLocalizedString("practiceSheetOnboarding.difficulty.title",
                value: "Choose Your Difficulty", comment: "")
        }
    }

    var description: String {
        switch self {
        case .newButton:
            return NSLocalizedString("practiceLibOnboarding.newBtn.desc",
                value: "Tap + New to generate a custom practice set. Choose your subject, difficulty, and question type.",
                comment: "")
        case .subjectFilter:
            return NSLocalizedString("practiceLibOnboarding.subjectFilter.desc",
                value: "Tap a subject to filter your sessions. Subjects appear here automatically as you practice.",
                comment: "")
        case .sortAndStatus:
            return NSLocalizedString("practiceLibOnboarding.sortStatus.desc",
                value: "Switch between All, Ongoing, and Completed. Use the sort menu on the right to reorder.",
                comment: "")
        case .swipeToDelete:
            return NSLocalizedString("practiceLibOnboarding.swipeDelete.desc",
                value: "Swipe any session card to the left to delete it.",
                comment: "")
        case .randomPractice:
            return NSLocalizedString("practiceSheetOnboarding.random.desc",
                value: "Generate random questions based on your learning progress and weaknesses. The AI adapts to your level.",
                comment: "")
        case .archivePractice:
            return NSLocalizedString("practiceSheetOnboarding.archive.desc",
                value: "Generate questions from your archived conversations or saved questions. Great for targeted review.",
                comment: "")
        case .questionConfig:
            return NSLocalizedString("practiceSheetOnboarding.config.desc",
                value: "Choose how many questions to generate (1\u{2013}10) and pick a question type: multiple choice, true/false, short answer, or any.",
                comment: "")
        case .difficultyBar:
            return NSLocalizedString("practiceSheetOnboarding.difficulty.desc",
                value: "Drag anywhere on the bar. Drag past the end for Adaptive mode \u{2014} the AI picks the right level for you.",
                comment: "")
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .newButton:       return 12
        case .subjectFilter:   return 14
        case .sortAndStatus:   return 12
        case .swipeToDelete:   return 16
        case .randomPractice:  return 16
        case .archivePractice: return 16
        case .questionConfig:  return 16
        case .difficultyBar:   return 12
        }
    }

    var isToolbarStep: Bool {
        self == .newButton
    }

    /// Whether this step belongs to the NewPracticeSheet (not the library).
    var isSheetStep: Bool {
        rawValue >= 4
    }

    /// Steps shown inside the NewPracticeSheet.
    static var sheetSteps: [PracticeLibOnboardingStep] {
        [.randomPractice, .archivePractice, .questionConfig, .difficultyBar]
    }
}

// MARK: - PreferenceKey (anchor capture)

struct PracticeLibOnboardingAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func practiceLibOnboardingAnchor(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: PracticeLibOnboardingAnchorKey.self,
                                value: [id: geo.frame(in: .global)])
            }
        )
    }
}

// MARK: - UIKit sync (local to this overlay)

private struct PLOnboardingUIKitSyncKey: PreferenceKey {
    static var defaultValue = UIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )
    static func reduce(value: inout UIKitSyncData, nextValue: () -> UIKitSyncData) {
        value = nextValue()
    }
}

// MARK: - Main Overlay View

struct PracticeLibOnboardingOverlayView: View {
    let step: PracticeLibOnboardingStep
    let anchors: [String: CGRect]
    let totalSteps: Int
    let onNext: () -> Void
    let onSkip: () -> Void
    /// When true, renders a SwiftUI-only dark overlay instead of using
    /// the UIKit SpotlightWindow. Required inside .sheet() presentations
    /// where UIKit window coordinates don't align with SwiftUI positions.
    var useSwiftUIScrim: Bool = false

    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.85
    @State private var cachedSyncData: UIKitSyncData = UIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )

    /// For library steps (0-3), the dot index is the rawValue.
    /// For sheet steps (4-7), offset by 4 so dots start at 0.
    private var dotIndex: Int {
        if step.isSheetStep { return step.rawValue - 4 }
        return step.rawValue
    }

    /// Whether this is the last step in the current context.
    private var isLastInContext: Bool {
        return dotIndex >= totalSteps - 1
    }

    var body: some View {
        GeometryReader { geo in
            let sRect = spotlightRect(in: geo)
            let cPos  = cardPosition(in: geo, spotlightRect: sRect)
            let cW: CGFloat = 290
            let cH: CGFloat = 170
            let cRect = CGRect(x: cPos.x - cW / 2, y: cPos.y - cH / 2,
                               width: cW, height: cH)

            ZStack {
                if useSwiftUIScrim {
                    // SwiftUI-only dark scrim with cutouts (for sheet context)
                    swiftUIScrim(spotlight: sRect, card: cRect, in: geo)
                } else {
                    // Invisible tap layer — UIKit SpotlightWindow handles the dark overlay
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { onNext() }
                }

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
            .preference(key: PLOnboardingUIKitSyncKey.self, value: UIKitSyncData(
                spotlightRect: sRect,
                cardRect: cRect,
                spotlightRadius: step.spotlightCornerRadius
            ))
        }
        .ignoresSafeArea()
        .onPreferenceChange(PLOnboardingUIKitSyncKey.self) { data in
            cachedSyncData = data
            guard !useSwiftUIScrim else { return }
            if SpotlightWindow.isShowing {
                SpotlightWindow.update(data: data)
            } else {
                SpotlightWindow.show(data: data)
            }
        }
        .onDisappear {
            if !useSwiftUIScrim { SpotlightWindow.hide() }
        }
        .onAppear {
            if !useSwiftUIScrim, !SpotlightWindow.isShowing, !cachedSyncData.spotlightRect.isEmpty {
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

    // MARK: - SwiftUI-only scrim (for sheet context)

    @ViewBuilder
    private func swiftUIScrim(spotlight sRect: CGRect, card cRect: CGRect, in geo: GeometryProxy) -> some View {
        Canvas { ctx, size in
            // Dark fill
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(.black.opacity(0.65)))
            // Punch spotlight hole
            if !sRect.isEmpty {
                ctx.blendMode = .clear
                let spotPath = Path(roundedRect: sRect,
                                    cornerRadius: step.spotlightCornerRadius)
                ctx.fill(spotPath, with: .color(.white))
            }
            // Punch card hole
            if !cRect.isEmpty {
                ctx.blendMode = .clear
                let cardPath = Path(roundedRect: cRect, cornerRadius: 18)
                ctx.fill(cardPath, with: .color(.white))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .contentShape(Rectangle())
        .onTapGesture { onNext() }
    }

    // MARK: - Spotlight rect

    private func spotlightRect(in geo: GeometryProxy) -> CGRect {
        let raw = anchors[step.anchorID] ?? .zero
        guard !raw.isEmpty else {
            return toolbarFallback(for: step, screenWidth: geo.size.width)
        }
        if useSwiftUIScrim {
            // Convert global coords to local GeometryReader coords
            let origin = geo.frame(in: .global).origin
            let local = CGRect(
                x: raw.minX - origin.x,
                y: raw.minY - origin.y,
                width: raw.width,
                height: raw.height
            )
            return local
        }
        return raw
    }

    private func toolbarFallback(for step: PracticeLibOnboardingStep, screenWidth w: CGFloat) -> CGRect {
        guard step == .newButton else { return .zero }
        let safeTop = SpotlightWindow.safeAreaTop()
        let navY: CGFloat = safeTop + 2
        let btnH: CGFloat = 40
        // "+ New" button is trailing, roughly 80pt from right edge
        return CGRect(x: w - 90, y: navY, width: 72, height: btnH)
    }

    // MARK: - Card position

    private func cardPosition(in geo: GeometryProxy, spotlightRect rect: CGRect) -> CGPoint {
        let cardW: CGFloat = 290
        let cardH: CGFloat = 170
        let margin: CGFloat = 16
        let gap: CGFloat = 14

        let screenW = geo.size.width
        let screenH = geo.size.height

        let safeTop: CGFloat
        let safeBottom: CGFloat
        let navBottom: CGFloat

        if useSwiftUIScrim {
            // In sheet context, use local coordinates (0-based)
            safeTop    = geo.safeAreaInsets.top
            safeBottom = geo.safeAreaInsets.bottom
            navBottom  = safeTop + 44.0
        } else {
            safeTop    = SpotlightWindow.safeAreaTop()
            safeBottom = SpotlightWindow.safeAreaBottom()
            navBottom  = safeTop + 44.0
        }

        if rect.isEmpty {
            return CGPoint(x: screenW / 2, y: screenH / 2)
        }

        let spaceBelow = screenH - safeBottom - rect.maxY
        let spaceAbove = rect.minY - navBottom

        var y: CGFloat
        if step.isToolbarStep {
            y = navBottom + gap + cardH / 2
        } else if spaceBelow >= cardH + gap + margin {
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
                            .fill(i == dotIndex
                                  ? DesignTokens.Colors.Cute.peach
                                  : Color(red: 0.4, green: 0.4, blue: 0.4))
                            .frame(width: 6, height: 6)
                    }
                }

                Spacer()

                Button(action: onNext) {
                    Text(isLastInContext
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
