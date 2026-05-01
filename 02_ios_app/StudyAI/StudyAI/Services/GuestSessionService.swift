//
//  GuestSessionService.swift
//  StudyAI
//

import Foundation
import Combine

/// Manages guest-to-account conversion prompt state.
/// All usage limits are enforced backend-side — no local counters here.
class GuestSessionService: ObservableObject {
    static let shared = GuestSessionService()

    @Published var showConversionPrompt = false
    @Published var blockedFeature: String? = nil

    private init() {}

    func promptConversion(for feature: String? = nil) {
        blockedFeature = feature
        showConversionPrompt = true
    }

    func dismissConversion() {
        showConversionPrompt = false
        blockedFeature = nil
    }
}
