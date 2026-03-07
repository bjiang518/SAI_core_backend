//
//  BranchLocalizer.swift
//  StudyAI
//
//  Localizes taxonomy branch names from the AI Engine's error analysis.
//  English branch names are used as keys; translations live in Taxonomy.strings.
//

import Foundation

enum BranchLocalizer {
    /// Returns the localized display name for a taxonomy branch.
    /// Falls back to the English name when no translation exists.
    static func localized(_ branch: String) -> String {
        NSLocalizedString(branch, tableName: "Taxonomy", comment: "Taxonomy branch name")
    }
}
