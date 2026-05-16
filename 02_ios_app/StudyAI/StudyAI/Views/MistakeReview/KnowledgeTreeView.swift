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
    /// Called when user taps "Light Up" on an untracked leaf — passes topic id.
    var onLightUpTopic: ((String) -> Void)? = nil

    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedLeaf: TreeLeafDetailData?
    @State private var showLeaves = false

    // Light-up animation state
    @State private var prevPracticedIds: Set<String> = []
    @State private var flashLeafIds:  Set<String> = []   // phase 1: white flash + scale
    @State private var glowLeafIds:   Set<String> = []   // phase 2: color + radial glow
    @State private var settleLeafIds: Set<String> = []   // phase 3: glow fading

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
                        // Position in ZStack coordinates (NOT offset-adjusted):
                        // y = layout.rootPosition.y puts the grass center at the canvas root.
                        // After ZStack .offset(y: -offset), it aligns with the visible trunk base.
                        let grassW = CGFloat(geo.size.width) * 0.44
                        let grassH = grassW * 0.48
                        Image("tree_grass")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: grassW, height: grassH)
                            .position(x: geo.size.width / 2,
                                      y: layout.rootPosition.y - grassH * 0.05)
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
            prevPracticedIds = practicedLeafIds(from: branches)
        }
        .onChange(of: practicedLeafIds(from: branches).sorted().joined()) { _, newHash in
            let newPracticed = practicedLeafIds(from: branches)
            let newlyLit = newPracticed.subtracting(prevPracticedIds)
            prevPracticedIds = newPracticed
            guard !newlyLit.isEmpty else { return }
            triggerLightUpAnimation(for: newlyLit)
        }
        .sheet(item: $selectedLeaf) { leaf in
            let extractedId = leaf.id.components(separatedBy: "/").last ?? leaf.topicName
            let _ = debugPrint("🌿 [LightUp] LeafDetailSheet opened — leaf.id='\(leaf.id)' extractedTopicId='\(extractedId)' topicName='\(leaf.topicName)'")
            LeafDetailSheet(leaf: leaf, onLightUp: onLightUpTopic.map { cb in { cb(extractedId) } })
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

    @ViewBuilder
    private func leafView(_ leaf: TreeLeafDetailData) -> some View {
        let isSelected   = selectedLeaf?.id == leaf.id
        let topic        = topicFor(leaf)
        let color        = topic?.leafColor ?? Color.secondary.opacity(0.40)
        let diameter     = topic?.leafDiameter ?? 9
        let container    = diameter + 14
        let imageRotation = leaf.angleDeg - 45

        let isFlashing  = flashLeafIds.contains(leaf.id)
        let isGlowing   = glowLeafIds.contains(leaf.id)
        let isSettling  = settleLeafIds.contains(leaf.id)
        let isAnimating = isFlashing || isGlowing || isSettling

        ZStack {
            // Radial glow bloom — phase 2 & 3
            if isGlowing || isSettling {
                Circle()
                    .fill(color)
                    .frame(width: diameter * 2.8, height: diameter * 2.8)
                    .blur(radius: 10)
                    .opacity(isGlowing ? 0.75 : 0)
                    .animation(.easeOut(duration: 0.5), value: isGlowing)
                    .allowsHitTesting(false)
            }

            // Selection ring
            Circle()
                .strokeBorder(color.opacity(0.5), lineWidth: 2)
                .frame(width: diameter + 10, height: diameter + 10)
                .opacity(isSelected ? 1 : 0)

            // Leaf image
            Image("tree_leaf")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .saturation(0)
                .colorMultiply(isFlashing ? Color.white : tintColor(for: leaf))
                .opacity(topic?.isPracticed == true ? 1.0 : (isFlashing ? 1.0 : 0.45))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(imageRotation))
                .shadow(
                    color: isGlowing ? color.opacity(0.9) : color.opacity(0.35),
                    radius: isGlowing ? 10 : 2,
                    x: 0, y: 1
                )
                .animation(.easeInOut(duration: 0.35), value: isFlashing)
                .animation(.easeInOut(duration: 0.4), value: isGlowing)
        }
        .frame(width: container, height: container)
        .scaleEffect(showLeaves ? (isFlashing ? 1.55 : (isGlowing ? 1.25 : 1.0)) : 0.01)
        .opacity(showLeaves ? 1 : 0)
        .animation(
            isFlashing
                ? .spring(response: 0.25, dampingFraction: 0.55)
                : (isGlowing
                    ? .spring(response: 0.35, dampingFraction: 0.65)
                    : .spring(response: 0.45, dampingFraction: 0.70)),
            value: isFlashing || isGlowing
        )
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

    // MARK: - Light-up animation helpers

    /// Returns the set of leaf IDs (branchId/topicId) that are currently practiced.
    private func practicedLeafIds(from branches: [KnowledgeTreeBranch]) -> Set<String> {
        Set(branches.flatMap { branch in
            branch.topics.compactMap { topic in
                topic.isPracticed ? "\(branch.id)/\(topic.id)" : nil
            }
        })
    }

    /// Runs a 3-phase light-up animation for the given leaf IDs.
    private func triggerLightUpAnimation(for ids: Set<String>) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Phase 1 — white flash + big scale
        withAnimation(.spring(response: 0.22, dampingFraction: 0.50)) {
            flashLeafIds = flashLeafIds.union(ids)
        }

        // Phase 2 — color blooms in + radial glow
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.spring(response: 0.40, dampingFraction: 0.60)) {
                flashLeafIds = flashLeafIds.subtracting(ids)
                glowLeafIds  = glowLeafIds.union(ids)
            }
        }

        // Phase 3 — glow fades, settle to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) {
            withAnimation(.easeOut(duration: 0.55)) {
                glowLeafIds   = glowLeafIds.subtracting(ids)
                settleLeafIds = settleLeafIds.union(ids)
            }
        }

        // Clean up settle flag
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
            settleLeafIds = settleLeafIds.subtracting(ids)
        }
    }
}
