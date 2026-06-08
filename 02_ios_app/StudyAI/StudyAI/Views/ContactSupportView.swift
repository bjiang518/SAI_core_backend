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
    @State private var showingReportProblem = false

    var body: some View {
        NavigationStack {
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
                        // Email — Feedback & Inquiries
                        Button(action: {
                            if MFMailComposeViewController.canSendMail() {
                                showingMailComposer = true
                            } else {
                                // Fallback to mailto URL — percent-encode the query parameters
                                var components = URLComponents()
                                components.scheme = "mailto"
                                components.path = AppURLs.supportEmail
                                components.queryItems = [URLQueryItem(name: "subject", value: "StudyAgent Support Request")]
                                if let url = components.url {
                                    UIApplication.shared.open(url) { success in
                                        if !success {
                                            showingMailError = true
                                        }
                                    }
                                } else {
                                    showingMailError = true
                                }
                            }
                        }) {
                            ContactMethodCard(
                                icon: "envelope.fill",
                                title: NSLocalizedString("contactSupport.emailTitle", comment: ""),
                                subtitle: AppURLs.supportEmail,
                                description: NSLocalizedString("contactSupport.emailDescription", comment: ""),
                                color: .blue
                            )
                        }
                        .buttonStyle(.plain)

                        // In-app feedback / problem report — lightweight channel that
                        // doesn't require switching to Mail. Goes straight to the
                        // feedback_submissions table for product review.
                        Button {
                            showingReportProblem = true
                        } label: {
                            ContactMethodCard(
                                icon: "exclamationmark.bubble.fill",
                                title: "Report a problem",
                                subtitle: "In-app — fastest",
                                description: "Tell us what broke or share an idea. We read every message.",
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
                recipient: AppURLs.supportEmail,
                subject: "StudyAgent Support Request"
            )
        }
        .sheet(isPresented: $showingReportProblem) {
            ReportProblemView()
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