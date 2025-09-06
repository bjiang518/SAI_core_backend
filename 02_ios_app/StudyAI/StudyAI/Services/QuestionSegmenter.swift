//
//  QuestionSegmenter.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import UIKit
import Vision
import CoreImage

// MARK: - Data Models

struct QuestionBoundary {
    let yPosition: CGFloat       // Y position in normalized coordinates (0-1)
    let confidence: Float        // Confidence score (0-1)
    let isUserAdjusted: Bool     // Whether user manually adjusted this boundary
    let width: CGFloat           // Width of the boundary line (for display)
    
    init(yPosition: CGFloat, confidence: Float, isUserAdjusted: Bool = false, width: CGFloat = 1.0) {
        self.yPosition = max(0, min(1, yPosition)) // Clamp to 0-1 range
        self.confidence = max(0, min(1, confidence))
        self.isUserAdjusted = isUserAdjusted
        self.width = width
    }
}

struct QuestionRegion {
    let id: String
    let bounds: CGRect           // Normalized coordinates (0-1)
    let thumbnail: UIImage       // Small preview image
    let questionNumber: Int?     // Detected question number (1, 2, 3...)
    let textConfidence: Float    // How confident we are this contains text
    let estimatedLines: Int      // Estimated number of text lines
    
    init(id: String, bounds: CGRect, thumbnail: UIImage, questionNumber: Int? = nil, textConfidence: Float = 0.8, estimatedLines: Int = 1) {
        self.id = id
        self.bounds = bounds
        self.thumbnail = thumbnail
        self.questionNumber = questionNumber
        self.textConfidence = textConfidence
        self.estimatedLines = estimatedLines
    }
}

struct SegmentationResult {
    let boundaries: [QuestionBoundary]
    let regions: [QuestionRegion]
    let processingTime: TimeInterval
    let algorithmUsed: String
    let qualityScore: Float      // Overall segmentation quality (0-1)
}

// MARK: - Question Segmenter Service

/// Core service for detecting question boundaries in homework images
class QuestionSegmenter {
    static let shared = QuestionSegmenter()
    
    private init() {}
    
    // MARK: - Main Segmentation Methods
    
    /// Detect question boundaries using horizontal projection algorithm
    func detectQuestionBoundaries(_ image: UIImage) async -> [QuestionBoundary] {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        print("🚀 Starting question boundary detection...")
        print("📐 Input image size: \(image.size)")
        
        // Preprocess image for better boundary detection
        let processedImage = await preprocessImageForSegmentation(image)
        print("✅ Image preprocessing completed")
        
        // Compute horizontal projection
        guard let projection = await computeHorizontalProjection(processedImage) else {
            print("❌ Failed to compute horizontal projection")
            return []
        }
        
        print("📊 Computed horizontal projection: \(projection.count) rows")
        
        // Find valleys (low text density areas)
        let valleys = findValleys(projection)
        print("🏔️ Found \(valleys.count) initial valleys")
        
        // Apply non-maximum suppression with moderate distance for automatic detection
        let filteredValleys = applyNonMaxSuppression(valleys, minDistance: 0.08) // Reduced from 15% to 8% of image height
        print("🔍 After NMS: \(filteredValleys.count) valleys")
        
        // Convert to QuestionBoundary objects with confidence scores
        let boundaries = validateAndScoreBoundaries(filteredValleys, imageHeight: processedImage.size.height, projection: projection)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        print("✅ Detected \(boundaries.count) question boundaries in \(Int(processingTime * 1000))ms")
        
        // Log boundary details
        for (index, boundary) in boundaries.enumerated() {
            print("📍 Boundary \(index): y=\(String(format: "%.3f", boundary.yPosition)), confidence=\(String(format: "%.3f", boundary.confidence))")
        }
        
        return boundaries
    }
    
    /// Complete segmentation - detect boundaries and create question regions
    func segmentHomeworkPage(_ image: UIImage) async -> SegmentationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Step 1: Detect boundaries
        let boundaries = await detectQuestionBoundaries(image)
        
        // Step 2: Create question regions from boundaries
        let regions = await createQuestionRegions(from: boundaries, originalImage: image)
        
        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        let qualityScore = assessSegmentationQuality(boundaries: boundaries, regions: regions)
        
        print("✅ Segmented homework page: \(regions.count) questions in \(Int(processingTime * 1000))ms (quality: \(String(format: "%.2f", qualityScore)))")
        
        return SegmentationResult(
            boundaries: boundaries,
            regions: regions,
            processingTime: processingTime,
            algorithmUsed: "Horizontal Projection with NMS",
            qualityScore: qualityScore
        )
    }
    
    // MARK: - Core Algorithm Implementation
    
    private func preprocessImageForSegmentation(_ image: UIImage) async -> UIImage {
        // Use our existing ImageEnhancer for optimal preprocessing
        let enhanced = await ImageEnhancer.shared.preprocessForSegmentation(image)
        
        // Convert to grayscale for projection analysis
        return await ImageEnhancer.shared.convertToGrayscale(enhanced)
    }
    
    private func computeHorizontalProjection(_ image: UIImage) async -> [Int]? {
        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return nil }
            
            let width = cgImage.width
            let height = cgImage.height
            
            // Create data provider to access pixel data
            guard let dataProvider = cgImage.dataProvider,
                  let data = dataProvider.data,
                  let pixelData = CFDataGetBytePtr(data) else {
                return nil
            }
            
            var projection = Array(repeating: 0, count: height)
            let bytesPerPixel = cgImage.bitsPerPixel / 8
            let bytesPerRow = cgImage.bytesPerRow
            
            // For each row, count dark pixels (text)
            for y in 0..<height {
                var darkPixelCount = 0
                
                for x in 0..<width {
                    let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                    
                    // For grayscale, we only need one channel
                    let pixelValue = pixelData[pixelIndex]
                    
                    // Consider pixels darker than threshold as "text"
                    let threshold: UInt8 = 128
                    if pixelValue < threshold {
                        darkPixelCount += 1
                    }
                }
                
                projection[y] = darkPixelCount
            }
            
            return projection
        }.value
    }
    
    private func findValleys(_ projection: [Int]) -> [CGFloat] {
        guard !projection.isEmpty else { return [] }
        
        // Calculate statistics with more robust analysis
        let maxValue = projection.max() ?? 1
        let minValue = projection.min() ?? 0
        let meanValue = projection.reduce(0, +) / projection.count
        let range = maxValue - minValue
        
        print("📊 Projection stats: min=\(minValue), max=\(maxValue), mean=\(meanValue), range=\(range)")
        
        // Adaptive threshold based on content type - More balanced for automatic segmentation
        let dynamicThreshold: Int
        if range < meanValue / 2 {
            // Low variance content (like music sheets) - use moderate threshold
            dynamicThreshold = max(1, Int(Float(meanValue) * 0.12))
            print("🎵 Low variance detected (music/uniform content), using threshold: \(dynamicThreshold)")
        } else {
            // High variance content (typical homework) - use moderate threshold for automatic detection
            // This will detect reasonable gaps between questions while avoiding sub-question splits
            dynamicThreshold = max(1, Int(Float(meanValue) * 0.18)) // More permissive than 0.1
            print("📝 High variance detected (homework content), using threshold: \(dynamicThreshold)")
        }
        
        var valleys: [CGFloat] = []
        var inValley = false
        var valleyStart = 0
        var valleySum = 0
        var valleyCount = 0
        
        // Find continuous regions below threshold with better valley analysis
        for (index, value) in projection.enumerated() {
            if value <= dynamicThreshold {
                if !inValley {
                    inValley = true
                    valleyStart = index
                    valleySum = value
                    valleyCount = 1
                } else {
                    valleySum += value
                    valleyCount += 1
                }
            } else {
                if inValley {
                    // End of valley - analyze valley quality
                    let valleyEnd = index - 1
                    let valleyLength = valleyEnd - valleyStart + 1
                    let valleyMidpoint = (valleyStart + valleyEnd) / 2
                    let normalizedY = CGFloat(valleyMidpoint) / CGFloat(projection.count)
                    let avgValleyValue = Float(valleySum) / Float(valleyCount)
                    
                    // Valley quality criteria for AUTOMATIC QUESTION DETECTION:
                    // 1. Reasonable minimum width (moderate gap required)
                    // 2. Not too close to edges
                    // 3. Moderate quality requirement for automatic detection
                    let minWidth = max(5, projection.count / 150) // Smaller minimum width (0.67% of image height)
                    let edgeMargin = max(8, projection.count / 20) // Moderate edge margin (5%)
                    let qualityScore = 1.0 - (avgValleyValue / Float(dynamicThreshold))
                    
                    // More balanced criteria for automatic detection
                    if valleyLength >= minWidth && 
                       valleyStart > edgeMargin && 
                       valleyEnd < projection.count - edgeMargin &&
                       qualityScore > 0.4 { // More permissive quality requirement
                        valleys.append(normalizedY)
                        print("✅ Question boundary found: pos=\(String(format: "%.3f", normalizedY)), length=\(valleyLength), quality=\(String(format: "%.2f", qualityScore))")
                    } else {
                        print("❌ Boundary rejected: pos=\(String(format: "%.3f", normalizedY)), length=\(valleyLength), quality=\(String(format: "%.2f", qualityScore))")
                    }
                    
                    inValley = false
                }
            }
        }
        
        // Handle case where image ends in a valley
        if inValley {
            let valleyEnd = projection.count - 1
            let valleyLength = valleyEnd - valleyStart + 1
            let valleyMidpoint = (valleyStart + valleyEnd) / 2
            let normalizedY = CGFloat(valleyMidpoint) / CGFloat(projection.count)
            let avgValleyValue = Float(valleySum) / Float(valleyCount)
            let qualityScore = 1.0 - (avgValleyValue / Float(dynamicThreshold))
            
            if valleyLength >= 3 && qualityScore > 0.3 {
                valleys.append(normalizedY)
                print("✅ End valley found: pos=\(String(format: "%.3f", normalizedY)), length=\(valleyLength)")
            }
        }
        
        // If no valleys found with standard approach, try more aggressive detection
        if valleys.isEmpty && range > 0 {
            print("🔍 No valleys found, trying aggressive detection...")
            let aggressiveThreshold = minValue + (range / 4) // Bottom 25% of values
            
            for (index, value) in projection.enumerated() {
                if value <= aggressiveThreshold {
                    let normalizedY = CGFloat(index) / CGFloat(projection.count)
                    if normalizedY > 0.1 && normalizedY < 0.9 { // Avoid edges
                        valleys.append(normalizedY)
                        if valleys.count >= 3 { break } // Limit aggressive detection
                    }
                }
            }
            print("🔍 Aggressive detection found \(valleys.count) potential valleys")
        }
        
        print("📊 Final valleys found: \(valleys.count)")
        return valleys.sorted()
    }
    
    private func applyNonMaxSuppression(_ valleys: [CGFloat], minDistance: CGFloat) -> [CGFloat] {
        guard valleys.count > 1 else { return valleys }
        
        let sortedValleys = valleys.sorted()
        var filteredValleys: [CGFloat] = []
        
        for valley in sortedValleys {
            let tooClose = filteredValleys.contains { abs($0 - valley) < minDistance }
            if !tooClose {
                filteredValleys.append(valley)
            }
        }
        
        print("🔍 Non-max suppression: \(valleys.count) → \(filteredValleys.count) valleys")
        return filteredValleys
    }
    
    private func validateAndScoreBoundaries(_ valleys: [CGFloat], imageHeight: CGFloat, projection: [Int]) -> [QuestionBoundary] {
        var boundaries: [QuestionBoundary] = []
        
        for valley in valleys {
            // Skip boundaries too close to image edges
            if valley < 0.05 || valley > 0.95 {
                continue
            }
            
            // Calculate confidence based on how "valley-like" this position is
            let projectionIndex = Int(valley * CGFloat(projection.count))
            let confidence = calculateBoundaryConfidence(at: projectionIndex, projection: projection)
            
            // Only keep boundaries with reasonable confidence
            if confidence > 0.2 {
                boundaries.append(QuestionBoundary(
                    yPosition: valley,
                    confidence: confidence,
                    isUserAdjusted: false,
                    width: 2.0
                ))
            }
        }
        
        return boundaries.sorted { $0.yPosition < $1.yPosition }
    }
    
    private func calculateBoundaryConfidence(at index: Int, projection: [Int]) -> Float {
        guard index >= 0 && index < projection.count else { return 0.0 }
        
        let windowSize = 5 // Look at ±5 pixels around the boundary
        let startIndex = max(0, index - windowSize)
        let endIndex = min(projection.count - 1, index + windowSize)
        
        // Calculate local minimum strength
        let localValues = Array(projection[startIndex...endIndex])
        let localMin = localValues.min() ?? 0
        let localMax = localValues.max() ?? 1
        let localMean = localValues.reduce(0, +) / localValues.count
        
        // Confidence is higher when:
        // 1. The boundary is at a strong local minimum
        // 2. There's good contrast around the boundary
        let minStrength = Float(localMean - localMin) / Float(max(1, localMax))
        let contrast = Float(localMax - localMin) / Float(max(1, localMax))
        
        return min(1.0, minStrength * 0.7 + contrast * 0.3)
    }
    
    // MARK: - Question Region Creation
    
    private func createQuestionRegions(from boundaries: [QuestionBoundary], originalImage: UIImage) async -> [QuestionRegion] {
        var regions: [QuestionRegion] = []
        
        print("🏗️ Creating question regions from \(boundaries.count) boundaries...")
        
        // Create regions between boundaries
        let sortedBoundaries = boundaries.sorted { $0.yPosition < $1.yPosition }
        let regionCount = sortedBoundaries.count + 1
        
        print("📊 Will create \(regionCount) regions")
        
        for i in 0..<regionCount {
            let topY: CGFloat = (i == 0) ? 0.015 : max(0.015, sortedBoundaries[i - 1].yPosition - 0.01) // Moderate expansion upward
            let bottomY: CGFloat = (i == sortedBoundaries.count) ? 0.985 : min(0.985, sortedBoundaries[i].yPosition + 0.01) // Moderate expansion downward
            
            print("🔍 Region \(i): topY=\(String(format: "%.3f", topY)), bottomY=\(String(format: "%.3f", bottomY))")
            
            // Skip regions that are too small - more permissive minimum
            let regionHeight = bottomY - topY
            if regionHeight < 0.05 { // Reduced to 5% of image height for more automatic detection
                print("❌ Region \(i) too small: height=\(String(format: "%.3f", regionHeight))")
                continue
            }
            
            let regionBounds = CGRect(
                x: 0.01,           // Standard margin from left
                y: topY,
                width: 0.98,       // Standard margin from right  
                height: regionHeight
            )
            
            print("📦 Creating region \(i) with bounds: \(regionBounds)")
            
            // Create thumbnail for this region
            guard let thumbnail = await createThumbnail(from: originalImage, bounds: regionBounds) else {
                print("❌ Failed to create thumbnail for region \(i)")
                continue
            }
            
            print("✅ Created thumbnail for region \(i): \(thumbnail.size)")
            
            // Detect question number and assess text content
            let questionNumber = await detectQuestionNumber(in: thumbnail)
            let textConfidence = await assessTextContent(in: thumbnail)
            let estimatedLines = await estimateLineCount(in: thumbnail)
            
            print("📋 Region \(i) analysis: questionNumber=\(questionNumber?.description ?? "nil"), textConfidence=\(String(format: "%.2f", textConfidence)), lines=\(estimatedLines)")
            
            let region = QuestionRegion(
                id: "region_\(i)_\(UUID().uuidString.prefix(8))",
                bounds: regionBounds,
                thumbnail: thumbnail,
                questionNumber: questionNumber,
                textConfidence: textConfidence,
                estimatedLines: estimatedLines
            )
            
            regions.append(region)
        }
        
        print("✅ Created \(regions.count) question regions")
        return regions
    }
    
    private func createThumbnail(from image: UIImage, bounds: CGRect) async -> UIImage? {
        return await Task.detached(priority: .userInitiated) {
            guard let cgImage = image.cgImage else { return nil }
            
            // Convert normalized bounds to pixel coordinates
            let imageWidth = CGFloat(cgImage.width)
            let imageHeight = CGFloat(cgImage.height)
            
            let pixelBounds = CGRect(
                x: bounds.origin.x * imageWidth,
                y: bounds.origin.y * imageHeight,
                width: bounds.size.width * imageWidth,
                height: bounds.size.height * imageHeight
            )
            
            // Crop the image to the region bounds
            guard let croppedCGImage = cgImage.cropping(to: pixelBounds) else { return nil }
            
            return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
        }.value
    }
    
    private func detectQuestionNumber(in thumbnail: UIImage) async -> Int? {
        // Use Vision framework to detect text and look for numbers
        guard let cgImage = thumbnail.cgImage else { return nil }
        
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("⚠️ Question number detection error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                
                // Look for patterns like "1.", "2)", "Question 1", etc.
                for observation in observations.prefix(3) { // Only check first few text blocks
                    if let text = observation.topCandidates(1).first?.string {
                        if let number = self.extractQuestionNumber(from: text) {
                            continuation.resume(returning: number)
                            return
                        }
                    }
                }
                
                continuation.resume(returning: nil)
            }
            
            request.recognitionLevel = .fast // Quick recognition for question numbers
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    print("⚠️ Failed to perform question number detection: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func extractQuestionNumber(from text: String) -> Int? {
        let patterns = [
            #"^(\d+)\."#,           // "1.", "2.", etc.
            #"^(\d+)\)"#,           // "1)", "2)", etc.
            #"Question\s+(\d+)"#,   // "Question 1", "Question 2", etc.
            #"^(\d+)[\s:]"#,        // "1 ", "2:", etc.
            #"^\((\d+)\)"#          // "(1)", "(2)", etc.
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.count)),
               let range = Range(match.range(at: 1), in: text) {
                let numberString = String(text[range])
                if let number = Int(numberString), number > 0 && number < 100 {
                    return number
                }
            }
        }
        
        return nil
    }
    
    private func assessTextContent(in thumbnail: UIImage) async -> Float {
        // Quick assessment of how much text content this region likely contains
        guard let cgImage = thumbnail.cgImage else { return 0.0 }
        
        // Simple heuristic based on pixel density and variance
        let pixelData = await getPixelData(from: cgImage)
        guard let data = pixelData else { return 0.5 }
        
        let textDensity = calculateTextDensity(data: data, width: cgImage.width, height: cgImage.height)
        return min(1.0, max(0.0, textDensity))
    }
    
    private func estimateLineCount(in thumbnail: UIImage) async -> Int {
        // Estimate number of text lines using horizontal projection on the thumbnail
        guard let projection = await computeHorizontalProjection(thumbnail) else { return 1 }
        
        let meanValue = projection.reduce(0, +) / projection.count
        let threshold = Int(Float(meanValue) * 0.7) // Higher threshold for line detection
        
        var lineCount = 0
        var inLine = false
        
        for value in projection {
            if value > threshold {
                if !inLine {
                    lineCount += 1
                    inLine = true
                }
            } else {
                inLine = false
            }
        }
        
        return max(1, lineCount) // At least 1 line
    }
    
    // MARK: - Helper Methods
    
    private func getPixelData(from cgImage: CGImage) async -> [UInt8]? {
        return await Task.detached(priority: .utility) {
            guard let dataProvider = cgImage.dataProvider,
                  let data = dataProvider.data,
                  let pixelData = CFDataGetBytePtr(data) else {
                return nil
            }
            
            let dataLength = CFDataGetLength(data)
            return Array(UnsafeBufferPointer(start: pixelData, count: dataLength))
        }.value
    }
    
    private func calculateTextDensity(data: [UInt8], width: Int, height: Int) -> Float {
        let totalPixels = width * height
        guard totalPixels > 0 else { return 0.0 }
        
        let darkPixels = data.filter { $0 < 128 }.count // Count dark pixels
        return Float(darkPixels) / Float(totalPixels)
    }
    
    private func assessSegmentationQuality(boundaries: [QuestionBoundary], regions: [QuestionRegion]) -> Float {
        guard !regions.isEmpty else { return 0.0 }
        
        // Quality factors:
        // 1. Average confidence of boundaries
        let avgConfidence = boundaries.isEmpty ? 0.5 : boundaries.map { $0.confidence }.reduce(0, +) / Float(boundaries.count)
        
        // 2. Reasonable number of regions (2-15 is typical for homework)
        let regionCountScore: Float = {
            let count = regions.count
            if count >= 2 && count <= 15 {
                return 1.0
            } else if count == 1 {
                return 0.7 // Single region might be valid
            } else if count > 15 {
                return max(0.2, 1.0 - Float(count - 15) * 0.05) // Penalty for too many
            } else {
                return 0.3 // Too few regions
            }
        }()
        
        // 3. Average text confidence of regions
        let avgTextConfidence = regions.map { $0.textConfidence }.reduce(0, +) / Float(regions.count)
        
        // Combined quality score
        let qualityScore = avgConfidence * 0.4 + regionCountScore * 0.4 + avgTextConfidence * 0.2
        
        return min(1.0, max(0.0, qualityScore))
    }
}

// MARK: - Debug and Visualization

extension QuestionSegmenter {
    /// Create a debug visualization showing detected boundaries and regions
    func createDebugVisualization(_ image: UIImage, result: SegmentationResult) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Draw original image first
        image.draw(at: .zero)
        
        guard let context = UIGraphicsGetCurrentContext() else { 
            print("❌ Failed to get graphics context for debug visualization")
            return image 
        }
        
        let imageWidth = image.size.width
        let imageHeight = image.size.height
        
        print("🖼️ Drawing debug visualization: \(result.regions.count) regions, \(result.boundaries.count) boundaries")
        
        // Draw question regions with semi-transparent fill
        for (index, region) in result.regions.enumerated() {
            let rect = CGRect(
                x: region.bounds.origin.x * imageWidth,
                y: region.bounds.origin.y * imageHeight,
                width: region.bounds.size.width * imageWidth,
                height: region.bounds.size.height * imageHeight
            )
            
            print("📦 Drawing region \(index): \(rect)")
            
            // Draw region with semi-transparent fill
            context.setFillColor(UIColor.blue.withAlphaComponent(0.15).cgColor)
            context.fill(rect)
            
            // Draw region border
            context.setStrokeColor(UIColor.blue.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(2.0)
            context.stroke(rect)
            
            // Draw region label with background
            let label = region.questionNumber != nil ? "Q\(region.questionNumber!)" : "R\(index + 1)"
            let labelAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: 18),
            ]
            
            // Calculate label size
            let labelSize = label.size(withAttributes: labelAttributes)
            let labelRect = CGRect(
                x: rect.minX + 10, 
                y: rect.minY + 10, 
                width: labelSize.width + 8, 
                height: labelSize.height + 4
            )
            
            // Draw label background
            context.setFillColor(UIColor.blue.withAlphaComponent(0.9).cgColor)
            context.fill(labelRect)
            
            // Draw label text
            label.draw(in: labelRect.insetBy(dx: 4, dy: 2), withAttributes: labelAttributes)
        }
        
        // Draw boundaries as horizontal lines
        for (index, boundary) in result.boundaries.enumerated() {
            let y = boundary.yPosition * imageHeight
            let alpha = max(0.5, CGFloat(boundary.confidence)) // Minimum 50% alpha for visibility
            
            print("📍 Drawing boundary \(index): y=\(y), confidence=\(boundary.confidence)")
            
            context.setStrokeColor(UIColor.red.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(3.0)
            
            // Draw the line
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: imageWidth, y: y))
            context.strokePath()
            
            // Draw confidence label with background
            let confidenceLabel = String(format: "%.2f", boundary.confidence)
            let confidenceAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: 14),
            ]
            
            let labelSize = confidenceLabel.size(withAttributes: confidenceAttributes)
            let labelRect = CGRect(
                x: imageWidth - labelSize.width - 20, 
                y: y - labelSize.height/2 - 2, 
                width: labelSize.width + 8, 
                height: labelSize.height + 4
            )
            
            // Draw label background
            context.setFillColor(UIColor.red.withAlphaComponent(0.9).cgColor)
            context.fill(labelRect)
            
            // Draw label text
            confidenceLabel.draw(in: labelRect.insetBy(dx: 4, dy: 2), withAttributes: confidenceAttributes)
        }
        
        // If no boundaries detected, add debug message
        if result.boundaries.isEmpty {
            let debugMessage = "No boundaries detected"
            let debugAttributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.boldSystemFont(ofSize: 16),
            ]
            
            let messageSize = debugMessage.size(withAttributes: debugAttributes)
            let messageRect = CGRect(
                x: (imageWidth - messageSize.width) / 2,
                y: 50,
                width: messageSize.width + 16,
                height: messageSize.height + 8
            )
            
            context.setFillColor(UIColor.red.withAlphaComponent(0.9).cgColor)
            context.fill(messageRect)
            
            debugMessage.draw(in: messageRect.insetBy(dx: 8, dy: 4), withAttributes: debugAttributes)
        }
        
        let result = UIGraphicsGetImageFromCurrentImageContext()
        print("✅ Debug visualization created: \(result != nil)")
        return result
    }
}