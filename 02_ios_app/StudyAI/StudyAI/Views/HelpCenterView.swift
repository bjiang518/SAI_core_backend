//
//  HelpCenterView.swift
//  StudyAI
//
//  Help Center with FAQ and support resources
//

import SwiftUI

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss

    private let faqItems: [(question: String, answer: String)] = [
        (
            question: "How do I use the Homework Grader?",
            answer: "Take a photo of your homework or upload an image. Our AI will analyze it, detect questions, and provide detailed feedback with corrections and explanations."
        ),
        (
            question: "What subjects are supported?",
            answer: "StudyAI supports Mathematics, Physics, Chemistry, Biology, English, History, Geography, and Computer Science. We're constantly adding more subjects!"
        ),
        (
            question: "How do I change the AI voice?",
            answer: "Go to Settings > Voice & Audio > Voice Settings. You can choose between Adam (boy voice) and Eva (girl voice), and customize speed, pitch, and volume."
        ),
        (
            question: "Can I review my past mistakes?",
            answer: "Yes! Use the Mistake Review feature from the home screen to revisit questions you got wrong and practice similar problems."
        ),
        (
            question: "How does the streak system work?",
            answer: "Your streak increases each day you complete at least one study session. Maintain your streak to unlock achievements and rewards!"
        ),
        (
            question: "Is my data secure?",
            answer: "Yes! We use industry-standard encryption and secure authentication. Your homework and learning data are stored securely and never shared with third parties."
        ),
        (
            question: "How do I track my progress?",
            answer: "Visit the Progress tab to see detailed statistics, accuracy trends, subject performance, and weekly learning patterns."
        ),
        (
            question: "What is the difference between Detail and Fast parsing?",
            answer: "Detail mode provides more accurate parsing with hierarchical structure and parent-child relationships. Fast mode is quicker but simpler. Use Detail for complex homework."
        )
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("Help Center")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("Find answers to common questions")
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
                        Text("Quick Links")
                            .font(.headline)
                            .padding(.horizontal)

                        Link(destination: URL(string: "https://studyai.com/getting-started")!) {
                            QuickLinkCard(
                                icon: "play.circle.fill",
                                title: "Getting Started Guide",
                                color: .blue
                            )
                        }

                        Link(destination: URL(string: "https://studyai.com/video-tutorials")!) {
                            QuickLinkCard(
                                icon: "video.fill",
                                title: "Video Tutorials",
                                color: .purple
                            )
                        }

                        Link(destination: URL(string: "https://studyai.com/tips")!) {
                            QuickLinkCard(
                                icon: "lightbulb.fill",
                                title: "Study Tips & Best Practices",
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
                    Button("Done") {
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