//
//  TermsOfServiceView.swift
//  StudyAI
//
//  Terms of Service view displaying terms and conditions
//

import SwiftUI

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Last Updated
                    Text(NSLocalizedString("terms.lastUpdated", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                    // Acceptance of Terms
                    SectionView(
                        title: NSLocalizedString("terms.acceptance.title", comment: ""),
                        content: NSLocalizedString("terms.acceptance.content", comment: "")
                    )

                    // Use of Service
                    SectionView(
                        title: NSLocalizedString("terms.use.title", comment: ""),
                        content: NSLocalizedString("terms.use.content", comment: "")
                    )

                    // User Accounts
                    SectionView(
                        title: NSLocalizedString("terms.accounts.title", comment: ""),
                        content: NSLocalizedString("terms.accounts.content", comment: "")
                    )

                    // Acceptable Use
                    SectionView(
                        title: NSLocalizedString("terms.acceptable.title", comment: ""),
                        content: NSLocalizedString("terms.acceptable.content", comment: "")
                    )

                    // Intellectual Property
                    SectionView(
                        title: NSLocalizedString("terms.intellectual.title", comment: ""),
                        content: NSLocalizedString("terms.intellectual.content", comment: "")
                    )

                    // User Content
                    SectionView(
                        title: NSLocalizedString("terms.userContent.title", comment: ""),
                        content: NSLocalizedString("terms.userContent.content", comment: "")
                    )

                    // Disclaimer
                    SectionView(
                        title: NSLocalizedString("terms.disclaimer.title", comment: ""),
                        content: NSLocalizedString("terms.disclaimer.content", comment: "")
                    )

                    // Limitation of Liability
                    SectionView(
                        title: NSLocalizedString("terms.liability.title", comment: ""),
                        content: NSLocalizedString("terms.liability.content", comment: "")
                    )

                    // Termination
                    SectionView(
                        title: NSLocalizedString("terms.termination.title", comment: ""),
                        content: NSLocalizedString("terms.termination.content", comment: "")
                    )

                    // Changes to Terms
                    SectionView(
                        title: NSLocalizedString("terms.changes.title", comment: ""),
                        content: NSLocalizedString("terms.changes.content", comment: "")
                    )

                    // Governing Law
                    SectionView(
                        title: NSLocalizedString("terms.law.title", comment: ""),
                        content: NSLocalizedString("terms.law.content", comment: "")
                    )

                    // Contact Us
                    SectionView(
                        title: NSLocalizedString("terms.contact.title", comment: ""),
                        content: NSLocalizedString("terms.contact.content", comment: "")
                    )
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("terms.title", comment: ""))
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

#Preview {
    TermsOfServiceView()
}
