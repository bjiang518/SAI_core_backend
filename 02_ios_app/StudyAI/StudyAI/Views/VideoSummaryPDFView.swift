import SwiftUI
import PDFKit
import WebKit

// MARK: - PDF Generator (lives outside SwiftUI hierarchy to avoid AttributeGraph cycles)

@MainActor
final class PDFGenerator: NSObject, WKNavigationDelegate {
    static let shared = PDFGenerator()

    private var webView: WKWebView?
    private var completion: ((Data?) -> Void)?
    private var didComplete = false

    private override init() { super.init() }

    func generate(html: String, completion: @escaping (Data?) -> Void) {
        didComplete = false
        self.completion = completion
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        wv.navigationDelegate = self
        self.webView = wv
        wv.loadHTMLString(html, baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard !self.didComplete else { return }
            // Wait for CSS/MathJax to finish rendering
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !self.didComplete else { return }
            self.didComplete = true

            // Measure actual content height so the PDF has no empty whitespace
            let heightStr = try? await webView.evaluateJavaScript(
                "Math.ceil(document.documentElement.scrollHeight)"
            )
            let contentHeight = (heightStr as? NSNumber).map { CGFloat($0.doubleValue) } ?? 842

            // Resize WebView to actual content before capturing
            webView.frame = CGRect(x: 0, y: 0, width: 612, height: contentHeight)

            // Small settle delay after resize
            try? await Task.sleep(nanoseconds: 200_000_000)

            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 612, height: contentHeight)
            webView.createPDF(configuration: config) { [weak self] result in
                Task { @MainActor in
                    self?.completion?(try? result.get())
                    self?.webView = nil
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            guard !self.didComplete else { return }
            self.didComplete = true
            self.completion?(nil)
            self.webView = nil
        }
    }
}

// MARK: - PDF View

struct VideoSummaryPDFView: View {
    let html: String
    let videoTitle: String

    @Environment(\.dismiss) private var dismiss
    // Store pdfData and pdfDocument as @State so they are created once, not on every render
    @State private var pdfData: Data? = nil
    @State private var pdfDocument: PDFDocument? = nil
    @State private var isRendering = true
    @State private var renderFailed = false
    @State private var showShareSheet = false
    @State private var savedConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if isRendering {
                    VStack(spacing: 14) {
                        ProgressView().scaleEffect(1.2)
                        Text(NSLocalizedString("pdf.generating", value: "Generating PDF…", comment: ""))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if renderFailed || pdfDocument == nil {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text(NSLocalizedString("pdf.failed", value: "Could not generate PDF", comment: ""))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let doc = pdfDocument {
                    PDFKitView(document: doc)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.done", value: "Done", comment: "")) { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if pdfData != nil {
                        Button { saveToFiles() } label: {
                            Image(systemName: savedConfirm ? "checkmark.circle.fill" : "tray.and.arrow.down")
                                .foregroundColor(savedConfirm ? .green : .primary)
                        }
                        Button { showShareSheet = true } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = pdfData {
                    ShareSheet(items: [tempPDFURL(data: data)])
                }
            }
            .overlay(alignment: .bottom) {
                if savedConfirm {
                    Text(NSLocalizedString("pdf.saved", value: "Saved to Files", comment: ""))
                        .font(.footnote.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: savedConfirm)
        }
        .onAppear {
            Task { @MainActor in
                PDFGenerator.shared.generate(html: html) { data in
                    pdfData = data
                    // Create PDFDocument once here, not in the view body
                    if let data {
                        pdfDocument = PDFDocument(data: data)
                    }
                    isRendering = false
                    renderFailed = data == nil
                }
            }
        }
    }

    private func saveToFiles() {
        guard let data = pdfData else { return }
        let url = tempPDFURL(data: data)
        let destDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dest = destDir.appendingPathComponent(url.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            withAnimation { savedConfirm = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { savedConfirm = false }
            }
        } catch {
            AppLogger.network.error("PDF save failed: \(error.localizedDescription)")
        }
    }

    private func tempPDFURL(data: Data) -> URL {
        let safe = String(
            videoTitle
                .components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "_")
                .prefix(60)
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        try? data.write(to: url)
        return url
    }
}
