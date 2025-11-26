//
//  ImageCropper.swift
//  StudyAI
//
//  Progressive homework grading utility
//  Crops images using normalized coordinates [0-1]
//

import UIKit

/// Utility for cropping images using normalized coordinates
struct ImageCropper {

    // MARK: - Image Region Model

    /// Represents a region in an image with normalized coordinates
    struct ImageRegion {
        let questionId: Int
        let topLeft: [Double]       // [x, y] normalized to [0-1]
        let bottomRight: [Double]   // [x, y] normalized to [0-1]
        let description: String

        /// Validate that coordinates are in valid range [0-1]
        var isValid: Bool {
            guard topLeft.count == 2, bottomRight.count == 2 else { return false }

            let allInRange = topLeft.allSatisfy { $0 >= 0 && $0 <= 1 } &&
                            bottomRight.allSatisfy { $0 >= 0 && $0 <= 1 }

            let properOrder = topLeft[0] < bottomRight[0] &&  // x1 < x2
                             topLeft[1] < bottomRight[1]      // y1 < y2

            return allInRange && properOrder
        }
    }

    // MARK: - Single Image Cropping

    /// Crop image using normalized coordinates with backend image scaling support
    ///
    /// CRITICAL: Handles coordinate mismatch between backend and iOS
    /// - Backend receives RESIZED image (e.g., 2048px) for bandwidth efficiency
    /// - iOS crops from ORIGINAL full-resolution image (e.g., 4000px) for quality
    /// - This function scales normalized coordinates to account for size difference
    ///
    /// - Parameters:
    ///   - image: Original full-resolution UIImage to crop
    ///   - topLeft: Normalized coordinates [x, y] in range [0-1] from backend
    ///   - bottomRight: Normalized coordinates [x, y] in range [0-1] from backend
    ///   - backendImageWidth: Width of the resized image that backend processed (optional)
    ///   - backendImageHeight: Height of the resized image that backend processed (optional)
    /// - Returns: Cropped UIImage, or nil if cropping fails
    ///
    /// Example: Backend processed 2048x1536, but originalImage is 4000x3000:
    /// - Backend returns coords based on 2048x1536
    /// - We scale coords to apply correctly to 4000x3000
    static func crop(
        image: UIImage,
        topLeft: [Double],
        bottomRight: [Double],
        backendImageWidth: Int? = nil,
        backendImageHeight: Int? = nil
    ) -> UIImage? {

        // Validate input
        guard topLeft.count == 2, bottomRight.count == 2 else {
            print("❌ ImageCropper: Invalid coordinate arrays")
            return nil
        }

        guard let cgImage = image.cgImage else {
            print("❌ ImageCropper: Failed to get CGImage")
            return nil
        }

        // Get original image dimensions (full resolution)
        let originalWidth = CGFloat(cgImage.width)
        let originalHeight = CGFloat(cgImage.height)

        // Calculate scale factors if backend dimensions provided
        var scaleX: CGFloat = 1.0
        var scaleY: CGFloat = 1.0

        if let backendWidth = backendImageWidth, let backendHeight = backendImageHeight {
            // Backend processed a resized image, calculate scale ratio
            scaleX = originalWidth / CGFloat(backendWidth)
            scaleY = originalHeight / CGFloat(backendHeight)

            print("🔧 ImageCropper: Coordinate scaling enabled")
            print("   Backend image: \(backendWidth)x\(backendHeight)")
            print("   Original image: \(Int(originalWidth))x\(Int(originalHeight))")
            print("   Scale factors: x=\(String(format: "%.2f", scaleX)), y=\(String(format: "%.2f", scaleY))")
        }

        // Convert normalized coordinates to pixel coordinates
        // Step 1: Apply normalized coords to backend image dimensions (implicit via [0-1] range)
        // Step 2: Scale to original image dimensions
        let x1 = CGFloat(topLeft[0]) * originalWidth
        let y1 = CGFloat(topLeft[1]) * originalHeight
        let x2 = CGFloat(bottomRight[0]) * originalWidth
        let y2 = CGFloat(bottomRight[1]) * originalHeight

        // Calculate crop dimensions
        let cropWidth = x2 - x1
        let cropHeight = y2 - y1

        // Validate crop dimensions
        guard cropWidth > 0, cropHeight > 0 else {
            print("❌ ImageCropper: Invalid crop dimensions")
            return nil
        }

        // Create crop rectangle
        let cropRect = CGRect(
            x: x1,
            y: y1,
            width: cropWidth,
            height: cropHeight
        )

        print("📐 ImageCropper: Cropping region (\(Int(x1)), \(Int(y1))) to (\(Int(x2)), \(Int(y2)))")

        // Perform crop
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else {
            print("❌ ImageCropper: CGImage cropping failed")
            return nil
        }

        // Create UIImage from cropped CGImage
        let croppedImage = UIImage(
            cgImage: croppedCGImage,
            scale: image.scale,
            orientation: image.imageOrientation
        )

        print("✅ ImageCropper: Successfully cropped image (\(Int(cropWidth))x\(Int(cropHeight)))")

        return croppedImage
    }

    // MARK: - Batch Cropping

    /// Crop multiple regions from the same image with backend dimension support
    /// - Parameters:
    ///   - image: Original UIImage
    ///   - regions: Array of ImageRegion objects
    ///   - backendImageWidth: Width of image processed by backend (optional)
    ///   - backendImageHeight: Height of image processed by backend (optional)
    /// - Returns: Dictionary mapping questionId to cropped UIImage
    static func batchCrop(
        image: UIImage,
        regions: [ImageRegion],
        backendImageWidth: Int? = nil,
        backendImageHeight: Int? = nil
    ) -> [Int: UIImage] {

        var croppedImages: [Int: UIImage] = [:]

        print("📝 ImageCropper: Batch cropping \(regions.count) regions...")

        for region in regions {
            // Validate region
            guard region.isValid else {
                print("⚠️ ImageCropper: Invalid region for question \(region.questionId), skipping")
                continue
            }

            // Crop region with backend dimensions
            if let cropped = crop(
                image: image,
                topLeft: region.topLeft,
                bottomRight: region.bottomRight,
                backendImageWidth: backendImageWidth,
                backendImageHeight: backendImageHeight
            ) {
                croppedImages[region.questionId] = cropped
                print("✅ Q\(region.questionId): \(region.description)")
            } else {
                print("❌ Q\(region.questionId): Crop failed")
            }
        }

        print("🎉 ImageCropper: Successfully cropped \(croppedImages.count)/\(regions.count) regions")

        return croppedImages
    }

    // MARK: - Utility Methods

    /// Calculate crop rectangle from normalized coordinates
    /// - Parameters:
    ///   - imageSize: Size of the original image
    ///   - topLeft: Normalized top-left coordinates
    ///   - bottomRight: Normalized bottom-right coordinates
    /// - Returns: CGRect for cropping
    static func calculateCropRect(
        imageSize: CGSize,
        topLeft: [Double],
        bottomRight: [Double]
    ) -> CGRect? {

        guard topLeft.count == 2, bottomRight.count == 2 else { return nil }

        let x1 = CGFloat(topLeft[0]) * imageSize.width
        let y1 = CGFloat(topLeft[1]) * imageSize.height
        let x2 = CGFloat(bottomRight[0]) * imageSize.width
        let y2 = CGFloat(bottomRight[1]) * imageSize.height

        guard x2 > x1, y2 > y1 else { return nil }

        return CGRect(
            x: x1,
            y: y1,
            width: x2 - x1,
            height: y2 - y1
        )
    }

    /// Add padding to normalized coordinates (e.g., 10% padding)
    /// - Parameters:
    ///   - topLeft: Original top-left coordinates
    ///   - bottomRight: Original bottom-right coordinates
    ///   - padding: Padding percentage (0.1 = 10%)
    /// - Returns: Padded coordinates (topLeft, bottomRight)
    static func addPadding(
        topLeft: [Double],
        bottomRight: [Double],
        padding: Double = 0.05  // 5% padding default
    ) -> (topLeft: [Double], bottomRight: [Double]) {

        guard topLeft.count == 2, bottomRight.count == 2 else {
            return (topLeft, bottomRight)
        }

        // Calculate region dimensions
        let width = bottomRight[0] - topLeft[0]
        let height = bottomRight[1] - topLeft[1]

        // Calculate padding in normalized coordinates
        let paddingX = width * padding
        let paddingY = height * padding

        // Apply padding (clamped to [0-1])
        let paddedTopLeft = [
            max(0.0, topLeft[0] - paddingX),
            max(0.0, topLeft[1] - paddingY)
        ]

        let paddedBottomRight = [
            min(1.0, bottomRight[0] + paddingX),
            min(1.0, bottomRight[1] + paddingY)
        ]

        return (paddedTopLeft, paddedBottomRight)
    }
}
