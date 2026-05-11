import Foundation
import SwiftUI

// MARK: - Raw JSON models

struct SubjectTaxonomyJSON: Codable {
    let subject: String
    let branches: [TaxonomyBranchJSON]
}

struct TaxonomyBranchJSON: Codable {
    let id: String
    let name: String
    let topics: [TaxonomyTopicJSON]
}

struct TaxonomyTopicJSON: Codable {
    let id: String
    let name: String
    let gradeMin: Int
    let gradeMax: Int
}

// MARK: - Overlay models (branch + topics with practice data)

struct KnowledgeTreeBranch: Identifiable {
    let id: String
    let name: String
    let topics: [KnowledgeTreeTopic]
}

struct KnowledgeTreeTopic: Identifiable {
    let id: String
    let topicName: String
    let branchName: String
    let gradeRange: ClosedRange<Int>
    /// nil = never practiced; non-nil = has tracking data
    let weaknessValue: WeaknessValue?
    /// total questions attempted for this topic (from local storage)
    let questionCount: Int

    var isPracticed: Bool { weaknessValue != nil || questionCount > 0 }

    var leafColor: Color {
        guard isPracticed, let wv = weaknessValue else {
            return Color.secondary.opacity(0.22)    // unlit: pale gray
        }
        let acc = wv.accuracy
        if wv.value <= 0 || acc >= 0.70 { return Color(red: 0.34, green: 0.80, blue: 0.01) }
        return acc < 0.45 ? .red : .yellow
    }

    var leafDiameter: CGFloat {
        guard isPracticed else { return 18 }          // untracked: visible but gray
        return max(20, min(34, 20 + CGFloat(questionCount) * 1.8))
    }
}
