//
//  VisionDocumentScanner.swift
//  StudyAI
//
//  Created by Claude Code on 9/14/25.
//  Advanced document scanning and enhancement using Vision and CoreImage
//

import Foundation
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

class VisionDocumentScanner: ScanningService {
    
    private let ciContext = CIContext()
    
    func autoDetectDocument(_ image: UIImage) async -> ScannedPage {
        return await withCheckedContinuation { continuation in
            detectDocumentRectangle(in: image) { [weak self] detectedRect in
                guard let self = self else {
                    let page = ScannedPage(originalImage: image, processedImage: image)
                    continuation.resume(returning: page)
                    return
                }
                
                var processedImage = image
                var cropRect: CGRect? = nil
                
                if let rect = detectedRect {
                    cropRect = rect
                    processedImage = self.cropImage(image, to: rect)
                    
                    // Apply perspective correction if the detected rectangle is significantly skewed
                    if self.isRectangleSkewed(rect) {
                        processedImage = self.applyPerspectiveCorrection(processedImage, rect: rect)
                    }
                }
                
                // Apply basic document enhancement
                processedImage = self.enhanceDocumentImage(processedImage)
                
                let page = ScannedPage(
                    originalImage: image,
                    processedImage: processedImage,
                    filename: "Document_\(Date().timeIntervalSince1970)"
                )
                
                continuation.resume(returning: page)
            }
        }
    }
    
    func enhanceDocument(_ page: ScannedPage) async -> ScannedPage {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let enhancedImage = self.enhanceDocumentImage(page.processedImage, params: page.enhanceParams)
                
                var updatedPage = page
                updatedPage.processedImage = enhancedImage
                updatedPage.enhanceParams.autoEnhanced = true
                updatedPage.updateFileSize()
                
                DispatchQueue.main.async {
                    continuation.resume(returning: updatedPage)
                }
            }
        }
    }
    
    func applyPerspectiveCorrection(_ page: ScannedPage, rect: CGRect) async -> ScannedPage {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let correctedImage = self.applyPerspectiveCorrection(page.processedImage, rect: rect)
                
                var updatedPage = page
                updatedPage.processedImage = correctedImage
                updatedPage.enhanceParams.perspectiveCorrected = true
                updatedPage.updateFileSize()
                
                DispatchQueue.main.async {
                    continuation.resume(returning: updatedPage)
                }
            }
        }
    }
    
    func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        // Convert rect coordinates to image coordinate system
        let imageRect = CGRect(
            x: rect.origin.x * CGFloat(cgImage.width),
            y: rect.origin.y * CGFloat(cgImage.height),
            width: rect.size.width * CGFloat(cgImage.width),
            height: rect.size.height * CGFloat(cgImage.height)
        )
        
        guard let croppedCGImage = cgImage.cropping(to: imageRect) else { return image }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    func rotateImage(_ image: UIImage, by degrees: Double) -> UIImage {
        let radians = degrees * Double.pi / 180.0
        
        guard let cgImage = image.cgImage else { return image }
        
        let rotatedSize = CGSize(
            width: abs(cos(radians)) * image.size.width + abs(sin(radians)) * image.size.height,
            height: abs(sin(radians)) * image.size.width + abs(cos(radians)) * image.size.height
        )
        
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: CGFloat(radians))
        context.translateBy(x: -image.size.width / 2, y: -image.size.height / 2)
        
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return rotatedImage
    }
    
    // MARK: - Private Methods
    
    private func detectDocumentRectangle(in image: UIImage, completion: @escaping (CGRect?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        let request = VNDetectRectanglesRequest { request, error in
            guard let observations = request.results as? [VNRectangleObservation],
                  let bestObservation = observations.first else {
                completion(nil)
                return
            }
            
            // Convert from Vision coordinates to UIImage coordinates
            let rect = CGRect(
                x: bestObservation.boundingBox.origin.x,
                y: 1.0 - bestObservation.boundingBox.origin.y - bestObservation.boundingBox.height,
                width: bestObservation.boundingBox.width,
                height: bestObservation.boundingBox.height
            )
            
            completion(rect)
        }
        
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 3.0
        request.minimumSize = 0.2
        request.maximumObservations = 1
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }
    
    private func isRectangleSkewed(_ rect: CGRect) -> Bool {
        // Simple heuristic: if the rectangle is significantly different from a standard rectangle
        let aspectRatio = rect.width / rect.height
        return aspectRatio < 0.5 || aspectRatio > 2.0
    }
    
    private func applyPerspectiveCorrection(_ image: UIImage, rect: CGRect) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        // Create perspective correction filter
        let perspectiveFilter = CIFilter.perspectiveCorrection()
        perspectiveFilter.inputImage = ciImage
        
        // Define the quadrilateral points (simplified - using rect bounds)
        let imageSize = ciImage.extent.size
        perspectiveFilter.topLeft = CGPoint(
            x: rect.minX * imageSize.width,
            y: (1.0 - rect.maxY) * imageSize.height
        )
        perspectiveFilter.topRight = CGPoint(
            x: rect.maxX * imageSize.width,
            y: (1.0 - rect.maxY) * imageSize.height
        )
        perspectiveFilter.bottomLeft = CGPoint(
            x: rect.minX * imageSize.width,
            y: (1.0 - rect.minY) * imageSize.height
        )
        perspectiveFilter.bottomRight = CGPoint(
            x: rect.maxX * imageSize.width,
            y: (1.0 - rect.minY) * imageSize.height
        )
        
        guard let outputImage = perspectiveFilter.outputImage,
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    private func enhanceDocumentImage(_ image: UIImage, params: EnhanceParams = EnhanceParams()) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }
        
        var processedImage = ciImage
        
        // Apply brightness and contrast adjustments
        if params.brightness != 0.0 || params.contrast != 1.0 {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = processedImage
            colorControls.brightness = params.brightness
            colorControls.contrast = params.contrast
            colorControls.saturation = params.saturation
            
            if let output = colorControls.outputImage {
                processedImage = output
            }
        }
        
        // Apply document enhancement if auto-enhance is enabled
        if params.autoEnhanced {
            // Sharpen the image
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = processedImage
            sharpen.sharpness = 0.4
            
            if let output = sharpen.outputImage {
                processedImage = output
            }
            
            // Increase contrast for text readability
            let contrast = CIFilter.colorControls()
            contrast.inputImage = processedImage
            contrast.contrast = 1.2
            
            if let output = contrast.outputImage {
                processedImage = output
            }
        }
        
        // Convert back to UIImage
        guard let cgImage = ciContext.createCGImage(processedImage, from: processedImage.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Updated Default Scanning Service

class DefaultScanningService: ScanningService {
    private let visionScanner = VisionDocumentScanner()
    
    func autoDetectDocument(_ image: UIImage) async -> ScannedPage {
        return await visionScanner.autoDetectDocument(image)
    }
    
    func enhanceDocument(_ page: ScannedPage) async -> ScannedPage {
        return await visionScanner.enhanceDocument(page)
    }
    
    func applyPerspectiveCorrection(_ page: ScannedPage, rect: CGRect) async -> ScannedPage {
        return await visionScanner.applyPerspectiveCorrection(page, rect: rect)
    }
    
    func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage {
        return visionScanner.cropImage(image, to: rect)
    }
    
    func rotateImage(_ image: UIImage, by degrees: Double) -> UIImage {
        return visionScanner.rotateImage(image, by: degrees)
    }
}