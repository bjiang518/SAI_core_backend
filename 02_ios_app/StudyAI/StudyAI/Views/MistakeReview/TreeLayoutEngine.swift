import SwiftUI

// MARK: - Layout data types

struct TreeLeafNode: Identifiable {
    let id: String
    let baseBranch: String
    let detailedBranch: String
    let mistakeCount: Int
    var position: CGPoint
    var animDelay: Double
    var angleDeg: Double    // branch angle (0=up, +right, -left) — used for leaf rotation
}

struct TreeBranchSegment {
    let from: CGPoint
    let to: CGPoint
    let control: CGPoint
    let startWidth: CGFloat
    let endWidth: CGFloat
    let alpha: CGFloat
    let isPrimary: Bool
}

struct TreeLayout {
    let rootPosition: CGPoint
    let trunkEnd: CGPoint
    let trunkWidth: CGFloat
    let segments: [TreeBranchSegment]
    let leaves: [TreeLeafNode]

    var topContentY: CGFloat {
        leaves.map(\.position.y).min() ?? 0
    }

    static let empty = TreeLayout(
        rootPosition: .zero, trunkEnd: .zero, trunkWidth: 8,
        segments: [], leaves: []
    )
}

// MARK: - Layout engine

struct TreeLayoutEngine {
    let canvasSize: CGSize
    private let leafUnit: CGFloat = 1.2

    func compute(branches: [KnowledgeTreeBranch]) -> TreeLayout {
        let w = canvasSize.width
        let h = canvasSize.height
        let root = CGPoint(x: w / 2, y: h - 28)

        guard !branches.isEmpty else {
            let trunkEnd = CGPoint(x: w / 2, y: h * 0.72)
            return TreeLayout(rootPosition: root, trunkEnd: trunkEnd, trunkWidth: 5,
                              segments: [], leaves: [])
        }

        let n           = branches.count
        let totalLeaves = branches.reduce(0) { $0 + $1.topics.count }
        let maturity    = min(CGFloat(totalLeaves) / 15.0, 1.0)

        // Trunk proportions scale with tree maturity — kept short so branches dominate
        let trunkHeight = h * (0.09 + maturity * 0.08)
        let trunkEnd    = CGPoint(x: w / 2, y: (h - 28) - trunkHeight)
        let trunkWidth  = clamp(CGFloat(totalLeaves) * leafUnit, 6, 13)

        // Primary branch lengths
        let primaryBase  = h * (0.15 + maturity * 0.07)
        // Secondary (sub-branch) and leaf stem lengths
        let secondaryBase = h * (0.10 + maturity * 0.05)
        let stemBase      = h * (0.07 + maturity * 0.03)

        // Primary half-span (degrees from vertical), capped to keep branches upward
        let halfSpan: Double = n == 1 ? 0 : min(Double(n - 1) * 16.0 + 8.0, 58.0)

        var segments: [TreeBranchSegment] = []
        var leaves:   [TreeLeafNode]      = []
        var leafIndex = 0

        for (i, branch) in branches.enumerated() {
            let primaryAngle: Double = n == 1 ? 0
                : -halfSpan + Double(i) * (2 * halfSpan / Double(n - 1))

            let primaryWidth = clamp(CGFloat(branch.topics.count) * leafUnit, 3, 8)
            let primaryLen   = primaryBase * (1.0 + min(CGFloat(branch.topics.count), 8) * 0.03)
            let primaryPos   = tip(from: trunkEnd, angleDeg: primaryAngle, length: primaryLen)

            segments.append(TreeBranchSegment(
                from: trunkEnd, to: primaryPos,
                control: CGPoint(x: trunkEnd.x, y: primaryPos.y),
                startWidth: primaryWidth, endWidth: primaryWidth * 0.55,
                alpha: 0.90, isPrimary: true
            ))

            // ── Sub-branches (2nd level) ──────────────────────────────────────
            let topicCount = branch.topics.count
            let numSubs    = max(1, min(3, (topicCount + 2) / 3))
            let subSpread: Double = numSubs == 1 ? 0 : min(Double(numSubs - 1) * 18.0, 28.0)
            let topicsPerSub = (topicCount + numSubs - 1) / numSubs

            for sg in 0..<numSubs {
                let subAngle: Double = numSubs == 1 ? primaryAngle
                    : primaryAngle - subSpread + Double(sg) * (2 * subSpread / Double(numSubs - 1))

                let subWidth = clamp(CGFloat(topicsPerSub) * leafUnit * 0.7, 1.5, 4.5)
                let subLen   = secondaryBase
                let subCtrl  = CGPoint(x: primaryPos.x, y: primaryPos.y - secondaryBase * 0.4)
                let subPos   = tip(from: primaryPos, angleDeg: subAngle, length: subLen)

                segments.append(TreeBranchSegment(
                    from: primaryPos, to: subPos,
                    control: CGPoint(x: primaryPos.x + (subPos.x - primaryPos.x) * 0.3,
                                    y: primaryPos.y + (subPos.y - primaryPos.y) * 0.3),
                    startWidth: subWidth, endWidth: subWidth * 0.45,
                    alpha: 0.80, isPrimary: false
                ))

                // ── Leaves (3rd level) ────────────────────────────────────────
                let startIdx  = sg * topicsPerSub
                let endIdx    = min(startIdx + topicsPerSub, topicCount)
                guard startIdx < endIdx else { continue }
                let subTopics = Array(branch.topics[startIdx..<endIdx])

                let lCount     = subTopics.count
                let leafSpread: Double = lCount <= 1 ? 0 : min(Double(lCount - 1) * 13.0, 20.0)

                for (j, topic) in subTopics.enumerated() {
                    let leafAngle: Double = lCount == 1 ? subAngle
                        : subAngle - leafSpread + Double(j) * (2 * leafSpread / Double(lCount - 1))

                    // Alternate near/far to prevent overlap
                    let distScale: CGFloat = j % 2 == 0 ? 0.85 : 1.15
                    let leafLen   = stemBase * distScale
                    let leafPos   = tip(from: subPos, angleDeg: leafAngle, length: leafLen)

                    let midX = (subPos.x + leafPos.x) / 2
                    let midY = (subPos.y + leafPos.y) / 2 - 6

                    segments.append(TreeBranchSegment(
                        from: subPos, to: leafPos,
                        control: CGPoint(x: midX, y: midY),
                        startWidth: 1.8, endWidth: 0.8,
                        alpha: 0.55, isPrimary: false
                    ))

                    leaves.append(TreeLeafNode(
                        id: "\(branch.id)/\(topic.id)",
                        baseBranch: branch.name,
                        detailedBranch: topic.topicName,
                        mistakeCount: topic.questionCount,
                        position: leafPos,
                        animDelay: Double(leafIndex) * 0.04,
                        angleDeg: leafAngle
                    ))
                    leafIndex += 1
                }
            }
        }

        return TreeLayout(rootPosition: root, trunkEnd: trunkEnd, trunkWidth: trunkWidth,
                          segments: segments, leaves: leaves)
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    private func tip(from origin: CGPoint, angleDeg: Double, length: CGFloat) -> CGPoint {
        let rad = angleDeg * .pi / 180
        return CGPoint(x: origin.x + CGFloat(sin(rad)) * length,
                       y: origin.y - CGFloat(cos(rad)) * length)
    }
}
