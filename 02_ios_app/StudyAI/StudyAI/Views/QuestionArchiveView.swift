//
//  QuestionArchiveView.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import SwiftUI

struct QuestionArchiveView: View {
    let questions: [ParsedQuestion]
    @Binding var selectedIndices: Set<Int>
    @Binding var questionNotes: [String]
    @Binding var questionTags: [[String]]
    let originalImageUrl: String
    let processingTime: Double
    let initialDetectedSubject: String?
    let initialSubjectConfidence: Float?
    let onArchive: (String, Float, [String], [[String]]) -> Void

    @State private var detectedSubject = "Other"
    @State private var subjectConfidence: Float = 0.5
    @State private var customSubject = ""
    @State private var useCustomSubject = false
    @State private var newTagText = ""
    @State private var expandedNotes: Set<Int> = []
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                // Subject Detection Section
                subjectDetectionSection
                
                // Selected Questions Section
                selectedQuestionsSection
                
                // Notes and Tags Section
                if !selectedIndices.isEmpty {
                    notesAndTagsSection
                }
            }
            .navigationTitle("Archive Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Archive") {
                        archiveSelectedQuestions()
                    }
                    .disabled(selectedIndices.isEmpty || (useCustomSubject && customSubject.isEmpty))
                }
            }
        }
        .onAppear {
            // Use AI-detected subject if available, otherwise auto-detect from questions
            if let initialSubject = initialDetectedSubject, !initialSubject.isEmpty {
                detectedSubject = initialSubject
                print("📚 Using AI-detected subject: \(initialSubject)")
            } else {
                // Fallback to auto-detect subject from questions (simple heuristic)
                autoDetectSubject()
            }

            // Use AI-provided confidence if available
            if let initialConfidence = initialSubjectConfidence {
                subjectConfidence = initialConfidence
                print("🎯 Using AI subject confidence: \(initialConfidence)")
            }
        }
    }
    
    // MARK: - Subject Detection Section
    
    private var subjectDetectionSection: some View {
        Section("Subject Classification") {
            HStack {
                Image(systemName: "brain.head.profile.fill")
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 4) {
                    if useCustomSubject {
                        TextField("Enter subject", text: $customSubject)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    } else {
                        Text(detectedSubject)
                            .font(.headline)
                            .foregroundColor(.black)
                        
                        HStack {
                            Text("AI Confidence: \(Int(subjectConfidence * 100))%")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            Image(systemName: confidenceIcon(subjectConfidence))
                                .font(.caption)
                                .foregroundColor(confidenceColor(subjectConfidence))
                        }
                    }
                }
                
                Spacer()
            }
            
            Button(useCustomSubject ? "Use AI Detection" : "Enter Custom Subject") {
                useCustomSubject.toggle()
                if !useCustomSubject {
                    customSubject = ""
                }
            }
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Selected Questions Section
    
    private var selectedQuestionsSection: some View {
        Section("Selected Questions (\(selectedIndices.count))") {
            if selectedIndices.isEmpty {
                Text("No questions selected")
                    .foregroundColor(.gray)
                    .italic()
            } else {
                ForEach(Array(selectedIndices).sorted(), id: \.self) { index in
                    if index < questions.count {
                        QuestionPreviewCard(
                            question: questions[index],
                            questionNumber: index + 1
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Notes and Tags Section
    
    private var notesAndTagsSection: some View {
        Section("Notes & Tags (Optional)") {
            ForEach(Array(selectedIndices).sorted(), id: \.self) { index in
                if index < questions.count {
                    VStack(alignment: .leading, spacing: 8) {
                        // Question identifier
                        HStack {
                            Text("Question \(index + 1)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.blue)
                            
                            Spacer()
                            
                            Button(action: {
                                toggleNotesExpansion(index)
                            }) {
                                Image(systemName: expandedNotes.contains(index) ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        if expandedNotes.contains(index) {
                            // Notes field
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                TextField("Add notes about mistakes or insights...", text: Binding(
                                    get: { 
                                        index < questionNotes.count ? questionNotes[index] : "" 
                                    },
                                    set: { newValue in
                                        if index < questionNotes.count {
                                            questionNotes[index] = newValue
                                        }
                                    }
                                ), axis: .vertical)
                                .lineLimit(2...4)
                            }
                            
                            // Tags field
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tags:")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                
                                // Display existing tags
                                if index < questionTags.count && !questionTags[index].isEmpty {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 4) {
                                        ForEach(questionTags[index], id: \.self) { tag in
                                            TagView(tag: tag) {
                                                removeTag(tag, from: index)
                                            }
                                        }
                                    }
                                }
                                
                                // Add new tag
                                HStack {
                                    TextField("Add tag", text: $newTagText)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                    
                                    Button("Add") {
                                        addTag(to: index)
                                    }
                                    .disabled(newTagText.isEmpty)
                                    .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func autoDetectSubject() {
        // Simple subject detection based on keywords in questions
        let allText = questions.map { $0.questionText + " " + $0.answerText }.joined(separator: " ").lowercased()
        
        let subjectKeywords: [(String, [String])] = [
            ("Mathematics", ["math", "equation", "solve", "calculate", "derivative", "integral", "algebra", "geometry", "trigonometry", "calculus", "fraction", "polynomial"]),
            ("Physics", ["force", "velocity", "acceleration", "momentum", "energy", "wave", "frequency", "electric", "magnetic", "quantum", "newton", "joule"]),
            ("Chemistry", ["atom", "molecule", "reaction", "compound", "element", "bond", "acid", "base", "ph", "molar", "periodic", "organic"]),
            ("Biology", ["cell", "dna", "gene", "organism", "evolution", "ecosystem", "protein", "enzyme", "bacteria", "virus", "photosynthesis"]),
            ("English", ["grammar", "literature", "essay", "poem", "shakespeare", "metaphor", "syntax", "paragraph", "thesis", "analyze"]),
            ("History", ["war", "treaty", "revolution", "empire", "democracy", "civilization", "ancient", "medieval", "renaissance", "century"])
        ]
        
        var bestMatch = ("Other", 0)
        for (subject, keywords) in subjectKeywords {
            let matchCount = keywords.reduce(0) { count, keyword in
                count + (allText.contains(keyword) ? 1 : 0)
            }
            if matchCount > bestMatch.1 {
                bestMatch = (subject, matchCount)
            }
        }
        
        detectedSubject = bestMatch.0
        subjectConfidence = bestMatch.1 > 0 ? min(Float(bestMatch.1) * 0.2 + 0.3, 1.0) : 0.3
    }
    
    private func toggleNotesExpansion(_ index: Int) {
        if expandedNotes.contains(index) {
            expandedNotes.remove(index)
        } else {
            expandedNotes.insert(index)
        }
    }
    
    private func addTag(to questionIndex: Int) {
        guard !newTagText.isEmpty, questionIndex < questionTags.count else { return }
        
        let trimmedTag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !questionTags[questionIndex].contains(trimmedTag) {
            questionTags[questionIndex].append(trimmedTag)
        }
        newTagText = ""
    }
    
    private func removeTag(_ tag: String, from questionIndex: Int) {
        guard questionIndex < questionTags.count else { return }
        questionTags[questionIndex].removeAll { $0 == tag }
    }
    
    private func archiveSelectedQuestions() {
        let finalSubject = useCustomSubject ? customSubject : detectedSubject
        
        // Create arrays of notes and tags for the selected questions in order
        var selectedNotes: [String] = []
        var selectedTags: [[String]] = []
        
        for index in Array(selectedIndices).sorted() {
            if index < questionNotes.count {
                selectedNotes.append(questionNotes[index])
            } else {
                selectedNotes.append("")
            }
            
            if index < questionTags.count {
                selectedTags.append(questionTags[index])
            } else {
                selectedTags.append([])
            }
        }
        
        onArchive(finalSubject, subjectConfidence, selectedNotes, selectedTags)
    }
    
    private func confidenceIcon(_ confidence: Float) -> String {
        if confidence > 0.8 {
            return "checkmark.seal.fill"
        } else if confidence > 0.6 {
            return "checkmark.seal"
        } else {
            return "questionmark.circle"
        }
    }
    
    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence > 0.8 {
            return .green
        } else if confidence > 0.6 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Supporting Views

struct QuestionPreviewCard: View {
    let question: ParsedQuestion
    let questionNumber: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Q\(questionNumber)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(8)
                
                if let confidence = question.confidence, confidence < 1.0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundColor(confidence > 0.8 ? .green : confidence > 0.6 ? .orange : .red)
                        Text("\(Int(confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                if question.hasVisualElements {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("Visual")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
            }
            
            Text(question.questionText.count > 100 ? 
                 String(question.questionText.prefix(97)) + "..." : 
                 question.questionText)
                .font(.subheadline)
                .foregroundColor(.black)
                .lineLimit(3)
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct TagView: View {
    let tag: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
                .foregroundColor(.blue)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    QuestionArchiveView(
        questions: [
            ParsedQuestion(
                questionNumber: 1,
                questionText: "What is the derivative of x²?",
                answerText: "The derivative of x² is 2x.",
                confidence: 0.95
            ),
            ParsedQuestion(
                questionNumber: 2,
                questionText: "Calculate the area of a circle with radius 5.",
                answerText: "Area = πr² = π × 5² = 25π",
                confidence: 0.92,
                hasVisualElements: true
            )
        ],
        selectedIndices: .constant(Set([0, 1])),
        questionNotes: .constant(["", ""]),
        questionTags: .constant([[], []]),
        originalImageUrl: "test-url",
        processingTime: 2.3,
        initialDetectedSubject: "Mathematics",
        initialSubjectConfidence: 0.95,
        onArchive: { _, _, _, _ in }
    )
}