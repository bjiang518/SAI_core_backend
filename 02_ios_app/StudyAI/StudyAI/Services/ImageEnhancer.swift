//
//  ImageEnhancer.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import UIKit
import CoreImage
import Vision

/// Service for enhancing images for optimal question segmentation
class ImageEnhancer {
    static let shared = ImageEnhancer()
    
    private let context = CIContext()
    
    private init() {}
    
    /// Complete preprocessing pipeline for homework segmentation
    func preprocessForSegmentation(_ image: UIImage) -> UIImage {
        var processedImage = image
        
        // Step 1: Remove shadows and even out lighting
        processedImage = removeShadows(processedImage)
        
        // Step 2: Enhance contrast for better text visibility
        processedImage = enhanceContrast(processedImage)
        
        // Step 3: Remove noise while preserving text edges
        processedImage = removeNoise(processedImage)
        
        // Step 4: Sharpen text for better boundary detection
        processedImage = sharpenText(processedImage)
        
        print("✅ Image preprocessing completed")
        return processedImage
    }
    
    /// Remove shadows using CLAHE (Contrast Limited Adaptive Histogram Equalization)
    func removeShadows(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Convert to LAB color space for better shadow handling
        guard let colorFilter = CIFilter(name: "CIColorControls") else { return image }
        colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
        colorFilter.setValue(1.2, forKey: kCIInputContrastKey)  // Slight contrast boost
        colorFilter.setValue(0.1, forKey: kCIInputBrightnessKey) // Slight brightness boost
        
        guard let contrastImage = colorFilter.outputImage else { return image }
        
        // Apply CLAHE-like effect using local contrast enhancement
        guard let localContrastFilter = CIFilter(name: "CILocalContrastEnhancement") else {
            // Fallback if filter not available
            return createImageFromCIImage(contrastImage, originalImage: image) ?? image
        }
        
        localContrastFilter.setValue(contrastImage, forKey: kCIInputImageKey)
        localContrastFilter.setValue(0.3, forKey: "inputLocalContrastAmount") // Moderate enhancement
        
        guard let shadowRemovedImage = localContrastFilter.outputImage else {
            return createImageFromCIImage(contrastImage, originalImage: image) ?? image
        }
        
        return createImageFromCIImage(shadowRemovedImage, originalImage: image) ?? image
    }
    
    /// Enhance contrast specifically for text visibility
    func enhanceContrast(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Use exposure adjustment for better text contrast
        guard let exposureFilter = CIFilter(name: "CIExposureAdjust") else { return image }
        exposureFilter.setValue(ciImage, forKey: kCIInputImageKey)
        exposureFilter.setValue(0.3, forKey: kCIInputEVKey) // Slight exposure increase
        
        guard let exposedImage = exposureFilter.outputImage else { return image }
        
        // Apply gamma correction for better text separation
        guard let gammaFilter = CIFilter(name: "CIGammaAdjust") else {
            return createImageFromCIImage(exposedImage, originalImage: image) ?? image
        }
        
        gammaFilter.setValue(exposedImage, forKey: kCIInputImageKey)
        gammaFilter.setValue(0.8, forKey: "inputPower") // Lower gamma for better text contrast
        
        guard let contrastImage = gammaFilter.outputImage else {
            return createImageFromCIImage(exposedImage, originalImage: image) ?? image
        }
        
        return createImageFromCIImage(contrastImage, originalImage: image) ?? image
    }
    
    /// Remove noise while preserving text edges
    func removeNoise(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Use bilateral filter-like effect (noise reduction with edge preservation)
        guard let noiseFilter = CIFilter(name: "CIMedianFilter") else { return image }
        noiseFilter.setValue(ciImage, forKey: kCIInputImageKey)
        
        guard let denoisedImage = noiseFilter.outputImage else { return image }
        
        // Blend with original to preserve fine details
        guard let blendFilter = CIFilter(name: "CIBlendWithAlphaMask") else {
            return createImageFromCIImage(denoisedImage, originalImage: image) ?? image
        }
        
        // Create edge mask to preserve text edges
        guard let edgeMask = createEdgeMask(ciImage) else {
            return createImageFromCIImage(denoisedImage, originalImage: image) ?? image
        }
        
        blendFilter.setValue(ciImage, forKey: kCIInputImageKey)        // Original
        blendFilter.setValue(denoisedImage, forKey: kCIInputBackgroundImageKey) // Denoised
        blendFilter.setValue(edgeMask, forKey: kCIInputMaskImageKey)   // Edge mask
        
        guard let finalImage = blendFilter.outputImage else {
            return createImageFromCIImage(denoisedImage, originalImage: image) ?? image
        }
        
        return createImageFromCIImage(finalImage, originalImage: image) ?? image
    }
    
    /// Sharpen text for better boundary detection
    func sharpenText(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // Use unsharp mask for text sharpening
        guard let sharpenFilter = CIFilter(name: "CIUnsharpMask") else { return image }
        sharpenFilter.setValue(ciImage, forKey: kCIInputImageKey)
        sharpenFilter.setValue(2.0, forKey: kCIInputRadiusKey)      // Moderate radius
        sharpenFilter.setValue(0.8, forKey: kCIInputIntensityKey)   // Strong but not harsh
        
        guard let sharpenedImage = sharpenFilter.outputImage else { return image }
        
        return createImageFromCIImage(sharpenedImage, originalImage: image) ?? image
    }
    
    /// Convert image to grayscale for segmentation algorithms
    func convertToGrayscale(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        guard let grayscaleFilter = CIFilter(name: "CIColorMonochrome") else { return image }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(CIColor.white, forKey: kCIInputColorKey)
        grayscaleFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        guard let grayscaleImage = grayscaleFilter.outputImage else { return image }
        
        return createImageFromCIImage(grayscaleImage, originalImage: image) ?? image
    }
    
    /// Adjust image brightness and contrast separately
    func adjustBrightnessAndContrast(_ image: UIImage, brightness: Float, contrast: Float) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        // FIXED: Contrast should work like brightness - positive values increase contrast
        // Convert from -1...1 range to 0...2 range where 1.0 is neutral
        let contrastValue = max(0.0, 1.0 + contrast)
        filter.setValue(contrastValue, forKey: kCIInputContrastKey)

        guard let adjustedImage = filter.outputImage else { return image }

        return createImageFromCIImage(adjustedImage, originalImage: image) ?? image
    }

    /// Adjust image brightness for optimal processing
    func adjustBrightness(_ image: UIImage, brightness: Float) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        guard let brightnessFilter = CIFilter(name: "CIColorControls") else { return image }
        brightnessFilter.setValue(ciImage, forKey: kCIInputImageKey)
        brightnessFilter.setValue(brightness, forKey: kCIInputBrightnessKey)
        
        guard let adjustedImage = brightnessFilter.outputImage else { return image }
        
        return createImageFromCIImage(adjustedImage, originalImage: image) ?? image
    }
    
    /// Create a binary mask for better segmentation
    func createBinaryMask(_ image: UIImage, threshold: Float = 0.5) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let ciImage = CIImage(cgImage: cgImage)
        
        // First convert to grayscale
        guard let grayscaleFilter = CIFilter(name: "CIColorMonochrome") else { return nil }
        grayscaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayscaleFilter.setValue(CIColor.white, forKey: kCIInputColorKey)
        grayscaleFilter.setValue(1.0, forKey: kCIInputIntensityKey)
        
        guard let grayscaleImage = grayscaleFilter.outputImage else { return nil }
        
        // Apply threshold to create binary mask
        guard let thresholdFilter = CIFilter(name: "CIColorThreshold") else {
            // Fallback using exposure for thresholding
            guard let exposureFilter = CIFilter(name: "CIExposureAdjust") else { return nil }
            exposureFilter.setValue(grayscaleImage, forKey: kCIInputImageKey)
            exposureFilter.setValue(threshold * 2, forKey: kCIInputEVKey)
            
            guard let thresholdedImage = exposureFilter.outputImage else { return nil }
            return createImageFromCIImage(thresholdedImage, originalImage: image)
        }
        
        thresholdFilter.setValue(grayscaleImage, forKey: kCIInputImageKey)
        thresholdFilter.setValue(threshold, forKey: "inputThreshold")
        
        guard let binaryImage = thresholdFilter.outputImage else { return nil }
        
        return createImageFromCIImage(binaryImage, originalImage: image)
    }
    
    // MARK: - Private Helper Methods
    
    private func createEdgeMask(_ image: CIImage) -> CIImage? {
        // Create edge detection mask to preserve text edges during noise reduction
        guard let edgeFilter = CIFilter(name: "CIEdges") else { return nil }
        edgeFilter.setValue(image, forKey: kCIInputImageKey)
        edgeFilter.setValue(2.0, forKey: kCIInputIntensityKey)
        
        return edgeFilter.outputImage
    }
    
    private func createImageFromCIImage(_ ciImage: CIImage, originalImage: UIImage) -> UIImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: originalImage.scale, orientation: originalImage.imageOrientation)
    }
    
    /// Create a debug comparison showing before/after enhancement
    func createDebugComparison(_ originalImage: UIImage, processedImage: UIImage) -> UIImage? {
        let size = CGSize(width: originalImage.size.width * 2, height: originalImage.size.height)
        
        UIGraphicsBeginImageContextWithOptions(size, false, originalImage.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Draw original image on left
        originalImage.draw(in: CGRect(x: 0, y: 0, width: originalImage.size.width, height: originalImage.size.height))
        
        // Draw processed image on right
        processedImage.draw(in: CGRect(x: originalImage.size.width, y: 0, width: originalImage.size.width, height: originalImage.size.height))
        
        // Add labels
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.setFillColor(UIColor.black.withAlphaComponent(0.7).cgColor)
        context.fill(CGRect(x: 10, y: 10, width: 100, height: 30))
        context.fill(CGRect(x: originalImage.size.width + 10, y: 10, width: 100, height: 30))
        
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.white,
            .font: UIFont.boldSystemFont(ofSize: 16)
        ]
        
        "Original".draw(at: CGPoint(x: 15, y: 15), withAttributes: attributes)
        "Enhanced".draw(at: CGPoint(x: originalImage.size.width + 15, y: 15), withAttributes: attributes)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

// MARK: - Quality Assessment

extension ImageEnhancer {
    /// Assess image quality for segmentation
    func assessImageQuality(_ image: UIImage) -> ImageQualityAssessment {
        guard let cgImage = image.cgImage else {
            return ImageQualityAssessment(overallScore: 0.0, needsEnhancement: true, recommendations: ["Invalid image"])
        }
        
        var recommendations: [String] = []
        var scores: [Float] = []
        
        // Check contrast
        let contrastScore = assessContrast(cgImage)
        scores.append(contrastScore)
        if contrastScore < 0.5 {
            recommendations.append("Low contrast - consider enhancement")
        }
        
        // Check brightness
        let brightnessScore = assessBrightness(cgImage)
        scores.append(brightnessScore)
        if brightnessScore < 0.3 {
            recommendations.append("Too dark - increase brightness")
        } else if brightnessScore > 0.8 {
            recommendations.append("Too bright - may have glare")
        }
        
        // Check sharpness
        let sharpnessScore = assessSharpness(cgImage)
        scores.append(sharpnessScore)
        if sharpnessScore < 0.4 {
            recommendations.append("Blurry image - try retaking photo")
        }
        
        let overallScore = scores.reduce(0, +) / Float(scores.count)
        let needsEnhancement = overallScore < 0.6
        
        if recommendations.isEmpty {
            recommendations.append("Image quality is good")
        }
        
        return ImageQualityAssessment(
            overallScore: overallScore,
            needsEnhancement: needsEnhancement,
            recommendations: recommendations
        )
    }
    
    private func assessContrast(_ cgImage: CGImage) -> Float {
        // Simple contrast assessment based on histogram spread
        // In a real implementation, you'd analyze the histogram
        // For now, return a placeholder value
        return 0.7
    }
    
    private func assessBrightness(_ cgImage: CGImage) -> Float {
        // Simple brightness assessment based on average pixel value
        // In a real implementation, you'd calculate mean luminance
        // For now, return a placeholder value  
        return 0.6
    }
    
    private func assessSharpness(_ cgImage: CGImage) -> Float {
        // Simple sharpness assessment based on edge detection
        // In a real implementation, you'd use Laplacian variance
        // For now, return a placeholder value
        return 0.8
    }
}

// MARK: - Supporting Types

struct ImageQualityAssessment {
    let overallScore: Float      // 0.0 to 1.0
    let needsEnhancement: Bool
    let recommendations: [String]
}