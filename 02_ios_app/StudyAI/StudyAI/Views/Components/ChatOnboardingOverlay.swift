//
//  ChatOnboardingOverlay.swift
//  StudyAI
//
//  AI avatar-guided onboarding for SessionChatView.
//
//  Architecture:
//  The dark scrim is a UIView added directly to UIWindow (SpotlightWindowOverlay).
//  This renders above the UIKit navigation bar, so toolbar buttons are properly
//  dimmed in non-target steps. The scrim punches two transparent holes:
//    1. The spotlight cutout at the target button.
//    2. A cutout at the callout card position, so the SwiftUI card is visible.
//
//  Sync: rects are computed during the SwiftUI render pass and propagated via
//  UIKitSyncKey (PreferenceKey → onPreferenceChange). This guarantees the UIKit
//  overlay always reflects the CURRENT step with zero lag.
//

import SwiftUI
import UIKit

// MARK: - Onboarding Steps

enum ChatOnboardingStep: Int, CaseIterable {
    case subjectPicker  = 0
    case cameraButton   = 1
    case deepMode       = 2
    case micButton      = 3
    case liveMode       = 4
    case libraryButton  = 5

    var isLast: Bool { rawValue == ChatOnboardingStep.allCases.count - 1 }

    var anchorID: String? {
        switch self {
        case .subjectPicker:  return "onboarding_subjectPicker"
        case .cameraButton:   return "onboarding_cameraButton"
        case .deepMode:       return "onboarding_inputField"
        case .micButton:      return "onboarding_micButton"
        case .liveMode:       return nil
        case .libraryButton:  return nil
        }
    }

    var isToolbarStep: Bool {
        switch self {
        case .subjectPicker, .liveMode, .libraryButton: return true
        case .cameraButton, .deepMode, .micButton:      return false
        }
    }

    var title: String {
        switch self {
        case .subjectPicker:
            return NSLocalizedString("onboarding.chat.subject.title",
                value: "Choose a Subject", comment: "")
        case .cameraButton:
            return NSLocalizedString("onboarding.chat.camera.title",
                value: "Add Images", comment: "")
        case .deepMode:
            return NSLocalizedString("onboarding.chat.deepmode.title",
                value: "Send or Go Deeper", comment: "")
        case .micButton:
            return NSLocalizedString("onboarding.chat.mic.title",
                value: "Voice Input", comment: "")
        case .liveMode:
            return NSLocalizedString("onboarding.chat.live.title",
                value: "Live Mode & More", comment: "")
        case .libraryButton:
            return NSLocalizedString("onboarding.chat.library.title",
                value: "Save to Library", comment: "")
        }
    }

    var description: String {
        switch self {
        case .subjectPicker:
            return NSLocalizedString("onboarding.chat.subject.desc",
                value: "Select a subject or leave it as General. This helps me give you more accurate answers.",
                comment: "")
        case .cameraButton:
            return NSLocalizedString("onboarding.chat.camera.desc",
                value: "Tap to take a photo or pick one from your gallery. I can read homework questions from images.",
                comment: "")
        case .deepMode:
            return NSLocalizedString("onboarding.chat.deepmode.desc",
                value: "Tap ↑ to send. Or hold the button and swipe up — it turns purple and uses a more thorough reasoning model for hard questions.",
                comment: "")
        case .micButton:
            return NSLocalizedString("onboarding.chat.mic.desc",
                value: "Hold this button to speak instead of typing. Your voice is transcribed automatically.",
                comment: "")
        case .liveMode:
            return NSLocalizedString("onboarding.chat.live.desc",
                value: "Tap ··· to access settings. You can switch to real-time Live Talk voice mode from here.",
                comment: "")
        case .libraryButton:
            return NSLocalizedString("onboarding.chat.library.desc",
                value: "Tap to archive this conversation. I'll analyze it and save key insights to your personal library.",
                comment: "")
        }
    }

    var spotlightCornerRadius: CGFloat {
        switch self {
        case .subjectPicker:                    return 18
        case .cameraButton, .micButton:         return 24
        case .deepMode:                         return 25
        case .liveMode, .libraryButton:         return 24
        }
    }
}

// MARK: - PreferenceKey (anchor capture)

struct ChatOnboardingAnchorKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func chatOnboardingAnchor(_ id: String) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ChatOnboardingAnchorKey.self,
                                value: [id: geo.frame(in: .global)])
            }
        )
    }
}

// MARK: - PreferenceKey (UIKit sync)
//
// Propagates the spotlight rect + card rect from the SwiftUI render pass
// out to onPreferenceChange, which then updates the UIKit overlay.
// This guarantees the overlay is ALWAYS in sync with the current step.

fileprivate struct UIKitSyncData: Equatable {
    var spotlightRect: CGRect
    var cardRect: CGRect
    var spotlightRadius: CGFloat
    var cardRadius: CGFloat = 18
}

fileprivate struct UIKitSyncKey: PreferenceKey {
    static var defaultValue = UIKitSyncData(
        spotlightRect: .zero, cardRect: .zero, spotlightRadius: 18
    )
    static func reduce(value: inout UIKitSyncData, nextValue: () -> UIKitSyncData) {
        value = nextValue()
    }
}

// MARK: - UIKit Window-Level Scrim

/// Drawn directly on UIWindow so it renders above the UIKit navigation bar.
private final class SpotlightWindowOverlay: UIView {
    /// Transparent hole for the target UI element.
    var spotlightRect: CGRect = .zero  { didSet { setNeedsDisplay() } }
    var spotlightRadius: CGFloat = 18  { didSet { setNeedsDisplay() } }
    /// Transparent hole for the callout card so the SwiftUI card shows through.
    var cardRect: CGRect = .zero       { didSet { setNeedsDisplay() } }
    var cardRadius: CGFloat = 18       { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = false  // taps fall through to SwiftUI
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // Solid dark fill
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.60).cgColor)
        ctx.fill(bounds)
        // Hole 1: target button spotlight
        if !spotlightRect.isEmpty {
            ctx.setBlendMode(.clear)
            UIBezierPath(roundedRect: spotlightRect, cornerRadius: spotlightRadius).fill()
        }
        // Hole 2: callout card region so the SwiftUI card is visible
        if !cardRect.isEmpty {
            ctx.setBlendMode(.clear)
            UIBezierPath(roundedRect: cardRect, cornerRadius: cardRadius).fill()
        }
    }
}

/// Manages the singleton UIKit scrim on the key window.
enum SpotlightWindow {
    private static var overlay: SpotlightWindowOverlay?
    static var isShowing: Bool { overlay != nil }

    fileprivate static func show(data: UIKitSyncData) {
        overlay?.removeFromSuperview()
        guard let window = keyWindow() else { return }
        let v = SpotlightWindowOverlay(frame: window.bounds)
        apply(data, to: v)
        window.addSubview(v)
        overlay = v
    }

    fileprivate static func update(data: UIKitSyncData) {
        guard let v = overlay else { show(data: data); return }
        apply(data, to: v)
    }

    static func hide() {
        overlay?.removeFromSuperview()
        overlay = nil
    }

    static func safeAreaTop() -> CGFloat {
        keyWindow()?.safeAreaInsets.top ?? 59
    }

    static func safeAreaBottom() -> CGFloat {
        keyWindow()?.safeAreaInsets.bottom ?? 34
    }

    static func screenSize() -> CGSize {
        keyWindow()?.bounds.size ?? UIScreen.main.bounds.size
    }

    private static func apply(_ data: UIKitSyncData, to v: SpotlightWindowOverlay) {
        v.spotlightRect   = data.spotlightRect
        v.spotlightRadius = data.spotlightRadius
        v.cardRect        = data.cardRect
        v.cardRadius      = data.cardRadius
    }

    fileprivate static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.keyWindow
    }
}

// MARK: - Main Overlay View

struct ChatOnboardingOverlayView: View {
    let step: ChatOnboardingStep
    let anchors: [String: CGRect]
    let voiceType: VoiceType
    let onNext: () -> Void
    let onSkip: () -> Void
    /// Called whenever the visible step changes (including on first appear).
    /// Use this to pre-fill or clear the input field for the deepMode step.
    var onStepChange: ((ChatOnboardingStep) -> Void)? = nil

    @StateObject private var themeManager = ThemeManager.shared
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.85
    // Deep-mode swipe hint animation
    @State private var swipeHintOffset: CGFloat = 0
    @State private var swipeHintOpacity: Double = 0
    // Mic step animation
    @State private var micTranscriptCount: Int = 0
    @State private var micSwipePhase: Int = 0   // 0=idle 1=deep 2=cancel 3=reset

    var body: some View {
        GeometryReader { geo in
            let sRect = spotlightRect(in: geo)
            let cPos  = cardPosition(in: geo, spotlightRect: sRect)
            let cW: CGFloat = step == .micButton ? 310 : 290
            let cH: CGFloat = step == .micButton ? 260 : 155
            let cRect = CGRect(x: cPos.x - cW / 2, y: cPos.y - cH / 2,
                               width: cW, height: cH)

            ZStack {
                // Tap-through layer — UIKit handles actual drawing
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { onNext() }

                // Pulsing ring (SwiftUI — visible for input-bar steps;
                // for toolbar steps it renders below the UIKit nav bar but the
                // UIKit cutout still clearly reveals the button)
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

                // Callout card — wider for micButton to accommodate inline animation
                calloutCard
                    .frame(width: step == .micButton ? 310 : 290)
                    .position(cPos)

                // Deep-mode swipe hint: animated finger swipe up over send button
                if step == .deepMode, !sRect.isEmpty {
                    deepModeSwipeHint(in: geo, spotlightRect: sRect)
                }
            }
            // Propagate current rects out of GeometryReader — fires AFTER render,
            // so UIKit overlay always reflects the step that's on screen right now.
            .preference(key: UIKitSyncKey.self, value: UIKitSyncData(
                spotlightRect: sRect,
                cardRect: cRect,
                spotlightRadius: step.spotlightCornerRadius
            ))
        }
        .ignoresSafeArea()
        .onPreferenceChange(UIKitSyncKey.self) { data in
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
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseScale   = 1.10
                pulseOpacity = 0.30
            }
            onStepChange?(step)
            if step == .deepMode  { startSwipeHintAnimation() }
            if step == .micButton { startMicAnimation() }
        }
        .onChange(of: step) { newStep in
            onStepChange?(newStep)
            if newStep == .deepMode {
                startSwipeHintAnimation()
            } else {
                swipeHintOffset  = 0
                swipeHintOpacity = 0
            }
            if newStep == .micButton {
                startMicAnimation()
            } else {
                micTranscriptCount = 0
                micSwipePhase = 0
            }
        }
    }

    // MARK: - Spotlight rect

    private func spotlightRect(in geo: GeometryProxy) -> CGRect {
        // For deepMode the anchor is on the inner HStack which sits inside
        // .padding(.horizontal, 20) — add 20pt extra to each side to cover the
        // full visible input bar including its background.
        let pad: CGFloat = step == .deepMode ? 28 : 8
        if let id = step.anchorID, let raw = anchors[id], !raw.isEmpty {
            return raw.insetBy(dx: -pad, dy: -pad)
        }
        return toolbarFallback(for: step, screenWidth: geo.size.width)
    }

    /// Pixel-measured positions for toolbar buttons on iPhone 15 Pro (@3x, 393pt wide).
    private func toolbarFallback(for step: ChatOnboardingStep, screenWidth w: CGFloat) -> CGRect {
        let safeTop = SpotlightWindow.safeAreaTop()
        let navY: CGFloat = safeTop + 2
        let btnH: CGFloat = 40
        switch step {
        case .subjectPicker:
            return CGRect(x: 22, y: navY, width: 118, height: btnH)
        case .liveMode:
            // center measured at 290.8pt from left → left edge = 269pt → x = w−124
            return CGRect(x: w - 124, y: navY, width: 44, height: btnH)
        case .libraryButton:
            // center measured at 349.7pt from left → left edge = 328pt → x = w−65
            return CGRect(x: w - 65, y: navY, width: 44, height: btnH)
        default:
            return .zero
        }
    }

    // MARK: - Card position

    private func cardPosition(in geo: GeometryProxy, spotlightRect rect: CGRect) -> CGPoint {
        let cardW: CGFloat = step == .micButton ? 310 : 290
        let cardH: CGFloat = step == .micButton ? 260 : 155
        let toolbarGap: CGFloat = 18
        let inputGap: CGFloat   = 12
        let margin: CGFloat     = 16

        let safeTop    = SpotlightWindow.safeAreaTop()
        let safeBottom = SpotlightWindow.safeAreaBottom()
        let screenW    = geo.size.width
        let screenH    = geo.size.height
        let navBottom  = safeTop + 44.0

        if rect.isEmpty {
            return CGPoint(x: screenW / 2, y: screenH - safeBottom - 220)
        }

        if step.isToolbarStep {
            let y = navBottom + toolbarGap + cardH / 2
            var x: CGFloat
            switch step {
            case .subjectPicker:
                x = max(cardW / 2 + margin, rect.midX + cardW / 3)
            default:
                x = min(rect.midX - cardW / 3, screenW - cardW / 2 - margin)
            }
            x = max(cardW / 2 + margin, min(x, screenW - cardW / 2 - margin))
            return CGPoint(x: x, y: y)
        } else {
            let y = rect.minY - inputGap - cardH / 2
            var x = rect.midX
            if step == .cameraButton {
                x = min(rect.midX + cardW / 3, screenW - cardW / 2 - margin)
            } else if step == .deepMode || step == .micButton {
                // Full-width steps — center the card
                x = screenW / 2
            }
            x = max(cardW / 2 + margin, min(x, screenW - cardW / 2 - margin))
            // Clamp Y so card never overflows below safe area
            let maxY = screenH - safeBottom - cardH / 2 - margin
            return CGPoint(x: x, y: min(maxY, max(safeTop + cardH / 2 + margin, y)))
        }
    }

    // MARK: - Deep-mode swipe hint

    /// Kicks off the looping upward-drift animation for the swipe hint.
    private func startSwipeHintAnimation() {
        swipeHintOffset  = 0
        swipeHintOpacity = 0
        withAnimation(
            .easeInOut(duration: 1.1)
            .repeatForever(autoreverses: false)
            .delay(0.2)
        ) {
            swipeHintOffset  = -70   // drift 70pt upward
            swipeHintOpacity = 1
        }
    }

    /// A mini illustration anchored near the send button: the ↑ send icon drifts
    /// upward and morphs into the purple 🧠 Deep badge, looping continuously.
    @ViewBuilder
    private func deepModeSwipeHint(in geo: GeometryProxy, spotlightRect sRect: CGRect) -> some View {
        // Use the micButton anchor (the send button itself) for precise centering.
        // Fall back to right-of-spotlight estimate only if the anchor is missing.
        let micRect = anchors["onboarding_micButton"] ?? .zero
        let btnCenterX: CGFloat = micRect.isEmpty ? (sRect.maxX - 30) : micRect.midX
        let btnCenterY: CGFloat = micRect.isEmpty ? sRect.midY        : micRect.midY
        let arrowFade: Double = {
            let progress = swipeHintOffset / CGFloat(-40.0)
            return swipeHintOpacity * Double(1.0 - min(CGFloat(1), max(CGFloat(0), progress)))
        }()
        let brainFade: Double = {
            let progress = (-swipeHintOffset - 20.0) / 30.0
            return swipeHintOpacity * Double(min(CGFloat(1), max(CGFloat(0), progress)))
        }()

        ZStack {
            // Phase 1 — send arrow at bottom, fades in
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)
                .opacity(arrowFade)
                .offset(y: swipeHintOffset * 0.3)

            // Phase 2 — deep brain badge rising and fading in
            ZStack {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 44, height: 44)
                VStack(spacing: 1) {
                    Image(systemName: "brain")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Deep")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.white)
            }
            .shadow(color: Color.purple.opacity(0.6), radius: 8)
            .opacity(brainFade)
            .offset(y: swipeHintOffset * 0.9)

            // Upward chevrons between them — subtle guide arrows
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .opacity(swipeHintOpacity * Double(i + 1) / 3.0)
                }
            }
            .offset(y: swipeHintOffset * 0.6 - 14)
        }
        .allowsHitTesting(false)
        .position(x: btnCenterX, y: btnCenterY)
    }

    // MARK: - Mic step animation

    private let micDemoText = "explain it in more detail"

    /// Drives the two-part mic animation loop:
    ///   Part 1 (0–2.5 s): typewriter transcript
    ///   Part 2 (2.5–6 s): finger drifts through Normal → Deep → Cancel zones
    ///   Part 3 (6–6.5 s): reset, then repeat
    private func startMicAnimation() {
        micTranscriptCount = 0
        micSwipePhase = 0
        runMicLoop()
    }

    private func runMicLoop() {
        // Typewriter: reveal one word every 0.28 s
        let words = micDemoText.split(separator: " ").count
        for i in 0..<words {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.32) {
                guard step == .micButton else { return }
                withAnimation(.easeIn(duration: 0.15)) { micTranscriptCount = i + 1 }
            }
        }
        // After transcript finishes, run swipe zones
        let phaseStart = Double(words) * 0.32 + 0.4
        // Phase 1 → normal swipe up
        DispatchQueue.main.asyncAfter(deadline: .now() + phaseStart) {
            guard step == .micButton else { return }
            withAnimation(.easeInOut(duration: 0.6)) { micSwipePhase = 1 }
        }
        // Phase 2 → deep mode zone
        DispatchQueue.main.asyncAfter(deadline: .now() + phaseStart + 0.9) {
            guard step == .micButton else { return }
            withAnimation(.easeInOut(duration: 0.5)) { micSwipePhase = 2 }
        }
        // Phase 3 → cancel zone
        DispatchQueue.main.asyncAfter(deadline: .now() + phaseStart + 1.7) {
            guard step == .micButton else { return }
            withAnimation(.easeInOut(duration: 0.4)) { micSwipePhase = 3 }
        }
        // Reset and loop
        let loopDelay = phaseStart + 2.6
        DispatchQueue.main.asyncAfter(deadline: .now() + loopDelay) {
            guard step == .micButton else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                micTranscriptCount = 0
                micSwipePhase = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard step == .micButton else { return }
                runMicLoop()
            }
        }
    }

    /// Illustrated voice-mode demo embedded inside the callout card.
    @ViewBuilder
    private var micVoiceHintInline: some View {
        let words = micDemoText.split(separator: " ").map(String.init)
        let visibleWords = words.prefix(micTranscriptCount).joined(separator: " ")

        let fingerY: CGFloat = {
            switch micSwipePhase {
            case 1: return -38
            case 2: return -72
            case 3: return -106
            default: return 0
            }
        }()

        let zoneColor: Color = micSwipePhase == 3 ? .red
                             : micSwipePhase == 2 ? .purple
                             : .white

        VStack(spacing: 6) {
            // ── Zone indicator ────────────────────────────────────────────
            ZStack {
                if micSwipePhase == 0 || micSwipePhase == 1 {
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(micSwipePhase == 0 ? 0.4 : 0.8))
                        }
                    }
                }
                if micSwipePhase == 2 {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(Color.purple).frame(width: 28, height: 28)
                            Image(systemName: "brain").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        }
                        Text("Deep Thinking Mode")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.purple)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                if micSwipePhase == 3 {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.red)
                        Text("Release to Cancel")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 28)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: micSwipePhase)

            // ── Hold-to-talk bar + travelling finger dot ──────────────────
            ZStack(alignment: .bottom) {
                HStack {
                    Spacer()
                    Text(micTranscriptCount > 0 ? "Release to Send" : "Hold to Talk")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 19)
                        .fill(micSwipePhase == 3 ? Color.red.opacity(0.85)
                              : micSwipePhase == 2 ? Color.purple.opacity(0.9)
                              : Color.green.opacity(0.9))
                )
                .animation(.easeInOut(duration: 0.3), value: micSwipePhase)

                Circle()
                    .fill(.white.opacity(0.95))
                    .frame(width: 16, height: 16)
                    .shadow(color: zoneColor.opacity(0.6), radius: 5)
                    .offset(y: fingerY - 19)
                    .animation(.easeInOut(duration: 0.5), value: fingerY)
            }

            // ── Live transcript bubble ────────────────────────────────────
            if micTranscriptCount > 0 {
                Text("\"\(visibleWords)\"")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
                    .transition(.opacity)
                    .animation(.easeIn(duration: 0.12), value: visibleWords)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.18)))
    }

    // MARK: - Callout card

    @ViewBuilder
    private var calloutCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                AIAvatarAnimation(state: .speaking, voiceType: voiceType)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(step.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    Text(step.description)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Inline mic animation — sits between description and divider
            if step == .micButton {
                micVoiceHintInline
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            Divider()
                .padding(.horizontal, 8)

            HStack {
                Button(action: onSkip) {
                    Text(NSLocalizedString("onboarding.skip", value: "Skip", comment: ""))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }

                Spacer()

                HStack(spacing: 5) {
                    ForEach(0..<ChatOnboardingStep.allCases.count, id: \.self) { i in
                        Circle()
                            .fill(i == step.rawValue
                                  ? DesignTokens.Colors.Cute.peach
                                  : Color.secondary.opacity(0.3))
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
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(themeManager.cardBackground)
                .shadow(color: .black.opacity(0.2), radius: 14, x: 0, y: 5)
        )
    }
}
