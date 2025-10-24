//
//  ContactSupportView.swift
//  StudyAI
//
//  Contact support with various communication channels
//

import SwiftUI
import MessageUI

struct ContactSupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingMailComposer = false
    @State private var showingMailError = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text(NSLocalizedString("settings.contact", comment: ""))
                            .font(.title)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("contactSupport.subtitle", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top)

                    // Contact Methods
                    VStack(spacing: 16) {
                        // Email Support
                        Button(action: {
                            if MFMailComposeViewController.canSendMail() {
                                showingMailComposer = true
                            } else {
                                // Fallback to mailto URL
                                if let url = URL(string: "mailto:support@studyai.com?subject=StudyMates Support Request") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }) {
                            ContactMethodCard(
                                icon: "envelope.fill",
                                title: NSLocalizedString("contactSupport.emailTitle", comment: ""),
                                subtitle: "support@studyai.com",
                                description: NSLocalizedString("contactSupport.emailDescription", comment: ""),
                                color: .blue
                            )
                        }
                        .buttonStyle(.plain)

                        // Live Chat (placeholder for future implementation)
                        Button(action: {
                            // Future: Open live chat
                            if let url = URL(string: "https://studyai.com/support/chat") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            ContactMethodCard(
                                icon: "message.fill",
                                title: NSLocalizedString("contactSupport.chatTitle", comment: ""),
                                subtitle: NSLocalizedString("contactSupport.chatSubtitle", comment: ""),
                                description: NSLocalizedString("contactSupport.chatDescription", comment: ""),
                                color: .green
                            )
                        }
                        .buttonStyle(.plain)

                        // Community Forum
                        Link(destination: URL(string: "https://community.studyai.com")!) {
                            ContactMethodCard(
                                icon: "person.3.fill",
                                title: NSLocalizedString("contactSupport.forumTitle", comment: ""),
                                subtitle: NSLocalizedString("contactSupport.forumSubtitle", comment: ""),
                                description: NSLocalizedString("contactSupport.forumDescription", comment: ""),
                                color: .purple
                            )
                        }

                        // Phone Support (business hours)
                        Button(action: {
                            if let url = URL(string: "tel:+1-800-STUDYAI") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            ContactMethodCard(
                                icon: "phone.fill",
                                title: NSLocalizedString("contactSupport.phoneTitle", comment: ""),
                                subtitle: "+1 (800) STUDY-AI",
                                description: NSLocalizedString("contactSupport.phoneDescription", comment: ""),
                                color: .orange
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Response Time
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("contactSupport.averageResponseTime", comment: ""))
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }

                        Text(NSLocalizedString("contactSupport.emailResponseTime", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("contactSupport.chatResponseTime", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("contactSupport.phoneResponseTime", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
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
        .sheet(isPresented: $showingMailComposer) {
            MailComposeView(
                recipient: "support@studyai.com",
                subject: "StudyMates Support Request"
            )
        }
        .alert(NSLocalizedString("contactSupport.emailNotAvailable", comment: ""), isPresented: $showingMailError) {
            Button(NSLocalizedString("common.ok", comment: ""), role: .cancel) { }
        } message: {
            Text(NSLocalizedString("contactSupport.emailNotAvailableMessage", comment: ""))
        }
    }
}

struct ContactMethodCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(color)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundColor(color.opacity(0.3))
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// Mail Composer Wrapper
struct MailComposeView: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([recipient])
        composer.setSubject(subject)

        // Add device info for better support
        let deviceInfo = """


        ---
        Device Info:
        App Version: 1.0
        iOS Version: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)
        """
        composer.setMessageBody(deviceInfo, isHTML: false)

        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposeView

        init(_ parent: MailComposeView) {
            self.parent = parent
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.dismiss()
        }
    }
}

#Preview {
    ContactSupportView()
}