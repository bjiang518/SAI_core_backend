//
//  FeatureGate.swift
//  StudyAI
//

import Foundation

struct FeatureGate {

    enum GateResult {
        case allowed
        case blocked(reason: BlockReason)
    }

    enum BlockReason {
        case upgradeRequired(minTier: UserTier)
        case monthlyLimitReached(feature: GatedFeature)
        case coppaRestricted
        case notAuthenticated
    }

    /// Check whether a user may access a feature.
    /// This is a fast local check based on stored tier — backend always re-validates.
    static func check(_ feature: GatedFeature, user: User?) -> GateResult {
        guard let user else { return .blocked(reason: .notAuthenticated) }

        // COPPA restriction overrides tier.
        // accountRestricted is read from ProfileService (populated from profile API).
        // Use switch (not ==) because GatedFeature has associated values and is NOT Equatable.
        if ProfileService.shared.currentProfile?.accountRestricted == true {
            switch feature {
            case .voiceChat, .parentReport:
                return .blocked(reason: .coppaRestricted)
            default:
                break
            }
        }

        // Tier-based access gate (instant UI gate before network call)
        switch feature {
        case .batchHomework:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        case .voiceChat:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        case .questionGeneration(let mode) where mode == 3:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        case .parentReport:
            if !user.tier.isPaid { return .blocked(reason: .upgradeRequired(minTier: .premium)) }
        case .errorAnalysis:
            // Guests have a lifetime limit of 0 — block immediately without a network round-trip
            if user.isAnonymous { return .blocked(reason: .upgradeRequired(minTier: .free)) }
        default:
            break
        }

        return .allowed
    }
}
