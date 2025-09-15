//
//  EnhancedImageProcessor.swift
//  StudyAI
//
//  Created by Claude Code on 9/13/25.
//  Advanced image processing to prevent VTPixelTransfer errors
//

import UIKit
import CoreImage
import VideoToolbox
import Accelerate

class EnhancedImageProcessor {
    static let shared = EnhancedImageProcessor()
    
    private let ciContext: CIContext
    private let processingQueue = DispatchQueue(label: "image.processing.queue", qos: .userInitiated)
    
    private init() {
        // Create high-performance Core Image context
        let options: [CIContextOption: Any] = [
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            .useSoftwareRenderer: false // Use GPU when available
        ]
        
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: metalDevice, options: options)
        } else {
            ciContext = CIContext(options: options)
        }
    }
    
    // MARK: - Main Processing Methods
    
    func processImageSafely(_ image: UIImage) async -> UIImage {
        return await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: image)
                    return
                }
                
                let processedImage = self.performSafeProcessing(image)
                continuation.resume(returning: processedImage)
            }
        }
    }
    
    func fixDimensionCompatibility(_ image: UIImage) -> UIImage {
        let size = image.size
        let scale = image.scale
        
        // Calculate even dimensions
        let evenWidth = (Int(size.width) % 2 == 0) ? Int(size.width) : Int(size.width) + 1
        let evenHeight = (Int(size.height) % 2 == 0) ? Int(size.height) : Int(size.height) + 1
        
        // Only process if dimensions need adjustment
        guard evenWidth != Int(size.width) || evenHeight != Int(size.height) else {
            return image
        }
        
        let evenSize = CGSize(width: CGFloat(evenWidth), height: CGFloat(evenHeight))
        
        return renderImageWithEvenDimensions(image, targetSize: evenSize, scale: scale)
    }
    
    func compressForUpload(_ image: UIImage, maxSizeBytes: Int = 1_000_000) async -> Data? {
        return await withCheckedContinuation { continuation in
            processingQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let compressedData = self.performIntelligentCompression(image, maxSizeBytes: maxSizeBytes)
                continuation.resume(returning: compressedData)
            }
        }
    }
    
    // MARK: - Private Processing Methods
    
    private func performSafeProcessing(_ image: UIImage) -> UIImage {
        // Step 1: Fix dimension compatibility
        var processedImage = fixDimensionCompatibility(image)
        
        // Step 2: Ensure proper color space
        processedImage = ensureProperColorSpace(processedImage)
        
        // Step 3: Apply any necessary corrections
        processedImage = applyQualityEnhancements(processedImage)
        
        return processedImage
    }
    
    private func renderImageWithEvenDimensions(_ image: UIImage, targetSize: CGSize, scale: CGFloat) -> UIImage {
        // Use high-quality rendering to prevent pixel transfer issues
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .extended
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: targetSize)
            
            // Fill with clear background to ensure proper RGBA format
            context.cgContext.clear(rect)
            context.cgContext.setFillColor(UIColor.clear.cgColor)
            context.cgContext.fill(rect)
            
            // Draw image with high quality interpolation
            context.cgContext.interpolationQuality = .high
            image.draw(in: rect)
        }
    }
    
    private func ensureProperColorSpace(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        // Check if image already has proper color space
        if cgImage.colorSpace?.name == CGColorSpace.sRGB {
            return image
        }
        
        // Convert to sRGB color space using Core Image for best quality
        let ciImage = CIImage(cgImage: cgImage)
        
        // Apply color space conversion
        guard let srgbColorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let outputImage = ciContext.createCGImage(ciImage, from: ciImage.extent, format: .RGBA8, colorSpace: srgbColorSpace) else {
            return image
        }
        
        return UIImage(cgImage: outputImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    private func applyQualityEnhancements(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Apply subtle contrast enhancement instead of noise reduction
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(ciImage, forKey: kCIInputImageKey)
        contrastFilter?.setValue(1.1, forKey: kCIInputContrastKey) // Slight contrast boost
        
        guard let enhancedImage = contrastFilter?.outputImage,
              let outputCGImage = ciContext.createCGImage(enhancedImage, from: enhancedImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    private func performIntelligentCompression(_ image: UIImage, maxSizeBytes: Int) -> Data? {
        // Step 1: Fix dimensions first
        let compatibleImage = fixDimensionCompatibility(image)
        
        // Step 2: Determine optimal size
        let originalSize = compatibleImage.size
        let maxDimension: CGFloat = 2048
        
        var targetImage = compatibleImage
        if max(originalSize.width, originalSize.height) > maxDimension {
            targetImage = resizeImageIntelligently(compatibleImage, maxDimension: maxDimension)
        }
        
        // Step 3: Progressive quality compression
        let qualityLevels: [CGFloat] = [0.9, 0.8, 0.7, 0.6, 0.5, 0.4]
        
        for quality in qualityLevels {
            if let data = targetImage.jpegData(compressionQuality: quality),
               data.count <= maxSizeBytes {
                print("📷 Image compressed to \(data.count) bytes at \(quality) quality")
                return data
            }
        }
        
        // If still too large, try further size reduction
        let smallerImage = resizeImageIntelligently(targetImage, maxDimension: maxDimension * 0.75)
        
        for quality in qualityLevels {
            if let data = smallerImage.jpegData(compressionQuality: quality),
               data.count <= maxSizeBytes {
                print("📷 Image compressed to \(data.count) bytes at reduced size and \(quality) quality")
                return data
            }
        }
        
        // Last resort: very small size
        return smallerImage.jpegData(compressionQuality: 0.3)
    }
    
    private func resizeImageIntelligently(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Ensure even dimensions
        let evenWidth = (Int(newSize.width) % 2 == 0) ? newSize.width : newSize.width + 1
        let evenHeight = (Int(newSize.height) % 2 == 0) ? newSize.height : newSize.height + 1
        newSize = CGSize(width: evenWidth, height: evenHeight)
        
        // Don't upscale
        if newSize.width > size.width || newSize.height > size.height {
            return fixDimensionCompatibility(image)
        }
        
        return renderImageWithEvenDimensions(image, targetSize: newSize, scale: 1.0)
    }
    
    // MARK: - Utility Methods
    
    func validateImageDimensions(_ image: UIImage) -> Bool {
        let size = image.size
        let width = Int(size.width)
        let height = Int(size.height)
        
        // Check if dimensions are even
        let hasEvenWidth = width % 2 == 0
        let hasEvenHeight = height % 2 == 0
        
        print("📐 Image dimensions: \(width)x\(height) - Even width: \(hasEvenWidth), Even height: \(hasEvenHeight)")
        
        return hasEvenWidth && hasEvenHeight
    }
    
    func getImageInfo(_ image: UIImage) -> String {
        let size = image.size
        let scale = image.scale
        let colorSpaceName = image.cgImage?.colorSpace?.name as String? ?? "Unknown"
        
        return "Size: \(size), Scale: \(scale), ColorSpace: \(colorSpaceName)"
    }
}

// MARK: - Accelerate Framework Optimizations

extension EnhancedImageProcessor {
    
    /// High-performance image resizing using Accelerate framework
    private func resizeImageWithAccelerate(_ image: UIImage, targetSize: CGSize) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        
        // Ensure even dimensions
        let evenWidth = (width % 2 == 0) ? width : width + 1
        let evenHeight = (height % 2 == 0) ? height : height + 1
        
        // Create source buffer
        var sourceBuffer = vImage_Buffer()
        var format = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )
        
        var error = vImageBuffer_InitWithCGImage(&sourceBuffer, &format, nil, cgImage, vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            print("❌ Failed to create source buffer: \(error)")
            return nil
        }
        
        defer {
            free(sourceBuffer.data)
        }
        
        // Create destination buffer
        var destinationBuffer = vImage_Buffer()
        error = vImageBuffer_Init(&destinationBuffer, vImagePixelCount(evenHeight), vImagePixelCount(evenWidth), 32, vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            print("❌ Failed to create destination buffer: \(error)")
            return nil
        }
        
        defer {
            free(destinationBuffer.data)
        }
        
        // Perform high-quality scaling
        error = vImageScale_ARGB8888(&sourceBuffer, &destinationBuffer, nil, vImage_Flags(kvImageHighQualityResampling))
        
        guard error == kvImageNoError else {
            print("❌ Failed to scale image: \(error)")
            return nil
        }
        
        // Create CGImage from result
        guard let outputCGImage = vImageCreateCGImageFromBuffer(&destinationBuffer, &format, nil, nil, vImage_Flags(kvImageNoAllocate), &error)?.takeRetainedValue() else {
            print("❌ Failed to create output CGImage: \(error)")
            return nil
        }
        
        return UIImage(cgImage: outputCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}