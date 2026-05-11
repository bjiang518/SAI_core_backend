import SwiftUI
import AudioToolbox

// MARK: - Leaf tap data

struct TreeLeafDetailData: Identifiable {
    let id: String
    let subject: String
    let branchName: String
    let topicName: String
    let gradeRange: ClosedRange<Int>
    let weaknessValue: WeaknessValue?
    let questionCount: Int
    let animDelay: Double
    let position: CGPoint
    let angleDeg: Double    // branch direction — used to orient the leaf shape
}

// MARK: - Leaf shape (teardrop / botanical leaf)

struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX

        // Tip at top, base at bottom
        path.move(to: CGPoint(x: cx, y: rect.minY))

        path.addCurve(
            to: CGPoint(x: cx, y: rect.maxY),
            control1: CGPoint(x: rect.maxX * 0.9 + rect.minX * 0.1, y: rect.minY + rect.height * 0.28),
            control2: CGPoint(x: rect.maxX * 0.7 + rect.minX * 0.3, y: rect.maxY - rect.height * 0.08)
        )
        path.addCurve(
            to: CGPoint(x: cx, y: rect.minY),
            control1: CGPoint(x: rect.minX * 0.7 + rect.maxX * 0.3, y: rect.maxY - rect.height * 0.08),
            control2: CGPoint(x: rect.minX * 0.9 + rect.maxX * 0.1, y: rect.minY + rect.height * 0.28)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Main view

struct KnowledgeTreeView: View {
    let subject: String
    let branches: [KnowledgeTreeBranch]

    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedLeaf: TreeLeafDetailData?
    @State private var showLeaves = false

    private let canvasHeight: CGFloat = 440
    private let leafTopPadding: CGFloat = 24

    private var topOffset: CGFloat {
        let layout = TreeLayoutEngine(canvasSize: CGSize(width: 390, height: canvasHeight))
            .compute(branches: branches)
        return max(0, layout.topContentY - leafTopPadding)
    }

    var body: some View {
        let offset       = topOffset
        let visibleHeight = canvasHeight - offset

        VStack(spacing: 0) {
            if branches.isEmpty {
                emptyState
            } else {
                GeometryReader { geo in
                    let layout = TreeLayoutEngine(
                        canvasSize: CGSize(width: geo.size.width, height: canvasHeight)
                    ).compute(branches: branches)

                    ZStack {
                        // Grass behind everything — rendered first = lowest z-order
                        let grassW = CGFloat(geo.size.width) * 0.44
                        let grassH = grassW * 0.48
                        let rootY  = layout.rootPosition.y - offset
                        Image("tree_grass")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: grassW, height: grassH)
                            .position(x: geo.size.width / 2,
                                      y: rootY + grassH * 0.55)
                            .allowsHitTesting(false)

                        // Trunk + branches above grass
                        Canvas { ctx, _ in
                            drawBranches(ctx, layout: layout)
                        }
                        .allowsHitTesting(false)

                        // Leaves on top
                        ForEach(buildLeaves(layout: layout), id: \.id) { leaf in
                            leafView(leaf)
                                .position(leaf.position)
                        }
                    }
                    .frame(width: geo.size.width, height: canvasHeight)
                    .offset(y: -offset)
                }
                .frame(height: visibleHeight)
                .clipped()
            }

            legend
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Text(NSLocalizedString("knowledgeTree.hint",
                                   value: "Each branch has 3 sub-branches, representing deeper topics.",
                                   comment: ""))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showLeaves = true }
        }
        .sheet(item: $selectedLeaf) { leaf in
            LeafDetailSheet(leaf: leaf)
        }
    }

    // MARK: - Build leaf data

    private func buildLeaves(layout: TreeLayout) -> [TreeLeafDetailData] {
        var result: [TreeLeafDetailData] = []
        var nodeIndex = 0
        for branch in branches {
            for topic in branch.topics {
                guard nodeIndex < layout.leaves.count else { break }
                let node = layout.leaves[nodeIndex]
                result.append(TreeLeafDetailData(
                    id: "\(branch.id)/\(topic.id)",
                    subject: subject,
                    branchName: branch.name,
                    topicName: topic.topicName,
                    gradeRange: topic.gradeRange,
                    weaknessValue: topic.weaknessValue,
                    questionCount: topic.questionCount,
                    animDelay: node.animDelay,
                    position: node.position,
                    angleDeg: node.angleDeg
                ))
                nodeIndex += 1
            }
        }
        return result
    }

    // MARK: - Leaf view (image asset, tinted by mastery, rotated by branch angle)

    @ViewBuilder
    private func leafView(_ leaf: TreeLeafDetailData) -> some View {
        let isSelected = selectedLeaf?.id == leaf.id
        let topic      = topicFor(leaf)
        let color      = topic?.leafColor ?? Color.secondary.opacity(0.40)
        let diameter   = topic?.leafDiameter ?? 9
        let container  = diameter + 14

        // The asset image tip points roughly 45° right of vertical (northeast).
        // Rotate by (angleDeg - 45) so the tip aligns with the branch direction.
        let imageRotation = leaf.angleDeg - 45

        ZStack {
            // Glow ring when selected
            Circle()
                .strokeBorder(color.opacity(0.5), lineWidth: 2)
                .frame(width: diameter + 10, height: diameter + 10)
                .opacity(isSelected ? 1 : 0)

            // Leaf image, desaturated then re-tinted with mastery color
            Image("tree_leaf")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(topic?.isPracticed == true ? 0 : 0)   // always desat then re-color
                .colorMultiply(tintColor(for: leaf))
                .opacity(topic?.isPracticed == true ? 1.0 : 0.45)
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(imageRotation))
                .shadow(color: color.opacity(0.35), radius: 2, x: 0, y: 1)
        }
        .frame(width: container, height: container)
        .scaleEffect(showLeaves ? 1.0 : 0.01)
        .opacity(showLeaves ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.65).delay(leaf.animDelay), value: showLeaves)
        .scaleEffect(isSelected ? 1.12 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.60), value: isSelected)
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.28)) {
                selectedLeaf = selectedLeaf?.id == leaf.id ? nil : leaf
            }
        }
    }

    /// Maps mastery state → tint color for `.colorMultiply()`.
    /// After `.saturation(0)` the image is grayscale, so multiplying by a color tints it cleanly.
    private func tintColor(for leaf: TreeLeafDetailData) -> Color {
        guard let topic = topicFor(leaf), topic.isPracticed else {
            return Color(white: 0.72)   // untracked: neutral gray leaf
        }
        guard let wv = topic.weaknessValue else {
            return Color(white: 0.72)
        }
        let acc = wv.accuracy
        if wv.value <= 0 || acc >= 0.70 {
            // Mastered: restore natural green
            return Color(red: 0.35, green: 0.85, blue: 0.30)
        }
        if acc >= 0.45 {
            // Borderline: warm yellow-orange
            return Color(red: 0.95, green: 0.80, blue: 0.10)
        }
        // Weakness: red
        return Color(red: 0.90, green: 0.18, blue: 0.18)
    }

    private func topicFor(_ leaf: TreeLeafDetailData) -> KnowledgeTreeTopic? {
        branches.first { $0.name == leaf.branchName }?
            .topics.first { $0.topicName == leaf.topicName }
    }

    // MARK: - Canvas drawing

    private func drawBranches(_ context: GraphicsContext, layout: TreeLayout) {
        let trunkColor = Color(red: 0.46, green: 0.32, blue: 0.14)

        // Trunk (tapered, sampling bezier)
        taperedBezier(context: context,
                      from: layout.rootPosition,
                      to: layout.trunkEnd,
                      control: CGPoint(x: layout.rootPosition.x + 4,
                                       y: (layout.rootPosition.y + layout.trunkEnd.y) / 2),
                      startW: layout.trunkWidth, endW: layout.trunkWidth * 0.62,
                      color: trunkColor, alpha: 1.0)

        // Segments
        for seg in layout.segments {
            taperedBezier(context: context,
                          from: seg.from, to: seg.to, control: seg.control,
                          startW: seg.startWidth, endW: seg.endWidth,
                          color: trunkColor, alpha: Double(seg.alpha))

            // Junction circle at primary endpoint
            if seg.isPrimary {
                let r = seg.startWidth / 2
                context.fill(
                    Path(ellipseIn: CGRect(x: seg.to.x - r, y: seg.to.y - r,
                                          width: seg.startWidth, height: seg.startWidth)),
                    with: .color(trunkColor)
                )
            }
        }
    }

    /// Tapered bezier: drawn by sampling the curve and varying lineWidth.
    private func taperedBezier(context: GraphicsContext,
                                from: CGPoint, to: CGPoint, control: CGPoint,
                                startW: CGFloat, endW: CGFloat,
                                color: Color, alpha: Double) {
        let steps = 12
        for i in 0..<steps {
            let t0 = CGFloat(i)     / CGFloat(steps)
            let t1 = CGFloat(i + 1) / CGFloat(steps)
            let p0 = bezierPoint(t: t0, p0: from, p1: control, p2: to)
            let p1 = bezierPoint(t: t1, p0: from, p1: control, p2: to)
            let w  = startW + (endW - startW) * t0
            var seg = Path()
            seg.move(to: p0)
            seg.addLine(to: p1)
            context.stroke(seg, with: .color(color.opacity(alpha)), lineWidth: w)
        }
    }

    private func bezierPoint(t: CGFloat, p0: CGPoint, p1: CGPoint, p2: CGPoint) -> CGPoint {
        let mt = 1 - t
        return CGPoint(x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
                       y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y)
    }

    // MARK: - Ground decoration

    private func drawGround(_ context: GraphicsContext, layout: TreeLayout) {
        let root  = layout.rootPosition
        let tW    = layout.trunkWidth

        // Soft green oval (ground)
        let ovalW: CGFloat = tW * 9
        let ovalH: CGFloat = 18
        let groundRect = CGRect(x: root.x - ovalW / 2, y: root.y - ovalH / 3,
                                width: ovalW, height: ovalH)
        context.fill(Path(ellipseIn: groundRect),
                     with: .color(Color(red: 0.38, green: 0.62, blue: 0.22).opacity(0.22)))

        // Grass blades
        let bladeColor = Color(red: 0.30, green: 0.55, blue: 0.15).opacity(0.55)
        for i in -4...4 {
            let bx    = root.x + CGFloat(i) * (tW * 0.9)
            let bh    = CGFloat.random(in: 9...18)
            let lean  = CGFloat(i) * 2.0
            var blade = Path()
            blade.move(to: CGPoint(x: bx, y: root.y - 2))
            blade.addQuadCurve(to: CGPoint(x: bx + lean, y: root.y - bh),
                               control: CGPoint(x: bx + lean * 0.5, y: root.y - bh * 0.5))
            context.stroke(blade, with: .color(bladeColor), lineWidth: 1.4)
        }

        // Small rocks
        let rockColor = Color.gray.opacity(0.30)
        for (rx, ry, rw, rh) in [(-tW * 3.5, -5.0, 9.0, 6.5), (tW * 2.5, -4.0, 7.0, 5.0)] {
            context.fill(Path(ellipseIn: CGRect(x: root.x + rx - rw / 2,
                                               y: root.y + ry - rh / 2,
                                               width: rw, height: rh)),
                         with: .color(rockColor))
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 0) {
            Spacer()
            legendDot(Color(red: 0.90, green: 0.18, blue: 0.18),
                      NSLocalizedString("mistakeTree.legend.weakness",   comment: ""))
            Spacer()
            legendDot(Color(red: 0.95, green: 0.80, blue: 0.10),
                      NSLocalizedString("mistakeTree.legend.borderline", comment: ""))
            Spacer()
            legendDot(Color(red: 0.35, green: 0.85, blue: 0.30),
                      NSLocalizedString("mistakeTree.legend.mastered",   comment: ""))
            Spacer()
            legendDot(Color(white: 0.72),
                      NSLocalizedString("mistakeTree.legend.untracked",  comment: ""))
            Spacer()
        }
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
    }

    private func legendDot(_ tint: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image("tree_leaf")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(0)
                .colorMultiply(tint)
                .frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
            Text(NSLocalizedString("mistakeTree.empty", comment: ""))
                .font(.subheadline).foregroundColor(.secondary)
        }
        .frame(height: canvasHeight).frame(maxWidth: .infinity)
    }
}
