//
//  UnifiedImageEditorView.swift
//  StudyAI
//
//  Created by Claude Code on 9/29/25.
//

import SwiftUI
import UIKit

struct UnifiedImageEditorView: View {
    @Binding var originalImage: UIImage?
    @Binding var editedImage: UIImage?
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme

    @State private var originalImageState: UIImage?
    @State private var imageUpdateTrigger = UUID()
    @State private var brightnessValue: Float = 0.0
    @State private var cropRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var selectedSizeReduction: SizeReductionOption = .raw
    @State private var previewResizedImage: UIImage?
    @State private var rotationAngle: Angle = .zero
    @State private var rotationScale: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero
    @GestureState private var gestureScale: CGFloat = 1.0
    @State private var showGestureHint = true

    private let imageEnhancer = ImageEnhancer.shared

    enum SizeReductionOption: String, CaseIterable, Identifiable {
        case raw = "Raw"
        case large = "Large"
        case medium = "Medium"
        case small = "Small"

        var id: String { self.rawValue }

        var localizedName: String {
            switch self {
            case .raw:    return NSLocalizedString("imageEditor.size.raw", value: "Raw", comment: "")
            case .large:  return NSLocalizedString("imageEditor.size.large", value: "Large", comment: "")
            case .medium: return NSLocalizedString("imageEditor.size.medium", value: "Medium", comment: "")
            case .small:  return NSLocalizedString("imageEditor.size.small", value: "Small", comment: "")
            }
        }

        var scale: CGFloat {
            switch self {
            case .raw: return 1.0      // 100% - Original size
            case .large: return 0.5    // 50% - Was 75%, now more aggressive
            case .medium: return 0.3   // 30% - Was 50%, much more aggressive
            case .small: return 0.15   // 15% - Was 25%, very aggressive
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Image preview — crop corners + rotate/zoom gestures always active
                if let image = displayImage ?? originalImageState {
                    GeometryReader { geometry in
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .brightness(Double(brightnessValue))
                                .rotationEffect(rotationAngle + gestureRotation)
                                .scaleEffect(max(0.1, rotationScale * gestureScale))
                                .id(imageUpdateTrigger)

                            buildCropOverlay(image: image, geometry: geometry)

                            // Gesture hint — fades out after 2.5s
                            if showGestureHint {
                                VStack(spacing: 6) {
                                    Image(systemName: "hand.pinch.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                    Text(NSLocalizedString("imageEditor.gestureHint", comment: ""))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 14)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                .background(Color.black.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .transition(.opacity)
                                .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(rotateAndScaleGesture)
                    }
                    .frame(height: UIScreen.main.bounds.height * 0.5)
                    .clipped()
                    .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                    .padding(.top, 20)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation(.easeOut(duration: 0.6)) { showGestureHint = false }
                        }
                    }
                }

                // Brightness slider
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Slider(value: $brightnessValue, in: -1.0...1.0, step: 0.05)
                        .accentColor(.orange)
                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()

                // Resize picker
                VStack(spacing: 10) {
                    HStack {
                        Text(NSLocalizedString("imageEditor.resolution", comment: "Resolution"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if let img = originalImageState {
                            Text(selectedSizeReduction == .raw
                                 ? formatImageSize(img)
                                 : "\(formatImageSize(img)) → \(formatReducedImageSize(img, scale: selectedSizeReduction.scale))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Picker("", selection: $selectedSizeReduction) {
                        ForEach(SizeReductionOption.allCases) { option in
                            Text(option.localizedName).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Spacer()

                // Done / Reset buttons
                HStack(spacing: 16) {
                    Button(NSLocalizedString("imageEditor.reset", comment: "Reset")) {
                        setupInitialImage()
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray5))
                    .cornerRadius(12)

                    Button(NSLocalizedString("imageEditor.done", comment: "Done")) {
                        applyEditsAndFinish()
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                setupInitialImage()
            }
            .onChange(of: selectedSizeReduction) { _, _ in
                updateResizePreview()
            }
        }
    }

    private var displayImage: UIImage? {
        selectedSizeReduction != .raw ? previewResizedImage ?? originalImageState : originalImageState
    }

    // MARK: - Crop Overlay View Helper
    private func buildCropOverlay(image: UIImage, geometry: GeometryProxy) -> some View {
        let imageAspectRatio = image.size.width / image.size.height
        let containerAspectRatio = geometry.size.width / geometry.size.height

        let displayedImageSize: CGSize
        let imageOffset: CGPoint

        if imageAspectRatio > containerAspectRatio {
            displayedImageSize = CGSize(
                width: geometry.size.width,
                height: geometry.size.width / imageAspectRatio
            )
            imageOffset = CGPoint(
                x: 0,
                y: (geometry.size.height - displayedImageSize.height) / 2
            )
        } else {
            displayedImageSize = CGSize(
                width: geometry.size.height * imageAspectRatio,
                height: geometry.size.height
            )
            imageOffset = CGPoint(
                x: (geometry.size.width - displayedImageSize.width) / 2,
                y: 0
            )
        }

        // Calculate the crop rectangle in screen coordinates
        let cropRectScreen = CGRect(
            x: imageOffset.x + cropRect.origin.x * displayedImageSize.width,
            y: imageOffset.y + cropRect.origin.y * displayedImageSize.height,
            width: cropRect.width * displayedImageSize.width,
            height: cropRect.height * displayedImageSize.height
        )

        return ZStack {
            // Dimmed overlay outside crop area
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .mask(
                    Rectangle()
                        .fill(Color.white)
                        .overlay(
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: cropRectScreen.width, height: cropRectScreen.height)
                                .position(x: cropRectScreen.midX, y: cropRectScreen.midY)
                                .blendMode(.destinationOut)
                        )
                )

            // Crop rectangle border
            Rectangle()
                .strokeBorder(colorScheme == .dark ? Color(.systemGray) : Color.white, lineWidth: 2)
                .background(Rectangle().fill(Color.clear))
                .frame(width: cropRectScreen.width, height: cropRectScreen.height)
                .position(x: cropRectScreen.midX, y: cropRectScreen.midY)

            // Grid lines (rule of thirds)
            Path { path in
                // Vertical lines
                let oneThirdWidth = cropRectScreen.width / 3
                path.move(to: CGPoint(x: cropRectScreen.minX + oneThirdWidth, y: cropRectScreen.minY))
                path.addLine(to: CGPoint(x: cropRectScreen.minX + oneThirdWidth, y: cropRectScreen.maxY))
                path.move(to: CGPoint(x: cropRectScreen.minX + 2 * oneThirdWidth, y: cropRectScreen.minY))
                path.addLine(to: CGPoint(x: cropRectScreen.minX + 2 * oneThirdWidth, y: cropRectScreen.maxY))

                // Horizontal lines
                let oneThirdHeight = cropRectScreen.height / 3
                path.move(to: CGPoint(x: cropRectScreen.minX, y: cropRectScreen.minY + oneThirdHeight))
                path.addLine(to: CGPoint(x: cropRectScreen.maxX, y: cropRectScreen.minY + oneThirdHeight))
                path.move(to: CGPoint(x: cropRectScreen.minX, y: cropRectScreen.minY + 2 * oneThirdHeight))
                path.addLine(to: CGPoint(x: cropRectScreen.maxX, y: cropRectScreen.minY + 2 * oneThirdHeight))
            }
            .stroke((colorScheme == .dark ? Color(.systemGray) : Color.white).opacity(0.5), lineWidth: 1)

            // Corner handles for resizing
            ForEach(0..<4, id: \.self) { corner in
                Circle()
                    .fill(colorScheme == .dark ? Color(.systemGray5) : Color.white)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                    .position(getCornerPosition(corner, cropRectScreen: cropRectScreen))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                resizeCropRect(corner: corner, dragLocation: value.location, imageOffset: imageOffset, displayedImageSize: displayedImageSize)
                            }
                    )
            }

            // Drag gesture for moving the entire rectangle
            Rectangle()
                .fill(Color.clear)
                .frame(width: cropRectScreen.width, height: cropRectScreen.height)
                .position(x: cropRectScreen.midX, y: cropRectScreen.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            moveCropRect(dragLocation: value.location, imageOffset: imageOffset, displayedImageSize: displayedImageSize)
                        }
                )
        }
    }

    // MARK: - Crop Helper Functions

    private func getCornerPosition(_ corner: Int, cropRectScreen: CGRect) -> CGPoint {
        switch corner {
        case 0: return CGPoint(x: cropRectScreen.minX, y: cropRectScreen.minY) // Top-left
        case 1: return CGPoint(x: cropRectScreen.maxX, y: cropRectScreen.minY) // Top-right
        case 2: return CGPoint(x: cropRectScreen.maxX, y: cropRectScreen.maxY) // Bottom-right
        case 3: return CGPoint(x: cropRectScreen.minX, y: cropRectScreen.maxY) // Bottom-left
        default: return .zero
        }
    }

    private func resizeCropRect(corner: Int, dragLocation: CGPoint, imageOffset: CGPoint, displayedImageSize: CGSize) {
        // Convert drag location to relative coordinates
        let relativeX = max(0, min(1, (dragLocation.x - imageOffset.x) / displayedImageSize.width))
        let relativeY = max(0, min(1, (dragLocation.y - imageOffset.y) / displayedImageSize.height))

        var newRect = cropRect

        switch corner {
        case 0: // Top-left
            let newWidth = max(0.1, cropRect.maxX - relativeX)
            let newHeight = max(0.1, cropRect.maxY - relativeY)
            newRect = CGRect(x: relativeX, y: relativeY, width: newWidth, height: newHeight)
        case 1: // Top-right
            let newWidth = max(0.1, relativeX - cropRect.minX)
            let newHeight = max(0.1, cropRect.maxY - relativeY)
            newRect = CGRect(x: cropRect.minX, y: relativeY, width: newWidth, height: newHeight)
        case 2: // Bottom-right
            let newWidth = max(0.1, relativeX - cropRect.minX)
            let newHeight = max(0.1, relativeY - cropRect.minY)
            newRect = CGRect(x: cropRect.minX, y: cropRect.minY, width: newWidth, height: newHeight)
        case 3: // Bottom-left
            let newWidth = max(0.1, cropRect.maxX - relativeX)
            let newHeight = max(0.1, relativeY - cropRect.minY)
            newRect = CGRect(x: relativeX, y: cropRect.minY, width: newWidth, height: newHeight)
        default:
            break
        }

        // Ensure the crop rect stays within bounds
        if newRect.minX >= 0 && newRect.maxX <= 1 && newRect.minY >= 0 && newRect.maxY <= 1 {
            cropRect = newRect
        }
    }

    private func moveCropRect(dragLocation: CGPoint, imageOffset: CGPoint, displayedImageSize: CGSize) {
        // Convert drag location to relative coordinates
        let relativeX = (dragLocation.x - imageOffset.x) / displayedImageSize.width
        let relativeY = (dragLocation.y - imageOffset.y) / displayedImageSize.height

        // Calculate new origin (center the rect on the drag location)
        let newX = relativeX - cropRect.width / 2
        let newY = relativeY - cropRect.height / 2

        // Ensure the crop rect stays within bounds
        let clampedX = max(0, min(1 - cropRect.width, newX))
        let clampedY = max(0, min(1 - cropRect.height, newY))

        cropRect.origin = CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - Rotate Gesture
    private var rotateAndScaleGesture: some Gesture {
        SimultaneousGesture(
            RotationGesture()
                .updating($gestureRotation) { value, state, _ in state = value }
                .onEnded { value in rotationAngle += value },
            MagnificationGesture()
                .updating($gestureScale) { value, state, _ in state = value }
                .onEnded { value in rotationScale = max(0.1, rotationScale * value) }
        )
    }

    // MARK: - Setup & Helpers

    private func setupInitialImage() {
        originalImageState = originalImage
        brightnessValue = 0.0
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        rotationAngle = .zero
        rotationScale = 1.0
        selectedSizeReduction = .raw
        previewResizedImage = nil
        imageUpdateTrigger = UUID()
    }

    private func updateResizePreview() {
        guard selectedSizeReduction != .raw, let base = originalImageState else {
            previewResizedImage = nil
            return
        }
        let newSize = CGSize(
            width: base.size.width * selectedSizeReduction.scale,
            height: base.size.height * selectedSizeReduction.scale
        )
        UIGraphicsBeginImageContextWithOptions(newSize, false, base.scale)
        base.draw(in: CGRect(origin: .zero, size: newSize))
        previewResizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }

    private func applyEditsAndFinish() {
        guard let base = selectedSizeReduction != .raw
                ? previewResizedImage ?? originalImageState
                : originalImageState else {
            isPresented = false
            return
        }

        // 1. Brightness via CIFilter (contrast 0 = no change)
        let brightened = imageEnhancer.adjustBrightnessAndContrast(base, brightness: brightnessValue, contrast: 0)

        // 2. Bake rotation + scale
        let size = brightened.size
        let totalAngle = rotationAngle + gestureRotation
        let totalScale = max(0.1, rotationScale * gestureScale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let rotated = renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.translateBy(x: size.width / 2, y: size.height / 2)
            cgCtx.rotate(by: CGFloat(totalAngle.radians))
            cgCtx.scaleBy(x: totalScale, y: totalScale)
            brightened.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }

        // 3. Apply crop via cgImage.cropping
        UIGraphicsBeginImageContextWithOptions(rotated.size, false, rotated.scale)
        rotated.draw(in: CGRect(origin: .zero, size: rotated.size))
        let oriented = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        var result = rotated
        if let cgImg = (oriented ?? rotated).cgImage {
            let px = CGRect(
                x: cropRect.origin.x * rotated.size.width * rotated.scale,
                y: cropRect.origin.y * rotated.size.height * rotated.scale,
                width: cropRect.width * rotated.size.width * rotated.scale,
                height: cropRect.height * rotated.size.height * rotated.scale
            )
            if let cropped = cgImg.cropping(to: px) {
                result = UIImage(cgImage: cropped, scale: rotated.scale, orientation: .up)
            }
        }

        editedImage = result
        isPresented = false
    }

    private func formatImageSize(_ image: UIImage) -> String {
        let sizeInBytes = image.jpegData(compressionQuality: 0.8)?.count ?? 0
        let sizeInMB = Double(sizeInBytes) / (1024 * 1024)
        return String(format: "%.1f MB", sizeInMB)
    }

    private func formatReducedImageSize(_ image: UIImage, scale: CGFloat) -> String {
        // Actually resize the image to get accurate size measurement
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let resized = resizedImage else {
            // Fallback to estimation if resize fails
            let originalBytes = image.jpegData(compressionQuality: 0.8)?.count ?? 0
            let reducedBytes = Int(Double(originalBytes) * Double(scale * scale))
            let sizeInMB = Double(reducedBytes) / (1024 * 1024)
            return String(format: "%.1f MB (est.)", sizeInMB)
        }

        // Get actual JPEG size of resized image
        let actualBytes = resized.jpegData(compressionQuality: 0.8)?.count ?? 0
        let sizeInMB = Double(actualBytes) / (1024 * 1024)
        return String(format: "%.1f MB", sizeInMB)
    }
}

#Preview {
    UnifiedImageEditorView(
        originalImage: .constant(UIImage(systemName: "photo")),
        editedImage: .constant(nil),
        isPresented: .constant(true)
    )
}