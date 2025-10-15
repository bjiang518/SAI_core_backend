//
//  HelpCenterView.swift
//  StudyAI
//
//  Help Center with FAQ and support resources
//

import SwiftUI

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss

    private var faqItems: [(question: String, answer: String)] {
        [
            (
                question: NSLocalizedString("helpCenter.faq1.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq1.answer", comment: "")
            ),
            (
                question: NSLocalizedString("helpCenter.faq2.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq2.answer", comment: "")
            ),
            (
                question: NSLocalizedString("helpCenter.faq3.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq3.answer", comment: "")
            ),
            (
                question: NSLocalizedString("helpCenter.faq4.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq4.answer", comment: "")
            ),
            (
                question: NSLocalizedString("helpCenter.faq5.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq5.answer", comment: "")
            ),
            (
                question: NSLocalizedString("helpCenter.faq6.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq6.answer", comment: "")
            ),
            (
                question: NSLocalizedString("helpCenter.faq7.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq7.answer", comment: "")
            ),
            (
                question: NSLocalizedString("helpCenter.faq8.question", comment: ""),
                answer: NSLocalizedString("helpCenter.faq8.answer", comment: "")
            )
        ]
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text(NSLocalizedString("settings.help", comment: ""))
                            .font(.title)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("helpCenter.subtitle", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)

                    // FAQ Section
                    VStack(spacing: 16) {
                        ForEach(Array(faqItems.enumerated()), id: \.offset) { index, item in
                            FAQCard(question: item.question, answer: item.answer)
                        }
                    }

                    // Quick Links
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("helpCenter.quickLinks", comment: ""))
                            .font(.headline)
                            .padding(.horizontal)

                        Link(destination: URL(string: "https://studyai.com/getting-started")!) {
                            QuickLinkCard(
                                icon: "play.circle.fill",
                                title: NSLocalizedString("helpCenter.gettingStarted", comment: ""),
                                color: .blue
                            )
                        }

                        Link(destination: URL(string: "https://studyai.com/video-tutorials")!) {
                            QuickLinkCard(
                                icon: "video.fill",
                                title: NSLocalizedString("helpCenter.videoTutorials", comment: ""),
                                color: .purple
                            )
                        }

                        Link(destination: URL(string: "https://studyai.com/tips")!) {
                            QuickLinkCard(
                                icon: "lightbulb.fill",
                                title: NSLocalizedString("helpCenter.studyTips", comment: ""),
                                color: .orange
                            )
                        }
                    }
                    .padding(.top)

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FAQCard: View {
    let question: String
    let answer: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text(question)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(answer)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct QuickLinkCard: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)

            Text(title)
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    HelpCenterView()
}