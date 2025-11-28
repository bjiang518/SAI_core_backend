//
//  ZoomableImageView.swift
//  StudyAI
//
//  Zoomable and pannable image view with annotation support
//

import SwiftUI
import UIKit

struct AnnotatableImageView: View {
    let image: UIImage
    let annotations: [QuestionAnnotation]
    @Binding var selectedAnnotationId: UUID?
    let isInteractive: Bool

    // ✅ NEW: For interactive mode, pass binding and available question numbers
    var annotationsBinding: Binding<[QuestionAnnotation]>?
    var availableQuestionNumbers: [String]?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            // ✅ Calculate fitted image size (unified calculation)
            let fittedSize = fittedImageSize(image.size, geometry.size)

            ZStack {
                // Image with zoom/pan gestures
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fittedSize.width, height: fittedSize.height)
                    .gesture(
                        SimultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 0.5), 4.0)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                },
                            DragGesture()
                                .onChanged { value in
                                    let newOffset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                    offset = newOffset
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.0
                            }
                        }
                    }
                    .overlay(
                        // ✅ CRITICAL FIX: Unified overlay rendering (both interactive and non-interactive)
                        // Both share the same coordinate system with scale/offset transforms
                        Group {
                            if isInteractive, let binding = annotationsBinding, let questionNumbers = availableQuestionNumbers {
                                // Interactive mode: user can drag/resize annotations
                                AnnotationOverlay(
                                    annotations: binding,
                                    selectedAnnotationId: $selectedAnnotationId,
                                    availableQuestionNumbers: questionNumbers,
                                    fittedImageSize: fittedSize
                                )
                            } else if !isInteractive && !annotations.isEmpty {
                                // Non-interactive mode: read-only visualization
                                annotationsOverlay(imageSize: fittedSize)
                            }
                        }
                    )
                    // ✅ CRITICAL: Apply transforms to BOTH image and overlay together
                    .scaleEffect(scale)
                    .offset(offset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .clipped()
        }
    }

    // ✅ Unified image size calculation (used by both view and overlay)
    private func fittedImageSize(_ imageSize: CGSize, _ containerSize: CGSize) -> CGSize {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    // MARK: - Annotations Overlay (Read-only)

    private func annotationsOverlay(imageSize: CGSize) -> some View {
        return ZStack {
            ForEach(Array(annotations.enumerated()), id: \.offset) { index, annotation in
                let topLeft = CGPoint(
                    x: CGFloat(annotation.topLeft[0]) * imageSize.width,
                    y: CGFloat(annotation.topLeft[1]) * imageSize.height
                )

                let bottomRight = CGPoint(
                    x: CGFloat(annotation.bottomRight[0]) * imageSize.width,
                    y: CGFloat(annotation.bottomRight[1]) * imageSize.height
                )

                let rect = CGRect(
                    x: topLeft.x,
                    y: topLeft.y,
                    width: bottomRight.x - topLeft.x,
                    height: bottomRight.y - topLeft.y
                )

                Rectangle()
                    .stroke(annotation.color, lineWidth: 2)
                    .background(
                        Rectangle()
                            .fill(annotation.color.opacity(0.1))
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .overlay(
                        Text(annotation.questionNumber ?? "?")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(annotation.color)
                            )
                            .position(x: topLeft.x + 30, y: topLeft.y - 10)
                    )
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)
    }
}

// MARK: - Annotation Overlay (Interactive)

struct AnnotationOverlay: View {
    @Binding var annotations: [QuestionAnnotation]
    @Binding var selectedAnnotationId: UUID?
    let availableQuestionNumbers: [String]
    let fittedImageSize: CGSize  // ✅ Accept fitted size from parent (no calculation)

    var body: some View {
        ZStack {
            // Tap to create new annotation (only on actual image area)
            Color.clear
                .contentShape(Rectangle())
                .frame(width: fittedImageSize.width, height: fittedImageSize.height)
                .onTapGesture { location in
                    createAnnotation(at: location, imageSize: fittedImageSize)
                }

            // Render interactive annotations
            ForEach(Array(annotations.enumerated()), id: \.element.id) { index, annotation in
                InteractiveAnnotationBox(
                    annotation: $annotations[index],
                    isSelected: selectedAnnotationId == annotation.id,
                    imageSize: fittedImageSize,
                    onSelect: {
                        withAnimation(.spring()) {
                            selectedAnnotationId = annotation.id
                        }
                    },
                    onMove: { delta in
                        moveAnnotation(id: annotation.id, delta: delta, imageSize: fittedImageSize)
                    },
                    onResize: { finalRect in
                        // ✅ CHANGED: Receive final rect instead of corner + delta
                        resizeAnnotation(id: annotation.id, to: finalRect, imageSize: fittedImageSize)
                    }
                )
            }
        }
        .frame(width: fittedImageSize.width, height: fittedImageSize.height)
    }

    // MARK: - Create Annotation

    private func createAnnotation(at location: CGPoint, imageSize: CGSize) {
        // Calculate square size (15% of image width)
        let squareSize = imageSize.width * 0.15

        // Calculate top-left corner (center the square at tap location)
        let topLeftX = max(0, min(imageSize.width - squareSize, location.x - squareSize / 2))
        let topLeftY = max(0, min(imageSize.height - squareSize, location.y - squareSize / 2))

        // Convert to normalized coordinates [0-1]
        let topLeft = [
            Double(topLeftX / imageSize.width),
            Double(topLeftY / imageSize.height)
        ]

        let bottomRight = [
            Double((topLeftX + squareSize) / imageSize.width),
            Double((topLeftY + squareSize) / imageSize.height)
        ]

        let annotationColors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        let color = annotationColors[annotations.count % annotationColors.count]

        let newAnnotation = QuestionAnnotation(
            topLeft: topLeft,
            bottomRight: bottomRight,
            questionNumber: nil,
            color: color
        )

        withAnimation(.spring()) {
            annotations.append(newAnnotation)
            selectedAnnotationId = newAnnotation.id
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    // MARK: - Move Annotation

    private func moveAnnotation(id: UUID, delta: CGSize, imageSize: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = annotations[index]

        // Convert delta to normalized coordinates
        let deltaX = Double(delta.width / imageSize.width)
        let deltaY = Double(delta.height / imageSize.height)

        // Calculate new position
        var newTopLeft = [
            annotation.topLeft[0] + deltaX,
            annotation.topLeft[1] + deltaY
        ]

        var newBottomRight = [
            annotation.bottomRight[0] + deltaX,
            annotation.bottomRight[1] + deltaY
        ]

        // Clamp to [0, 1] bounds
        let width = newBottomRight[0] - newTopLeft[0]
        let height = newBottomRight[1] - newTopLeft[1]

        if newTopLeft[0] < 0 {
            newTopLeft[0] = 0
            newBottomRight[0] = width
        }
        if newTopLeft[1] < 0 {
            newTopLeft[1] = 0
            newBottomRight[1] = height
        }
        if newBottomRight[0] > 1 {
            newBottomRight[0] = 1
            newTopLeft[0] = 1 - width
        }
        if newBottomRight[1] > 1 {
            newBottomRight[1] = 1
            newTopLeft[1] = 1 - height
        }

        annotation.topLeft = newTopLeft
        annotation.bottomRight = newBottomRight

        // ✅ FIX: Immediately update array to prevent snap-back
        annotations[index] = annotation
    }

    // MARK: - Resize Annotation

    /// ✅ CHANGED: Accept final rect instead of corner + delta
    /// This ensures preview rect (with clamp) = final rect (no jump)
    private func resizeAnnotation(id: UUID, to finalRect: CGRect, imageSize: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = annotations[index]

        // ✅ Convert final rect to normalized coordinates [0-1]
        let newTopLeft = [
            Double(finalRect.minX / imageSize.width),
            Double(finalRect.minY / imageSize.height)
        ]
        let newBottomRight = [
            Double(finalRect.maxX / imageSize.width),
            Double(finalRect.maxY / imageSize.height)
        ]

        annotation.topLeft = newTopLeft
        annotation.bottomRight = newBottomRight

        // ✅ Update array immediately
        annotations[index] = annotation
    }
}

// MARK: - Interactive Annotation Box

struct InteractiveAnnotationBox: View {
    @Binding var annotation: QuestionAnnotation
    let isSelected: Bool
    let imageSize: CGSize
    let onSelect: () -> Void
    let onMove: (CGSize) -> Void
    let onResize: (CGRect) -> Void

    // ✅ NEW SOLUTION: Track which corner is being dragged (for resize only)
    @State private var activeResizeCorner: ResizeCorner? = nil
    @State private var lastDragLocation: CGPoint = .zero

    var body: some View {
        let minScreenSize: CGFloat = 60
        let minNormalizedWidth = max(0.05, Double(minScreenSize / imageSize.width))
        let minNormalizedHeight = max(0.05, Double(minScreenSize / imageSize.height))

        // ✅ CRITICAL: Always use annotation data directly (no preview layer)
        let topLeft = CGPoint(
            x: CGFloat(annotation.topLeft[0]) * imageSize.width,
            y: CGFloat(annotation.topLeft[1]) * imageSize.height
        )
        let bottomRight = CGPoint(
            x: CGFloat(annotation.bottomRight[0]) * imageSize.width,
            y: CGFloat(annotation.bottomRight[1]) * imageSize.height
        )
        let currentRect = CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )

        return ZStack {
            // Bounding box
            Rectangle()
                .stroke(annotation.color, lineWidth: isSelected ? 4 : 2)
                .background(
                    Rectangle()
                        .fill(annotation.color.opacity(isSelected ? 0.15 : 0.05))
                )
                .frame(width: currentRect.width, height: currentRect.height)
                .position(x: currentRect.midX, y: currentRect.midY)
                .highPriorityGesture(moveGesture())

            // Question number label
            Text(annotation.questionNumber ?? "?")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(annotation.color)
                )
                .position(x: currentRect.minX + 30, y: currentRect.minY - 10)

            // Corner resize handles (only when selected)
            if isSelected {
                ResizeHandleView(corner: .topLeft, color: annotation.color)
                    .position(x: currentRect.minX, y: currentRect.minY)
                    .highPriorityGesture(resizeGesture(corner: .topLeft, minNormalizedWidth: minNormalizedWidth, minNormalizedHeight: minNormalizedHeight))

                ResizeHandleView(corner: .topRight, color: annotation.color)
                    .position(x: currentRect.maxX, y: currentRect.minY)
                    .highPriorityGesture(resizeGesture(corner: .topRight, minNormalizedWidth: minNormalizedWidth, minNormalizedHeight: minNormalizedHeight))

                ResizeHandleView(corner: .bottomLeft, color: annotation.color)
                    .position(x: currentRect.minX, y: currentRect.maxY)
                    .highPriorityGesture(resizeGesture(corner: .bottomLeft, minNormalizedWidth: minNormalizedWidth, minNormalizedHeight: minNormalizedHeight))

                ResizeHandleView(corner: .bottomRight, color: annotation.color)
                    .position(x: currentRect.maxX, y: currentRect.maxY)
                    .highPriorityGesture(resizeGesture(corner: .bottomRight, minNormalizedWidth: minNormalizedWidth, minNormalizedHeight: minNormalizedHeight))
            }
        }
    }

    // MARK: - Move Gesture (Real-time data updates)

    private func moveGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onSelect()

                // ✅ Calculate incremental delta from last position
                let dx = value.location.x - lastDragLocation.x
                let dy = value.location.y - lastDragLocation.y

                // Update last position
                lastDragLocation = value.location

                // ✅ CRITICAL: Update annotation data in real-time (not on .onEnded)
                if dx != 0 || dy != 0 {
                    onMove(CGSize(width: dx, height: dy))
                }
            }
            .onEnded { _ in
                // Reset tracking
                lastDragLocation = .zero
            }
    }

    // MARK: - Resize Gesture (Real-time data updates)

    private func resizeGesture(corner: ResizeCorner, minNormalizedWidth: Double, minNormalizedHeight: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onSelect()

                if activeResizeCorner == nil {
                    activeResizeCorner = corner
                    lastDragLocation = value.startLocation
                }

                // ✅ Calculate incremental delta from last position
                let dx = value.location.x - lastDragLocation.x
                let dy = value.location.y - lastDragLocation.y

                // Update last position
                lastDragLocation = value.location

                // ✅ CRITICAL: Update annotation data in real-time
                if dx != 0 || dy != 0 {
                    // Calculate new rect with delta applied
                    let topLeft = CGPoint(
                        x: CGFloat(annotation.topLeft[0]) * imageSize.width,
                        y: CGFloat(annotation.topLeft[1]) * imageSize.height
                    )
                    let bottomRight = CGPoint(
                        x: CGFloat(annotation.bottomRight[0]) * imageSize.width,
                        y: CGFloat(annotation.bottomRight[1]) * imageSize.height
                    )

                    var newTopLeft = topLeft
                    var newBottomRight = bottomRight

                    let minWidth = CGFloat(minNormalizedWidth * Double(imageSize.width))
                    let minHeight = CGFloat(minNormalizedHeight * Double(imageSize.height))

                    // Apply delta to appropriate corner with clamping
                    switch corner {
                    case .topLeft:
                        newTopLeft.x = max(0, min(bottomRight.x - minWidth, topLeft.x + dx))
                        newTopLeft.y = max(0, min(bottomRight.y - minHeight, topLeft.y + dy))

                    case .topRight:
                        newBottomRight.x = max(topLeft.x + minWidth, min(imageSize.width, bottomRight.x + dx))
                        newTopLeft.y = max(0, min(bottomRight.y - minHeight, topLeft.y + dy))

                    case .bottomLeft:
                        newTopLeft.x = max(0, min(bottomRight.x - minWidth, topLeft.x + dx))
                        newBottomRight.y = max(topLeft.y + minHeight, min(imageSize.height, bottomRight.y + dy))

                    case .bottomRight:
                        newBottomRight.x = max(topLeft.x + minWidth, min(imageSize.width, bottomRight.x + dx))
                        newBottomRight.y = max(topLeft.y + minHeight, min(imageSize.height, bottomRight.y + dy))
                    }

                    let finalRect = CGRect(
                        x: newTopLeft.x,
                        y: newTopLeft.y,
                        width: newBottomRight.x - newTopLeft.x,
                        height: newBottomRight.y - newTopLeft.y
                    )

                    // Submit rect immediately
                    onResize(finalRect)
                }
            }
            .onEnded { _ in
                // Reset tracking
                activeResizeCorner = nil
                lastDragLocation = .zero
            }
    }
}

// MARK: - Resize Handle View

struct ResizeHandleView: View {
    let corner: ResizeCorner
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Resize Corner Enum

enum ResizeCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

extension ResizeCorner: CustomStringConvertible {
    var description: String {
        switch self {
        case .topLeft: return "topLeft"
        case .topRight: return "topRight"
        case .bottomLeft: return "bottomLeft"
        case .bottomRight: return "bottomRight"
        }
    }
}
