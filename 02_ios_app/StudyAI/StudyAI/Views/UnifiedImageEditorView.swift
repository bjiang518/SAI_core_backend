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

    @State private var currentImage: UIImage?
    @State private var imageUpdateTrigger = UUID() // Force image refresh when this changes
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
    @State private var isCropApplied = false  // Track if crop has been applied

    // Size reduction options
    @State private var selectedSizeReduction: SizeReductionOption = .raw
    @State private var isResizeApplied = false  // Track if resize has been applied
    @State private var appliedSizeReduction: SizeReductionOption = .raw  // Track which size was applied
    @State private var previewResizedImage: UIImage?  // Preview of selected resize (not yet applied)


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
            case .raw: return 1.0      // 100% - Original size
            case .large: return 0.5    // 50% - Was 75%, now more aggressive
            case .medium: return 0.3   // 30% - Was 50%, much more aggressive
            case .small: return 0.15   // 15% - Was 25%, very aggressive
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
                                .id(imageUpdateTrigger) // Force refresh when trigger changes

                            // Show crop overlay only when:
                            // 1. Crop tab is selected AND
                            // 2. Crop has not been applied yet (user is still adjusting)
                            if selectedTab == .crop && !isCropApplied {
                                buildCropOverlay(image: image, geometry: geometry)
                            }
                        }
                    }
                    .frame(height: UIScreen.main.bounds.height * 0.5)
                    .background(
                        colorScheme == .dark
                            ? Color(.systemGray6)
                            : Color.white
                    )
                    .padding(.top, 20) // Add spacing at the top
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
                            .foregroundColor(selectedTab == tab ? .blue : (colorScheme == .dark ? Color(.systemGray) : .gray))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .background(
                            selectedTab == tab ? Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.1) : Color.clear
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Editor Controls with grey background extending to bottom
                VStack(spacing: 12) {
                    // Controls section
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
                .frame(maxWidth: .infinity)
                .background(Color(.systemGroupedBackground))
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                setupInitialImage()
            }
            .onChange(of: selectedSizeReduction) { newSize in
                updateResizePreview()
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
                .background(Color.green.opacity(colorScheme == .dark ? 0.3 : 0.15))
                .foregroundColor(.green)
                .cornerRadius(10)

                Button("Reset") {
                    resetBrightness()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.15))
                .foregroundColor(.gray)
                .cornerRadius(10)
            }
        }
    }

    // MARK: - Crop Controls
    private var cropControls: some View {
        VStack(spacing: 16) {
            // Status indicator
            if isCropApplied {
                Text("Crop applied • Press Reset to adjust again")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Drag corners to resize • Drag center to move")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Button(isCropApplied ? "Applied" : "Apply Crop") {
                    applyRectangleCrop()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isCropApplied ? (colorScheme == .dark ? Color(.systemGray4) : Color.secondary) : Color.blue)
                .cornerRadius(10)
                .disabled(isCropApplied)

                Button("Reset Crop") {
                    resetCrop()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.gray)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.15))
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
                // Show file size comparison (centralized)
                if let baseImage = getCombinedImageForResize() {
                    HStack(spacing: 8) {
                        Spacer()

                        // Original size
                        VStack(spacing: 2) {
                            Text(isResizeApplied ? "Before:" : "Original:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(formatImageSize(baseImage))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                        }

                        // Arrow and preview/applied size
                        if selectedSizeReduction != .raw && !isResizeApplied {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 4)

                            VStack(spacing: 2) {
                                Text("Preview:")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text(formatReducedImageSize(baseImage, scale: selectedSizeReduction.scale))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        } else if isResizeApplied, let resized = resizedAdjustedImage {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .padding(.horizontal, 4)

                            VStack(spacing: 2) {
                                Text("Applied:")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text(formatImageSize(resized))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                            }
                        }

                        Spacer()
                    }
                }

                // Independent Action Buttons
                HStack(spacing: 16) {
                    Button(isResizeApplied ? "Applied" : "Apply Size") {
                        applySizeReduction()
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background((selectedSizeReduction == .raw || isResizeApplied) ? (colorScheme == .dark ? Color(.systemGray4) : Color.secondary) : Color.blue)
                    .cornerRadius(10)
                    .disabled(selectedSizeReduction == .raw || isResizeApplied)

                    Button("Reset Size") {
                        resetToOriginalSize()
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.15))
                    .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Independent State Management Helper Methods

    /// Get the base image for brightness/contrast adjustments
    /// If crop has been applied, use cropped image; otherwise use original
    private func getBaseImageForBrightness() -> UIImage? {
        // Priority: resized > cropped > original
        // This ensures brightness can be applied after resize
        if isResizeApplied, let resized = resizedAdjustedImage {
            return resized
        }
        if isCropApplied, let cropped = croppedAdjustedImage {
            return cropped
        }
        return originalImageState
    }

    /// Rebuild current image by combining all active edits
    private func rebuildCurrentImage() {
        // The brightness adjustment methods already handle applying to cropped or original
        // So just use brightnessAdjustedImage as the base
        var baseImage = brightnessAdjustedImage ?? (isCropApplied ? croppedAdjustedImage : originalImageState)

        // Show resize preview if selected but not applied
        if !isResizeApplied && selectedSizeReduction != .raw, let preview = previewResizedImage {
            baseImage = preview
        }
        // Or apply actual resize if applied
        else if isResizeApplied, let resizedImage = resizedAdjustedImage {
            baseImage = resizedImage
        }

        currentImage = baseImage
        imageUpdateTrigger = UUID() // Force preview to refresh
    }

    /// Get combined image for resize operations (brightness + crop, but not previous resize)
    private func getCombinedImageForResize() -> UIImage? {
        // Use brightness adjusted image as base (which already includes crop if applied)
        return brightnessAdjustedImage ?? (isCropApplied ? croppedAdjustedImage : originalImageState)
    }

    /// Generate a preview of the resize without applying it
    private func updateResizePreview() {
        // If resize is already applied, don't generate preview (user must reset first)
        if isResizeApplied {
            return
        }

        // If raw selected, clear preview and show base image
        if selectedSizeReduction == .raw {
            previewResizedImage = nil
            rebuildCurrentImage()
            return
        }

        // Generate preview for the selected size
        guard let baseImage = getCombinedImageForResize() else { return }

        let newSize = CGSize(
            width: baseImage.size.width * selectedSizeReduction.scale,
            height: baseImage.size.height * selectedSizeReduction.scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, false, baseImage.scale)
        baseImage.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        previewResizedImage = resizedImage
        rebuildCurrentImage()
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
        isCropApplied = false  // Initialize crop state
        isResizeApplied = false  // Initialize resize state
        appliedSizeReduction = .raw
        previewResizedImage = nil  // Initialize preview
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
        // Get the appropriate base image (includes brightness and/or resize if applied)
        guard let image = currentImage else { return }

        // Calculate pixel coordinates from relative coordinates
        let pixelRect = CGRect(
            x: cropRect.origin.x * image.size.width,
            y: cropRect.origin.y * image.size.height,
            width: cropRect.width * image.size.width,
            height: cropRect.height * image.size.height
        )

        // Validate crop rect
        guard pixelRect.width > 0 && pixelRect.height > 0,
              pixelRect.minX >= 0 && pixelRect.minY >= 0,
              pixelRect.maxX <= image.size.width && pixelRect.maxY <= image.size.height else {
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
            return
        }

        // Scale the crop rect for CGImage coordinates
        let scaledCropRect = CGRect(
            x: pixelRect.origin.x * image.scale,
            y: pixelRect.origin.y * image.scale,
            width: pixelRect.width * image.scale,
            height: pixelRect.height * image.scale
        )

        // Perform the crop
        guard let croppedCGImage = cgImage.cropping(to: scaledCropRect) else {
            return
        }

        // Create final UIImage with .up orientation (already oriented correctly)
        let croppedUIImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)

        // Update the state - crop is applied on top of any existing edits
        // If resize was applied, we need to reset it and apply crop to the pre-resize state
        if isResizeApplied {
            // User cropped after resize - reset resize and apply crop
            isResizeApplied = false
            selectedSizeReduction = .raw
            appliedSizeReduction = .raw
            resizedAdjustedImage = originalImageState
            previewResizedImage = nil
        }

        // Clear any resize preview (even if not applied) to prevent override
        previewResizedImage = nil
        selectedSizeReduction = .raw

        croppedAdjustedImage = croppedUIImage

        // Don't reset brightness - keep the existing brightness settings
        // Just update brightnessAdjustedImage to match the cropped image
        if brightnessValue != 0.0 || contrastValue != 0.0 {
            // Reapply brightness to the cropped image
            let adjustedImage = imageEnhancer.adjustBrightnessAndContrast(croppedUIImage, brightness: brightnessValue, contrast: contrastValue)
            brightnessAdjustedImage = adjustedImage
        } else {
            brightnessAdjustedImage = croppedUIImage
        }

        rebuildCurrentImage()
        isCropApplied = true  // Hide the crop overlay after applying
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8) // Reset for next crop
    }

    private func applyBrightnessAdjustment() {
        guard let baseImage = getBaseImageForBrightness() else { return }
        // Apply both brightness and contrast adjustments together
        let adjustedImage = imageEnhancer.adjustBrightnessAndContrast(baseImage, brightness: brightnessValue, contrast: contrastValue)

        // Update the appropriate state based on what's applied
        if isResizeApplied {
            // If resize is applied, update the resized image with brightness
            resizedAdjustedImage = adjustedImage
        } else {
            brightnessAdjustedImage = adjustedImage
        }

        rebuildCurrentImage()
    }

    private func applyContrastAdjustment() {
        guard let baseImage = getBaseImageForBrightness() else { return }
        // Apply both brightness and contrast adjustments together
        let adjustedImage = imageEnhancer.adjustBrightnessAndContrast(baseImage, brightness: brightnessValue, contrast: contrastValue)

        // Update the appropriate state based on what's applied
        if isResizeApplied {
            // If resize is applied, update the resized image with contrast
            resizedAdjustedImage = adjustedImage
        } else {
            brightnessAdjustedImage = adjustedImage
        }

        rebuildCurrentImage()
    }

    private func autoEnhanceImage() {
        guard let baseImage = getBaseImageForBrightness() else { return }
        let enhancedImage = imageEnhancer.preprocessForSegmentation(baseImage)

        // Update the appropriate state based on what's applied
        if isResizeApplied {
            resizedAdjustedImage = enhancedImage
        } else {
            brightnessAdjustedImage = enhancedImage
        }

        // Update the slider values to reflect the enhancement
        brightnessValue = 0.1 // Indicate that enhancement was applied
        contrastValue = 0.1
        rebuildCurrentImage()
    }

    private func resetBrightness() {
        brightnessValue = 0.0
        contrastValue = 0.0
        // Reset brightness to the base image (resized if resize applied, cropped if crop applied, otherwise original)
        let baseImage = getBaseImageForBrightness()

        if isResizeApplied {
            resizedAdjustedImage = baseImage
        } else {
            brightnessAdjustedImage = baseImage
        }

        rebuildCurrentImage()
    }

    private func resetToOriginalSize() {
        selectedSizeReduction = .raw
        resizedAdjustedImage = originalImageState
        isResizeApplied = false
        appliedSizeReduction = .raw
        previewResizedImage = nil  // Clear preview
        rebuildCurrentImage()
    }

    private func applySizeReduction() {
        // Commit the previewed resize
        guard selectedSizeReduction != .raw, let preview = previewResizedImage else { return }

        // Move preview to the applied state
        resizedAdjustedImage = preview
        isResizeApplied = true
        appliedSizeReduction = selectedSizeReduction

        // Clear preview since it's now applied
        previewResizedImage = nil

        rebuildCurrentImage()
    }

    private func resetCrop() {
        // Reset crop rectangle to default position
        cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        // Reset cropped image to brightness adjusted or original state
        croppedAdjustedImage = brightnessAdjustedImage ?? originalImageState
        rebuildCurrentImage()
        isCropApplied = false  // Show the crop overlay again
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