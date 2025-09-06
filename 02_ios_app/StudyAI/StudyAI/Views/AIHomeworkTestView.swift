//
//  AIHomeworkTestView.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import SwiftUI
import UIKit

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
        .onChange(of: originalImage) { _, newImage in
            if let image = newImage {
                processImage(image)
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
        
        Task {
            let startTime = Date()
            
            // Convert image to base64
            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                await MainActor.run {
                    parsingError = "Failed to process image data"
                    processingStatus = "❌ Failed to process image"
                    showingErrorAlert = true
                    isProcessing = false
                }
                return
            }
            
            let base64Image = imageData.base64EncodedString()
            let prompt = createHomeworkParsingPrompt()
            
            // Generate a temporary URL for the image
            await MainActor.run {
                originalImageUrl = "temp://homework-image-\(UUID().uuidString)"
                processingStatus = "🤖 AI analyzing homework content..."
            }
            
            // Use enhanced NetworkService method with subject detection
            let result = await NetworkService.shared.processHomeworkImageWithSubjectDetection(
                base64Image: base64Image,
                prompt: prompt
            )
            
            let processingTime = Date().timeIntervalSince(startTime)
            
            await MainActor.run {
                if result.success, let response = result.response {
                    processSuccessfulResponse(response, processingTime: processingTime)
                } else {
                    processFailedResponse(result, processingTime: processingTime)
                }
                isProcessing = false
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
                jsonParsingUsed: enhanced.jsonParsingUsed
            )
            
            // Also create basic result for compatibility
            parsingResult = HomeworkParsingResult(
                questions: enhanced.questions,
                processingTime: processingTime,
                overallConfidence: enhanced.overallConfidence,
                parsingMethod: enhanced.parsingMethod,
                rawAIResponse: enhanced.rawAIResponse
            )
            
            processingStatus = enhanced.questions.count > 0 ?
                "✅ Enhanced AI parsing completed: \(enhanced.questions.count) questions found (\(enhanced.parsingQualityDescription))" :
                "⚠️ Enhanced AI parsing completed: No questions detected"
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
                rawAIResponse: actualResponse
            )
            
            processingStatus = questions.count > 0 ?
                "⚠️ Fallback parsing completed: \(questions.count) questions found" :
                "❌ Parsing failed: No questions detected"
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
            rawAIResponse: errorMessage
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
            jsonParsingUsed: false
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
    
    private func calculateOverallConfidence(_ questions: [ParsedQuestion]) -> Float {
        guard !questions.isEmpty else { return 0.0 }
        
        let totalConfidence = questions.reduce(0) { $0 + $1.confidence }
        return totalConfidence / Float(questions.count)
    }
    
    private func clearImages() {
        originalImage = nil
        parsingResult = nil
        processingStatus = "Ready to test AI homework parsing"
    }
}

#Preview {
    AIHomeworkTestView()
}