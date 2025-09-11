//
//  PerspectiveCorrector.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import UIKit
@preconcurrency import Vision
import CoreImage
import VisionKit
import AVFoundation

/// Service for detecting and correcting document perspective in images
/// Now supports both custom Vision-based detection and iOS native document scanning
class PerspectiveCorrector {
    static let shared = PerspectiveCorrector()
    
    private init() {}
    
    // MARK: - Native Document Scanning
    
    /// Check if native document scanning is available
    var isNativeDocumentScanningAvailable: Bool {
        return VNDocumentCameraViewController.isSupported
    }
    
    
    /// Present native document scanner (call from SwiftUI)
    /// Returns a configured VNDocumentCameraViewController
    func createNativeDocumentScanner(delegate: VNDocumentCameraViewControllerDelegate) -> VNDocumentCameraViewController? {
        guard isNativeDocumentScanningAvailable else {
            print("❌ Native document scanning not available on this device")
            return nil
        }
        
        let scannerViewController = VNDocumentCameraViewController()
        scannerViewController.delegate = delegate
        return scannerViewController
    }
    
    /// Process scanned document from native scanner
    /// This handles the high-quality scanned image from VNDocumentCameraViewController
    func processNativeScannedDocument(_ scan: VNDocumentCameraScan, at index: Int) -> UIImage? {
        guard index < scan.pageCount else {
            print("❌ Invalid scan index: \(index), pageCount: \(scan.pageCount)")
            return nil
        }
        
        let scannedImage = scan.imageOfPage(at: index)
        print("✅ Native scan processed: page \(index), size: \(scannedImage.size)")
        
        // The native scanner already handles:
        // - Edge detection
        // - Perspective correction  
        // - Lighting optimization
        // - Contrast enhancement
        // So we just return the high-quality result
        return scannedImage
    }
    
    /// Detect rectangular document bounds in image
    /// Returns 4 corner points in clockwise order: topLeft, topRight, bottomRight, bottomLeft
    func detectPageBounds(_ image: UIImage) async -> [CGPoint]? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("❌ Document detection error: \(error)")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let observations = request.results as? [VNRectangleObservation],
                          let largestRect = observations.first else {
                        print("⚠️ No document rectangles detected")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Convert normalized coordinates to image coordinates
                    let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                    let corners = self.convertToImageCoordinates(
                        rectangle: largestRect,
                        imageSize: imageSize
                    )
                    
                    print("✅ Document bounds detected: \(corners.count) corners")
                    continuation.resume(returning: corners)
                }
            }
            
            // Configure for document detection
            request.minimumAspectRatio = 0.3  // Allow tall documents
            request.maximumAspectRatio = 3.0  // Allow wide documents
            request.minimumSize = 0.1         // Minimum 10% of image
            request.minimumConfidence = 0.6   // Reasonable confidence threshold
            request.maximumObservations = 1   // Only need the largest rectangle
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    DispatchQueue.main.async {
                        print("❌ Failed to perform document detection: \(error)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
    /// Apply perspective correction using detected corners
    func correctPerspective(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4,
              let cgImage = image.cgImage else {
            print("❌ Invalid corners for perspective correction")
            return nil
        }
        
        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)
        
        // Create perspective correction filter
        guard let perspectiveFilter = CIFilter(name: "CIPerspectiveCorrection") else {
            print("❌ CIPerspectiveCorrection filter not available")
            return image
        }
        
        // Convert corners to CIVector format for the filter
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let vectors = convertCornersToVectors(corners: corners, imageSize: imageSize)
        
        perspectiveFilter.setValue(ciImage, forKey: kCIInputImageKey)
        perspectiveFilter.setValue(vectors.topLeft, forKey: "inputTopLeft")
        perspectiveFilter.setValue(vectors.topRight, forKey: "inputTopRight")
        perspectiveFilter.setValue(vectors.bottomLeft, forKey: "inputBottomLeft")
        perspectiveFilter.setValue(vectors.bottomRight, forKey: "inputBottomRight")
        
        guard let outputImage = perspectiveFilter.outputImage,
              let correctedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            print("❌ Failed to apply perspective correction")
            return image
        }
        
        let correctedUIImage = UIImage(cgImage: correctedCGImage, scale: image.scale, orientation: image.imageOrientation)
        print("✅ Perspective correction applied successfully")
        return correctedUIImage
    }
    
    /// Auto-detect and correct perspective in one step
    func autoCorrectPerspective(_ image: UIImage) async -> UIImage {
        guard let corners = await detectPageBounds(image) else {
            print("⚠️ No document bounds detected, returning original image")
            return image
        }
        
        guard let correctedImage = correctPerspective(image, corners: corners) else {
            print("⚠️ Perspective correction failed, returning original image")
            return image
        }
        
        return correctedImage
    }
    
    /// Check if an image likely needs perspective correction
    func needsPerspectiveCorrection(_ image: UIImage) async -> Bool {
        guard let corners = await detectPageBounds(image) else {
            return false // Can't detect document, assume no correction needed
        }
        
        // Calculate how "rectangular" the detected shape is
        let rectangularityScore = calculateRectangularityScore(corners: corners)
        
        // If rectangularity score is below threshold, correction is recommended
        let threshold: Float = 0.85
        let needsCorrection = rectangularityScore < threshold
        
        print("📐 Rectangularity score: \(rectangularityScore), needs correction: \(needsCorrection)")
        return needsCorrection
    }
    
    // MARK: - Private Helper Methods
    
    private func convertToImageCoordinates(rectangle: VNRectangleObservation, imageSize: CGSize) -> [CGPoint] {
        // Vision coordinates are normalized (0-1) with origin at bottom-left
        // Convert to image coordinates with origin at top-left
        
        let topLeft = CGPoint(
            x: rectangle.topLeft.x * imageSize.width,
            y: (1 - rectangle.topLeft.y) * imageSize.height
        )
        
        let topRight = CGPoint(
            x: rectangle.topRight.x * imageSize.width,
            y: (1 - rectangle.topRight.y) * imageSize.height
        )
        
        let bottomRight = CGPoint(
            x: rectangle.bottomRight.x * imageSize.width,
            y: (1 - rectangle.bottomRight.y) * imageSize.height
        )
        
        let bottomLeft = CGPoint(
            x: rectangle.bottomLeft.x * imageSize.width,
            y: (1 - rectangle.bottomLeft.y) * imageSize.height
        )
        
        return [topLeft, topRight, bottomRight, bottomLeft]
    }
    
    private func convertCornersToVectors(corners: [CGPoint], imageSize: CGSize) -> (topLeft: CIVector, topRight: CIVector, bottomLeft: CIVector, bottomRight: CIVector) {
        // Corners array is: [topLeft, topRight, bottomRight, bottomLeft]
        let topLeft = CIVector(x: corners[0].x, y: corners[0].y)
        let topRight = CIVector(x: corners[1].x, y: corners[1].y)
        let bottomRight = CIVector(x: corners[2].x, y: corners[2].y)
        let bottomLeft = CIVector(x: corners[3].x, y: corners[3].y)
        
        return (topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight)
    }
    
    private func calculateRectangularityScore(corners: [CGPoint]) -> Float {
        guard corners.count == 4 else { return 0.0 }
        
        // Calculate angles at each corner
        let angles = [
            angleAtPoint(corners[0], corners[3], corners[1]), // Top-left
            angleAtPoint(corners[1], corners[0], corners[2]), // Top-right
            angleAtPoint(corners[2], corners[1], corners[3]), // Bottom-right
            angleAtPoint(corners[3], corners[2], corners[0])  // Bottom-left
        ]
        
        // Perfect rectangle has all 90-degree angles
        let targetAngle: Float = 90.0
        let deviations = angles.map { abs($0 - targetAngle) }
        let averageDeviation = deviations.reduce(0, +) / Float(deviations.count)
        
        // Convert deviation to score (0-1, where 1 is perfect rectangle)
        let maxAllowableDeviation: Float = 30.0 // degrees
        let score = max(0, 1 - (averageDeviation / maxAllowableDeviation))
        
        return score
    }
    
    private func angleAtPoint(_ point: CGPoint, _ prev: CGPoint, _ next: CGPoint) -> Float {
        let vector1 = CGPoint(x: prev.x - point.x, y: prev.y - point.y)
        let vector2 = CGPoint(x: next.x - point.x, y: next.y - point.y)
        
        let dotProduct = vector1.x * vector2.x + vector1.y * vector2.y
        let magnitude1 = sqrt(vector1.x * vector1.x + vector1.y * vector1.y)
        let magnitude2 = sqrt(vector2.x * vector2.x + vector2.y * vector2.y)
        
        guard magnitude1 > 0, magnitude2 > 0 else { return 0 }
        
        let cosine = dotProduct / (magnitude1 * magnitude2)
        let clampedCosine = max(-1, min(1, cosine)) // Clamp to avoid numerical errors
        let angleRadians = acos(clampedCosine)
        let angleDegrees = angleRadians * 180.0 / .pi
        
        return Float(angleDegrees)
    }
}

// MARK: - Debug Helpers

extension PerspectiveCorrector {
    /// Create a debug image showing detected corners
    func createDebugImage(_ image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4 else { return image }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Draw original image
        image.draw(at: .zero)
        
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        // Draw detected corners
        context.setStrokeColor(UIColor.red.cgColor)
        context.setLineWidth(3.0)
        context.setFillColor(UIColor.yellow.cgColor)
        
        // Draw corner points
        for (index, corner) in corners.enumerated() {
            let rect = CGRect(x: corner.x - 10, y: corner.y - 10, width: 20, height: 20)
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
            
            // Label corners
            let label = "\(index)"
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.black,
                .font: UIFont.boldSystemFont(ofSize: 16)
            ]
            label.draw(at: CGPoint(x: corner.x - 5, y: corner.y - 8), withAttributes: attributes)
        }
        
        // Draw boundary lines
        context.setStrokeColor(UIColor.blue.cgColor)
        context.setLineWidth(2.0)
        context.move(to: corners[0])
        for i in 1..<corners.count {
            context.addLine(to: corners[i])
        }
        context.addLine(to: corners[0]) // Close the shape
        context.strokePath()
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}