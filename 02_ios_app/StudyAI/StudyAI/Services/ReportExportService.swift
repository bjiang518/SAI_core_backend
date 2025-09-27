//
//  ReportExportService.swift
//  StudyAI
//
//  Service for handling report export and sharing functionality
//

import Foundation
import SwiftUI
import Combine

@MainActor
class ReportExportService: ObservableObject {
    @Published var isExporting = false
    @Published var isProcessing = false
    @Published var exportStatus = ""
    @Published var exportProgress: Double = 0.0
    @Published var errorMessage: String?

    private let networkService = NetworkService.shared

    // MARK: - Export Functions

    func exportReport(reportId: String, format: ReportExportView.ExportFormat) async throws -> URL {
        isExporting = true
        exportStatus = "Preparing export..."
        exportProgress = 0.1

        defer {
            isExporting = false
            exportProgress = 0.0
            exportStatus = ""
        }

        do {
            exportStatus = "Generating \(format.displayName.lowercased())..."
            exportProgress = 0.3

            let endpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/export?format=\(format.rawValue)"

            guard let url = URL(string: endpoint) else {
                throw ReportExportError.networkError("Invalid URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"

            // Add authentication header
            if let token = AuthenticationService.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            exportProgress = 0.7

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReportExportError.networkError("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                throw ReportExportError.networkError("Server error: \(httpResponse.statusCode)")
            }

            exportStatus = "Saving file..."
            let fileName = format == .pdf ? "report-\(reportId).pdf" : "report-\(reportId).json"
            let fileURL = try saveToTemporaryFile(data: data, fileName: fileName)

            exportProgress = 1.0
            exportStatus = "Export complete!"
            return fileURL
        } catch {
            print("❌ Export error: \(error)")
            throw error
        }
    }

    func emailReport(reportId: String, recipients: [String], subject: String, message: String) async throws {
        isProcessing = true
        exportStatus = "Sending email..."
        exportProgress = 0.1

        defer {
            isProcessing = false
            exportProgress = 0.0
            exportStatus = ""
        }

        do {
            let endpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/email"
            guard let url = URL(string: endpoint) else {
                throw ReportExportError.networkError("Invalid URL")
            }

            let requestBody: [String: Any] = [
                "to": recipients.filter { !$0.isEmpty },
                "subject": subject.isEmpty ? nil as String? : subject,
                "message": message.isEmpty ? nil as String? : message
            ].compactMapValues { $0 }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add authentication header
            if let token = AuthenticationService.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            exportProgress = 0.5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReportExportError.networkError("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ReportExportError.networkError("Server error: \(httpResponse.statusCode) - \(errorMessage)")
            }

            exportProgress = 1.0
            exportStatus = "Email sent successfully!"

            print("✅ Email sent successfully")
        } catch {
            print("❌ Email error: \(error)")
            throw error
        }
    }

    func generateShareLink(reportId: String, expiryDays: Int = 7, maxAccess: Int? = nil, password: String? = nil) async throws -> ShareLinkData {
        isProcessing = true
        exportStatus = "Generating share link..."
        exportProgress = 0.1

        defer {
            isProcessing = false
            exportProgress = 0.0
            exportStatus = ""
        }

        do {
            let endpoint = "\(networkService.apiBaseURL)/api/reports/\(reportId)/share"
            guard let url = URL(string: endpoint) else {
                throw ReportExportError.networkError("Invalid URL")
            }

            var requestBody: [String: Any] = [
                "expiryDays": expiryDays
            ]

            if let maxAccess = maxAccess {
                requestBody["maxAccess"] = maxAccess
            }

            if let password = password, !password.isEmpty {
                requestBody["password"] = password
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            // Add authentication header
            if let token = AuthenticationService.shared.getAuthToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            exportProgress = 0.5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ReportExportError.networkError("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ReportExportError.networkError("Server error: \(httpResponse.statusCode) - \(errorMessage)")
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let shareUrl: String = json?["shareUrl"] as? String,
                  let shareId: String = json?["shareId"] as? String,
                  let expiresAtString: String = json?["expiresAt"] as? String,
                  let accessInstructions: String = json?["accessInstructions"] as? String else {
                throw ReportExportError.invalidResponse
            }

            let dateFormatter = ISO8601DateFormatter()
            let expiresAt = dateFormatter.date(from: expiresAtString) ?? Date()

            exportProgress = 1.0
            exportStatus = "Share link generated!"

            return ShareLinkData(
                shareUrl: shareUrl,
                shareId: shareId,
                expiresAt: expiresAt,
                accessInstructions: accessInstructions
            )
        } catch {
            print("❌ Share link error: \(error)")
            throw error
        }
    }

    // MARK: - Utility Functions

    private func saveToTemporaryFile(data: Data, fileName: String) throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(fileName)

        try data.write(to: fileURL)
        return fileURL
    }

    func setError(_ message: String) {
        errorMessage = message
    }

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Error Types

enum ReportExportError: LocalizedError {
    case invalidResponse
    case networkError(String)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError(let message):
            return "Network error: \(message)"
        case .fileSystemError(let message):
            return "File system error: \(message)"
        }
    }
}

// MARK: - Supporting Views for Email and Share Link Generation

struct EmailComposerView: View {
    @Binding var recipients: [String]
    @Binding var subject: String
    @Binding var message: String
    let report: ParentReport
    let onSend: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Recipients Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recipients")
                            .font(.headline)

                        ForEach(recipients.indices, id: \.self) { index in
                            HStack {
                                TextField("Email address", text: $recipients[index])
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)

                                if recipients.count > 1 {
                                    Button(action: { removeRecipient(at: index) }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }

                        if recipients.count < 5 {
                            Button(action: addRecipient) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Recipient")
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }

                    // Subject Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subject")
                            .font(.headline)

                        TextField("Email subject", text: $subject)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    // Message Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message (Optional)")
                            .font(.headline)

                        TextEditor(text: $message)
                            .frame(minHeight: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }

                    // Report Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report Details")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report: \(report.reportTitle)")
                            Text("Period: \(formatDate(report.startDate)) - \(formatDate(report.endDate))")
                            Text("Type: \(report.reportType.rawValue.capitalized)")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Email Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        onSend()
                    }
                    .disabled(recipients.filter { !$0.isEmpty && isValidEmail($0) }.isEmpty)
                }
            }
        }
        .onAppear {
            setupDefaultValues()
        }
    }

    private func addRecipient() {
        recipients.append("")
    }

    private func removeRecipient(at index: Int) {
        recipients.remove(at: index)
    }

    private func setupDefaultValues() {
        if subject.isEmpty {
            subject = "StudyAI Progress Report - \(report.reportType.rawValue.capitalized)"
        }
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct ShareLinkGeneratorView: View {
    let report: ParentReport
    let onGenerated: (ShareLinkData) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var expiryDays = 7
    @State private var maxAccess: String = ""
    @State private var password: String = ""
    @State private var isGenerating = false
    @StateObject private var exportService = ReportExportService()

    private let expiryOptions = [1, 3, 7, 14, 30]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Expiry Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Link Expiry")
                            .font(.headline)

                        Picker("Expiry", selection: $expiryDays) {
                            ForEach(expiryOptions, id: \.self) { days in
                                Text("\(days) day\(days == 1 ? "" : "s")")
                                    .tag(days)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }

                    // Access Limit
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Access Limit (Optional)")
                            .font(.headline)

                        TextField("Maximum number of views", text: $maxAccess)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)

                        Text("Leave empty for unlimited access")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Password Protection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password Protection (Optional)")
                            .font(.headline)

                        SecureField("Password", text: $password)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Text("Add a password for extra security")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Report Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Report Details")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Report: \(report.reportTitle)")
                            Text("Period: \(formatDate(report.startDate)) - \(formatDate(report.endDate))")
                            Text("Type: \(report.reportType.rawValue.capitalized)")
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }

                    // Generate Button
                    Button(action: generateLink) {
                        HStack {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "link")
                            }
                            Text(isGenerating ? "Generating..." : "Generate Share Link")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isGenerating)
                }
                .padding()
            }
            .navigationTitle("Share Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: .constant(exportService.errorMessage != nil)) {
            Button("OK") {
                exportService.clearError()
            }
        } message: {
            Text(exportService.errorMessage ?? "")
        }
    }

    private func generateLink() {
        isGenerating = true

        Task {
            do {
                let maxAccessInt = maxAccess.isEmpty ? nil : Int(maxAccess)
                let passwordValue = password.isEmpty ? nil : password

                let shareLink = try await exportService.generateShareLink(
                    reportId: report.id,
                    expiryDays: expiryDays,
                    maxAccess: maxAccessInt,
                    password: passwordValue
                )

                await MainActor.run {
                    onGenerated(shareLink)
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    exportService.setError(error.localizedDescription)
                    isGenerating = false
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Activity View Controller for System Share Sheet

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {}
}