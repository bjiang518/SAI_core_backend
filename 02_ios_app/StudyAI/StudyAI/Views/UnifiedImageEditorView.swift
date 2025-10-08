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

    @State private var currentImage: UIImage?
    @State private var brightnessValue: Float = 0.0
    @State private var contrastValue: Float = 0.0
    @State private var showingCropView = false
    @State private var showingSizeReduction = false
    @State private var croppedImage: UIImage?

    // Independent image states for each edit type
    @State private var originalImageState: UIImage? // Store the true original
    @State private var brightnessAdjustedImage: UIImage? // Image with brightness/contrast applied
    @State private var croppedAdjustedImage: UIImage? // Image with crop applied
    @State private var resizedAdjustedImage: UIImage? // Image with resize applied

    // Crop state with simple rectangle (relative coordinates 0-1)
    @State private var cropRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var isDraggingRect = false
    @State private var dragStartLocation: CGPoint = .zero

    // Size reduction options
    @State private var selectedSizeReduction: SizeReductionOption = .raw


    private let imageEnhancer = ImageEnhancer.shared

    enum EditorTab: String, CaseIterable, Identifiable {
        case brightness = "Brightness"
        case crop = "Crop"
        case resize = "Resize"

        var id: String { self.rawValue }

        var icon: String {
            switch self {
            case .brightness: return "sun.max.fill"
            case .crop: return "crop"
            case .resize: return "arrow.down.right.and.arrow.up.left"
            }
        }
    }

    enum SizeReductionOption: String, CaseIterable, Identifiable {
        case raw = "Raw"
        case large = "Large"
        case medium = "Medium"
        case small = "Small"

        var id: String { self.rawValue }

        var scale: CGFloat {
            switch self {
            case .raw: return 1.0
            case .large: return 0.75
            case .medium: return 0.5
            case .small: return 0.25
            }
        }
    }

    @State private var selectedTab: EditorTab = .brightness

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Image Preview - with crop overlay when crop tab is selected
                if let image = currentImage {
                    GeometryReader { geometry in
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()

                            // Show crop overlay when crop tab is selected
                            if selectedTab == .crop {
                                buildCropOverlay(image: image, geometry: geometry)
                            }
                        }
                    }
                    .frame(height: 400)
                    .background(Color.black.opacity(0.05))
                }

                // Tab Selector
                HStack(spacing: 0) {
                    ForEach(EditorTab.allCases) { tab in
                        Button(action: {
                            selectedTab = tab
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 16))
                                Text(tab.rawValue)
                                    .font(.caption)
                            }
                            .foregroundColor(selectedTab == tab ? .blue : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .background(
                            selectedTab == tab ? Color.blue.opacity(0.1) : Color.clear
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Editor Controls
                VStack(spacing: 12) {
                    switch selectedTab {
                    case .brightness:
                        brightnessControls
                    case .crop:
                        cropControls
                    case .resize:
                        resizeControls
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, maxHeight: 180, alignment: .top)
                .background(Color(.systemGroupedBackground))

                Spacer()

                // Action Button - Centered and Enlarged Done Button
                HStack {
                    Spacer()

                    Button("Done") {
                        applyEditsAndFinish()
                    }
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 60)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Edit Image")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                setupInitialImage()
            }
        }
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
                .strokeBorder(Color.white, lineWidth: 2)
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
            .stroke(Color.white.opacity(0.5), lineWidth: 1)

            // Corner handles for resizing
            ForEach(0..<4, id: \.self) { corner in
                Circle()
                    .fill(Color.white)
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

    // MARK: - Brightness Controls
    private var brightnessControls: some View {
        VStack(spacing: 16) {
            // Brightness Slider
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "sun.min")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Slider(value: $brightnessValue, in: -1.0...1.0, step: 0.1, onEditingChanged: { editing in
                        if !editing {
                            applyBrightnessAdjustment()
                        }
                    })
                    .accentColor(.orange)

                    Image(systemName: "sun.max.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                Text("Brightness: \(String(format: "%.1f", brightnessValue))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Contrast Slider
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    Slider(value: $contrastValue, in: -1.0...1.0, step: 0.1, onEditingChanged: { editing in
                        if !editing {
                            applyContrastAdjustment()
                        }
                    })
                    .accentColor(.blue)

                    Image(systemName: "circle.righthalf.filled")
                        .foregroundColor(.primary)
                        .font(.caption)
                }

                Text("Contrast: \(String(format: "%.1f", contrastValue))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Action Buttons - Enlarged
            HStack(spacing: 16) {
                Button("Auto Enhance") {
                    autoEnhanceImage()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.15))
                .foregroundColor(.green)
                .cornerRadius(10)

                Button("Reset") {
                    resetBrightness()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.15))
                .foregroundColor(.gray)
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Crop Controls
    private var cropControls: some View {
        VStack(spacing: 16) {
            Text("Drag corners to resize • Drag center to move")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Apply Crop") {
                    applyRectangleCrop()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)

                Button("Reset Crop") {
                    resetCrop()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.gray)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Resize Controls
    private var resizeControls: some View {
        VStack(spacing: 16) {
            // Size Selection
            VStack(spacing: 8) {
                Text("Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Picker("Size", selection: $selectedSizeReduction) {
                    ForEach(SizeReductionOption.allCases) { option in
                        Text(option.rawValue)
                            .font(.subheadline)
                            .tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Size Info and Actions
            VStack(spacing: 12) {
                if let image = currentImage {
                    HStack {
                        Text("Current: \(formatImageSize(image))")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if selectedSizeReduction != .raw {
                            Text("→ \(formatReducedImageSize(image, scale: selectedSizeReduction.scale))")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }

                        Spacer()
                    }
                }

                // Independent Action Buttons
                HStack(spacing: 16) {
                    Button("Apply Size") {
                        applySizeReduction()
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(selectedSizeReduction == .raw ? Color.gray : Color.blue)
                    .cornerRadius(10)
                    .disabled(selectedSizeReduction == .raw)

                    Button("Reset Size") {
                        resetToOriginalSize()
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Independent State Management Helper Methods

    /// Rebuild current image by combining all active edits
    private func rebuildCurrentImage() {
        // Start with brightness/contrast adjusted image (or original if no brightness adjustments)
        var baseImage = brightnessAdjustedImage ?? originalImageState

        // Apply crop if different from original
        if let croppedImage = croppedAdjustedImage, croppedImage != originalImageState {
            baseImage = croppedImage
        }

        // Apply resize if different from raw
        if selectedSizeReduction != .raw, let resizedImage = resizedAdjustedImage {
            baseImage = resizedImage
        }

        currentImage = baseImage
    }

    /// Get combined image for resize operations (brightness + crop, but not previous resize)
    private func getCombinedImageForResize() -> UIImage? {
        // Start with brightness/contrast adjusted image
        var baseImage = brightnessAdjustedImage ?? originalImageState

        // Apply crop if different from original
        if let croppedImage = croppedAdjustedImage, croppedImage != originalImageState {
            baseImage = croppedImage
        }

        return baseImage
    }

    // MARK: - Helper Methods

    private func setupInitialImage() {
        currentImage = originalImage
        originalImageState = originalImage // Store true original
        brightnessAdjustedImage = originalImage
        croppedAdjustedImage = originalImage
        resizedAdjustedImage = originalImage
        brightnessValue = 0.0
        contrastValue = 0.0
        selectedSizeReduction = .raw
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    }

    private func resetToOriginal() {
        currentImage = originalImage
        brightnessValue = 0.0
        contrastValue = 0.0
        selectedSizeReduction = .raw
        croppedImage = nil
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    }

    private func applyRectangleCrop() {
        guard let image = currentImage else { return }

        print("📐 === RECTANGLE CROP ===")
        print("📐 Original image size: \(image.size)")
        print("📐 Crop rect (relative): \(cropRect)")

        // Calculate pixel coordinates from relative coordinates
        let pixelRect = CGRect(
            x: cropRect.origin.x * image.size.width,
            y: cropRect.origin.y * image.size.height,
            width: cropRect.width * image.size.width,
            height: cropRect.height * image.size.height
        )

        print("📐 Crop rect (pixels): \(pixelRect)")

        // Validate crop rect
        guard pixelRect.width > 0 && pixelRect.height > 0,
              pixelRect.minX >= 0 && pixelRect.minY >= 0,
              pixelRect.maxX <= image.size.width && pixelRect.maxY <= image.size.height else {
            print("❌ Invalid crop rect")
            return
        }

        // Create a graphics context with the original image size
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        // Draw the original image (this handles orientation automatically)
        image.draw(in: CGRect(origin: .zero, size: image.size))

        // Get the properly oriented image
        guard let orientedImage = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = orientedImage.cgImage else {
            print("❌ Failed to get oriented image")
            return
        }

        // Scale the crop rect for CGImage coordinates
        let scaledCropRect = CGRect(
            x: pixelRect.origin.x * image.scale,
            y: pixelRect.origin.y * image.scale,
            width: pixelRect.width * image.scale,
            height: pixelRect.height * image.scale
        )

        print("📐 Scaled crop rect for CGImage: \(scaledCropRect)")

        // Perform the crop
        guard let croppedCGImage = cgImage.cropping(to: scaledCropRect) else {
            print("❌ Failed to crop CGImage")
            return
        }

        // Create final UIImage with .up orientation (already oriented correctly)
        let croppedUIImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)

        print("📐 Cropped image size: \(croppedUIImage.size)")
        print("✅ Rectangle crop successful")
        print("📐 === END RECTANGLE CROP ===")

        // Update the state
        croppedAdjustedImage = croppedUIImage
        rebuildCurrentImage()
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8) // Reset for next crop
    }

    private func applyBrightnessAdjustment() {
        guard let original = originalImageState else { return }
        // Apply both brightness and contrast adjustments together
        let adjustedImage = imageEnhancer.adjustBrightnessAndContrast(original, brightness: brightnessValue, contrast: contrastValue)
        brightnessAdjustedImage = adjustedImage
        rebuildCurrentImage()
    }

    private func applyContrastAdjustment() {
        guard let original = originalImageState else { return }
        // Apply both brightness and contrast adjustments together
        let adjustedImage = imageEnhancer.adjustBrightnessAndContrast(original, brightness: brightnessValue, contrast: contrastValue)
        brightnessAdjustedImage = adjustedImage
        rebuildCurrentImage()
    }

    private func autoEnhanceImage() {
        guard let original = originalImageState else { return }
        let enhancedImage = imageEnhancer.preprocessForSegmentation(original)
        brightnessAdjustedImage = enhancedImage
        // Update the slider values to reflect the enhancement
        brightnessValue = 0.1 // Indicate that enhancement was applied
        contrastValue = 0.1
        rebuildCurrentImage()
    }

    private func resetBrightness() {
        brightnessValue = 0.0
        contrastValue = 0.0
        brightnessAdjustedImage = originalImageState
        rebuildCurrentImage()
    }

    private func resetToOriginalSize() {
        selectedSizeReduction = .raw
        resizedAdjustedImage = originalImageState
        rebuildCurrentImage()
    }

    private func applySizeReduction() {
        guard let baseImage = getCombinedImageForResize(), selectedSizeReduction != .raw else { return }

        let newSize = CGSize(
            width: baseImage.size.width * selectedSizeReduction.scale,
            height: baseImage.size.height * selectedSizeReduction.scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, false, baseImage.scale)
        baseImage.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        if let resized = resizedImage {
            resizedAdjustedImage = resized
            rebuildCurrentImage()
        }
    }

    private func resetCrop() {
        // Reset crop rectangle to default position
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        // Reset cropped image to brightness adjusted or original state
        croppedAdjustedImage = brightnessAdjustedImage ?? originalImageState
        rebuildCurrentImage()
    }

    private func applyCrop() {
        // Redirect to rectangle crop method
        applyRectangleCrop()
    }

    private func applyEditsAndFinish() {
        editedImage = currentImage
        isPresented = false
    }

    private func formatImageSize(_ image: UIImage) -> String {
        let sizeInBytes = image.jpegData(compressionQuality: 0.8)?.count ?? 0
        let sizeInMB = Double(sizeInBytes) / (1024 * 1024)
        return String(format: "%.1f MB", sizeInMB)
    }

    private func formatReducedImageSize(_ image: UIImage, scale: CGFloat) -> String {
        let originalBytes = image.jpegData(compressionQuality: 0.8)?.count ?? 0
        let reducedBytes = Int(Double(originalBytes) * Double(scale * scale))
        let sizeInMB = Double(reducedBytes) / (1024 * 1024)
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