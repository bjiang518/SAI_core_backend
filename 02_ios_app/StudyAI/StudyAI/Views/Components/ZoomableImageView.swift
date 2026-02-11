//
//  ZoomableImageView.swift
//  StudyAI
//
//  Fully zoomable, pannable, and annotatable image view
//

import SwiftUI
import UIKit

// MARK: - AnnotatableImageView

struct AnnotatableImageView: View {
    let image: UIImage
    let annotations: [QuestionAnnotation]             // read-only
    @Binding var selectedAnnotationId: UUID?
    let isInteractive: Bool

    var annotationsBinding: Binding<[QuestionAnnotation]>?
    var availableQuestionNumbers: [String]?
    var pageIndex: Int = 0  // ✅ NEW: Track which page this image is on

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let fittedSize = fittedImageSize(image.size, geo.size)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .gesture(
                        // ✅ FIX: Only allow zoom/pan gestures when NOT in interactive mode
                        // In interactive mode, gestures are used for annotation boxes
                        isInteractive ? nil : zoomGesture().simultaneously(with: panGesture())
                    )
                    .onTapGesture(count: 2) {
                        // ✅ FIX: Only allow double-tap zoom when NOT in interactive mode
                        if !isInteractive {
                            doubleTap()
                        }
                    }
                    .overlay(
                        overlayForImage(fittedSize: fittedSize)
                    )
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .clipped()
        }
    }

    // MARK: - Gestures

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                scale = min(max(scale * delta, 0.5), 4.0)
            }
            .onEnded { _ in lastScale = 1.0 }
    }

    private func panGesture() -> some Gesture {
        DragGesture()
            .onChanged { v in
                offset = CGSize(
                    width: lastOffset.width + v.translation.width,
                    height: lastOffset.height + v.translation.height
                )
            }
            .onEnded { _ in
                // ✅ FIX: Only save offset if zoomed in (scale > 1)
                // If not zoomed, snap back to center with animation
                if scale > 1.0 {
                    lastOffset = offset
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }

    private func doubleTap() {
        withAnimation(.spring()) {
            if scale > 1 {
                scale = 1
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.0
            }
        }
    }

    // MARK: - Overlay Router

    @ViewBuilder
    private func overlayForImage(fittedSize: CGSize) -> some View {
        if isInteractive,
           let binding = annotationsBinding,
           let available = availableQuestionNumbers
        {
            AnnotationOverlay(
                annotations: binding,
                selectedAnnotationId: $selectedAnnotationId,
                fittedImageSize: fittedSize,
                scale: scale,
                availableNumbers: available,
                pageIndex: pageIndex  // ✅ Pass page index
            )
        } else {
            readOnlyAnnotationsOverlay(fittedSize: fittedSize)
        }
    }

    // MARK: - Read-only overlay

    private func readOnlyAnnotationsOverlay(fittedSize: CGSize) -> some View {
        ZStack {
            ForEach(annotations) { ann in
                let rect = ann.rect(in: fittedSize)

                Rectangle()
                    .stroke(
                        ann.color,
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: ann.questionNumber == nil ? [5, 5] : []  // ✅ Dashed if unmapped
                        )
                    )
                    .background(Rectangle().fill(ann.color.opacity(0.1)))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .overlay(
                        annotationLabel(for: ann, rect: rect),
                        alignment: .topLeading
                    )
            }
        }
    }

    private func annotationLabel(for ann: QuestionAnnotation, rect: CGRect) -> some View {
        Group {
            if let num = ann.questionNumber {
                Text(num)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(ann.color))
                    .offset(x: rect.minX + 5, y: rect.minY - 20)
            }
        }
    }

    // MARK: - Fit calculation

    private func fittedImageSize(_ img: CGSize, _ box: CGSize) -> CGSize {
        let ratioImg = img.width / img.height
        let ratioBox = box.width / box.height

        if ratioImg > ratioBox {
            let w = box.width
            return CGSize(width: w, height: w / ratioImg)
        } else {
            let h = box.height
            return CGSize(width: h * ratioImg, height: h)
        }
    }
}

// MARK: - AnnotationOverlay

struct AnnotationOverlay: View {
    @Binding var annotations: [QuestionAnnotation]
    @Binding var selectedAnnotationId: UUID?

    let fittedImageSize: CGSize
    let scale: CGFloat
    let availableNumbers: [String]
    let pageIndex: Int  // ✅ NEW: Track which page we're annotating

    @State private var newColorIndex = 0

    var body: some View {
        ZStack {
            // Tap to add new annotation
            Color.clear
                .frame(width: fittedImageSize.width, height: fittedImageSize.height)
                .contentShape(Rectangle())
                .onTapGesture { p in addAnnotation(at: p) }

            // Existing annotation boxes
            ForEach(Array(annotations.enumerated()), id: \.element.id) { index, ann in
                InteractiveAnnotationBox(
                    annotation: $annotations[index],
                    isSelected: selectedAnnotationId == ann.id,
                    imageSize: fittedImageSize,
                    scale: scale,
                    onSelect: { selectedAnnotationId = ann.id },
                    onRectChanged: { rect in updateAnnotationRect(id: ann.id, newRect: rect) }
                )
            }
        }
        .frame(width: fittedImageSize.width, height: fittedImageSize.height)
    }

    private let colorPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint
    ]

    // MARK: - Add annotation

    private func addAnnotation(at p: CGPoint) {
        let size = fittedImageSize.width * 0.15
        var rect = CGRect(x: p.x - size/2, y: p.y - size/2, width: size, height: size)
        rect = rect.clamped(to: fittedImageSize)

        let color = colorPalette[newColorIndex % colorPalette.count]
        newColorIndex += 1

        let ann = QuestionAnnotation.from(rect: rect, in: fittedImageSize, color: color, pageIndex: pageIndex)  // ✅ Pass pageIndex

        // ✅ FIX: Do NOT auto-assign question number - user must select manually
        // This prevents confusion with pseudo/auto-generated labels
        // Annotation will show with NO badge until user explicitly selects a question

        annotations.append(ann)
        selectedAnnotationId = ann.id

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Update annotation rect

    private func updateAnnotationRect(id: UUID, newRect: CGRect) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[i] = annotations[i].updating(rect: newRect, in: fittedImageSize)
    }
}

// MARK: - InteractiveAnnotationBox

struct InteractiveAnnotationBox: View {
    @Binding var annotation: QuestionAnnotation
    let isSelected: Bool
    let imageSize: CGSize
    let scale: CGFloat

    let onSelect: () -> Void
    let onRectChanged: (CGRect) -> Void

    @State private var gestureStartRect: CGRect = .zero
    @State private var began = false

    var body: some View {
        let rect = annotation.rect(in: imageSize)

        ZStack {
            Rectangle()
                .stroke(
                    annotation.color,
                    style: StrokeStyle(
                        lineWidth: isSelected ? 4 : 2,
                        dash: annotation.questionNumber == nil ? [8, 4] : []  // ✅ Dashed if unmapped
                    )
                )
                .background(Rectangle().fill(annotation.color.opacity(isSelected ? 0.15 : 0.05)))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.minY + rect.height / 2)
                .highPriorityGesture(moveGesture(initialRect: rect))

            // label
            if let num = annotation.questionNumber {
                Text(num)
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(annotation.color))
                    .position(x: rect.minX + 25, y: rect.minY - 12)
            }

            if isSelected {
                corner(.topLeft, rect)
                corner(.topRight, rect)
                corner(.bottomLeft, rect)
                corner(.bottomRight, rect)
            }
        }
    }

    // MARK: - Move

    private func moveGesture(initialRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                onSelect()

                if !began {
                    gestureStartRect = initialRect
                    began = true
                }

                let dx = v.translation.width / scale
                let dy = v.translation.height / scale
                let newRect = gestureStartRect.offsetBy(dx: dx, dy: dy).clamped(to: imageSize)

                onRectChanged(newRect)
            }
            .onEnded { _ in began = false }
    }

    // MARK: - Resize

    private func resizeGesture(corner: ResizeCorner, initialRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                onSelect()

                if !began {
                    gestureStartRect = initialRect
                    began = true
                }

                var r = gestureStartRect
                let dx = v.translation.width / scale
                let dy = v.translation.height / scale

                switch corner {
                case .topLeft:
                    r.origin.x += dx; r.origin.y += dy
                    r.size.width -= dx; r.size.height -= dy
                case .topRight:
                    r.origin.y += dy
                    r.size.width += dx; r.size.height -= dy
                case .bottomLeft:
                    r.origin.x += dx
                    r.size.width -= dx; r.size.height += dy
                case .bottomRight:
                    r.size.width += dx; r.size.height += dy
                }

                onRectChanged(r.clamped(to: imageSize))
            }
            .onEnded { _ in began = false }
    }

    // MARK: handles

    private func corner(_ c: ResizeCorner, _ r: CGRect) -> some View {
        Circle()
            .fill(annotation.color)
            .frame(width: 20, height: 20)
            .position(c.position(in: r))
            .highPriorityGesture(resizeGesture(corner: c, initialRect: r))
    }
}

// MARK: - CGRect Clamp

extension CGRect {
    func clamped(to container: CGSize) -> CGRect {
        var r = self

        // ✅ Reduced from 40 to 20 to allow smaller, more precise annotations for small questions
        let minSize: CGFloat = 20
        if r.width < minSize { r.size.width = minSize }
        if r.height < minSize { r.size.height = minSize }

        if r.minX < 0 { r.origin.x = 0 }
        if r.minY < 0 { r.origin.y = 0 }
        if r.maxX > container.width {
            r.origin.x = container.width - r.width
        }
        if r.maxY > container.height {
            r.origin.y = container.height - r.height
        }

        return r
    }
}

// MARK: - QuestionAnnotation Helpers

extension QuestionAnnotation {
    static func from(rect: CGRect, in size: CGSize, color: Color = .blue, pageIndex: Int = 0) -> QuestionAnnotation {
        QuestionAnnotation(
            topLeft: [Double(rect.minX / size.width), Double(rect.minY / size.height)],
            bottomRight: [Double(rect.maxX / size.width), Double(rect.maxY / size.height)],
            questionNumber: nil,
            color: color,
            pageIndex: pageIndex  // ✅ NEW: Include page index
        )
    }

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: CGFloat(topLeft[0]) * size.width,
            y: CGFloat(topLeft[1]) * size.height,
            width: CGFloat(bottomRight[0] - topLeft[0]) * size.width,
            height: CGFloat(bottomRight[1] - topLeft[1]) * size.height
        )
    }

    func updating(rect: CGRect, in size: CGSize) -> QuestionAnnotation {
        var a = self
        a.topLeft = [
            Double(rect.minX / size.width),
            Double(rect.minY / size.height)
        ]
        a.bottomRight = [
            Double(rect.maxX / size.width),
            Double(rect.maxY / size.height)
        ]
        return a
    }
}

// MARK: - ResizeCorner

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}
