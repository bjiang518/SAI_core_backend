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

// MARK: - iPad sheet sizing

extension View {
    /// Locks the iPad form-sheet size so it doesn't oscillate when inner content dimensions
    /// change (e.g. conditional sections, mode toggles, async loading).
    /// No-op on iPhone — bottom sheets are sized by the system, the min/ideal hints are ignored.
    /// Apply to the root view inside the sheet body.
    func iPadSheetFixedSize(width: CGFloat = 540, height: CGFloat = 760) -> some View {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        return self.frame(
            minWidth: isPad ? width : nil,
            idealWidth: isPad ? width : nil,
            minHeight: isPad ? height : nil,
            idealHeight: isPad ? height : nil
        )
    }
}
