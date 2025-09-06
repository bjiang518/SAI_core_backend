//
//  SessionDetailView.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import SwiftUI

struct SessionDetailView: View {
    let sessionId: String
    @StateObject private var supabaseService = SupabaseService.shared
    @State private var session: ArchivedSession?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text("Loading session...")
                            .foregroundColor(.gray)
                            .padding(.top)
                    }
                } else if let errorMessage = errorMessage.isEmpty ? nil : errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text("Error loading session")
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let session = session {
                    SessionDetailContent(session: session)
                } else {
                    Text("Session not found")
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Session Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadSessionDetails()
            }
        }
    }
    
    private func loadSessionDetails() async {
        isLoading = true
        errorMessage = ""
        
        do {
            let loadedSession = try await supabaseService.getSessionDetails(sessionId: sessionId)
            await MainActor.run {
                session = loadedSession
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct SessionDetailContent: View {
    let session: ArchivedSession
    
    private func colorForSubject(_ colorName: String) -> Color {
        switch colorName.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "brown": return .brown
        case "teal": return .teal
        case "indigo": return .indigo
        case "pink": return .pink
        case "yellow": return .yellow
        case "gray": return .gray
        default: return .gray
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if let category = SubjectCategory(rawValue: session.subject) {
                            Image(systemName: category.icon)
                                .foregroundColor(colorForSubject(category.color))
                                .font(.title2)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.subject)
                                .font(.headline)
                            Text(session.sessionDate, style: .date)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(session.aiParsingResult.questionCount) Questions")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("\(Int(session.overallConfidence * 100))% Confidence")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    if let title = session.title {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                
                // Questions Section
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Questions & Answers")
                            .font(.headline)
                        Spacer()
                        Text("\(session.aiParsingResult.questions.count) items")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    ForEach(Array(session.aiParsingResult.questions.enumerated()), id: \.offset) { index, question in
                        DetailQuestionCard(question: question, index: index + 1)
                    }
                }
                
                // Notes Section (if any)
                if let notes = session.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Notes")
                            .font(.headline)
                        Text(notes)
                            .padding()
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(8)
                    }
                }
                
                // Metadata Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session Info")
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        InfoRow(label: "Processing Time", value: "\(String(format: "%.1f", session.processingTime))s")
                        InfoRow(label: "Parsing Method", value: session.aiParsingResult.parsingMethod)
                        InfoRow(label: "Review Count", value: "\(session.reviewCount)")
                        InfoRow(label: "Created", value: session.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

struct DetailQuestionCard: View {
    let question: ParsedQuestion
    let index: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question Header
            HStack {
                Text("Q\(index)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(4)
                
                if question.hasVisualElements {
                    Image(systemName: "photo")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                Text("\(Int(question.confidence * 100))%")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            // Question Text
            Text(question.questionText)
                .font(.body)
                .fontWeight(.medium)
            
            // Answer Text
            Text(question.answerText)
                .font(.body)
                .foregroundColor(.gray)
                .padding()
                .background(Color.green.opacity(0.05))
                .cornerRadius(8)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .gray.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }
}

#Preview {
    SessionDetailView(sessionId: "sample-id")
}