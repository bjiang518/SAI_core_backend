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

    private init() {}

    func promptConversion() {
        showConversionPrompt = true
    }

    func dismissConversion() {
        showConversionPrompt = false
    }
}
