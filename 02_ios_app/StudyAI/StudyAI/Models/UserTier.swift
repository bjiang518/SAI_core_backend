//
//  UserTier.swift
//  StudyAI
//

import Foundation

// MARK: - UserTier

enum UserTier: String, Codable {
    // Note: backend stores anonymous users with tier='free' and is_anonymous=true.
    // The server NEVER sends "guest" as a tier value.
    // Guest detection uses user.isAnonymous exclusively.
    case free         = "free"
    case premium      = "premium"
    case premiumPlus  = "premium_plus"

    var displayName: String {
        switch self {
        case .free:        return "Free"
        case .premium:     return "Premium"
        case .premiumPlus: return "Premium Plus"
        }
    }

    var isPaid: Bool { self == .premium || self == .premiumPlus }
}

// MARK: - GatedFeature

enum GatedFeature {
    case homeworkAnalysis
    case batchHomework
    case chatMessage
    case voiceChat
    case questionGeneration(mode: Int)   // mode 3 = premium only
    case errorAnalysis                   // blocked for guests; 5/month for free
    case errorAnalysisDeep
    case parentReport
}
