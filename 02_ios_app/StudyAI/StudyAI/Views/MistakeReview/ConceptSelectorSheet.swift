import SwiftUI

struct ConceptSelectorSheet: View {
    let subject: String
    let branches: [KnowledgeTreeBranch]
    let onSelect: (KnowledgeTreeTopic) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        NavigationView {
            List {
                ForEach(branches) { branch in
                    Section(BranchLocalizer.localized(branch.name)) {
                        ForEach(branch.topics) { topic in
                            Button {
                                onSelect(topic)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(topic.leafColor)
                                        .frame(width: 10, height: 10)
                                    Text(BranchLocalizer.localized(topic.topicName))
                                        .font(.system(size: 15))
                                        .foregroundColor(themeManager.primaryText)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("knowledgeTree.learnNewConcept",
                                               value: "Learn New Concept",
                                               comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text(subject)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.cancel", value: "Cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
