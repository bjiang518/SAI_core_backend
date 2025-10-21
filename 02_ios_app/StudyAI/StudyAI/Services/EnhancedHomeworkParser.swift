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

    /// Parse backend JSON response directly (NEW - High Performance)
    func parseBackendJSON(_ jsonData: [String: Any]) -> EnhancedHomeworkParsingResult? {
        print("🚀 === PARSING BACKEND JSON DIRECTLY ===")
        print("📊 JSON keys: \(jsonData.keys.joined(separator: ", "))")

        do {
            // Convert dictionary to Data
            let data = try JSONSerialization.data(withJSONObject: jsonData)

            // Decode using Codable
            let decoder = JSONDecoder()
            let backendResponse = try decoder.decode(BackendHomeworkResponse.self, from: data)

            // Convert to iOS models
            let questions = backendResponse.toParsedQuestions()
            let performanceSummary = backendResponse.toPerformanceSummary()

            let overallConfidence = questions.isEmpty ? 0.0 : questions.map { $0.confidence ?? 0.0 }.reduce(0.0, +) / Float(questions.count)

            let result = EnhancedHomeworkParsingResult(
                questions: questions,
                detectedSubject: backendResponse.subject,
                subjectConfidence: backendResponse.subjectConfidence,
                processingTime: 0.0, // Will be set by caller
                overallConfidence: overallConfidence,
                parsingMethod: "Direct JSON Parsing (Fast)",
                rawAIResponse: backendResponse.processingNotes ?? "Parsed from JSON",
                totalQuestionsFound: backendResponse.totalQuestionsFound,
                jsonParsingUsed: true,
                performanceSummary: performanceSummary
            )

            print("✅ === JSON PARSING SUCCESS ===")
            print("📚 Subject: \(backendResponse.subject) (confidence: \(backendResponse.subjectConfidence))")
            print("📊 Questions: \(questions.count)")
            print("📈 Accuracy: \(performanceSummary.accuracyPercentage)")
            print("⚡ Method: Direct JSON (no conversion overhead)")

            return result

        } catch {
            print("❌ JSON parsing error: \(error)")
            print("📋 Error details: \(error.localizedDescription)")
            return nil
        }
    }

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
        _ = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
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
        let performanceSummary = extractPerformanceSummary(from: response, questions: questions)
        
        let overallConfidence = questions.isEmpty ? 0.0 : questions.map { $0.confidence ?? 0.0 }.reduce(0.0, +) / Float(questions.count)
        
        let result = EnhancedHomeworkParsingResult(
            questions: questions,
            detectedSubject: detectedSubject,
            subjectConfidence: subjectConfidence,
            processingTime: 0.0,
            overallConfidence: overallConfidence,
            parsingMethod: parsingMethod,
            rawAIResponse: response,
            totalQuestionsFound: totalQuestionsFound,
            jsonParsingUsed: jsonParsingUsed,
            performanceSummary: performanceSummary
        )
        
        print("✅ Enhanced parsing successful:")
        print("📚 Detected Subject: \(detectedSubject) (confidence: \(subjectConfidence))")
        print("📊 Questions found: \(questions.count)")
        print("🔧 Parsing Method: \(parsingMethod)")
        print("🎯 Overall confidence: \(overallConfidence)")
        if let summary = performanceSummary {
            print("📈 Accuracy: \(summary.accuracyPercentage)")
        }
        
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
        let overallConfidence = questions.isEmpty ? 0.0 : questions.map { $0.confidence ?? 0.0 }.reduce(0.0, +) / Float(questions.count)
        
        let result = EnhancedHomeworkParsingResult(
            questions: questions,
            detectedSubject: detectedSubject,
            subjectConfidence: subjectConfidence,
            processingTime: 0.0, // Will be set by caller
            overallConfidence: overallConfidence,
            parsingMethod: "Traditional AI Backend Parsing with Subject Detection",
            rawAIResponse: response,
            totalQuestionsFound: questions.count,
            jsonParsingUsed: false,
            performanceSummary: extractPerformanceSummary(from: response, questions: questions)
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
        // Check if the response explicitly indicates no questions were found
        let lowercaseResponse = response.lowercased()
        if lowercaseResponse.contains("no questions detected") ||
           lowercaseResponse.contains("no questions found") ||
           lowercaseResponse.contains("unable to detect any questions") ||
           lowercaseResponse.contains("could not find any questions") {
            print("📊 AI explicitly reported no questions detected")
            return []
        }

        let questionBlocks = response.components(separatedBy: "═══QUESTION_SEPARATOR═══")
        var questions: [ParsedQuestion] = []

        for (index, block) in questionBlocks.enumerated() {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedBlock.isEmpty else { continue }

            // Skip blocks that are just "no questions" messages
            let lowercaseBlock = trimmedBlock.lowercased()
            if lowercaseBlock.contains("no questions detected") ||
               lowercaseBlock.contains("no questions found") ||
               lowercaseBlock.contains("unable to detect") {
                print("📊 Skipping 'no questions' message block")
                continue
            }

            // Check if this is a parent question with subquestions
            if trimmedBlock.contains("═══PARENT_QUESTION_START═══") {
                if let parentQuestion = parseParentQuestionBlock(trimmedBlock, defaultNumber: index + 1) {
                    questions.append(parentQuestion)
                }
            } else {
                let question = parseQuestionBlock(trimmedBlock, defaultNumber: index + 1)

                // Filter out invalid questions (empty text or confidence 0)
                if !question.questionText.isEmpty && (question.confidence ?? 0.0) > 0 {
                    questions.append(question)
                } else {
                    print("📊 Filtered out invalid question block")
                }
            }
        }

        print("📊 Parsed \(questions.count) valid questions from enhanced response")
        return questions
    }

    /// Parse parent question block with subquestions
    private func parseParentQuestionBlock(_ block: String, defaultNumber: Int) -> ParsedQuestion? {
        print("🔍 Parsing parent question block...")

        // Extract content between PARENT_QUESTION_START and PARENT_QUESTION_END
        guard let startRange = block.range(of: "═══PARENT_QUESTION_START═══"),
              let endRange = block.range(of: "═══PARENT_QUESTION_END═══") else {
            print("❌ Missing parent question delimiters")
            return nil
        }

        let parentContent = String(block[startRange.upperBound..<endRange.lowerBound])
        let lines = parentContent.components(separatedBy: .newlines)

        var questionNumber: Int? = nil
        var parentContentText = ""
        var subquestions: [ParsedQuestion] = []
        var totalEarned: Float = 0.0
        var totalPossible: Float = 0.0
        var overallFeedback: String? = nil

        // Parse parent question header
        var headerLines: [String] = []
        var isInSubquestion = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("QUESTION_NUMBER:") {
                let numberString = trimmedLine.replacingOccurrences(of: "QUESTION_NUMBER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                questionNumber = parseQuestionNumber(numberString)
            } else if trimmedLine.hasPrefix("PARENT_CONTENT:") {
                parentContentText = trimmedLine.replacingOccurrences(of: "PARENT_CONTENT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("SUBQUESTION_NUMBER:") {
                isInSubquestion = true
                headerLines.append(line)
            } else if trimmedLine.hasPrefix("TOTAL_POINTS:") {
                let pointsString = trimmedLine.replacingOccurrences(of: "TOTAL_POINTS:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let components = pointsString.components(separatedBy: "/")
                if components.count == 2 {
                    totalEarned = Float(components[0].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
                    totalPossible = Float(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
                }
            } else if trimmedLine.hasPrefix("OVERALL_FEEDBACK:") {
                overallFeedback = trimmedLine.replacingOccurrences(of: "OVERALL_FEEDBACK:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if isInSubquestion {
                headerLines.append(line)
            }
        }

        // Parse subquestions
        let subquestionBlocks = headerLines.joined(separator: "\n").components(separatedBy: "───SUBQUESTION_SEPARATOR───")
        for subBlock in subquestionBlocks {
            if let subquestion = parseSubquestionBlock(subBlock.trimmingCharacters(in: .whitespacesAndNewlines)) {
                subquestions.append(subquestion)
            }
        }

        // Create parent summary if available
        var parentSummary: ParentSummary? = nil
        if totalPossible > 0 {
            parentSummary = ParentSummary(
                totalEarned: totalEarned,
                totalPossible: totalPossible,
                overallFeedback: overallFeedback
            )
        }

        print("✅ Parsed parent question with \(subquestions.count) subquestions")

        return ParsedQuestion(
            questionNumber: questionNumber ?? defaultNumber,
            rawQuestionText: nil,
            questionText: parentContentText.isEmpty ? "Parent Question \(questionNumber ?? defaultNumber)" : parentContentText,
            answerText: "",
            confidence: 0.9,
            hasVisualElements: false,
            isParent: true,
            hasSubquestions: true,
            parentContent: parentContentText,
            subquestions: subquestions,
            parentSummary: parentSummary
        )
    }

    /// Parse individual subquestion
    private func parseSubquestionBlock(_ block: String) -> ParsedQuestion? {
        let lines = block.components(separatedBy: .newlines)
        var subquestionNumber = ""
        var rawQuestionText = ""
        var questionText = ""
        var studentAnswer = ""
        var correctAnswer = ""
        var grade = ""
        var pointsEarned: Float = 0.0
        var pointsPossible: Float = 1.0
        var feedback = ""
        var confidence: Float = 0.8
        var hasVisualElements = false

        var currentSection = ""

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("SUBQUESTION_NUMBER:") {
                subquestionNumber = trimmedLine.replacingOccurrences(of: "SUBQUESTION_NUMBER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("RAW_QUESTION:") {
                currentSection = "raw_question"
                rawQuestionText = trimmedLine.replacingOccurrences(of: "RAW_QUESTION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("QUESTION:") {
                currentSection = "question"
                questionText = trimmedLine.replacingOccurrences(of: "QUESTION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("STUDENT_ANSWER:") {
                currentSection = "student_answer"
                studentAnswer = trimmedLine.replacingOccurrences(of: "STUDENT_ANSWER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("CORRECT_ANSWER:") {
                currentSection = "correct_answer"
                correctAnswer = trimmedLine.replacingOccurrences(of: "CORRECT_ANSWER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("GRADE:") {
                grade = trimmedLine.replacingOccurrences(of: "GRADE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("POINTS:") {
                let pointsString = trimmedLine.replacingOccurrences(of: "POINTS:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let components = pointsString.components(separatedBy: "/")
                if components.count == 2 {
                    pointsEarned = Float(components[0].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
                    pointsPossible = Float(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
                }
            } else if trimmedLine.hasPrefix("FEEDBACK:") {
                currentSection = "feedback"
                feedback = trimmedLine.replacingOccurrences(of: "FEEDBACK:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("CONFIDENCE:") {
                let confidenceString = trimmedLine.replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                confidence = Float(confidenceString) ?? 0.8
            } else if trimmedLine.hasPrefix("HAS_VISUALS:") {
                let visualString = trimmedLine.replacingOccurrences(of: "HAS_VISUALS:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                hasVisualElements = visualString == "true" || visualString == "yes"
            } else if !trimmedLine.isEmpty && currentSection == "raw_question" {
                rawQuestionText += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "question" {
                questionText += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "student_answer" {
                studentAnswer += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "correct_answer" {
                correctAnswer += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "feedback" {
                feedback += " " + trimmedLine
            }
        }

        guard !questionText.isEmpty else { return nil }

        return ParsedQuestion(
            questionNumber: nil,  // Subquestions don't have numeric question numbers
            rawQuestionText: rawQuestionText.isEmpty ? nil : rawQuestionText,
            questionText: questionText,
            answerText: correctAnswer.isEmpty ? studentAnswer : correctAnswer,
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            studentAnswer: studentAnswer,
            correctAnswer: correctAnswer,
            grade: grade,
            pointsEarned: pointsEarned,
            pointsPossible: pointsPossible,
            feedback: feedback,
            subquestionNumber: subquestionNumber
        )
    }

    
    /// Parse individual question block
    private func parseQuestionBlock(_ block: String, defaultNumber: Int) -> ParsedQuestion {
        let lines = block.components(separatedBy: .newlines)
        var questionNumber: Int? = nil
        var rawQuestionText = ""
        var questionText = ""
        var answerText = ""
        var studentAnswer = ""
        var correctAnswer = ""
        var grade = ""
        var pointsEarned: Float = 0.0
        var pointsPossible: Float = 1.0
        var feedback = ""
        var confidence: Float = 0.8
        var hasVisualElements = false
        
        var currentSection = ""
        var isParsingAnswer = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("QUESTION_NUMBER:") {
                let numberString = trimmedLine.replacingOccurrences(of: "QUESTION_NUMBER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                questionNumber = parseQuestionNumber(numberString)
            } else if trimmedLine.hasPrefix("RAW_QUESTION:") {
                currentSection = "raw_question"
                rawQuestionText = trimmedLine.replacingOccurrences(of: "RAW_QUESTION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("QUESTION:") {
                currentSection = "question"
                questionText = trimmedLine.replacingOccurrences(of: "QUESTION:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("STUDENT_ANSWER:") {
                currentSection = "student_answer"
                studentAnswer = trimmedLine.replacingOccurrences(of: "STUDENT_ANSWER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("CORRECT_ANSWER:") {
                currentSection = "correct_answer"
                correctAnswer = trimmedLine.replacingOccurrences(of: "CORRECT_ANSWER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("GRADE:") {
                grade = trimmedLine.replacingOccurrences(of: "GRADE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("POINTS:") {
                // New compact format: "POINTS: X/Y"
                let pointsString = trimmedLine.replacingOccurrences(of: "POINTS:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                let components = pointsString.components(separatedBy: "/")
                if components.count == 2 {
                    pointsEarned = Float(components[0].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0.0
                    pointsPossible = Float(components[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1.0
                }
            } else if trimmedLine.hasPrefix("POINTS_EARNED:") {
                // Legacy format support
                let pointsString = trimmedLine.replacingOccurrences(of: "POINTS_EARNED:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                pointsEarned = Float(pointsString) ?? 0.0
            } else if trimmedLine.hasPrefix("POINTS_POSSIBLE:") {
                // Legacy format support
                let pointsString = trimmedLine.replacingOccurrences(of: "POINTS_POSSIBLE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                pointsPossible = Float(pointsString) ?? 1.0
            } else if trimmedLine.hasPrefix("FEEDBACK:") {
                currentSection = "feedback"
                feedback = trimmedLine.replacingOccurrences(of: "FEEDBACK:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("ANSWER:") {
                // Legacy support for old format
                currentSection = "answer"
                isParsingAnswer = true
                answerText = trimmedLine.replacingOccurrences(of: "ANSWER:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmedLine.hasPrefix("CONFIDENCE:") {
                let confidenceString = trimmedLine.replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                confidence = Float(confidenceString) ?? 0.8
            } else if trimmedLine.hasPrefix("HAS_VISUALS:") {
                let visualString = trimmedLine.replacingOccurrences(of: "HAS_VISUALS:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                hasVisualElements = visualString == "true" || visualString == "yes"
            } else if !trimmedLine.isEmpty && currentSection == "raw_question" {
                rawQuestionText += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "question" {
                questionText += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "student_answer" {
                studentAnswer += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "correct_answer" {
                correctAnswer += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "feedback" {
                feedback += " " + trimmedLine
            } else if !trimmedLine.isEmpty && currentSection == "answer" && isParsingAnswer {
                answerText += " " + trimmedLine
            }
        }
        
        // For grading mode, use correct_answer as the main answer
        // For legacy mode, use answerText
        let mainAnswer = !correctAnswer.isEmpty ? correctAnswer : answerText
        
        // If no grading info, assume this is legacy format
        if grade.isEmpty && !correctAnswer.isEmpty {
            answerText = correctAnswer
        }
        
        // Fallback: if no structured format found, check if this looks like a real question
        if questionText.isEmpty && mainAnswer.isEmpty {
            // Check if block contains "no questions" indicators
            let lowercaseBlock = block.lowercased()
            if lowercaseBlock.contains("no questions") ||
               lowercaseBlock.contains("unable to detect") ||
               lowercaseBlock.contains("could not find") ||
               lowercaseBlock.count < 10 { // Too short to be a real question
                // Don't create a dummy question - this will be filtered out
                questionText = ""
                answerText = ""
                confidence = 0.0
            } else {
                // Treat entire block as question only if it looks substantial
                questionText = block.trimmingCharacters(in: .whitespacesAndNewlines)
                answerText = "Unable to parse answer from response"
                confidence = 0.3
            }
        }
        
        // Create ParsedQuestion with new grading fields
        return ParsedQuestion(
            questionNumber: questionNumber ?? (defaultNumber > 0 ? defaultNumber : nil),
            rawQuestionText: rawQuestionText.isEmpty ? nil : rawQuestionText,
            questionText: questionText,
            answerText: mainAnswer.isEmpty ? answerText : mainAnswer,
            confidence: confidence,
            hasVisualElements: hasVisualElements,
            studentAnswer: studentAnswer,
            correctAnswer: correctAnswer,
            grade: grade,
            pointsEarned: pointsEarned,
            pointsPossible: pointsPossible,
            feedback: feedback
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
        
        let overallConfidence = questions.map { $0.confidence ?? 0.0 }.reduce(0.0, +) / Float(questions.count)
        
        return HomeworkParsingResult(
            questions: questions,
            processingTime: processingTime,
            overallConfidence: overallConfidence,
            parsingMethod: "AI Backend Parsing (Fallback)",
            rawAIResponse: response,
            performanceSummary: nil
        )
    }
    
    /// Extract performance summary from response
    private func extractPerformanceSummary(from response: String, questions: [ParsedQuestion]) -> PerformanceSummary? {
        let lines = response.components(separatedBy: .newlines)
        var totalCorrect = 0
        var totalIncorrect = 0
        var totalEmpty = 0
        var totalPartialCredit = 0  // Declare at method level
        var accuracyRate: Float = 0.0
        var summaryText = ""

        // Try to extract from response first
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("TOTAL_CORRECT:") {
                let numberString = trimmedLine.replacingOccurrences(of: "TOTAL_CORRECT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                totalCorrect = Int(numberString) ?? 0
            } else if trimmedLine.hasPrefix("TOTAL_INCORRECT:") {
                let numberString = trimmedLine.replacingOccurrences(of: "TOTAL_INCORRECT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                totalIncorrect = Int(numberString) ?? 0
            } else if trimmedLine.hasPrefix("TOTAL_EMPTY:") {
                let numberString = trimmedLine.replacingOccurrences(of: "TOTAL_EMPTY:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                totalEmpty = Int(numberString) ?? 0
            } else if trimmedLine.hasPrefix("ACCURACY_RATE:") {
                let rateString = trimmedLine.replacingOccurrences(of: "ACCURACY_RATE:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                accuracyRate = Float(rateString) ?? 0.0
            } else if trimmedLine.hasPrefix("SUMMARY_TEXT:") {
                summaryText = trimmedLine.replacingOccurrences(of: "SUMMARY_TEXT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // If no performance summary found in response, calculate from questions
        if totalCorrect == 0 && totalIncorrect == 0 && totalEmpty == 0 {
            for question in questions {
                switch question.grade {
                case "CORRECT":
                    totalCorrect += 1
                case "INCORRECT":
                    totalIncorrect += 1
                case "EMPTY":
                    totalEmpty += 1
                case "PARTIAL_CREDIT":
                    totalPartialCredit += 1
                default:
                    break
                }
            }

            let totalQuestions = totalCorrect + totalIncorrect + totalEmpty + totalPartialCredit
            if totalQuestions > 0 {
                accuracyRate = Float(totalCorrect) / Float(totalQuestions)
            }

            // Generate basic summary if not provided
            if summaryText.isEmpty {
                summaryText = "Graded \(totalQuestions) questions with \(totalCorrect) correct answers."
            }
        }

        // Only return summary if we have meaningful data
        if totalCorrect > 0 || totalIncorrect > 0 || totalEmpty > 0 {
            return PerformanceSummary(
                totalCorrect: totalCorrect,
                totalIncorrect: totalIncorrect,
                totalEmpty: totalEmpty,
                totalPartialCredit: totalPartialCredit,
                accuracyRate: accuracyRate,
                summaryText: summaryText
            )
        }

        return nil
    }
}