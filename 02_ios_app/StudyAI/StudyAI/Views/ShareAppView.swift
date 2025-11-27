//
//  ShareAppView.swift
//  StudyAI
//
//  Share the app with friends and family
//

import SwiftUI

struct ShareAppView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    private let appURL = "https://apps.apple.com/app/id6504105201"
    private var shareText: String {
        """
        \(NSLocalizedString("shareApp.messagePreview", comment: ""))

        \(NSLocalizedString("shareApp.feature1", comment: ""))
        \(NSLocalizedString("shareApp.feature2", comment: ""))
        \(NSLocalizedString("shareApp.feature3", comment: ""))
        \(NSLocalizedString("shareApp.feature4", comment: ""))

        \(NSLocalizedString("shareApp.downloadNow", comment: "")) \(appURL)
        """
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.cyan)

                        Text(NSLocalizedString("settings.shareApp", comment: ""))
                            .font(.title)
                            .fontWeight(.bold)

                        Text(NSLocalizedString("shareApp.subtitle", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top)

                    // Share Message Preview
                    VStack(alignment: .leading, spacing: 12) {
                        Text(NSLocalizedString("shareApp.messageTitle", comment: ""))
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(NSLocalizedString("shareApp.messagePreview", comment: ""))
                                .font(.body)
                                .foregroundColor(.primary)
                                .italic()

                            Divider()

                            Text(NSLocalizedString("shareApp.feature1", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("shareApp.feature2", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("shareApp.feature3", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(NSLocalizedString("shareApp.feature4", comment: ""))
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Divider()

                            Text(NSLocalizedString("shareApp.downloadLink", comment: ""))
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Share Methods
                    VStack(spacing: 16) {
                        // Native Share Sheet
                        Button(action: {
                            shareApp()
                        }) {
                            ShareMethodCard(
                                icon: "square.and.arrow.up.fill",
                                title: NSLocalizedString("shareApp.shareViaTitle", comment: ""),
                                subtitle: NSLocalizedString("shareApp.shareViaSubtitle", comment: ""),
                                color: .blue
                            )
                        }
                        .buttonStyle(.plain)

                        // Copy Link
                        Button(action: {
                            copyLink()
                        }) {
                            ShareMethodCard(
                                icon: "link.circle.fill",
                                title: NSLocalizedString("shareApp.copyLinkTitle", comment: ""),
                                subtitle: NSLocalizedString("shareApp.copyLinkSubtitle", comment: ""),
                                color: .green
                            )
                        }
                        .buttonStyle(.plain)

                        // QR Code
                        VStack(spacing: 12) {
                            Text(NSLocalizedString("shareApp.scanToDownload", comment: ""))
                                .font(.headline)

                            // QR Code placeholder (in production, generate actual QR code)
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemBackground))
                                    .frame(width: 200, height: 200)
                                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)

                                VStack(spacing: 8) {
                                    Image(systemName: "qrcode")
                                        .font(.system(size: 120))
                                        .foregroundColor(.primary)

                                    Text(NSLocalizedString("shareApp.qrCode", comment: ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text(NSLocalizedString("shareApp.showQRCode", comment: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // Referral Info (future feature)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "gift.fill")
                                .foregroundColor(.purple)
                            Text(NSLocalizedString("shareApp.comingSoonReferral", comment: ""))
                                .font(.headline)
                                .foregroundColor(.purple)
                        }

                        Text(NSLocalizedString("shareApp.earnPoints", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.1), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
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
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(activityItems: [shareText])
        }
    }

    private func shareApp() {
        showShareSheet = true
    }

    private func copyLink() {
        let appURL = "https://apps.apple.com/app/id6504105201"
        UIPasteboard.general.string = appURL

        // Show feedback (you could add a toast notification here)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

struct ShareMethodCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
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
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.right.circle.fill")
                .font(.title3)
                .foregroundColor(color.opacity(0.3))
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    ShareAppView()
}