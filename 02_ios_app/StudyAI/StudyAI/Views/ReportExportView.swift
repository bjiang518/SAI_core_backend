//
//  ReportExportView.swift
//  StudyAI
//
//  Advanced export and sharing functionality for parent reports
//

import SwiftUI
import MessageUI

struct ReportExportView: View {
    let report: ParentReport
    @StateObject private var exportService = ReportExportService()
    @Environment(\.dismiss) private var dismiss

    @State private var showingEmailComposer = false
    @State private var showingShareSheet = false
    @State private var showingShareLinkGenerator = false
    @State private var generatedShareLink: ShareLinkData?
    @State private var selectedExportFormat: ExportFormat = .pdf
    @State private var emailRecipients: [String] = [""]
    @State private var emailSubject = ""
    @State private var emailMessage = ""
    @State private var exportedFileURL: URL?

    enum ExportFormat: String, CaseIterable {
        case pdf = "pdf"
        case json = "json"

        var displayName: String {
            switch self {
            case .pdf: return "PDF Document"
            case .json: return "JSON Data"
            }
        }

        var icon: String {
            switch self {
            case .pdf: return "doc.fill"
            case .json: return "curlybraces"
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    ReportHeaderCard(report: report)

                    // Export Options
                    ExportOptionsSection(
                        selectedFormat: $selectedExportFormat,
                        isExporting: exportService.isExporting,
                        onExport: handleExport
                    )

                    // Sharing Options
                    SharingOptionsSection(
                        onEmailShare: { showingEmailComposer = true },
                        onGenerateLink: { showingShareLinkGenerator = true },
                        onDirectShare: handleDirectShare,
                        isProcessing: exportService.isProcessing
                    )

                    // Export Status
                    if exportService.isExporting || exportService.isProcessing {
                        ExportStatusCard(
                            status: exportService.exportStatus,
                            progress: exportService.exportProgress
                        )
                    }

                    // Success Actions
                    if let fileURL = exportedFileURL {
                        ExportSuccessCard(
                            fileURL: fileURL,
                            onShare: { showingShareSheet = true }
                        )
                    }

                    // Generated Share Link
                    if let shareLink = generatedShareLink {
                        ShareLinkCard(shareLink: shareLink)
                    }
                }
                .padding()
            }
            .navigationTitle("Export & Share")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingEmailComposer) {
            EmailComposerView(
                recipients: $emailRecipients,
                subject: $emailSubject,
                message: $emailMessage,
                report: report,
                onSend: handleEmailSend
            )
        }
        .sheet(isPresented: $showingShareLinkGenerator) {
            ShareLinkGeneratorView(
                report: report,
                onGenerated: { shareLink in
                    generatedShareLink = shareLink
                    showingShareLinkGenerator = false
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = exportedFileURL {
                ActivityViewController(activityItems: [fileURL])
            }
        }
        .alert("Export Error", isPresented: .constant(exportService.errorMessage != nil)) {
            Button("OK") {
                exportService.clearError()
            }
        } message: {
            Text(exportService.errorMessage ?? "")
        }
    }

    private func handleExport() {
        Task {
            do {
                let fileURL = try await exportService.exportReport(
                    reportId: report.id,
                    format: selectedExportFormat
                )
                await MainActor.run {
                    exportedFileURL = fileURL
                }
            } catch {
                await MainActor.run {
                    exportService.setError(error.localizedDescription)
                }
            }
        }
    }

    private func handleDirectShare() {
        handleExport()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if exportedFileURL != nil {
                showingShareSheet = true
            }
        }
    }

    private func handleEmailSend() {
        Task {
            do {
                try await exportService.emailReport(
                    reportId: report.id,
                    recipients: emailRecipients,
                    subject: emailSubject,
                    message: emailMessage
                )
                await MainActor.run {
                    showingEmailComposer = false
                }
            } catch {
                await MainActor.run {
                    exportService.setError(error.localizedDescription)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ReportHeaderCard: View {
    let report: ParentReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.reportTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(formatDate(report.startDate)) - \(formatDate(report.endDate))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Label(report.reportType.rawValue.capitalized, systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text("Generated \(formatDate(report.generatedAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct ExportOptionsSection: View {
    @Binding var selectedFormat: ReportExportView.ExportFormat
    let isExporting: Bool
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Format")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(ReportExportView.ExportFormat.allCases, id: \.self) { format in
                    FormatOptionCard(
                        format: format,
                        isSelected: selectedFormat == format,
                        onSelect: { selectedFormat = format }
                    )
                }
            }

            Button(action: onExport) {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isExporting ? "Exporting..." : "Export Report")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isExporting)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct FormatOptionCard: View {
    let format: ReportExportView.ExportFormat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: format.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)

                Text(format.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isSelected ? Color.blue : Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SharingOptionsSection: View {
    let onEmailShare: () -> Void
    let onGenerateLink: () -> Void
    let onDirectShare: () -> Void
    let isProcessing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sharing Options")
                .font(.headline)

            VStack(spacing: 12) {
                ShareOptionButton(
                    title: "Email Report",
                    subtitle: "Send via email with custom message",
                    icon: "envelope.fill",
                    color: .green,
                    action: onEmailShare,
                    isDisabled: isProcessing
                )

                ShareOptionButton(
                    title: "Generate Share Link",
                    subtitle: "Create a secure, expiring link",
                    icon: "link",
                    color: .orange,
                    action: onGenerateLink,
                    isDisabled: isProcessing
                )

                ShareOptionButton(
                    title: "Share Directly",
                    subtitle: "Use system share sheet",
                    icon: "square.and.arrow.up",
                    color: .blue,
                    action: onDirectShare,
                    isDisabled: isProcessing
                )
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct ShareOptionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    let isDisabled: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

struct ExportStatusCard: View {
    let status: String
    let progress: Double

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }

            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ExportSuccessCard: View {
    let fileURL: URL
    let onShare: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Complete")
                        .fontWeight(.medium)
                    Text("File ready for sharing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Button("Share File", action: onShare)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }
}

struct ShareLinkCard: View {
    let shareLink: ShareLinkData
    @State private var showingCopiedAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Link Generated")
                        .fontWeight(.medium)
                    Text("Expires \(formatDate(shareLink.expiresAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack {
                Text(shareLink.shareUrl)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Button("Copy") {
                    UIPasteboard.general.string = shareLink.shareUrl
                    showingCopiedAlert = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .alert("Copied!", isPresented: $showingCopiedAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Data Models

struct ShareLinkData {
    let shareUrl: String
    let shareId: String
    let expiresAt: Date
    let accessInstructions: String
}

#Preview {
    ReportExportView(report: ParentReport.sampleReport)
}