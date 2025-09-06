//
//  EnhancedHomeworkParser.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import Foundation

class EnhancedHomeworkParser {
    static let shared = EnhancedHomeworkParser()
    
    private init() {}
    
    /// Parse AI response that includes subject detection and questions
    func parseEnhancedHomeworkResponse(_ response: String) -> EnhancedHomeworkParsingResult? {
        print("🔍 Parsing enhanced AI response...")
        print("📄 Response length: \(response.count) characters")
        
        // Try to detect if this is a JSON response from the improved AI engine
        if let jsonResult = tryParseImprovedAIResponse(response) {
            print("✅ Successfully parsed improved AI JSON response")
            return jsonResult
        }
        
        // Fallback to traditional parsing for compatibility
        return parseTraditionalResponse(response)
    }
    
    /// Try to parse JSON response from improved AI engine
    private func tryParseImprovedAIResponse(_ response: String) -> EnhancedHomeworkParsingResult? {
        // Look for JSON indicators in the response
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for legacy format with enhanced fields (more flexible detection)
        if response.contains("SUBJECT_CONFIDENCE:") || response.contains("TOTAL_QUESTIONS:") || response.contains("JSON_PARSING:") {
            return parseEnhancedLegacyFormat(response)
        }
        
        // If neither JSON nor enhanced legacy format, return nil for fallback
        return nil
    }
    
    /// Parse enhanced legacy format with additional metadata
    private func parseEnhancedLegacyFormat(_ response: String) -> EnhancedHomeworkParsingResult? {
        let (detectedSubject, subjectConfidence, remainingResponse) = extractEnhancedSubjectInfo(from: response)
        let questions = parseQuestionsFromResponse(remainingResponse)
        
        guard !questions.isEmpty else {
            print("❌ No questions found in enhanced legacy response")
            return nil
        }
        
        // Extract additional metadata
        let totalQuestionsFound = extractTotalQuestions(from: response)
        let jsonParsingUsed = response.contains("JSON_PARSING: true")
        let parsingMethod = extractParsingMethod(from: response) ?? "Enhanced AI Backend Parsing with Subject Detection"
        
        let overallConfidence = questions.isEmpty ? 0.0 : questions.map { $0.confidence }.reduce(0.0, +) / Float(questions.count)
        
        let result = EnhancedHomeworkParsingResult(
            questions: questions,
            detectedSubject: detectedSubject,
            subjectConfidence: subjectConfidence,
            processingTime: 0.0,
            overallConfidence: overallConfidence,
            parsingMethod: parsingMethod,
            rawAIResponse: response,
            totalQuestionsFound: totalQuestionsFound,
            jsonParsingUsed: jsonParsingUsed
        )
        
        print("✅ Enhanced parsing successful:")
        print("📚 Detected Subject: \(detectedSubject) (confidence: \(subjectConfidence))")
        print("📊 Questions found: \(questions.count)")
        print("🔧 Parsing Method: \(parsingMethod)")
        print("🎯 Overall confidence: \(overallConfidence)")
        
        return result
    }
    
    /// Parse traditional response format for backward compatibility
    private func parseTraditionalResponse(_ response: String) -> EnhancedHomeworkParsingResult? {
        // Extract subject information from the beginning of the response
        let (detectedSubject, subjectConfidence, remainingResponse) = extractSubjectInfo(from: response)
        
        // Parse questions from the remaining response using existing logic
        let questions = parseQuestionsFromResponse(remainingResponse)
        
        guard !questions.isEmpty else {
            print("❌ No questions found in traditional response")
            return nil
        }
        
        // Calculate overall confidence
        let overallConfidence = questions.isEmpty ? 0.0 : questions.map { $0.confidence }.reduce(0.0, +) / Float(questions.count)
        
        let result = EnhancedHomeworkParsingResult(
            questions: questions,
            detectedSubject: detectedSubject,
            subjectConfidence: subjectConfidence,
            processingTime: 0.0, // Will be set by caller
            overallConfidence: overallConfidence,
            parsingMethod: "Traditional AI Backend Parsing with Subject Detection",
            rawAIResponse: response,
            totalQuestionsFound: questions.count,
            jsonParsingUsed: false
        )
        
        print("✅ Traditional parsing successful:")
        print("📚 Detected Subject: \(detectedSubject) (confidence: \(subjectConfidence))")
        print("📊 Questions found: \(questions.count)")
        print("🎯 Overall confidence: \(overallConfidence)")
        
        return result
    }
    
    /// Extract subject and confidence from response header
    private func extractSubjectInfo(from response: String) -> (subject: String, confidence: Float, remainingResponse: String) {
        let lines = response.components(separatedBy: .newlines)
        var detectedSubject = "Other"
        var subjectConfidence: Float = 0.5
        var remainingLines: [String] = []
        var foundSubjectInfo = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("SUBJECT:") {
                detectedSubject = trimmedLine.replacingOccurrences(of: "SUBJECT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                foundSubjectInfo = true
            } else if trimmedLine.hasPrefix("SUBJECT_CONFIDENCE:") {
                let confidenceString = trimmedLine.replacingOccurrences(of: "SUBJECT_CONFIDENCE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                subjectConfidence = Float(confidenceString) ?? 0.5
            } else if foundSubjectInfo {
                // Once we've found subject info, add remaining lines
                remainingLines.append(line)
            }
        }
        
        // If no subject info found, use the entire response for question parsing
        if !foundSubjectInfo {
            remainingLines = lines
        }
        
        let remainingResponse = remainingLines.joined(separator: "\n")
        
        print("🎯 Extracted subject: \(detectedSubject) (confidence: \(subjectConfidence))")
        return (detectedSubject, subjectConfidence, remainingResponse)
    }
    
    /// Parse questions from response using existing delimiter logic
    private func parseQuestionsFromResponse(_ response: String) -> [ParsedQuestion] {
        let questionBlocks = response.components(separatedBy: "═══QUESTION_SEPARATOR═══")
        var questions: [ParsedQuestion] = []
        
        for (index, block) in questionBlocks.enumerated() {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedBlock.isEmpty else { continue }
            
            let question = parseQuestionBlock(trimmedBlock, defaultNumber: index + 1)
            questions.append(question)
        }
        
        print("📊 Parsed \(questions.count) questions from enhanced response")
        return questions
    }
    
    /// Parse individual question block
    private func parseQuestionBlock(_ block: String, defaultNumber: Int) -> ParsedQuestion {
        let lines = block.components(separatedBy: .newlines)
        var questionNumber: Int? = nil
        var questionText = ""
        var answerText = ""
        var confidence: Float = 0.8
        var hasVisualElements = false
        
        var currentSection = ""
        var isParsingAnswer = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("QUESTION_NUMBER:") {
                let numberString = trimmedLine.replacingOccurrences(of: "QUESTION_NUMBER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                questionNumber = parseQuestionNumber(numberString)
            } else if trimmedLine.hasPrefix("QUESTION:") {
                currentSection = "question"
                questionText = trimmedLine.replacingOccurrences(of: "QUESTION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("ANSWER:") {
                currentSection = "answer"
                isParsingAnswer = true
                answerText = trimmedLine.replacingOccurrences(of: "ANSWER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("CONFIDENCE:") {
                let confidenceString = trimmedLine.replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                confidence = Float(confidenceString) ?? 0.8
            } else if trimmedLine.hasPrefix("HAS_VISUALS:") {
                let visualString = trimmedLine.replacingOccurrences(of: "HAS_VISUALS:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                hasVisualElements = visualString == "true" || visualString == "yes"
            } else if !trimmedLine.isEmpty && currentSection == "question" && !isParsingAnswer {
                questionText += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "answer" && isParsingAnswer {
                answerText += " " + trimmedLine
            }
        }
        
        // Fallback: if no structured format found, treat entire block as question
        if questionText.isEmpty && answerText.isEmpty {
            questionText = block.trimmingCharacters(in: .whitespacesAndNewlines)
            answerText = "Unable to parse answer from response"
            confidence = 0.3
        }
        
        return ParsedQuestion(
            questionNumber: questionNumber ?? (defaultNumber > 0 ? defaultNumber : nil),
            questionText: questionText,
            answerText: answerText,
            confidence: confidence,
            hasVisualElements: hasVisualElements
        )
    }
    
    /// Parse question number from string (handles formats like "1", "1a", "Q1", etc.)
    private func parseQuestionNumber(_ numberString: String) -> Int? {
        let cleanedString = numberString.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return Int(cleanedString)
    }
    
    /// Extract enhanced subject info with additional metadata
    private func extractEnhancedSubjectInfo(from response: String) -> (subject: String, confidence: Float, remainingResponse: String) {
        let lines = response.components(separatedBy: .newlines)
        var detectedSubject = "Other"
        var subjectConfidence: Float = 0.5
        var remainingLines: [String] = []
        var foundSubjectInfo = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("SUBJECT:") {
                detectedSubject = trimmedLine.replacingOccurrences(of: "SUBJECT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                foundSubjectInfo = true
            } else if trimmedLine.hasPrefix("SUBJECT_CONFIDENCE:") {
                let confidenceString = trimmedLine.replacingOccurrences(of: "SUBJECT_CONFIDENCE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                subjectConfidence = Float(confidenceString) ?? 0.5
            } else if foundSubjectInfo && !trimmedLine.hasPrefix("TOTAL_QUESTIONS:") && !trimmedLine.hasPrefix("JSON_PARSING:") && !trimmedLine.hasPrefix("PARSING_METHOD:") {
                // Once we've found subject info, add remaining lines (skip metadata)
                remainingLines.append(line)
            }
        }
        
        // If no subject info found, use the entire response for question parsing
        if !foundSubjectInfo {
            remainingLines = lines
        }
        
        let remainingResponse = remainingLines.joined(separator: "\n")
        
        print("🎯 Enhanced subject extraction: \(detectedSubject) (confidence: \(subjectConfidence))")
        return (detectedSubject, subjectConfidence, remainingResponse)
    }
    
    /// Extract total questions metadata
    private func extractTotalQuestions(from response: String) -> Int? {
        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("TOTAL_QUESTIONS:") {
                let numberString = trimmedLine.replacingOccurrences(of: "TOTAL_QUESTIONS:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(numberString)
            }
        }
        return nil
    }
    
    /// Extract parsing method metadata
    private func extractParsingMethod(from response: String) -> String? {
        let lines = response.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("PARSING_METHOD:") {
                return trimmedLine.replacingOccurrences(of: "PARSING_METHOD:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    /// Fallback to original parsing if enhanced parsing fails
    func parseOriginalHomeworkResponse(_ response: String, processingTime: Double = 0.0) -> HomeworkParsingResult? {
        let questions = parseQuestionsFromResponse(response)
        
        guard !questions.isEmpty else {
            print("❌ No questions found in original response")
            return nil
        }
        
        let overallConfidence = questions.map { $0.confidence }.reduce(0.0, +) / Float(questions.count)
        
        return HomeworkParsingResult(
            questions: questions,
            processingTime: processingTime,
            overallConfidence: overallConfidence,
            parsingMethod: "AI Backend Parsing (Fallback)",
            rawAIResponse: response
        )
    }
}