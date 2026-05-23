import SwiftUI

struct RecentSummariesSheet: View {
    let subject: String

    @ObservedObject private var store = VideoSummaryStore.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @State private var selectedSummary: VideoSummary? = nil

    private var summaries: [VideoSummary] { store.summaries(for: subject) }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationView {
            Group {
                if summaries.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.image")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary.opacity(0.35))
                        Text(NSLocalizedString("summaries.empty",
                                               value: "No summaries saved yet",
                                               comment: ""))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(summaries) { summary in
                        Button { selectedSummary = summary } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.image.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(DesignTokens.Colors.Cute.mint)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(summary.videoTitle)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(themeManager.primaryText)
                                        .lineLimit(1)
                                    Text(summary.channelTitle)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Text(Self.dateFormatter.string(from: summary.savedAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(NSLocalizedString("knowledgeTree.recentSummaries",
                                               value: "Recent Learning Summaries",
                                               comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text(subject)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", value: "Done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $selectedSummary) { summary in
            VideoSummarySheet(
                html: summary.html,
                videoId: summary.videoId,
                videoTitle: summary.videoTitle,
                channelTitle: summary.channelTitle,
                subject: summary.subject,
                topicName: summary.topicName
            )
        }
    }
}
