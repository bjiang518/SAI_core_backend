//
//  ImageCropView.swift
//  StudyAI
//
//  Created by Claude Code on 9/1/25.
//

import SwiftUI
import UIKit

struct ImageCropView: View {
    @Binding var originalImage: UIImage?
    @Binding var croppedImage: UIImage?
    @Binding var isPresented: Bool
    
    @State private var cropRect = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
    @State private var imageSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = originalImage {
                    GeometryReader { geometry in
                        ZStack {
                            // Background Image
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .opacity(0.7)
                                .onAppear {
                                    containerSize = geometry.size
                                    imageSize = calculateImageSize(in: geometry.size, for: image)
                                }
                            
                            // Custom Crop Overlay
                            CustomCropOverlay(
                                cropRect: $cropRect,
                                imageSize: imageSize,
                                containerSize: containerSize
                            )
                        }
                    }
                    .padding()
                }
                
                // Instructions and Controls
                VStack {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        // Quick Tips
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "hand.draw")
                                        .foregroundColor(.yellow)
                                    Text("Drag edges to resize crop area")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                
                                HStack {
                                    Image(systemName: "move")
                                        .foregroundColor(.yellow)
                                    Text("Drag corners to move rectangle")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            Spacer()
                        }
                        .padding()
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(12)
                        
                        // Action Buttons
                        HStack(spacing: 20) {
                            Button("Cancel") {
                                isPresented = false
                                originalImage = nil
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(8)
                            
                            Button("Reset") {
                                cropRect = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.gray.opacity(0.8))
                            .cornerRadius(8)
                            
                            Button("Crop & Use") {
                                cropAndUseImage()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                        originalImage = nil
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        cropAndUseImage()
                    }
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .semibold))
                }
            }
        }
    }
    
    private func calculateImageSize(in containerSize: CGSize, for image: UIImage) -> CGSize {
        let imageAspectRatio = image.size.width / image.size.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        if imageAspectRatio > containerAspectRatio {
            // Image is wider than container
            let height = containerSize.width / imageAspectRatio
            return CGSize(width: containerSize.width, height: height)
        } else {
            // Image is taller than container
            let width = containerSize.height * imageAspectRatio
            return CGSize(width: width, height: containerSize.height)
        }
    }
    
    private func cropAndUseImage() {
        guard let image = originalImage else { return }
        
        // Calculate the actual displayed image size and position using the same logic as overlay
        let displayedImageRect = calculateActualImageRect(containerSize: containerSize, imageSize: imageSize)
        
        // Convert crop rectangle from normalized coordinates (0-1) to actual image coordinates
        let cropInDisplayCoords = CGRect(
            x: cropRect.origin.x * displayedImageRect.width + displayedImageRect.origin.x,
            y: cropRect.origin.y * displayedImageRect.height + displayedImageRect.origin.y,
            width: cropRect.size.width * displayedImageRect.width,
            height: cropRect.size.height * displayedImageRect.height
        )
        
        // Convert from display coordinates to actual image coordinates
        let scaleX = image.size.width / displayedImageRect.width
        let scaleY = image.size.height / displayedImageRect.height
        
        let actualCropRect = CGRect(
            x: (cropInDisplayCoords.origin.x - displayedImageRect.origin.x) * scaleX,
            y: (cropInDisplayCoords.origin.y - displayedImageRect.origin.y) * scaleY,
            width: cropInDisplayCoords.width * scaleX,
            height: cropInDisplayCoords.height * scaleY
        )
        
        // Crop the image
        if let cropped = cropImage(image, to: actualCropRect) {
            croppedImage = cropped
        } else {
            croppedImage = image // Fallback to original if cropping fails
        }
        
        isPresented = false
    }
    
    private func calculateActualImageRect(containerSize: CGSize, imageSize: CGSize) -> CGRect {
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        let actualSize: CGSize
        if imageAspectRatio > containerAspectRatio {
            actualSize = CGSize(width: containerSize.width, height: containerSize.width / imageAspectRatio)
        } else {
            actualSize = CGSize(width: containerSize.height * imageAspectRatio, height: containerSize.height)
        }
        
        return CGRect(
            x: (containerSize.width - actualSize.width) / 2,
            y: (containerSize.height - actualSize.height) / 2,
            width: actualSize.width,
            height: actualSize.height
        )
    }
    
    private func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard image.cgImage != nil else { return nil }
        
        // Handle image orientation - we need to work with the actual pixel data
        let actualImage: UIImage
        if image.imageOrientation != .up {
            // Draw the image in the correct orientation first
            UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            actualImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            actualImage = image
        }
        
        guard let orientedCGImage = actualImage.cgImage else { return image }
        
        // Ensure the crop rect is within image bounds
        let clampedRect = CGRect(
            x: max(0, min(rect.origin.x, CGFloat(orientedCGImage.width))),
            y: max(0, min(rect.origin.y, CGFloat(orientedCGImage.height))),
            width: min(rect.size.width, CGFloat(orientedCGImage.width) - max(0, rect.origin.x)),
            height: min(rect.size.height, CGFloat(orientedCGImage.height) - max(0, rect.origin.y))
        )
        
        guard let croppedCGImage = orientedCGImage.cropping(to: clampedRect) else { return nil }
        
        // Create the final image with correct orientation
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)
    }
}

struct CustomCropOverlay: View {
    @Binding var cropRect: CGRect
    let imageSize: CGSize
    let containerSize: CGSize
    
    @State private var isDragging = false
    @State private var lastDragValue: DragGesture.Value?
    @State private var dragStartRect: CGRect = .zero
    
    enum HandleType {
        case topLeft, topRight, bottomLeft, bottomRight
        case topEdge, bottomEdge, leftEdge, rightEdge
        case center
    }
    
    private let handleSize: CGFloat = 44  // Apple's recommended touch target size
    private let edgeHandleThickness: CGFloat = 20
    private let minimumCropSize: CGFloat = 0.15 // Larger minimum size
    
    var body: some View {
        GeometryReader { geometry in
            let actualImageRect = getActualImageRect(in: geometry.size)
            let cropFrameRect = getCropFrameRect(in: actualImageRect)
            
            ZStack {
                // Dark overlay with clear crop area
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .mask(
                        Rectangle()
                            .fill(Color.black)
                            .overlay(
                                Rectangle()
                                    .frame(
                                        width: max(10, cropFrameRect.width), 
                                        height: max(10, cropFrameRect.height)
                                    )
                                    .position(
                                        x: cropFrameRect.midX,
                                        y: cropFrameRect.midY
                                    )
                                    .blendMode(.destinationOut)
                            )
                    )
                
                // Crop frame border
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 3)
                    .frame(
                        width: max(10, cropFrameRect.width), 
                        height: max(10, cropFrameRect.height)
                    )
                    .position(x: cropFrameRect.midX, y: cropFrameRect.midY)
                
                // Corner handles with larger touch areas
                cornerHandle(.topLeft, at: CGPoint(x: cropFrameRect.minX, y: cropFrameRect.minY), imageRect: actualImageRect)
                cornerHandle(.topRight, at: CGPoint(x: cropFrameRect.maxX, y: cropFrameRect.minY), imageRect: actualImageRect)
                cornerHandle(.bottomLeft, at: CGPoint(x: cropFrameRect.minX, y: cropFrameRect.maxY), imageRect: actualImageRect)
                cornerHandle(.bottomRight, at: CGPoint(x: cropFrameRect.maxX, y: cropFrameRect.maxY), imageRect: actualImageRect)
                
                // Edge handles with larger touch areas
                edgeHandle(.topEdge, at: CGPoint(x: cropFrameRect.midX, y: cropFrameRect.minY), isHorizontal: true, imageRect: actualImageRect)
                edgeHandle(.bottomEdge, at: CGPoint(x: cropFrameRect.midX, y: cropFrameRect.maxY), isHorizontal: true, imageRect: actualImageRect)
                edgeHandle(.leftEdge, at: CGPoint(x: cropFrameRect.minX, y: cropFrameRect.midY), isHorizontal: false, imageRect: actualImageRect)
                edgeHandle(.rightEdge, at: CGPoint(x: cropFrameRect.maxX, y: cropFrameRect.midY), isHorizontal: false, imageRect: actualImageRect)
                
                // Center drag area - make it larger and more visible for debugging
                Rectangle()
                    .fill(Color.blue.opacity(0.1)) // Slightly visible for debugging
                    .frame(
                        width: max(60, cropFrameRect.width - 100), 
                        height: max(60, cropFrameRect.height - 100)
                    )
                    .position(x: cropFrameRect.midX, y: cropFrameRect.midY)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragStartRect = cropRect
                                }
                                handleCenterDrag(with: value, imageRect: actualImageRect)
                            }
                            .onEnded { _ in
                                isDragging = false
                                lastDragValue = nil
                            }
                    )
                
                // Grid lines
                gridLines(in: cropFrameRect)
            }
        }
    }
    
    private func getActualImageRect(in containerSize: CGSize) -> CGRect {
        let imageAspectRatio = imageSize.width / imageSize.height
        let containerAspectRatio = containerSize.width / containerSize.height
        
        let actualSize: CGSize
        if imageAspectRatio > containerAspectRatio {
            actualSize = CGSize(width: containerSize.width, height: containerSize.width / imageAspectRatio)
        } else {
            actualSize = CGSize(width: containerSize.height * imageAspectRatio, height: containerSize.height)
        }
        
        return CGRect(
            x: (containerSize.width - actualSize.width) / 2,
            y: (containerSize.height - actualSize.height) / 2,
            width: actualSize.width,
            height: actualSize.height
        )
    }
    
    private func getCropFrameRect(in imageRect: CGRect) -> CGRect {
        // Ensure safe bounds for crop rectangle
        let safeX = max(0, min(cropRect.origin.x, 1))
        let safeY = max(0, min(cropRect.origin.y, 1))
        let safeWidth = max(0.1, min(cropRect.width, 1 - safeX))
        let safeHeight = max(0.1, min(cropRect.height, 1 - safeY))
        
        return CGRect(
            x: imageRect.minX + safeX * imageRect.width,
            y: imageRect.minY + safeY * imageRect.height,
            width: safeWidth * imageRect.width,
            height: safeHeight * imageRect.height
        )
    }
    
    @ViewBuilder
    private func cornerHandle(_ handle: HandleType, at position: CGPoint, imageRect: CGRect) -> some View {
        ZStack {
            // Larger invisible touch area
            Circle()
                .fill(Color.clear)
                .frame(width: handleSize, height: handleSize)
                .position(position)
            
            // Visible handle (smaller)
            Circle()
                .fill(Color.yellow)
                .overlay(
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                )
                .frame(width: 20, height: 20)
                .position(position)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartRect = cropRect
                    }
                    handleCornerDrag(for: handle, with: value, imageRect: imageRect)
                }
                .onEnded { _ in
                    isDragging = false
                    lastDragValue = nil
                }
        )
    }
    
    @ViewBuilder
    private func edgeHandle(_ handle: HandleType, at position: CGPoint, isHorizontal: Bool, imageRect: CGRect) -> some View {
        ZStack {
            // Larger invisible touch area
            Rectangle()
                .fill(Color.clear)
                .frame(
                    width: isHorizontal ? 80 : edgeHandleThickness + 20,
                    height: isHorizontal ? edgeHandleThickness + 20 : 80
                )
                .position(position)
            
            // Visible handle (smaller)
            Rectangle()
                .fill(Color.yellow.opacity(0.8))
                .overlay(
                    Rectangle()
                        .stroke(Color.black, lineWidth: 1)
                )
                .frame(
                    width: isHorizontal ? 50 : 8,
                    height: isHorizontal ? 8 : 50
                )
                .position(position)
        }
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragStartRect = cropRect
                    }
                    handleEdgeDrag(for: handle, with: value, imageRect: imageRect)
                }
                .onEnded { _ in
                    isDragging = false
                    lastDragValue = nil
                }
        )
    }
    
    private func handleCenterDrag(with value: DragGesture.Value, imageRect: CGRect) {
        guard isDragging else { return }
        
        let sensitivity: CGFloat = 0.8  // 0.7 + 0.1
        let deltaX = (value.translation.width * sensitivity) / imageRect.width
        let deltaY = (value.translation.height * sensitivity) / imageRect.height
        
        var newRect = dragStartRect
        newRect.origin.x += deltaX
        newRect.origin.y += deltaY
        
        cropRect = constrainCropRect(newRect)
    }
    
    private func handleCornerDrag(for handle: HandleType, with value: DragGesture.Value, imageRect: CGRect) {
        guard isDragging else { return }
        
        let sensitivity: CGFloat = 0.6  // 0.5 + 0.1
        let deltaX = (value.translation.width * sensitivity) / imageRect.width
        let deltaY = (value.translation.height * sensitivity) / imageRect.height
        
        var newRect = dragStartRect
        
        switch handle {
        case .topLeft:
            newRect.origin.x += deltaX
            newRect.origin.y += deltaY
            newRect.size.width -= deltaX
            newRect.size.height -= deltaY
        case .topRight:
            newRect.origin.y += deltaY
            newRect.size.width += deltaX
            newRect.size.height -= deltaY
        case .bottomLeft:
            newRect.origin.x += deltaX
            newRect.size.width -= deltaX
            newRect.size.height += deltaY
        case .bottomRight:
            newRect.size.width += deltaX
            newRect.size.height += deltaY
        default:
            break
        }
        
        cropRect = constrainCropRect(newRect)
    }
    
    private func handleEdgeDrag(for handle: HandleType, with value: DragGesture.Value, imageRect: CGRect) {
        guard isDragging else { return }
        
        let sensitivity: CGFloat = 0.6  // 0.5 + 0.1
        let deltaX = (value.translation.width * sensitivity) / imageRect.width
        let deltaY = (value.translation.height * sensitivity) / imageRect.height
        
        var newRect = dragStartRect
        
        switch handle {
        case .topEdge:
            newRect.origin.y += deltaY
            newRect.size.height -= deltaY
        case .bottomEdge:
            newRect.size.height += deltaY
        case .leftEdge:
            newRect.origin.x += deltaX
            newRect.size.width -= deltaX
        case .rightEdge:
            newRect.size.width += deltaX
        default:
            break
        }
        
        cropRect = constrainCropRect(newRect)
    }
    
    @ViewBuilder
    private func gridLines(in rect: CGRect) -> some View {
        // Vertical grid lines
        ForEach(1..<3) { i in
            Path { path in
                let x = rect.minX + rect.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            .stroke(Color.yellow.opacity(0.5), lineWidth: 0.5)
        }
        
        // Horizontal grid lines
        ForEach(1..<3) { i in
            Path { path in
                let y = rect.minY + rect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            .stroke(Color.yellow.opacity(0.5), lineWidth: 0.5)
        }
    }
    
    private func constrainCropRect(_ rect: CGRect) -> CGRect {
        var constrained = rect
        
        // Ensure minimum size
        constrained.size.width = max(minimumCropSize, constrained.size.width)
        constrained.size.height = max(minimumCropSize, constrained.size.height)
        
        // Ensure position stays within bounds
        constrained.origin.x = max(0, min(constrained.origin.x, 1 - constrained.size.width))
        constrained.origin.y = max(0, min(constrained.origin.y, 1 - constrained.size.height))
        
        // Ensure size doesn't exceed bounds
        constrained.size.width = min(constrained.size.width, 1 - constrained.origin.x)
        constrained.size.height = min(constrained.size.height, 1 - constrained.origin.y)
        
        return constrained
    }
}

#Preview {
    ImageCropView(
        originalImage: .constant(UIImage(systemName: "photo")),
        croppedImage: .constant(nil),
        isPresented: .constant(true)
    )
}