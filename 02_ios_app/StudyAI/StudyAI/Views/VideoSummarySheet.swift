import SwiftUI

/// Full-screen sheet that renders an AI-generated HTML video summary.
/// HTMLView is defined in PassiveReportDetailView.swift and accessible app-wide.
struct VideoSummarySheet: View {
    let html: String
    let videoId: String
    let videoTitle: String
    let channelTitle: String
    let subject: String
    let topicName: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @ObservedObject private var store = VideoSummaryStore.shared
    @State private var contentHeight: CGFloat = 500
    @State private var showPDFView = false
    @State private var archiveConfirm = false
    /// ⭐ Set true when the user scrolls the bottom sentinel into view, gating
    /// the feedback bar so we only ask after they've actually read the summary.
    @State private var hasScrolledToBottom = false

    private var isArchived: Bool { store.isSaved(videoId: videoId) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HTMLView(htmlContent: html, contentHeight: $contentHeight)
                        .frame(height: max(contentHeight, 500))
                        .padding(.horizontal, 4)
                        .padding(.bottom, 20)

                    // ⭐ Scroll-to-bottom sentinel: invisible 1pt view; .onAppear fires
                    // when user scrolls past the HTMLView, marking the summary as "read".
                    Color.clear
                        .frame(height: 1)
                        .onAppear { hasScrolledToBottom = true }

                    // ⭐ Feedback bar — only after the user has reached the bottom of the summary,
                    // and only once per video.
                    if hasScrolledToBottom,
                       FeedbackService.shared.shouldAsk(surface: .videoSummary, refId: videoId) {
                        FeedbackThumbsBar(
                            surface:  .videoSummary,
                            refType:  "video",
                            refId:    videoId,
                            metadata: [
                                "video_title":   videoTitle,
                                "channel_title": channelTitle,
                                "subject":       subject,
                                "topic_name":    topicName,
                            ]
                        )
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                }
            }
            .background(themeManager.cardBackground)
            .navigationTitle(NSLocalizedString("video.summary.title", value: "Video Summary", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        archiveSummary()
                    } label: {
                        Image(systemName: isArchived ? "bookmark.fill" : "bookmark")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showPDFView = true
                    } label: {
                        Image(systemName: "arrow.up.doc")
                    }
                    Button(NSLocalizedString("common.done", value: "Done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if archiveConfirm {
                    Text(NSLocalizedString("video.summary.archived", value: "Saved to Library", comment: ""))
                        .font(.footnote.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: archiveConfirm)
        }
        .fullScreenCover(isPresented: $showPDFView) {
            VideoSummaryPDFView(html: html, videoTitle: videoTitle)
        }
    }

    private func archiveSummary() {
        let summary = VideoSummary(
            id: UUID(),
            videoId: videoId,
            videoTitle: videoTitle,
            channelTitle: channelTitle,
            subject: subject,
            topicName: topicName,
            html: html,
            savedAt: Date()
        )
        store.save(summary)
        withAnimation { archiveConfirm = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { archiveConfirm = false }
        }
    }
}
