/*
 * ============================================================================
 * TEMPORARY DEACTIVATION - OPTIMIZATION PHASE 2
 * ============================================================================
 * 
 * This file has been temporarily commented out during project optimization.
 * 
 * REASON FOR DEACTIVATION:
 * - Legacy testing view, replaced by DirectAIHomeworkView
 * - DirectAIHomeworkView is the production homework analysis view
 * - This is a test/debug version that's no longer needed
 * 
 * RECOVERY INSTRUCTIONS:
 * 1. Remove this comment block (lines 1-25)
 * 2. Remove the closing comment block at the end of the file
 * 3. Remove the /* at line 27 and */ at the end
 * 4. The original code will be fully restored
 * 
 * ORIGINAL FILE: AIHomeworkTestView.swift
 * DEACTIVATED: 2025-09-19
 * PHASE: 2 - Legacy View Commenting
 * 
 * If any issues arise, simply uncomment this entire file.
 * ============================================================================
 */

/*
//
//  AIHomeworkTestView.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import SwiftUI
import UIKit
import os.log

struct AIHomeworkTestView: View {
    @State private var originalImage: UIImage?
    @State private var originalImageUrl: String?
    @State private var parsingResult: HomeworkParsingResult?
    @State private var enhancedResult: EnhancedHomeworkParsingResult?
    @State private var showingCamera = false
    @State private var isProcessing = false
    @State private var processingStatus = "Ready to test AI homework parsing"
    @State private var showingResults = false
    @State private var parsingError: String?
    @State private var showingErrorAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Status section
                    statusSection
                    
                    // Image sections
                    if let original = originalImage {
                        imageSection(title: "Scanned Document", image: original)
                    }
                    
                    // Results section
                    if let result = parsingResult {
                        resultsSection(result)
                    }
                    
                    // Controls
                    controlsSection
                    
                    Spacer(minLength: 100)
                }
                .padding()
            }
        }
        .navigationTitle("AI Homework Parser")
        .sheet(isPresented: $showingCamera) {
            ImageSourceSelectionView(selectedImage: $originalImage, isPresented: $showingCamera)
                .onAppear {
                    // CRITICAL: Log complete state when AI homework function is entered
                    let logger = Logger(subsystem: "com.studyai", category: "AIHomeworkTestView")
                    logger.info("🚀 === AI HOMEWORK FUNCTION ENTERED ===")
                    logger.info("📊 Current ViewModel state: \(CameraViewModel.shared.captureState)")
                    logger.info("🖼️ ViewModel has captured image: \(CameraViewModel.shared.capturedImage != nil)")
                    logger.info("🔄 Processing state: \(CameraViewModel.shared.isProcessingImage)")
                    logger.info("❌ Last camera error: \(CameraViewModel.shared.lastCameraError ?? "None")")
                    logger.info("🎛️ Suppress next cleanup: \(CameraViewModel.shared.suppressNextCleanup)")
                    logger.info("📱 Original image in view: \(originalImage != nil)")
                    logger.info("🎬 Show camera state: \(showingCamera)")
                    logger.info("🔄 Is processing: \(isProcessing)")
                    logger.info("📝 Processing status: \(processingStatus)")
                    logger.info("📊 Has parsing result: \(parsingResult != nil)")
                    logger.info("🔍 Has enhanced result: \(enhancedResult != nil)")
                    logger.info("⚠️ Parsing error: \(parsingError ?? "None")")
                    logger.info("✅ === AI HOMEWORK STATE LOGGING COMPLETE ===")
                }
        }
        .sheet(isPresented: $showingResults) {
            if let enhanced = enhancedResult {
                HomeworkResultsView(
                    enhancedResult: enhanced,
                    originalImageUrl: originalImageUrl
                )
            } else if let result = parsingResult {
                HomeworkResultsView(
                    parsingResult: result,
                    originalImageUrl: originalImageUrl
                )
            }
        }
        .alert("Parsing Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                parsingError = nil
            }
        } message: {
            if let error = parsingError {
                Text(error)
            }
        }
        .onChange(of: originalImage) { oldValue, newImage in
            let logger = Logger(subsystem: "com.studyai", category: "AIHomeworkTestView")
            logger.info("🔄 === ORIGINAL IMAGE CHANGED ===")
            logger.info("🖼️ Had old image: \(oldValue != nil)")
            logger.info("🖼️ Has new image: \(newImage != nil)")
            if let image = newImage {
                logger.info("🖼️ New image size: \(image.size.width)x\(image.size.height)")
                logger.info("✅ Starting processing after 0.5s delay...")
                // Add delay to ensure view controller dismissal is complete
                Task {
                    // Wait for UI to settle before processing
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                    await MainActor.run {
                        logger.info("🚀 Calling processImage()...")
                        processImage(image)
                    }
                }
            } else {
                logger.info("❌ originalImage set to nil - no processing")
            }
        }
    }
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(isProcessing ? Color.orange : Color.green)
                    .frame(width: 12, height: 12)
                
                Text(processingStatus)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if isProcessing {
                ProgressView(value: 0.6)
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func imageSection(title: String, image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .padding(.horizontal)
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }
    
    private func resultsSection(_ result: HomeworkParsingResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI Parsing Results")
                    .font(.headline)
                    .padding(.horizontal)
                
                Spacer()
                
                // Show enhanced indicators
                if let enhanced = enhancedResult {
                    HStack(spacing: 4) {
                        if enhanced.isReliableParsing {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("Enhanced")
                                .font(.caption2)
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Fallback")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            VStack(spacing: 12) {
                // Enhanced subject detection display
                if let enhanced = enhancedResult {
                    HStack {
                        Text("Detected Subject:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(enhanced.detectedSubject)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            if enhanced.isHighConfidenceSubject {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                            
                            Text("(\(String(format: "%.0f%%", enhanced.subjectConfidence * 100)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                HStack {
                    Text("Processing Time:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fs", result.processingTime))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Method:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let enhanced = enhancedResult {
                            Text(enhanced.parsingQualityDescription)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(enhanced.isReliableParsing ? .green : .orange)
                        } else {
                            Text(result.parsingMethod)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.purple)
                        }
                    }
                }
                
                HStack {
                    Text("Overall Confidence:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", result.overallConfidence * 100))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(result.overallConfidence > 0.8 ? .green : result.overallConfidence > 0.6 ? .orange : .red)
                }
                
                HStack {
                    Text("Questions Found:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(result.questionCount)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        
                        // Show total vs parsed if different
                        if let enhanced = enhancedResult,
                           let totalFound = enhanced.totalQuestionsFound,
                           totalFound != result.questionCount {
                            Text("(of \(totalFound))")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Show Questions Summary
                if result.questionCount > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        if !result.numberedQuestions.isEmpty {
                            HStack {
                                Text("Numbered Questions:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(result.numberedQuestions.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        if !result.unnumberedQuestions.isEmpty {
                            HStack {
                                Text("Additional Items:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(result.unnumberedQuestions.count)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                // View Details Button
                Button(action: {
                    showingResults = true
                }) {
                    HStack {
                        Image(systemName: "eye.fill")
                        Text("View Detailed Results")
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(result.questionCount > 0 ? Color.blue : Color.gray)
                    .cornerRadius(12)
                }
                .disabled(result.questionCount == 0)
            }
        }
        .padding()
        .background(
            (enhancedResult?.isReliableParsing == true) ? 
                Color.green.opacity(0.05) : 
                Color.blue.opacity(0.05)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    (enhancedResult?.isReliableParsing == true) ? 
                        Color.green.opacity(0.3) : 
                        Color.blue.opacity(0.3), 
                    lineWidth: 1
                )
        )
    }
    
    private var controlsSection: some View {
        VStack(spacing: 12) {
            // Main capture button - uses new ImageSourceSelectionView
            Button("📸 Scan or Upload Homework") {
                showingCamera = true
            }
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green)
            .cornerRadius(12)
            
            if originalImage != nil {
                Button("Process Again") {
                    if let image = originalImage {
                        processImage(image)
                    }
                }
                .foregroundColor(.blue)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                Button("Clear Images") {
                    clearImages()
                }
                .foregroundColor(.red)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }
    
    private func processImage(_ image: UIImage) {
        isProcessing = true
        processingStatus = "Sending to improved AI backend for enhanced parsing..."
        parsingError = nil
        
        print("🚀 === HOMEWORK IMAGE PROCESSING DEBUG ===")
        print("📊 Original image size: \(image.size)")
        print("📱 Original image scale: \(image.scale)")
        
        Task {
            do {
                let startTime = Date()
                
                // Compress image to ensure it's under API limits
                print("🔄 Starting image compression for API...")
                guard let imageData = compressImageForAPI(image) else {
                    print("❌ Image compression failed completely")
                    await MainActor.run {
                        parsingError = "Failed to compress image to acceptable size"
                        processingStatus = "❌ Image too large to process"
                        showingErrorAlert = true
                        isProcessing = false
                    }
                    return
                }
            
            let imageSizeMB = Double(imageData.count) / (1024 * 1024)
            print("✅ Final compressed image size: \(String(format: "%.2f", imageSizeMB))MB")
            
            let base64Image = imageData.base64EncodedString()
            let base64SizeMB = Double(base64Image.count) / (1024 * 1024)
            print("📦 Base64 encoded size: \(String(format: "%.2f", base64SizeMB))MB")
            print("📄 Base64 length: \(base64Image.count) characters")
            
            let prompt = createHomeworkParsingPrompt()
            print("📝 Created homework parsing prompt")
            
            // Generate a temporary URL for the image
            await MainActor.run {
                originalImageUrl = "temp://homework-image-\(UUID().uuidString)"
                processingStatus = "🤖 AI analyzing homework content..."
            }
            
            print("📡 Sending to NetworkService.processHomeworkImageWithSubjectDetection...")
            print("🔗 Using backend: https://sai-backend-production.up.railway.app")
            
            // Use enhanced NetworkService method with subject detection
            let result = await NetworkService.shared.processHomeworkImageWithSubjectDetection(
                base64Image: base64Image,
                prompt: prompt
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            print("⏱️ Total processing time: \(String(format: "%.2f", processingTime))s")
            
            await MainActor.run {
                if result.success, let response = result.response {
                    print("🎉 === SUCCESS: AI PARSING COMPLETED ===")
                    print("📈 Response length: \(response.count) characters")
                    print("🔍 Response preview: \(String(response.prefix(200)))")
                    processSuccessfulResponse(response, processingTime: processingTime)
                } else {
                    print("❌ === FAILURE: AI PARSING FAILED ===")
                    if let errorMsg = result.response {
                        print("💬 Error message: \(errorMsg)")
                    } else {
                        print("💬 No error message provided")
                    }
                    processFailedResponse(result, processingTime: processingTime)
                }
                isProcessing = false
            }
            print("🏁 === END HOMEWORK IMAGE PROCESSING DEBUG ===")
            
            } catch {
                // Catch any unexpected errors during processing
                print("❌ === UNEXPECTED ERROR DURING PROCESSING ===")
                print("💥 Error: \(error.localizedDescription)")
                
                await MainActor.run {
                    parsingError = "Unexpected error during image processing: \(error.localizedDescription)"
                    processingStatus = "❌ Processing failed unexpectedly"
                    showingErrorAlert = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func processSuccessfulResponse(_ response: String, processingTime: TimeInterval) {
        processingStatus = "🔍 Parsing AI response with enhanced parser..."
        
        // Extract actual response from JSON wrapper if needed
        let actualResponse: String
        if let jsonData = response.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let extractedResponse = jsonObject["response"] as? String {
            actualResponse = extractedResponse
            print("📋 Extracted response from JSON wrapper")
        } else {
            actualResponse = response
            print("📋 Using response as plain text")
        }
        
        // Try enhanced parsing first
        if let enhanced = EnhancedHomeworkParser.shared.parseEnhancedHomeworkResponse(actualResponse) {
            // Update processing time
            enhancedResult = EnhancedHomeworkParsingResult(
                questions: enhanced.questions,
                detectedSubject: enhanced.detectedSubject,
                subjectConfidence: enhanced.subjectConfidence,
                processingTime: processingTime,
                overallConfidence: enhanced.overallConfidence,
                parsingMethod: enhanced.parsingMethod,
                rawAIResponse: enhanced.rawAIResponse,
                totalQuestionsFound: enhanced.totalQuestionsFound,
                jsonParsingUsed: enhanced.jsonParsingUsed,
                performanceSummary: nil
            )
            
            // Also create basic result for compatibility
            parsingResult = HomeworkParsingResult(
                questions: enhanced.questions,
                processingTime: processingTime,
                overallConfidence: enhanced.overallConfidence,
                parsingMethod: enhanced.parsingMethod,
                rawAIResponse: enhanced.rawAIResponse,
                performanceSummary: nil
            )
            
            processingStatus = enhanced.questions.count > 0 ?
                "✅ Enhanced AI parsing completed: \(enhanced.questions.count) questions found (\(enhanced.parsingQualityDescription))" :
                "⚠️ Enhanced AI parsing completed: No questions detected"
            
            // Clear ViewModel after successful processing to prepare for next capture
            CameraViewModel.shared.handleUploadSuccess()
        } else {
            // Fallback to legacy parsing
            processingStatus = "🔄 Using fallback parsing method..."
            let questions = parseAIResponse(actualResponse)
            let overallConfidence = calculateOverallConfidence(questions)
            
            parsingResult = HomeworkParsingResult(
                questions: questions,
                processingTime: processingTime,
                overallConfidence: overallConfidence,
                parsingMethod: "Legacy AI Backend Parsing (Fallback)",
                rawAIResponse: actualResponse,
                performanceSummary: nil
            )
            
            processingStatus = questions.count > 0 ?
                "⚠️ Fallback parsing completed: \(questions.count) questions found" :
                "❌ Parsing failed: No questions detected"
            
            // Clear ViewModel after successful processing to prepare for next capture
            CameraViewModel.shared.handleUploadSuccess()
        }
    }
    
    private func processFailedResponse(_ result: (success: Bool, response: String?), processingTime: TimeInterval) {
        let errorMessage = result.response ?? "Unknown error occurred"
        parsingError = "AI parsing failed: \(errorMessage)"
        processingStatus = "❌ AI parsing failed"
        showingErrorAlert = true
        
        // Create empty results for error case
        parsingResult = HomeworkParsingResult(
            questions: [],
            processingTime: processingTime,
            overallConfidence: 0.0,
            parsingMethod: "AI Backend Parsing (Failed)",
            rawAIResponse: errorMessage,
            performanceSummary: nil
        )
        
        enhancedResult = EnhancedHomeworkParsingResult(
            questions: [],
            detectedSubject: "Unknown",
            subjectConfidence: 0.0,
            processingTime: processingTime,
            overallConfidence: 0.0,
            parsingMethod: "Enhanced AI Backend Parsing (Failed)",
            rawAIResponse: errorMessage,
            totalQuestionsFound: 0,
            jsonParsingUsed: false,
            performanceSummary: nil
        )
    }
    
    private func createHomeworkParsingPrompt() -> String {
        return ""
    }
    
    private func parseAIResponse(_ response: String) -> [ParsedQuestion] {
        print("🔍 === DEBUGGING AI RESPONSE ===")
        print("📄 Full Response Length: \(response.count) characters")
        print("📄 First 500 characters: \(String(response.prefix(500)))")
        print("📄 Last 500 characters: \(String(response.suffix(500)))")
        
        // First, extract subject information if present
        var detectedSubject = "Other"
        var subjectConfidence: Float = 0.5
        
        let lines = response.components(separatedBy: .newlines)
        print("📊 Total lines in response: \(lines.count)")
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if index < 10 { // Print first 10 lines for debugging
                print("Line \(index): '\(trimmedLine)'")
            }
            
            if trimmedLine.hasPrefix("SUBJECT:") {
                detectedSubject = trimmedLine.replacingOccurrences(of: "SUBJECT:", with: "").trimmingCharacters(in: .whitespaces)
                print("✅ Found Subject: '\(detectedSubject)'")
            } else if trimmedLine.hasPrefix("SUBJECT_CONFIDENCE:") {
                let confidenceString = trimmedLine.replacingOccurrences(of: "SUBJECT_CONFIDENCE:", with: "").trimmingCharacters(in: .whitespaces)
                subjectConfidence = Float(confidenceString) ?? 0.5
                print("✅ Found Subject Confidence: \(subjectConfidence)")
            }
        }
        
        // Check for question separators
        let questionBlocks = response.components(separatedBy: "═══QUESTION_SEPARATOR═══")
        print("📊 Question blocks found: \(questionBlocks.count)")
        
        for (index, block) in questionBlocks.enumerated() {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            print("Block \(index) length: \(trimmedBlock.count)")
            if trimmedBlock.count > 0 {
                print("Block \(index) preview: \(String(trimmedBlock.prefix(200)))")
            }
        }
        
        var questions: [ParsedQuestion] = []
        
        for (index, block) in questionBlocks.enumerated() {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBlock.isEmpty { 
                print("⚠️ Block \(index) is empty, skipping")
                continue 
            }
            
            print("🔍 Parsing block \(index)...")
            if let question = parseQuestionBlock(trimmedBlock, fallbackIndex: index + 1) {
                print("✅ Successfully parsed question \(index): '\(question.questionText.prefix(50))...'")
                questions.append(question)
            } else {
                print("❌ Failed to parse block \(index)")
            }
        }
        
        // Store detected subject information (could be used later for automatic archiving)
        print("📚 Final Results:")
        print("📚 Detected Subject: \(detectedSubject) (confidence: \(subjectConfidence))")
        print("📚 Total Questions Parsed: \(questions.count)")
        print("🔍 === END DEBUG ===")
        
        return questions
    }
    
    private func parseQuestionBlock(_ block: String, fallbackIndex: Int) -> ParsedQuestion? {
        print("🔧 === PARSING QUESTION BLOCK \(fallbackIndex) ===")
        print("📄 Block content: '\(block)'")
        
        let lines = block.components(separatedBy: .newlines)
        print("📊 Lines in block: \(lines.count)")
        
        var questionNumber: Int?
        var questionText = ""
        var answerText = ""
        var confidence: Float = 0.8
        var hasVisuals = false
        
        for (lineIndex, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            print("Line \(lineIndex): '\(trimmedLine)'")
            
            // Handle Markdown format: **Question 1a:** or **Question 3:**
            if trimmedLine.hasPrefix("**Question") && trimmedLine.contains(":**") {
                // Extract question number if present (e.g., "1a", "3", "2d")
                let questionPattern = "\\*\\*Question ([^:]+):\\*\\* (.+)"
                if let regex = try? NSRegularExpression(pattern: questionPattern, options: []) {
                    let range = NSRange(location: 0, length: trimmedLine.count)
                    if let match = regex.firstMatch(in: trimmedLine, options: [], range: range) {
                        if let questionNumberRange = Range(match.range(at: 1), in: trimmedLine),
                           let questionTextRange = Range(match.range(at: 2), in: trimmedLine) {
                            let questionNumberStr = String(trimmedLine[questionNumberRange])
                            questionText = String(trimmedLine[questionTextRange])
                            
                            // Try to extract just the numeric part (e.g., "1" from "1a")
                            if let firstDigit = questionNumberStr.first(where: { $0.isNumber }) {
                                questionNumber = Int(String(firstDigit))
                            }
                            
                            print("✅ Found markdown question: '\(questionText)'")
                            print("✅ Found question number: \(questionNumber ?? -1) (from \(questionNumberStr))")
                        }
                    }
                }
            }
            // Handle Markdown format: **Answer 1a:** or **Answer 3:**
            else if trimmedLine.hasPrefix("**Answer") && trimmedLine.contains(":**") {
                let answerPattern = "\\*\\*Answer [^:]+:\\*\\* (.+)"
                if let regex = try? NSRegularExpression(pattern: answerPattern, options: []) {
                    let range = NSRange(location: 0, length: trimmedLine.count)
                    if let match = regex.firstMatch(in: trimmedLine, options: [], range: range) {
                        if let answerTextRange = Range(match.range(at: 1), in: trimmedLine) {
                            answerText = String(trimmedLine[answerTextRange])
                            print("✅ Found markdown answer: '\(answerText)'")
                        }
                    }
                }
            }
            // Handle legacy structured format (for backward compatibility)
            else if trimmedLine.hasPrefix("QUESTION_NUMBER:") {
                let numberString = trimmedLine.replacingOccurrences(of: "QUESTION_NUMBER:", with: "").trimmingCharacters(in: .whitespaces)
                questionNumber = Int(numberString)
                print("✅ Found legacy question number: \(questionNumber ?? -1)")
            } else if trimmedLine.hasPrefix("QUESTION:") {
                questionText = trimmedLine.replacingOccurrences(of: "QUESTION:", with: "").trimmingCharacters(in: .whitespaces)
                print("✅ Found legacy question text: '\(questionText)'")
            } else if trimmedLine.hasPrefix("ANSWER:") {
                answerText = trimmedLine.replacingOccurrences(of: "ANSWER:", with: "").trimmingCharacters(in: .whitespaces)
                print("✅ Found legacy answer text: '\(answerText)'")
            } else if trimmedLine.hasPrefix("CONFIDENCE:") {
                let confidenceString = trimmedLine.replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespaces)
                confidence = Float(confidenceString) ?? 0.8
                print("✅ Found confidence: \(confidence)")
            } else if trimmedLine.hasPrefix("HAS_VISUALS:") {
                let visualsString = trimmedLine.replacingOccurrences(of: "HAS_VISUALS:", with: "").trimmingCharacters(in: .whitespaces)
                hasVisuals = visualsString.lowercased() == "true"
                print("✅ Found visuals flag: \(hasVisuals)")
            } else if !trimmedLine.isEmpty {
                print("⚠️ Unhandled line: '\(trimmedLine)'")
            }
        }
        
        print("🔍 Final parsed values:")
        print("   Question Number: \(questionNumber ?? -1)")
        print("   Question Text: '\(questionText)'")
        print("   Answer Text: '\(answerText)'")
        print("   Confidence: \(confidence)")
        print("   Has Visuals: \(hasVisuals)")
        
        guard !questionText.isEmpty else {
            print("❌ Question text is empty, returning nil")
            return nil
        }
        
        let result = ParsedQuestion(
            questionNumber: questionNumber,
            questionText: questionText,
            answerText: answerText.isEmpty ? "Answer not provided." : answerText,
            confidence: confidence,
            hasVisualElements: hasVisuals
        )
        
        print("✅ Successfully created ParsedQuestion")
        print("🔧 === END PARSING BLOCK ===")
        
        return result
    }
    
    // MARK: - Image Compression Helper
    
    private func compressImageForAPI(_ image: UIImage) -> Data? {
        print("🔧 === IMAGE COMPRESSION DEBUG ===")
        print("📊 Original image size: \(image.size)")
        print("📱 Original image scale: \(image.scale)")
        
        let originalPixels = Int(image.size.width * image.size.height)
        print("🖼️ Original pixels: \(originalPixels) (\(originalPixels / 1_000_000)MP)")
        
        // First, resize if the image is too large - more aggressive resize
        let maxDimension: CGFloat = 800 // Even smaller than 1200px for better compression
        print("📐 Max dimension target: \(maxDimension)px")
        
        let resizedImage = resizeImage(image, maxDimension: maxDimension)
        print("✂️ Resized to: \(resizedImage.size)")
        
        let resizedPixels = Int(resizedImage.size.width * resizedImage.size.height)
        print("🖼️ Resized pixels: \(resizedPixels) (\(String(format: "%.1f", Double(resizedPixels) / 1_000_000))MP)")
        
        let compressionRatio = Double(resizedPixels) / Double(originalPixels)
        print("📉 Pixel reduction ratio: \(String(format: "%.2f", compressionRatio)) (\(String(format: "%.1f", (1-compressionRatio) * 100))% smaller)")
        
        // Try different compression levels until we get under 1MB (more aggressive limit)
        let maxSizeBytes = 1 * 1024 * 1024 // 1MB limit (even more aggressive)
        print("🎯 Target size limit: \(String(format: "%.1f", Double(maxSizeBytes) / (1024 * 1024)))MB")
        
        let compressionLevels: [CGFloat] = [0.6, 0.4, 0.3, 0.2, 0.15, 0.1]
        print("🔄 Trying compression levels: \(compressionLevels)")
        
        for (index, quality) in compressionLevels.enumerated() {
            print("🔍 Attempt \(index + 1)/\(compressionLevels.count): Testing quality \(quality)...")
            
            if let data = resizedImage.jpegData(compressionQuality: quality) {
                let dataSizeMB = Double(data.count) / (1024 * 1024)
                let dataSizeKB = Double(data.count) / 1024
                
                print("📊 Quality \(quality) result: \(String(format: "%.2f", dataSizeMB))MB (\(String(format: "%.0f", dataSizeKB))KB)")
                
                if data.count <= maxSizeBytes {
                    print("✅ SUCCESS: Image compressed to \(String(format: "%.2f", dataSizeMB))MB")
                    print("🎉 Selected compression quality: \(quality)")
                    
                    // Calculate base64 size estimation
                    let estimatedBase64Size = Double(data.count) * 1.33 // Base64 adds ~33% overhead
                    let estimatedBase64MB = estimatedBase64Size / (1024 * 1024)
                    print("📦 Estimated base64 size: \(String(format: "%.2f", estimatedBase64MB))MB")
                    
                    print("🔧 === IMAGE COMPRESSION SUCCESS ===")
                    return data
                } else {
                    let overage = Double(data.count - maxSizeBytes) / (1024 * 1024)
                    print("❌ Still too large by \(String(format: "%.2f", overage))MB, trying next level...")
                }
            } else {
                print("❌ Failed to create JPEG data at quality \(quality)")
            }
        }
        
        print("💥 === IMAGE COMPRESSION FAILED ===")
        print("❌ Could not compress image to acceptable size after \(compressionLevels.count) attempts")
        return nil
    }
    
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        print("🔧 Resize function - Input: \(size)")
        
        if size.width <= maxDimension && size.height <= maxDimension {
            print("✅ Image already within size limits, no resize needed")
            return image
        }
        
        let ratio = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        
        print("📐 Resize ratio: \(String(format: "%.3f", ratio))")
        print("📏 New size: \(newSize)")
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        print("✅ Resize completed successfully")
        return resizedImage
    }
    
    private func calculateOverallConfidence(_ questions: [ParsedQuestion]) -> Float {
        guard !questions.isEmpty else { return 0.0 }
        
        let totalConfidence = questions.reduce(0) { $0 + $1.confidence }
        return totalConfidence / Float(questions.count)
    }
    
    private func clearImages() {
        originalImage = nil
        parsingResult = nil
        processingStatus = "Ready to test AI homework parsing"
        
        // Also clear the CameraViewModel for clean state
        CameraViewModel.shared.clearForNextCapture()
    }
}

#Preview {
    AIHomeworkTestView()
}
*/

/* 
 * ============================================================================
 * END OF TEMPORARILY DEACTIVATED CODE - AIHomeworkTestView.swift
 * ============================================================================
 * 
 * To recover this file:
 * 1. Remove the opening comment block (lines 1-25)
 * 2. Remove this closing comment block
 * 3. Remove the /* at line 27 and */ before this block
 * 
 * The original AIHomeworkTestView.swift will be fully restored.
 * ============================================================================
 */