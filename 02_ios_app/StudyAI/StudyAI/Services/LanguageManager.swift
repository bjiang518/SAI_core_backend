//
//  LanguageManager.swift
//  StudyAI
//
//  Immediate in-app language switching via Bundle swizzle.
//  NSLocalizedString calls return the new language without any app restart.
//

import Foundation
import ObjectiveC

// MARK: - Language Manager

/// Manages in-app language switching. Apply once at startup via `setup()`.
/// Change language at runtime via `setLanguage(_:)` — takes effect immediately.
final class LanguageManager {
    static let shared = LanguageManager()
    private init() {}

    /// Call in `StudyAIApp.init()` before any UI renders.
    func setup() {
        Bundle.swizzleLocalization()
        let code = UserDefaults.standard.string(forKey: "appLanguage")
            ?? LanguageManager.detectedSystemLanguage()
        applyBundle(for: code)
    }

    /// Persist and immediately apply a new language.
    /// Writing to UserDefaults["appLanguage"] triggers all @AppStorage("appLanguage")
    /// observers, causing StudyAIApp to re-render with the new locale environment.
    func setLanguage(_ code: String) {
        UserDefaults.standard.set(code, forKey: "appLanguage")
        applyBundle(for: code)
    }

    private func applyBundle(for code: String) {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            // Fallback: clear override so Bundle.main is used directly
            LanguageBundleOverride.current = nil
            return
        }
        LanguageBundleOverride.current = bundle
    }

    /// Maps the device's first preferred language to a supported code.
    static func detectedSystemLanguage() -> String {
        let lang = Locale.preferredLanguages.first ?? "en"
        if lang.hasPrefix("zh-Hant") || lang.hasPrefix("zh-TW")
            || lang.hasPrefix("zh-HK") || lang.hasPrefix("zh-MO") {
            return "zh-Hant"
        } else if lang.hasPrefix("zh") {
            return "zh-Hans"
        }
        return "en"
    }
}

// MARK: - Bundle override storage

/// Holds the currently active language bundle. nil = use Bundle.main directly.
enum LanguageBundleOverride {
    static var current: Bundle?
}

// MARK: - Bundle swizzle

private let _swizzleOnce: Void = {
    guard
        let original = class_getInstanceMethod(Bundle.self,
            #selector(Bundle.localizedString(forKey:value:table:))),
        let replacement = class_getInstanceMethod(Bundle.self,
            #selector(Bundle._lng_localizedString(forKey:value:table:)))
    else { return }
    method_exchangeImplementations(original, replacement)
}()

extension Bundle {
    /// Trigger the swizzle exactly once (called from LanguageManager.setup()).
    static func swizzleLocalization() { _swizzleOnce }

    /// After swizzling this name holds the ORIGINAL NSBundle implementation,
    /// while `localizedString(forKey:value:table:)` runs the code below.
    @objc func _lng_localizedString(forKey key: String,
                                    value: String?,
                                    table tableName: String?) -> String {
        // If there is an active language bundle and it is NOT self (prevents infinite
        // recursion when we call through to the override bundle), delegate to it.
        if let override = LanguageBundleOverride.current, override !== self {
            // _lng_localizedString now points to the original NSBundle implementation,
            // so this call goes straight to the localization file lookup.
            return override._lng_localizedString(forKey: key, value: value, table: tableName)
        }
        // No override (or we ARE the override bundle): call the original implementation.
        return _lng_localizedString(forKey: key, value: value, table: tableName)
    }
}
