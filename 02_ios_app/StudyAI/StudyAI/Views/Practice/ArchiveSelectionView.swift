//
//  ArchiveSelectionView.swift
//  StudyAI
//
//  Archive selection sheet used by NewPracticeSheet when generating from archives.
//

import SwiftUI

struct ArchiveSelectionView: View {
    let conversations: [[String: Any]]
    let questions: [QuestionSummary]
    @Binding var selectedConversations: Set<String>
    @Binding var selectedQuestions: Set<String>
    @Environment(\.dismiss) private var dismiss

    enum ArchiveFilter: String, CaseIterable {
        case all = "All"
        case conversations = "Conversations"
        case questions = "Questions"

        var localizedName: String {
            switch self {
            case .all: return NSLocalizedString("questionGeneration.filter.all", value: "All", comment: "")
            case .conversations: return NSLocalizedString("questionGeneration.filter.conversations", value: "Conversations", comment: "")
            case .questions: return NSLocalizedString("questionGeneration.filter.questions", value: "Questions", comment: "")
            }
        }
    }

    @State private var selectedFilter: ArchiveFilter = .all
    @State private var selectedSubject: String = "All"
    @State private var selectedTimeFilter: TimeFilter = .allTime
    @State private var showingLimitAlert = false
    @State private var showingSubjectMismatchAlert = false

    private let maxSources = 5

    private var totalSelected: Int {
        selectedConversations.count + selectedQuestions.count
    }

    private var lockedSubject: String? {
        for id in selectedConversations {
            if let conv = conversations.first(where: { $0["id"] as? String == id }),
               let s = conv["subject"] as? String, !s.isEmpty { return s }
        }
        for id in selectedQuestions {
            if let q = questions.first(where: { $0.id == id }), !q.subject.isEmpty { return q.subject }
        }
        return nil
    }

    private func subjectOf(conversationId: String) -> String? {
        conversations.first(where: { $0["id"] as? String == conversationId })?["subject"] as? String
    }

    enum TimeFilter: String, CaseIterable {
        case thisWeek  = "thisWeek"
        case thisMonth = "thisMonth"
        case thisYear  = "thisYear"
        case allTime   = "allTime"

        var localizedName: String {
            switch self {
            case .thisWeek:  return NSLocalizedString("questionGeneration.timeFilter.thisWeek", comment: "")
            case .thisMonth: return NSLocalizedString("questionGeneration.timeFilter.thisMonth", comment: "")
            case .thisYear:  return NSLocalizedString("questionGeneration.timeFilter.thisYear", comment: "")
            case .allTime:   return NSLocalizedString("questionGeneration.timeFilter.allTime", comment: "")
            }
        }
    }

    private var availableSubjects: [String] {
        var subjects = Set<String>()
        for conv in conversations {
            if let s = conv["subject"] as? String, !s.isEmpty { subjects.insert(s) }
        }
        for q in questions {
            if !q.subject.isEmpty { subjects.insert(q.subject) }
        }
        return ["All"] + subjects.sorted()
    }

    private var dateCutoff: Date? {
        let cal = Calendar.current
        let now = Date()
        switch selectedTimeFilter {
        case .allTime:   return nil
        case .thisWeek:  return cal.date(byAdding: .day,   value: -7,   to: now)
        case .thisMonth: return cal.date(byAdding: .month, value: -1,   to: now)
        case .thisYear:  return cal.date(byAdding: .year,  value: -1,   to: now)
        }
    }

    private func conversationDate(_ conv: [String: Any]) -> Date? {
        let keys = ["archived_date", "archivedDate", "archived_at", "sessionDate", "created_at"]
        for key in keys {
            if let s = conv[key] as? String {
                let fmt = ISO8601DateFormatter()
                fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = fmt.date(from: s) { return d }
                fmt.formatOptions = [.withInternetDateTime]
                if let d = fmt.date(from: s) { return d }
                let simple = DateFormatter()
                simple.dateFormat = "yyyy-MM-dd"
                if let d = simple.date(from: s) { return d }
            }
        }
        return nil
    }

    private var filteredConversations: [[String: Any]] {
        conversations.filter { conv in
            let subjectOK = selectedSubject == "All" || (conv["subject"] as? String) == selectedSubject
            let dateOK: Bool
            if let cutoff = dateCutoff, let d = conversationDate(conv) {
                dateOK = d >= cutoff
            } else {
                dateOK = dateCutoff == nil
            }
            return subjectOK && dateOK
        }
    }

    private var filteredQuestions: [QuestionSummary] {
        questions.filter { q in
            let subjectOK = selectedSubject == "All" || q.subject == selectedSubject
            let dateOK: Bool
            if let cutoff = dateCutoff {
                dateOK = q.archivedAt >= cutoff
            } else {
                dateOK = true
            }
            return subjectOK && dateOK
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if conversations.isEmpty && questions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.green)
                        Text(NSLocalizedString("questionGeneration.noArchivesFound", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(NSLocalizedString("questionGeneration.createArchivesMessage", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    Picker(NSLocalizedString("questionGeneration.filter.archiveType", comment: ""), selection: $selectedFilter) {
                        ForEach(ArchiveFilter.allCases, id: \.self) { filter in
                            Text(filter.localizedName).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        Menu {
                            ForEach(availableSubjects, id: \.self) { subject in
                                Button(action: { selectedSubject = subject }) {
                                    HStack {
                                        Text(subject == "All" ? NSLocalizedString("questionGeneration.filter.all", value: "All", comment: "") : BranchLocalizer.localized(subject))
                                        if selectedSubject == subject { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "book.closed").font(.caption)
                                Text(selectedSubject == "All" ? NSLocalizedString("questionGeneration.filter.subject", comment: "") : BranchLocalizer.localized(selectedSubject))
                                    .font(.subheadline).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selectedSubject == "All" ? Color(.systemGray6) : Color.green.opacity(0.15))
                            .foregroundColor(selectedSubject == "All" ? .primary : .green)
                            .cornerRadius(8)
                        }

                        Menu {
                            ForEach(TimeFilter.allCases, id: \.self) { tf in
                                Button(action: { selectedTimeFilter = tf }) {
                                    HStack {
                                        Text(tf.localizedName)
                                        if selectedTimeFilter == tf { Image(systemName: "checkmark") }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar").font(.caption)
                                Text(selectedTimeFilter.localizedName).font(.subheadline)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(selectedTimeFilter == .allTime ? Color(.systemGray6) : Color.green.opacity(0.15))
                            .foregroundColor(selectedTimeFilter == .allTime ? .primary : .green)
                            .cornerRadius(8)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)

                    if let locked = lockedSubject {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.fill").font(.caption)
                            Text(BranchLocalizer.localized(locked)).font(.caption.bold())
                            Text("·").foregroundColor(.secondary)
                            Text(NSLocalizedString("questionGeneration.subjectLock.hint", value: "Only same-subject items can be added", comment: ""))
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                selectedConversations.removeAll()
                                selectedQuestions.removeAll()
                            }) {
                                Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .foregroundColor(.green)
                        .cornerRadius(8)
                        .padding(.horizontal).padding(.top, 4)
                    }

                    HStack {
                        Button(action: {
                            let totalItems = filteredConversations.count + filteredQuestions.count
                            let selectedItems = selectedConversations.count + selectedQuestions.count
                            if selectedItems == totalItems || selectedItems >= maxSources {
                                selectedConversations.removeAll()
                                selectedQuestions.removeAll()
                            } else {
                                let targetSubject = lockedSubject
                                selectedConversations.removeAll()
                                selectedQuestions.removeAll()
                                var remaining = maxSources
                                let conversationIds = filteredConversations.compactMap { conv -> String? in
                                    guard let id = conv["id"] as? String else { return nil }
                                    if let target = targetSubject, (conv["subject"] as? String) != target { return nil }
                                    return id
                                }
                                for id in conversationIds {
                                    guard remaining > 0 else { break }
                                    selectedConversations.insert(id)
                                    remaining -= 1
                                }
                                for q in filteredQuestions {
                                    guard remaining > 0 else { break }
                                    if let target = targetSubject, q.subject != target { continue }
                                    selectedQuestions.insert(q.id)
                                    remaining -= 1
                                }
                                if totalItems > maxSources { showingLimitAlert = true }
                            }
                        }) {
                            let selectableCount: Int = {
                                if let locked = lockedSubject {
                                    let c = filteredConversations.filter { ($0["subject"] as? String) == locked }.count
                                    let q = filteredQuestions.filter { $0.subject == locked }.count
                                    return min(c + q, maxSources)
                                }
                                return min(filteredConversations.count + filteredQuestions.count, maxSources)
                            }()
                            let selectedItems = selectedConversations.count + selectedQuestions.count
                            Text(selectedItems == selectableCount && selectableCount > 0 ? NSLocalizedString("common.deselectAll", comment: "") : NSLocalizedString("common.selectAll", comment: ""))
                                .font(.subheadline).foregroundColor(.green)
                        }
                        Spacer()
                        Text("\(selectedConversations.count + selectedQuestions.count) \(NSLocalizedString("common.selected", comment: ""))")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.horizontal).padding(.bottom, 8)

                    List {
                        if (selectedFilter == .all || selectedFilter == .conversations) && !filteredConversations.isEmpty {
                            Section(NSLocalizedString("questionGeneration.conversations", comment: "")) {
                                ForEach(filteredConversations.indices, id: \.self) { index in
                                    let conversation = filteredConversations[index]
                                    let conversationId = conversation["id"] as? String ?? ""
                                    let conversationPreview = extractConversationPreview(from: conversation)
                                    ArchiveConversationSelectionCard(
                                        conversationTitle: conversationPreview,
                                        isSelected: selectedConversations.contains(conversationId),
                                        onToggle: {
                                            if selectedConversations.contains(conversationId) {
                                                selectedConversations.remove(conversationId)
                                            } else if let locked = lockedSubject,
                                                      subjectOf(conversationId: conversationId) != locked {
                                                showingSubjectMismatchAlert = true
                                            } else if totalSelected < maxSources {
                                                selectedConversations.insert(conversationId)
                                            } else {
                                                showingLimitAlert = true
                                            }
                                        }
                                    )
                                    .opacity({
                                        guard let locked = lockedSubject else { return 1.0 }
                                        return subjectOf(conversationId: conversationId) == locked ? 1.0 : 0.4
                                    }())
                                }
                            }
                        }

                        if (selectedFilter == .all || selectedFilter == .questions) && !filteredQuestions.isEmpty {
                            Section(NSLocalizedString("questionGeneration.questions", comment: "")) {
                                ForEach(filteredQuestions) { question in
                                    ArchiveQuestionSelectionCard(
                                        question: question,
                                        isSelected: selectedQuestions.contains(question.id),
                                        onToggle: {
                                            if selectedQuestions.contains(question.id) {
                                                selectedQuestions.remove(question.id)
                                            } else if let locked = lockedSubject,
                                                      question.subject != locked {
                                                showingSubjectMismatchAlert = true
                                            } else if totalSelected < maxSources {
                                                selectedQuestions.insert(question.id)
                                            } else {
                                                showingLimitAlert = true
                                            }
                                        }
                                    )
                                    .opacity(lockedSubject != nil && question.subject != lockedSubject ? 0.4 : 1.0)
                                }
                            }
                        }

                        if filteredConversations.isEmpty && filteredQuestions.isEmpty {
                            Section {
                                Text(NSLocalizedString("questionGeneration.filter.noResults", comment: ""))
                                    .font(.subheadline).foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 24)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(NSLocalizedString("questionGeneration.selectArchives", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(selectedConversations.isEmpty && selectedQuestions.isEmpty)
                }
            }
            .alert(NSLocalizedString("questionGeneration.sourceLimitTitle", comment: ""), isPresented: $showingLimitAlert) {
                Button(NSLocalizedString("common.ok", comment: "")) { }
            } message: {
                Text(String(format: NSLocalizedString("questionGeneration.sourceLimitMessage", comment: ""), maxSources))
            }
            .alert(NSLocalizedString("questionGeneration.subjectMismatch.title", value: "Different Subject", comment: ""), isPresented: $showingSubjectMismatchAlert) {
                Button(NSLocalizedString("questionGeneration.subjectMismatch.clearAndSwitch", value: "Clear & Switch", comment: ""), role: .destructive) {
                    selectedConversations.removeAll()
                    selectedQuestions.removeAll()
                }
                Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) { }
            } message: {
                if let locked = lockedSubject {
                    Text(String(format: NSLocalizedString("questionGeneration.subjectMismatch.message", value: "You've already selected %@ material. Clear your selection to choose from a different subject.", comment: ""), BranchLocalizer.localized(locked)))
                } else {
                    Text(NSLocalizedString("questionGeneration.subjectMismatch.messageFallback", value: "Clear your selection to choose from a different subject.", comment: ""))
                }
            }
        }
    }

    private func extractConversationPreview(from conversation: [String: Any]) -> String {
        if let summary = conversation["summary"] as? String, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return summary
        }
        if let title = conversation["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        if let messages = conversation["messages"] as? [[String: Any]], !messages.isEmpty {
            for message in messages {
                let role = message["role"] as? String ?? ""
                let sender = message["sender"] as? String ?? ""
                if role.lowercased() == "user" || sender.lowercased() == "user" {
                    if let content = message["content"] as? String ?? message["message"] as? String {
                        let words = content.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                        let preview = words.prefix(50).joined(separator: " ")
                        return preview + (words.count > 50 ? "..." : "")
                    }
                }
            }
        }
        let messageCount = conversation["message_count"] as? Int ?? conversation["messageCount"] as? Int ?? 0
        if messageCount > 0 {
            return String.localizedStringWithFormat(NSLocalizedString("questionGeneration.messagesInConversation", comment: ""), messageCount)
        }
        return NSLocalizedString("questionGeneration.studySession", comment: "")
    }
}

// MARK: - Selection Cards

struct ArchiveConversationSelectionCard: View {
    let conversationTitle: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversationTitle)
                        .font(.body).fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                    Text(NSLocalizedString("questionGeneration.conversation", comment: ""))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ArchiveQuestionSelectionCard: View {
    let question: QuestionSummary
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .gray)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.shortQuestionText)
                        .font(.body).fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                    HStack {
                        Text(question.subject)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                        Spacer()
                        Text(RelativeDateTimeFormatter().localizedString(for: question.archivedAt, relativeTo: Date()))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
