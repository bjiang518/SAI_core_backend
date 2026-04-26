//
//  ShareAppView.swift
//  StudyAI
//
//  Share the app with friends and family
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct ShareAppView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false

    private let appStoreURL = URL(string: "https://apps.apple.com/us/app/studyagent/id6754365864")!
    private var shareText: String {
        """
        \(NSLocalizedString("shareApp.messagePreview", comment: ""))

        \(NSLocalizedString("shareApp.feature1", comment: ""))
        \(NSLocalizedString("shareApp.feature2", comment: ""))
        \(NSLocalizedString("shareApp.feature3", comment: ""))
        \(NSLocalizedString("shareApp.feature4", comment: ""))
        """
    }

    var body: some View {
        NavigationStack {
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

                    // QR Code Section
                    VStack(spacing: 12) {
                        Text(NSLocalizedString("shareApp.scanToDownload", value: "Scan to Download", comment: ""))
                            .font(.headline)

                        if let qrImage = generateQRCode(from: appStoreURL.absoluteString) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 180, height: 180)
                                .padding(16)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                        }

                        Text(NSLocalizedString("shareApp.qrHint", value: "Let friends scan this with their camera", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)

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
                    }

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
            ActivityViewController(activityItems: [shareText, appStoreURL])
        }
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for crisp rendering
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func shareApp() {
        showShareSheet = true
        // Award one-time share points
        let _ = AppReviewService.shared.shareAppForPoints()
    }

    private func copyLink() {
        UIPasteboard.general.string = appStoreURL.absoluteString

        // Show feedback
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