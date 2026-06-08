//
//  CancelReasonSheet.swift
//  StudyAI
//
//  Pre-prompt before Apple's "Manage Subscriptions" flow. Captures why
//  paying users are heading toward cancel — Apple's sheet gives us no
//  signal back. Optional: users can skip and continue.
//

import SwiftUI

struct CancelReasonSheet: View {
    let tier: String
    let onContinue: () -> Void
    let onDismiss:  () -> Void

    @State private var selectedReason: Reason?
    @State private var customDetail: String = ""

    enum Reason: String, CaseIterable, Identifiable {
        case tooExpensive    = "too_expensive"
        case notUsingEnough  = "not_using_enough"
        case missingFeatures = "missing_features"
        case bugsOrQuality   = "bugs_or_quality"
        case foundAlternative = "found_alternative"
        case justExploring   = "just_exploring"
        case other           = "other"

        var id: String { rawValue }
        var label: String {
            switch self {
            case .tooExpensive:     return "Too expensive"
            case .notUsingEnough:   return "Not using it enough"
            case .missingFeatures:  return "Missing a feature I need"
            case .bugsOrQuality:    return "Bugs or quality issues"
            case .foundAlternative: return "Using something else now"
            case .justExploring:    return "Just trying things out"
            case .other:            return "Something else"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Before you go")) {
                    Text("If you have a moment, what's prompting this? Your answer goes straight to the team — it stays anonymous in our reports.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Reason")) {
                    ForEach(Reason.allCases) { r in
                        Button {
                            selectedReason = r
                        } label: {
                            HStack {
                                Text(r.label)
                                Spacer()
                                if selectedReason == r {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedReason == .other || selectedReason != nil {
                    Section(header: Text("Anything else? (optional)")) {
                        TextEditor(text: $customDetail)
                            .frame(minHeight: 80)
                    }
                }
            }
            .navigationTitle("Manage subscription")
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen("CancelReason")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        emit(reason: nil)
                        onContinue()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        emit(reason: selectedReason)
                        onContinue()
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    private func emit(reason: Reason?) {
        var props: [String: Any] = [
            "tier":   tier,
            "reason": reason?.rawValue ?? "skipped",
        ]
        let detail = customDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { props["detail_len"] = detail.count }
        JourneyTracker.shared.track("subscription_cancel_reason", props)
    }
}
