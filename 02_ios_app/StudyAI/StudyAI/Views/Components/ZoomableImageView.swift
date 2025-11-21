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

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Image with zoom/pan gestures
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
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

                // Annotation boxes overlay (non-interactive visualization)
                if !isInteractive && !annotations.isEmpty {
                    annotationsOverlay(geometry: geometry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .clipped()
        }
    }

    // MARK: - Annotations Overlay (Read-only)

    private func annotationsOverlay(geometry: GeometryProxy) -> some View {
        let imageSize = calculateImageSize(containerSize: geometry.size)

        return ZStack {
            ForEach(Array(annotations.enumerated()), id: \.element.id) { index, annotation in
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
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
    }

    // MARK: - Helper Methods

    private func calculateImageSize(containerSize: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            // Image is wider, fit to width
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image is taller, fit to height
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }
}

// MARK: - Annotation Overlay (Interactive)

struct AnnotationOverlay: View {
    @Binding var annotations: [QuestionAnnotation]
    @Binding var selectedAnnotationId: UUID?
    let availableQuestionNumbers: [String]
    let originalImageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Tap to create new annotation
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        createAnnotation(at: location, imageSize: geometry.size)
                    }

                // Render interactive annotations
                ForEach(Array(annotations.enumerated()), id: \.element.id) { index, annotation in
                    InteractiveAnnotationBox(
                        annotation: $annotations[index],
                        isSelected: selectedAnnotationId == annotation.id,
                        imageSize: geometry.size,
                        onSelect: {
                            withAnimation(.spring()) {
                                selectedAnnotationId = annotation.id
                            }
                        },
                        onMove: { delta in
                            moveAnnotation(id: annotation.id, delta: delta, imageSize: geometry.size)
                        },
                        onResize: { corner, delta in
                            resizeAnnotation(id: annotation.id, corner: corner, delta: delta, imageSize: geometry.size)
                        }
                    )
                }
            }
        }
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

        print("📝 Created annotation at (\(Int(location.x)), \(Int(location.y)))")
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

        annotations[index] = annotation
    }

    // MARK: - Resize Annotation

    private func resizeAnnotation(id: UUID, corner: ResizeCorner, delta: CGSize, imageSize: CGSize) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        var annotation = annotations[index]

        // Convert delta to normalized coordinates
        let deltaX = Double(delta.width / imageSize.width)
        let deltaY = Double(delta.height / imageSize.height)

        // Adjust coordinates based on corner
        switch corner {
        case .topLeft:
            annotation.topLeft[0] = max(0, min(annotation.bottomRight[0] - 0.05, annotation.topLeft[0] + deltaX))
            annotation.topLeft[1] = max(0, min(annotation.bottomRight[1] - 0.05, annotation.topLeft[1] + deltaY))

        case .topRight:
            annotation.bottomRight[0] = max(annotation.topLeft[0] + 0.05, min(1, annotation.bottomRight[0] + deltaX))
            annotation.topLeft[1] = max(0, min(annotation.bottomRight[1] - 0.05, annotation.topLeft[1] + deltaY))

        case .bottomLeft:
            annotation.topLeft[0] = max(0, min(annotation.bottomRight[0] - 0.05, annotation.topLeft[0] + deltaX))
            annotation.bottomRight[1] = max(annotation.topLeft[1] + 0.05, min(1, annotation.bottomRight[1] + deltaY))

        case .bottomRight:
            annotation.bottomRight[0] = max(annotation.topLeft[0] + 0.05, min(1, annotation.bottomRight[0] + deltaX))
            annotation.bottomRight[1] = max(annotation.topLeft[1] + 0.05, min(1, annotation.bottomRight[1] + deltaY))
        }

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
    let onResize: (ResizeCorner, CGSize) -> Void

    @GestureState private var dragOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    var body: some View {
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

        return ZStack {
            // Bounding box
            Rectangle()
                .stroke(annotation.color, lineWidth: isSelected ? 4 : 2)
                .background(
                    Rectangle()
                        .fill(annotation.color.opacity(isSelected ? 0.15 : 0.05))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX + dragOffset.width, y: rect.midY + dragOffset.height)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($dragOffset) { value, state, _ in
                            state = value.translation
                        }
                        .onChanged { _ in
                            if !isDragging {
                                onSelect()
                                isDragging = true
                            }
                        }
                        .onEnded { value in
                            onMove(value.translation)
                            isDragging = false
                        }
                )

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
                .position(x: topLeft.x + 30 + dragOffset.width, y: topLeft.y - 10 + dragOffset.height)

            // Corner resize handles (only when selected)
            if isSelected {
                ResizeHandleView(corner: .topLeft, color: annotation.color)
                    .position(x: topLeft.x + dragOffset.width, y: topLeft.y + dragOffset.height)
                    .gesture(cornerDragGesture(corner: .topLeft))

                ResizeHandleView(corner: .topRight, color: annotation.color)
                    .position(x: bottomRight.x + dragOffset.width, y: topLeft.y + dragOffset.height)
                    .gesture(cornerDragGesture(corner: .topRight))

                ResizeHandleView(corner: .bottomLeft, color: annotation.color)
                    .position(x: topLeft.x + dragOffset.width, y: bottomRight.y + dragOffset.height)
                    .gesture(cornerDragGesture(corner: .bottomLeft))

                ResizeHandleView(corner: .bottomRight, color: annotation.color)
                    .position(x: bottomRight.x + dragOffset.width, y: bottomRight.y + dragOffset.height)
                    .gesture(cornerDragGesture(corner: .bottomRight))
            }
        }
    }

    private func cornerDragGesture(corner: ResizeCorner) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isDragging {
                    onSelect()
                }
            }
            .onEnded { value in
                onResize(corner, value.translation)
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
