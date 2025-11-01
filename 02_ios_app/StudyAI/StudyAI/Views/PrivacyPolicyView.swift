//
//  PrivacyPolicyView.swift
//  StudyAI
//
//  Privacy Policy view displaying privacy information
//

import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Last Updated
                    Text(NSLocalizedString("privacy.lastUpdated", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                    // Introduction
                    SectionView(
                        title: NSLocalizedString("privacy.intro.title", comment: ""),
                        content: NSLocalizedString("privacy.intro.content", comment: "")
                    )

                    // Information We Collect
                    SectionView(
                        title: NSLocalizedString("privacy.collect.title", comment: ""),
                        content: NSLocalizedString("privacy.collect.content", comment: "")
                    )

                    // How We Use Your Information
                    SectionView(
                        title: NSLocalizedString("privacy.usage.title", comment: ""),
                        content: NSLocalizedString("privacy.usage.content", comment: "")
                    )

                    // Data Security
                    SectionView(
                        title: NSLocalizedString("privacy.security.title", comment: ""),
                        content: NSLocalizedString("privacy.security.content", comment: "")
                    )

                    // COPPA Compliance
                    SectionView(
                        title: NSLocalizedString("privacy.coppa.title", comment: ""),
                        content: NSLocalizedString("privacy.coppa.content", comment: "")
                    )

                    // GDPR Rights
                    SectionView(
                        title: NSLocalizedString("privacy.gdpr.title", comment: ""),
                        content: NSLocalizedString("privacy.gdpr.content", comment: "")
                    )

                    // Third-Party Services
                    SectionView(
                        title: NSLocalizedString("privacy.thirdParty.title", comment: ""),
                        content: NSLocalizedString("privacy.thirdParty.content", comment: "")
                    )

                    // Data Retention
                    SectionView(
                        title: NSLocalizedString("privacy.retention.title", comment: ""),
                        content: NSLocalizedString("privacy.retention.content", comment: "")
                    )

                    // Your Rights
                    SectionView(
                        title: NSLocalizedString("privacy.rights.title", comment: ""),
                        content: NSLocalizedString("privacy.rights.content", comment: "")
                    )

                    // Changes to Policy
                    SectionView(
                        title: NSLocalizedString("privacy.changes.title", comment: ""),
                        content: NSLocalizedString("privacy.changes.content", comment: "")
                    )

                    // Contact Us
                    SectionView(
                        title: NSLocalizedString("privacy.contact.title", comment: ""),
                        content: NSLocalizedString("privacy.contact.content", comment: "")
                    )
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("privacy.title", comment: ""))
            .navigationBarTitleDisplayMode(.large)
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

struct SectionView: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)

            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    PrivacyPolicyView()
}
