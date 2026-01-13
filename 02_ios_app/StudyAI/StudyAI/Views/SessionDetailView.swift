//
//  SessionDetailView.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import SwiftUI

struct SessionDetailView: View {
    let sessionId: String
    let isConversation: Bool // Add parameter to distinguish between conversations and sessions
    @StateObject private var railwayService = RailwayArchiveService.shared
    @State private var session: ArchivedSession?
    @State private var conversation: ArchivedConversation?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    init(sessionId: String, isConversation: Bool = false) {
        self.sessionId = sessionId
        self.isConversation = isConversation
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack {
                        ProgressView()
                        Text(NSLocalizedString("sessionDetail.loading", comment: ""))
                            .foregroundColor(.gray)
                            .padding(.top)
                    }
                } else if let errorMessage = errorMessage.isEmpty ? nil : errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(NSLocalizedString("sessionDetail.errorLoading", comment: ""))
                            .font(.headline)
                        Text(errorMessage)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else if let session = session {
                    SessionDetailContent(session: session)
                } else if let conversation = conversation {
                    ConversationDetailContent(conversation: conversation)
                } else {
                    Text(NSLocalizedString("sessionDetail.contentNotFound", comment: ""))
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle(isConversation ? NSLocalizedString("sessionDetail.conversationDetails", comment: "") : NSLocalizedString("sessionDetail.sessionDetails", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadDetails()
            }
        }
    }
    
    private func loadDetails() async {
        isLoading = true
        errorMessage = ""

        do {
            if isConversation {
                // ✅ Try loading from LOCAL storage first (for archived conversations)
                let localConversations = ConversationLocalStorage.shared.getLocalConversations()
                if let localConversation = localConversations.first(where: { ($0["id"] as? String) == sessionId }) {
                    let archivedConversation = ArchivedConversation(
                        id: localConversation["id"] as? String ?? sessionId,
                        userId: "", // Local conversations don't have userId
                        subject: localConversation["subject"] as? String ?? "General",
                        topic: localConversation["topic"] as? String,
                        conversationContent: localConversation["conversationContent"] as? String ?? "",
                        archivedDate: ISO8601DateFormatter().date(from: localConversation["archivedDate"] as? String ?? "") ?? Date(),
                        createdAt: ISO8601DateFormatter().date(from: localConversation["createdAt"] as? String ?? "") ?? Date(),
                        diagrams: localConversation["diagrams"] as? [[String: Any]]  // ✅ NEW: Load diagrams from archive
                    )

                    await MainActor.run {
                        conversation = archivedConversation
                        isLoading = false
                    }
                    return
                }

                // If not found locally, try loading from server
                let loadedConversation = try await railwayService.getConversationDetails(conversationId: sessionId)
                await MainActor.run {
                    conversation = loadedConversation
                    isLoading = false
                }
            } else {
                let loadedSession = try await railwayService.getSessionDetails(sessionId: sessionId)
                await MainActor.run {
                    session = loadedSession
                    isLoading = false
                }
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
                            Text("\(session.aiParsingResult.questionCount) \(NSLocalizedString("sessionDetail.questions", comment: ""))")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("\(Int(session.overallConfidence * 100))% \(NSLocalizedString("sessionDetail.confidence", comment: ""))")
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
                        Text(NSLocalizedString("sessionDetail.questionsAndAnswers", comment: ""))
                            .font(.headline)
                        Spacer()
                        Text("\(session.aiParsingResult.questions.count) \(NSLocalizedString("sessionDetail.items", comment: ""))")
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
                        Text(NSLocalizedString("sessionDetail.notes", comment: ""))
                            .font(.headline)
                        Text(notes)
                            .padding()
                            .background(Color.blue.opacity(0.05))
                            .cornerRadius(8)
                    }
                }

                // Metadata Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("sessionDetail.sessionInfo", comment: ""))
                        .font(.headline)

                    VStack(spacing: 8) {
                        InfoRow(label: NSLocalizedString("sessionDetail.processingTime", comment: ""), value: "\(String(format: "%.1f", session.processingTime))s")
                        InfoRow(label: NSLocalizedString("sessionDetail.parsingMethod", comment: ""), value: session.aiParsingResult.parsingMethod)
                        InfoRow(label: NSLocalizedString("sessionDetail.reviewCount", comment: ""), value: "\(session.reviewCount)")
                        InfoRow(label: NSLocalizedString("sessionDetail.created", comment: ""), value: session.createdAt.formatted(date: .abbreviated, time: .shortened))
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
                
                Text("\(Int((question.confidence ?? 0.0) * 100))%")
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

struct ConversationDetailContent: View {
    let conversation: ArchivedConversation
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Conversation Content with inline diagrams
                VStack(alignment: .leading, spacing: 16) {
                    Text(NSLocalizedString("sessionDetail.conversation", comment: ""))
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 12) {
                        // Show all conversation messages
                        ForEach(parseConversation(conversation.conversationContent), id: \.offset) { messageItem in
                            ConversationMessageView(
                                speaker: messageItem.element.speaker,
                                message: messageItem.element.message,
                                isUser: messageItem.element.speaker.lowercased().contains("user")
                            )
                        }

                        // Show diagrams inline at the end as AI messages (if diagrams exist in archive)
                        if let diagrams = conversation.diagrams, !diagrams.isEmpty {
                            ForEach(Array(diagrams.enumerated()), id: \.offset) { index, diagramDict in
                                // Wrap diagram in AI message style
                                HStack {
                                    VStack(alignment: .leading, spacing: 12) {
                                        // AI character indicator
                                        HStack {
                                            Image(systemName: "chart.bar.doc.horizontal.fill")
                                                .font(.system(size: 14))
                                                .foregroundColor(.blue)

                                            Text(NSLocalizedString("diagram.header", comment: ""))
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }

                                        if let type = diagramDict["type"] as? String,
                                           let code = diagramDict["code"] as? String {
                                            // Create rendering hint if available
                                            let hint: NetworkService.DiagramRenderingHint? = {
                                                if let width = diagramDict["width"] as? Int,
                                                   let height = diagramDict["height"] as? Int {
                                                    return NetworkService.DiagramRenderingHint(
                                                        width: width,
                                                        height: height,
                                                        background: diagramDict["background"] as? String ?? "white",
                                                        scaleFactor: 1.0
                                                    )
                                                }
                                                return nil
                                            }()

                                            // Display the diagram
                                            DiagramRendererView(
                                                diagramType: type,
                                                diagramCode: code,
                                                diagramTitle: diagramDict["title"] as? String,
                                                renderingHint: hint
                                            )
                                            .frame(maxHeight: 400)
                                        }

                                        // Explanation text (if provided)
                                        if let explanation = diagramDict["explanation"] as? String, !explanation.isEmpty {
                                            VStack(alignment: .leading, spacing: 8) {
                                                Divider()

                                                HStack {
                                                    Image(systemName: "text.bubble")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.secondary)

                                                    Text(NSLocalizedString("diagram.explanation", comment: ""))
                                                        .font(.system(size: 12, weight: .medium))
                                                        .foregroundColor(.secondary)
                                                }

                                                Text(explanation)
                                                    .font(.body)
                                                    .foregroundColor(.primary.opacity(0.9))
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )

                                    Spacer(minLength: 50)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Metadata Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(NSLocalizedString("sessionDetail.conversationInfo", comment: ""))
                        .font(.headline)

                    VStack(spacing: 8) {
                        if let topic = conversation.topic {
                            InfoRow(label: NSLocalizedString("sessionDetail.topic", comment: ""), value: topic)
                        }
                        InfoRow(label: NSLocalizedString("sessionDetail.created", comment: ""), value: conversation.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }
    
    private func parseConversation(_ content: String) -> [(offset: Int, element: (speaker: String, message: String))] {
        let lines = content.components(separatedBy: .newlines)
        var messages: [(speaker: String, message: String)] = []
        var currentMessage = ""
        var currentSpeaker = ""

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for timestamped format like "[9/25/2025, 7:20:22 PM] User:" or "[9/25/2025, 7:20:22 PM] AI Assistant:"
            if trimmedLine.contains("] User:") || trimmedLine.contains("] AI Assistant:") || trimmedLine.contains("] Assistant:") {
                // Save previous message if exists
                if !currentSpeaker.isEmpty && !currentMessage.isEmpty {
                    messages.append((speaker: currentSpeaker, message: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)))
                }

                // Extract speaker from timestamped format
                if let closingBracketIndex = trimmedLine.firstIndex(of: "]") {
                    let afterBracket = String(trimmedLine[trimmedLine.index(after: closingBracketIndex)...])
                    let components = afterBracket.components(separatedBy: ":")
                    if components.count >= 2 {
                        currentSpeaker = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        currentMessage = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            // Check for speaker prefix (case-insensitive, supports various formats)
            // Formats: "User:", "USER:", "AI:", "A:", "Assistant:", "ASSISTANT:"
            else if trimmedLine.contains(":") && isSpeakerLine(trimmedLine) {
                // Save previous message if exists
                if !currentSpeaker.isEmpty && !currentMessage.isEmpty {
                    messages.append((speaker: currentSpeaker, message: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)))
                }

                // Start new message
                let components = trimmedLine.components(separatedBy: ":")
                if components.count >= 2 {
                    let rawSpeaker = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    // Normalize speaker name for display
                    currentSpeaker = normalizeSpeakerName(rawSpeaker)
                    currentMessage = components.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if !trimmedLine.isEmpty && !currentSpeaker.isEmpty {
                // Continue current message (skip metadata lines if no current speaker)
                if !currentMessage.isEmpty {
                    currentMessage += "\n"
                }
                currentMessage += trimmedLine
            }
        }

        // Save final message
        if !currentSpeaker.isEmpty && !currentMessage.isEmpty {
            messages.append((speaker: currentSpeaker, message: currentMessage.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return Array(messages.enumerated())
    }

    // Helper: Check if line starts with a speaker prefix (case-insensitive)
    private func isSpeakerLine(_ line: String) -> Bool {
        let uppercasedLine = line.uppercased()
        let speakerPrefixes = ["USER:", "AI:", "A:", "ASSISTANT:"]

        for prefix in speakerPrefixes {
            if uppercasedLine.hasPrefix(prefix) {
                return true
            }
        }

        return false
    }

    // Helper: Normalize speaker name for consistent display
    private func normalizeSpeakerName(_ rawSpeaker: String) -> String {
        let uppercased = rawSpeaker.uppercased()

        switch uppercased {
        case "USER":
            return "User"
        case "AI", "A", "ASSISTANT":
            return "AI Assistant"
        default:
            // Return original with proper capitalization
            return rawSpeaker.capitalized
        }
    }
}

struct ConversationMessageView: View {
    let speaker: String
    let message: String
    let isUser: Bool

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 50)
                messageContent
            } else {
                messageContent
                Spacer(minLength: 50)
            }
        }
    }

    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            // Use MathFormattedText for proper math rendering (same as raw chat session)
            MathFormattedText(message, fontSize: 16)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
        .padding(12)
        .background(isUser ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isUser ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    SessionDetailView(sessionId: "sample-id", isConversation: false)
}