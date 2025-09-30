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

    // Crop state with four corner points
    @State private var cropCorners: [CGPoint] = [
        CGPoint(x: 0.1, y: 0.1), // Top-left
        CGPoint(x: 0.9, y: 0.1), // Top-right
        CGPoint(x: 0.9, y: 0.9), // Bottom-right
        CGPoint(x: 0.1, y: 0.9)  // Bottom-left
    ]
    @State private var draggedCornerIndex: Int? = nil

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

        return ZStack {
            // Scanner-style crop overlay with four adjustable corners
            Path { path in
                let points = cropCorners.map { point in
                    CGPoint(
                        x: imageOffset.x + point.x * displayedImageSize.width,
                        y: imageOffset.y + point.y * displayedImageSize.height
                    )
                }
                path.move(to: points[0])
                for i in 1..<points.count {
                    path.addLine(to: points[i])
                }
                path.closeSubpath()
            }
            .stroke(Color.blue, lineWidth: 2)
            .background(
                Path { path in
                    let points = cropCorners.map { point in
                        CGPoint(
                            x: imageOffset.x + point.x * displayedImageSize.width,
                            y: imageOffset.y + point.y * displayedImageSize.height
                        )
                    }
                    path.move(to: points[0])
                    for i in 1..<points.count {
                        path.addLine(to: points[i])
                    }
                    path.closeSubpath()
                }
                .fill(Color.blue.opacity(0.1))
            )

            // Four corner handles
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .position(
                        x: imageOffset.x + cropCorners[index].x * displayedImageSize.width,
                        y: imageOffset.y + cropCorners[index].y * displayedImageSize.height
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Convert drag position back to relative coordinates
                                let relativeX = max(0, min(1, (value.location.x - imageOffset.x) / displayedImageSize.width))
                                let relativeY = max(0, min(1, (value.location.y - imageOffset.y) / displayedImageSize.height))
                                cropCorners[index] = CGPoint(x: relativeX, y: relativeY)
                            }
                    )
            }
        }
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
            Text("Drag the corners to select the area to crop")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Apply Crop") {
                    applyScannerCrop()
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
        resetCropCorners()
    }

    private func resetToOriginal() {
        currentImage = originalImage
        brightnessValue = 0.0
        contrastValue = 0.0
        selectedSizeReduction = .raw
        croppedImage = nil
        resetCropCorners()
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

    private func resetCropCorners() {
        cropCorners = [
            CGPoint(x: 0.1, y: 0.1), // Top-left
            CGPoint(x: 0.9, y: 0.1), // Top-right
            CGPoint(x: 0.9, y: 0.9), // Bottom-right
            CGPoint(x: 0.1, y: 0.9)  // Bottom-left
        ]
    }

    private func resetCrop() {
        // Reset crop corners to default position
        resetCropCorners()
        // Reset cropped image to brightness adjusted or original state
        croppedAdjustedImage = brightnessAdjustedImage ?? originalImageState
        rebuildCurrentImage()
    }

    private func autoDetectCropArea() {
        // Auto-detect edges (simplified version - in production you'd use image processing)
        cropCorners = [
            CGPoint(x: 0.05, y: 0.05),
            CGPoint(x: 0.95, y: 0.05),
            CGPoint(x: 0.95, y: 0.95),
            CGPoint(x: 0.05, y: 0.95)
        ]
    }

    private func applyScannerCrop() {
        guard let image = currentImage else { return }

        print("📐 === SIMPLE RECTANGULAR CROP ===")
        print("📐 Original UIImage size: \(image.size)")
        print("📐 Image orientation: \(image.imageOrientation.rawValue)")
        print("📐 Crop corners (relative): \(cropCorners)")

        guard let cgImage = image.cgImage else {
            print("❌ No CGImage available")
            return
        }

        // Use UIImage.size (orientation-aware) instead of CGImage dimensions
        let imageSize = image.size
        print("📐 Using orientation-aware image size: \(imageSize)")

        // Convert relative crop corner coordinates to pixel coordinates using UIImage.size
        let pixelCorners = cropCorners.map { relativePoint in
            CGPoint(
                x: relativePoint.x * imageSize.width,
                y: relativePoint.y * imageSize.height
            )
        }

        print("📐 Pixel corners: \(pixelCorners)")

        // Create a simple rectangular crop using bounding box
        if let croppedImage = createBoundingBoxCrop(image: image, corners: pixelCorners) {
            croppedAdjustedImage = croppedImage
            rebuildCurrentImage()
            resetCropCorners()
            print("✅ Simple rectangular crop successful")
        } else {
            print("❌ Simple rectangular crop failed")
        }

        print("📐 === END SIMPLE RECTANGULAR CROP ===")
    }

    /// Simple bounding box crop - creates a rectangular crop from the selected area
    private func createBoundingBoxCrop(image: UIImage, corners: [CGPoint]) -> UIImage? {
        print("📐 Starting createBoundingBoxCrop")
        print("📐 Input image size: \(image.size)")
        print("📐 Input corners: \(corners)")

        // Create a graphics context with the image size (orientation-aware)
        let imageSize = image.size
        UIGraphicsBeginImageContextWithOptions(imageSize, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        // Draw the original image in the context (this handles orientation automatically)
        image.draw(in: CGRect(origin: .zero, size: imageSize))

        // Get the context image (this is now properly oriented)
        guard let contextImage = UIGraphicsGetImageFromCurrentImageContext(),
              let cgImage = contextImage.cgImage else {
            print("❌ Failed to get context image")
            return nil
        }

        print("📐 Context image size: \(contextImage.size)")
        print("📐 CGImage size: \(CGSize(width: cgImage.width, height: cgImage.height))")

        // Now calculate crop frame using the properly oriented image
        let minX = max(0, corners.map { $0.x }.min() ?? 0)
        let maxX = min(imageSize.width, corners.map { $0.x }.max() ?? imageSize.width)
        let minY = max(0, corners.map { $0.y }.min() ?? 0)
        let maxY = min(imageSize.height, corners.map { $0.y }.max() ?? imageSize.height)

        let cropFrame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        print("📐 Crop frame: \(cropFrame)")
        print("📐 Crop aspect ratio: \(cropFrame.width / cropFrame.height)")
        print("📐 Crop is: \(cropFrame.width > cropFrame.height ? "HORIZONTAL" : "VERTICAL")")

        // Validate crop frame
        guard cropFrame.width > 0 && cropFrame.height > 0,
              cropFrame.minX >= 0 && cropFrame.minY >= 0,
              cropFrame.maxX <= imageSize.width && cropFrame.maxY <= imageSize.height else {
            print("❌ Invalid crop frame")
            return nil
        }

        // Convert to CGImage coordinates (scale by image.scale)
        let scaledCropFrame = CGRect(
            x: cropFrame.origin.x * image.scale,
            y: cropFrame.origin.y * image.scale,
            width: cropFrame.size.width * image.scale,
            height: cropFrame.size.height * image.scale
        )

        print("📐 Scaled crop frame for CGImage: \(scaledCropFrame)")

        guard let croppedCGImage = cgImage.cropping(to: scaledCropFrame) else {
            print("❌ Failed to crop CGImage")
            return nil
        }

        // Create final UIImage with no orientation (since we've already handled it)
        let finalImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)
        print("📐 Final cropped image size: \(finalImage.size)")

        return finalImage
    }

    private func applyCrop() {
        // Legacy method - redirects to scanner crop
        applyScannerCrop()
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