//
//  AppReviewService.swift
//  StudyAI
//
//  Smart App Store review prompt — triggers at positive moments with throttling
//

import Foundation
import StoreKit
import UIKit

/// Tracks user engagement milestones and requests App Store reviews at positive moments.
/// Apple throttles `requestReview` to ~3 prompts per year per device, so we pre-filter
/// aggressively and only call it when the user is genuinely satisfied.
@MainActor
class AppReviewService {
    static let shared = AppReviewService()

    private let userDefaults = UserDefaults.standard

    // MARK: - Keys

    private var keyPrefix: String {
        let userId = AuthenticationService.shared.currentUser?.id ?? "anonymous"
        return "studyai_\(userId)_review_"
    }
    private var lastPromptDateKey: String { keyPrefix + "last_prompt_date" }
    private var promptCountKey: String { keyPrefix + "prompt_count" }
    private var dismissedForeverKey: String { keyPrefix + "dismissed_forever" }
    private var homeworkCountKey: String { keyPrefix + "homework_count" }
    private var chatCountKey: String { keyPrefix + "chat_count" }
    private var focusCountKey: String { keyPrefix + "focus_count" }
    private var ratedForPointsKey: String { keyPrefix + "rated_for_points" }
    private var ratingPromptedKey: String { keyPrefix + "rating_prompted" }
    private var sharedForPointsKey: String { keyPrefix + "shared_for_points" }
    private var sharePromptedKey: String { keyPrefix + "share_prompted" }

    /// Whether the user has already earned points for rating (one-time)
    var hasEarnedRatingPoints: Bool {
        userDefaults.bool(forKey: ratedForPointsKey)
    }

    /// Whether the review dialog has been shown but points not yet claimed
    var hasPromptedRating: Bool {
        userDefaults.bool(forKey: ratingPromptedKey)
    }

    /// Whether the share sheet has been shown but points not yet claimed
    var hasPromptedShare: Bool {
        userDefaults.bool(forKey: sharePromptedKey)
    }

    /// Whether the user has already earned points for sharing (one-time)
    var hasEarnedSharePoints: Bool {
        userDefaults.bool(forKey: sharedForPointsKey)
    }

    /// Points awarded for rating the app
    static let ratingPointsReward = 50

    /// Points awarded for sharing the app
    static let sharePointsReward = 30

    // MARK: - Thresholds

    /// Minimum days between review prompts (Apple may throttle further)
    private let minDaysBetweenPrompts = 30

    /// Maximum prompts per user lifetime (we self-limit beyond Apple's ~3/year)
    private let maxLifetimePrompts = 5

    // MARK: - Trigger Events

    /// Call after homework grading completes successfully.
    func recordHomeworkCompleted() {
        let count = userDefaults.integer(forKey: homeworkCountKey) + 1
        userDefaults.set(count, forKey: homeworkCountKey)

        // Trigger after 1st homework — immediate positive impression
        if count == 1 { tryRequestReview() }
    }

    /// Call after AI chat response completes successfully.
    func recordChatCompleted() {
        let count = userDefaults.integer(forKey: chatCountKey) + 1
        userDefaults.set(count, forKey: chatCountKey)

        // Trigger after 3rd chat — user had a real conversation
        if count == 3 { tryRequestReview() }
    }

    /// Call after Pomodoro focus session completes (25+ min).
    func recordFocusCompleted() {
        let count = userDefaults.integer(forKey: focusCountKey) + 1
        userDefaults.set(count, forKey: focusCountKey)

        // Trigger after 2nd focus session
        if count == 2 { tryRequestReview() }
    }

    /// Call when user earns a points milestone (30, 100, 500).
    func checkPointsMilestone(_ totalPoints: Int) {
        let milestones = [30, 100, 500]
        for m in milestones {
            let milestoneKey = keyPrefix + "milestone_\(m)"
            if totalPoints >= m && !userDefaults.bool(forKey: milestoneKey) {
                userDefaults.set(true, forKey: milestoneKey)
                tryRequestReview()
                break // Only one milestone per check
            }
        }
    }

    /// Call when streak reaches a milestone (3, 7, 14).
    func checkStreakMilestone(_ streak: Int) {
        let milestones = [3, 7, 14]
        for m in milestones {
            let milestoneKey = keyPrefix + "streak_milestone_\(m)"
            if streak >= m && !userDefaults.bool(forKey: milestoneKey) {
                userDefaults.set(true, forKey: milestoneKey)
                tryRequestReview()
                break
            }
        }
    }

    // MARK: - Core Logic

    /// Attempt to show the system review prompt if all conditions are met.
    private func tryRequestReview() {
        // User opted out permanently
        guard !userDefaults.bool(forKey: dismissedForeverKey) else { return }

        // Lifetime prompt cap
        let promptCount = userDefaults.integer(forKey: promptCountKey)
        guard promptCount < maxLifetimePrompts else { return }

        // Throttle: minimum days between prompts
        if let lastDate = userDefaults.object(forKey: lastPromptDateKey) as? Date {
            let daysSinceLast = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            guard daysSinceLast >= minDaysBetweenPrompts else { return }
        }

        // All conditions met — request review
        // Delay slightly so it doesn't interrupt the current action
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.presentReview()
        }
    }

    private func presentReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return
        }

        SKStoreReviewController.requestReview(in: scene)

        // Record the prompt
        userDefaults.set(Date(), forKey: lastPromptDateKey)
        userDefaults.set(userDefaults.integer(forKey: promptCountKey) + 1, forKey: promptCountKey)
    }

    /// Let user opt out of future prompts (e.g. from settings).
    func dismissForever() {
        userDefaults.set(true, forKey: dismissedForeverKey)
    }

    // MARK: - Rate for Points (Two-Phase: prompt first, claim after)

    /// Phase 1: Opens the review dialog. Does NOT award points yet.
    /// Call this on the first star tap.
    func promptRatingForPoints() {
        guard !hasEarnedRatingPoints, !hasPromptedRating else { return }

        // Present the review dialog
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        } else {
            // Fallback: open App Store review page
            if let url = URL(string: "itms-apps://itunes.apple.com/app/id6754365864?action=write-review") {
                UIApplication.shared.open(url)
            }
        }

        // Mark as prompted — points become claimable on next tap
        userDefaults.set(true, forKey: ratingPromptedKey)
    }

    /// Phase 2: Claims the rating reward after the user has been prompted.
    /// Call this on the second star tap (after promptRatingForPoints was called).
    /// Returns the points earned (50 if eligible, 0 if already claimed).
    func claimRatingPoints() -> Int {
        guard hasPromptedRating, !hasEarnedRatingPoints else { return 0 }

        let reward = Self.ratingPointsReward
        PointsEarningManager.shared.pointsBalance += reward
        PointsEarningManager.shared.totalPointsEarned += reward
        PointsEarningManager.shared.dailyPointsEarned += reward
        PointsEarningManager.shared.forceSave()

        userDefaults.set(true, forKey: ratedForPointsKey)
        return reward
    }

    /// Legacy: kept for backward compat but now does both phases at once.
    @available(*, deprecated, message: "Use promptRatingForPoints() then claimRatingPoints()")
    func rateAppForPoints() -> Int {
        promptRatingForPoints()
        return claimRatingPoints()
    }

    // MARK: - Share for Points (Two-Phase: share first, claim after)

    /// Phase 1: Marks that the share sheet was presented. Does NOT award points yet.
    func markSharePrompted() {
        guard !hasEarnedSharePoints, !hasPromptedShare else { return }
        userDefaults.set(true, forKey: sharePromptedKey)
    }

    /// Phase 2: Claims the share reward after the user has shared.
    /// Returns the points earned (30 if eligible, 0 if already claimed).
    func claimSharePoints() -> Int {
        guard hasPromptedShare, !hasEarnedSharePoints else { return 0 }

        let reward = Self.sharePointsReward
        PointsEarningManager.shared.pointsBalance += reward
        PointsEarningManager.shared.totalPointsEarned += reward
        PointsEarningManager.shared.dailyPointsEarned += reward
        PointsEarningManager.shared.forceSave()

        userDefaults.set(true, forKey: sharedForPointsKey)
        return reward
    }

    /// Legacy: kept for backward compat.
    @available(*, deprecated, message: "Use markSharePrompted() then claimSharePoints()")
    func shareAppForPoints() -> Int {
        markSharePrompted()
        return claimSharePoints()
    }

    private init() {}
}
