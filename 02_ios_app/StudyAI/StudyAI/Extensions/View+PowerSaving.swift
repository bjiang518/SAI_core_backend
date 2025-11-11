//
//  View+PowerSaving.swift
//  StudyAI
//
//  Created by Claude Code
//

import SwiftUI

extension View {
    /// Apply animation only if Power Saving Mode is disabled
    /// - Parameters:
    ///   - animation: The animation to apply
    ///   - value: The value to observe for changes
    /// - Returns: The view with conditional animation
    func animationIfNotPowerSaving<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        let isPowerSaving = AppState.shared.isPowerSavingMode
        return self.animation(isPowerSaving ? nil : animation, value: value)
    }

    /// Apply transition only if Power Saving Mode is disabled
    /// - Parameter transition: The transition to apply
    /// - Returns: The view with conditional transition
    func transitionIfNotPowerSaving(_ transition: AnyTransition) -> some View {
        let isPowerSaving = AppState.shared.isPowerSavingMode
        return self.transition(isPowerSaving ? .identity : transition)
    }
}

/// Apply withAnimation only if Power Saving Mode is disabled
/// - Parameters:
///   - animation: The animation to apply
///   - action: The action to perform
/// - Returns: The result of the action
func withAnimationIfNotPowerSaving<Result>(_ animation: Animation? = .default, _ action: () throws -> Result) rethrows -> Result {
    let isPowerSaving = AppState.shared.isPowerSavingMode
    if isPowerSaving {
        return try action()
    } else {
        return try withAnimation(animation) {
            try action()
        }
    }
}

extension Animation {
    /// Returns nil if Power Saving Mode is enabled, otherwise returns self
    func disabledIfPowerSaving() -> Animation? {
        return AppState.shared.isPowerSavingMode ? nil : self
    }
}
