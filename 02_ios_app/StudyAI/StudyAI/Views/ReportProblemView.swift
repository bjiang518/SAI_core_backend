//
//  ReportProblemView.swift
//  StudyAI
//
//  Free-text "Report a problem" / suggestion entry. Surfaces from
//  Settings → Help & Support. Posts to /api/feedback/report and emits a
//  feedback_submitted analytics event so we can track topic distribution
//  in the admin dashboard.
//

import SwiftUI

struct ReportProblemView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    @State private var category: Category = .bug
    @State private var message: String = ""
    @State private var isSending: Bool = false
    @State private var showResultBanner: Bool = false
    @State private var resultWasSuccess: Bool = false

    private let maxChars = 4000

    enum Category: String, CaseIterable, Identifiable {
        case bug, suggestion, content, praise, other
        var id: String { rawValue }

        var label: String {
            switch self {
            case .bug:        return "Something is broken"
            case .suggestion: return "I have an idea"
            case .content:    return "Wrong answer or content"
            case .praise:     return "I like something"
            case .other:      return "Other"
            }
        }
        var icon: String {
            switch self {
            case .bug:        return "ladybug"
            case .suggestion: return "lightbulb"
            case .content:    return "text.badge.xmark"
            case .praise:     return "heart"
            case .other:      return "ellipsis.bubble"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("What's going on?")) {
                    ForEach(Category.allCases) { c in
                        Button {
                            category = c
                        } label: {
                            HStack {
                                Image(systemName: c.icon)
                                    .frame(width: 24)
                                Text(c.label)
                                Spacer()
                                if category == c {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(header: Text("Tell us more"),
                        footer: Text("\(message.count)/\(maxChars)").foregroundColor(.secondary)) {
                    TextEditor(text: $message)
                        .frame(minHeight: 140)
                        .onChange(of: message) { _, new in
                            if new.count > maxChars {
                                message = String(new.prefix(maxChars))
                            }
                        }
                }

                if showResultBanner {
                    Section {
                        Label(
                            resultWasSuccess
                                ? "Thanks — we got it."
                                : "Couldn't send. Please try again later.",
                            systemImage: resultWasSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundColor(resultWasSuccess ? .green : .orange)
                    }
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("ReportProblem")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") { Task { await send() } }
                            .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = await NetworkService.shared.submitProblemReport(
            category: category.rawValue,
            message:  trimmed
        )
        resultWasSuccess = ok
        showResultBanner = true

        JourneyTracker.shared.track("feedback_submitted", [
            "category":    category.rawValue,
            "message_len": trimmed.count,
            "success":     ok,
        ])

        if ok {
            // Auto-dismiss on success after a brief banner.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { dismiss() }
        }
    }
}
