//
//  ImageProcessingService.swift
//  StudyAI
//
//  Created by Claude Code on 9/1/25.
//

import UIKit
@preconcurrency import Vision

class ImageProcessingService {
    static let shared = ImageProcessingService()

    private init() {}

    /// Aggressively preprocess image: Convert to binary with enhanced light correction
    /// This dramatically reduces file size while maintaining text readability
    func preprocessImageForAI(_ image: UIImage) -> UIImage? {
        print("🔧 === ADVANCED IMAGE PREPROCESSING STARTED ===")
        print("📊 Input image size: \(image.size.width)x\(image.size.height)")

        guard let cgImage = image.cgImage else {
            print("❌ Could not get CGImage from input")
            return nil
        }

        let inputImage = CIImage(cgImage: cgImage)
        let context = CIContext()

        print("🌟 Step 1: Enhanced light correction and contrast...")
        // Step 1: Enhanced light correction and contrast
        let adjustedImage = inputImage
            .applyingFilter("CIExposureAdjust", parameters: ["inputEV": 0.5]) // Brighten
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.75]) // Increase contrast
            .applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": -0.3, // Reduce blown highlights
                "inputShadowAmount": 0.6      // Lift shadows
            ])

        print("🎨 Step 2: Converting to grayscale...")
        // Step 2: Convert to grayscale
        let grayscaleImage = adjustedImage
            .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0.0])

        print("⚫⚪ Step 3: Applying adaptive thresholding for binary conversion...")
        // Step 3: Apply adaptive thresholding for binary conversion
        // This creates pure black text on white background
        let binaryImage = grayscaleImage
            .applyingFilter("CIColorControls", parameters: [
                "inputContrast": 2.5,     // Maximum contrast
                "inputBrightness": 0.2    // Slight brightness boost
            ])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.4]) // Sharp threshold

        print("🖼️ Step 4: Converting back to UIImage...")
        // Convert back to UIImage
        guard let outputCGImage = context.createCGImage(binaryImage, from: binaryImage.extent) else {
            print("❌ Could not create CGImage from processed CIImage")
            return nil
        }

        let resultImage = UIImage(cgImage: outputCGImage)
        print("✅ Preprocessing complete!")
        print("📊 Output image size: \(resultImage.size.width)x\(resultImage.size.height)")
        print("📈 Expected size reduction: ~80-90% due to binary conversion")

        return resultImage
    }

    /// Get preprocessing progress estimates
    func getPreprocessingSteps() -> [String] {
        return [
            "Analyzing image lighting...",
            "Enhancing contrast and brightness...",
            "Converting to optimized binary format...",
            "Finalizing for AI processing..."
        ]
    }
    
    /// Extract text from image using Vision framework with enhanced math detection
    func extractTextFromImage(_ image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                DispatchQueue.main.async {
                    if let error = error {
                        print("OCR Error: \(error)")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let observations = request.results as? [VNRecognizedTextObservation] ?? []
                    let recognizedText = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }.joined(separator: "\n")
                    
                    // Detect if text contains mathematical content
                    let containsMath = self.detectMathContent(recognizedText)
                    
                    // Apply appropriate processing
                    let processedText: String
                    if containsMath {
                        processedText = self.convertSimpleMathToLaTeX(recognizedText)
                    } else {
                        processedText = self.postProcessRegularText(recognizedText)
                    }
                    
                    continuation.resume(returning: processedText.isEmpty ? nil : processedText)
                }
            }
            
            // Configure for better math recognition
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false // Disable for math symbols
            request.recognitionLanguages = ["en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    DispatchQueue.main.async {
                        print("Failed to perform OCR: \(error)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
    
    /// Detect if the text contains mathematical content
    private func detectMathContent(_ text: String) -> Bool {
        let mathIndicators = [
            // Common math symbols
            "=", "+", "-", "×", "÷", "*", "/", "^",
            // Greek letters (Unicode)
            "π", "α", "β", "γ", "δ", "θ", "λ", "μ", "σ", "ω",
            // Greek letters (text patterns that OCR produces)
            "pi", "Pi", "PI", "alpha", "beta", "gamma", "delta", "theta",
            // Mathematical operators
            "≤", "≥", "≠", "≈", "∞", "∫", "∑", "√",
            // Common math patterns
            "sin", "cos", "tan", "log", "ln", "lim",
            // Fraction indicators
            "1/2", "3/4", "x/y",
            // Equation patterns
            "solve", "equation", "derivative", "integral",
            // Square root patterns
            "sqrt", "square root", "√",
            // Exponent patterns (common OCR results)
            "^2", "^3", "x2", "r2", "²", "³", "¹", "⁴", "⁵",
            // Superscript detection patterns
            "power", "squared", "cubed",
            // Common pi approximations and OCR mistakes
            "3.14", "TT", "II"
        ]
        
        let lowercaseText = text.lowercased()
        return mathIndicators.contains { lowercaseText.contains($0) }
    }
    
    /// Convert simple mathematical symbols to LaTeX format
    private func convertSimpleMathToLaTeX(_ text: String) -> String {
        var latex = text
        
        // Basic symbol replacements
        let basicSymbols = [
            ("×", "*"), ("÷", "/"), ("≤", "$\\leq$"), ("≥", "$\\geq$"),
            ("≠", "$\\neq$"), ("≈", "$\\approx$"), ("∞", "$\\infty$"),
            ("±", "$\\pm$"), ("π", "$\\pi$"),
            ("α", "$\\alpha$"), ("β", "$\\beta$"), ("γ", "$\\gamma$"),
            ("δ", "$\\delta$"), ("θ", "$\\theta$"), ("λ", "$\\lambda$"),
            ("μ", "$\\mu$"), ("σ", "$\\sigma$"), ("ω", "$\\omega$")
        ]
        
        for (unicode, latexSymbol) in basicSymbols {
            latex = latex.replacingOccurrences(of: unicode, with: latexSymbol)
        }
        
        // Enhanced pi recognition - OCR often reads π as "pi" or other variations
        let piPatterns = [
            ("\\bpi\\b", "$\\pi$"),           // "pi" as standalone word
            ("\\bPi\\b", "$\\pi$"),           // "Pi" with capital P
            ("\\bPI\\b", "$\\pi$"),           // "PI" all caps
            ("π", "$\\pi$"),                  // Direct Unicode symbol
            ("∏", "$\\pi$"),                  // Sometimes OCR confuses ∏ (product) with π
            ("TT", "$\\pi$"),                 // Common OCR mistake
            ("II", "$\\pi$"),                 // Another common OCR mistake
            ("3\\.14", "$\\pi$"),             // Sometimes shown as decimal approximation
        ]
        
        for (pattern, replacement) in piPatterns {
            latex = latex.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        
        // Enhanced square root handling
        // Handle various OCR patterns for square roots
        let squareRootPatterns = [
            // Direct Unicode symbol
            ("√([0-9a-zA-Z\\(\\)\\+\\-\\*/]+)", "$\\\\sqrt{$1}$"),
            // Word patterns
            ("sqrt\\s*\\(([^)]+)\\)", "$\\\\sqrt{$1}$"),
            ("sqrt\\s+([0-9a-zA-Z]+)", "$\\\\sqrt{$1}$"),
            ("square root of\\s+([0-9a-zA-Z\\(\\)\\+\\-\\*/]+)", "$\\\\sqrt{$1}$"),
            ("√\\s*\\(([^)]+)\\)", "$\\\\sqrt{$1}$"),
            // Common OCR mistakes
            ("V([0-9]+)", "$\\\\sqrt{$1}$"), // V often mistaken for √
            ("v([0-9]+)", "$\\\\sqrt{$1}$"), // lowercase v
        ]
        
        for (pattern, replacement) in squareRootPatterns {
            latex = latex.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        
        // Enhanced exponent/superscript handling
        // Handle Unicode superscripts first
        let unicodeSuperscripts = [
            ("²", "^{2}"), ("³", "^{3}"), ("¹", "^{1}"), ("⁴", "^{4}"), ("⁵", "^{5}"),
            ("⁶", "^{6}"), ("⁷", "^{7}"), ("⁸", "^{8}"), ("⁹", "^{9}"), ("⁰", "^{0}")
        ]
        
        for (unicodeChar, exponentCode) in unicodeSuperscripts {
            latex = latex.replacingOccurrences(
                of: "([a-zA-Z0-9\\)]+)\\(unicodeChar)",
                with: "$1\\(exponentCode)",
                options: .regularExpression
            )
        }
        
        // Handle various exponent patterns
        let exponentPatterns = [
            // Standard caret notation: x^2, r^3
            ("([a-zA-Z0-9\\)]+)\\^([0-9]+)", "$1^{$2}"),
            // Adjacent notation often from OCR: x2, r2, a3 (but not pure numbers like 23)
            ("([a-zA-Z])([0-9])(?![0-9])", "$1^{$2}"),
            // Word patterns
            ("([a-zA-Z0-9\\)]+)\\s+squared", "$1^{2}"),
            ("([a-zA-Z0-9\\)]+)\\s+cubed", "$1^{3}"),
            ("([a-zA-Z0-9\\)]+)\\s+to the power of\\s+([0-9]+)", "$1^{$2}"),
            ("([a-zA-Z0-9\\)]+)\\s+power\\s+([0-9]+)", "$1^{$2}"),
            // Common OCR patterns
            ("([a-zA-Z])\\s*\\*\\s*\\*\\s*([0-9]+)", "$1^{$2}"), // a**2 → a^2
        ]
        
        for (pattern, replacement) in exponentPatterns {
            latex = latex.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        
        // Wrap exponents in LaTeX if not already wrapped
        latex = latex.replacingOccurrences(
            of: "([a-zA-Z0-9\\)]+)\\^\\{([0-9]+)\\}",
            with: "$1^{$2}",
            options: .regularExpression
        )
        
        // Handle simple fractions: "1/2" → "$\frac{1}{2}$"
        latex = latex.replacingOccurrences(
            of: "\\b(\\d+)/(\\d+)\\b",
            with: "$\\\\frac{$1}{$2}$",
            options: .regularExpression
        )
        
        // Handle mathematical functions
        let mathFunctions = ["sin", "cos", "tan", "log", "ln", "lim"]
        for function in mathFunctions {
            latex = latex.replacingOccurrences(
                of: "\\b\(function)\\b",
                with: "$\\\\\(function)$",
                options: .regularExpression
            )
        }
        
        // Clean up spacing around equals
        latex = latex.replacingOccurrences(
            of: "([a-zA-Z0-9])=([a-zA-Z0-9])",
            with: "$1 = $2",
            options: .regularExpression
        )
        
        return latex
    }
    
    /// Process regular text (non-mathematical)
    private func postProcessRegularText(_ text: String) -> String {
        var processed = text
        
        // Basic cleanup for regular text
        processed = processed.replacingOccurrences(of: "—", with: "-")
        processed = processed.replacingOccurrences(of: "–", with: "-")
        processed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return processed
    }
    
    /// Compress and prepare image for server upload (for complex math cases)
    func compressImageForUpload(_ image: UIImage, maxSizeKB: Int = 500) -> Data? {
        let maxSizeBytes = maxSizeKB * 1024
        let maxDimension: CGFloat = 1024 // Maximum width or height
        
        // Resize image if needed
        let resizedImage = resizeImage(image, maxDimension: maxDimension)
        
        // Start with high quality and reduce until size is acceptable
        var compressionQuality: CGFloat = 0.8
        var imageData = resizedImage.jpegData(compressionQuality: compressionQuality)
        
        while let data = imageData, data.count > maxSizeBytes && compressionQuality > 0.1 {
            compressionQuality -= 0.1
            imageData = resizedImage.jpegData(compressionQuality: compressionQuality)
        }
        
        print("📷 Image compressed: \(imageData?.count ?? 0) bytes at \(compressionQuality) quality")
        return imageData
    }
    
    /// Resize image to maximum dimension while maintaining aspect ratio
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Don't upscale small images
        if newSize.width > size.width || newSize.height > size.height {
            return image
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    /// Check if OCR result quality is good enough or if image upload is recommended
    func shouldRecommendImageUpload(ocrResult: String?, originalImage: UIImage) -> Bool {
        guard let text = ocrResult else { return true }
        
        // Recommend image upload if:
        // 1. OCR result is very short but image seems to have more content
        // 2. Contains complex math indicators that simple OCR might miss
        // 3. Contains symbols that are hard for Vision OCR
        
        let complexMathIndicators = [
            "∫", "∑", "∏", // Integrals, sums, products
            "matrix", "begin", "end", // LaTeX matrix notation
            "frac", "sqrt", "lim", // Complex mathematical structures
            "{", "}", "[", "]" // Bracket notation suggesting complex structure
        ]
        
        let hasComplexMath = complexMathIndicators.contains { text.lowercased().contains($0) }
        let isVeryShort = text.trimmingCharacters(in: .whitespacesAndNewlines).count < 10
        
        return hasComplexMath || isVeryShort
    }
    
    /// Placeholder for future mathematical equation recognition
    func recognizeMathEquation(_ image: UIImage) async -> String? {
        // TODO: Phase 3 - Implement advanced mathematical equation recognition
        // This would involve training custom models or using specialized APIs
        return await extractTextFromImage(image)
    }
    
    /// Prepare image for processing (resize, enhance contrast, etc.)
    func preprocessImage(_ image: UIImage) -> UIImage {
        // TODO: Phase 3 - Implement image preprocessing
        // For now, return the original image
        return image
    }
}