//
//  HTMLRendererView.swift
//  StudyAI
//
//  Created by Claude Code on 11/10/25.
//

import SwiftUI
import WebKit

/// Renders HTML content using WKWebView with mobile optimization
/// Perfect for displaying LaTeX-converted grammar corrections
struct HTMLRendererView: UIViewRepresentable {
    let htmlContent: String
    let dynamicHeight: Bool
    @Binding var contentHeight: CGFloat

    init(htmlContent: String, dynamicHeight: Bool = true, contentHeight: Binding<CGFloat> = .constant(100)) {
        self.htmlContent = htmlContent
        self.dynamicHeight = dynamicHeight
        self._contentHeight = contentHeight
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        // Disable zoom and user interaction (read-only)
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLRendererView

        init(parent: HTMLRendererView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Calculate dynamic height after content loads
            if parent.dynamicHeight {
                webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, error in
                    if let height = result as? CGFloat {
                        DispatchQueue.main.async {
                            self.parent.contentHeight = height
                        }
                    }
                }
            }
        }
    }
}

/// Simple wrapper for displaying LaTeX-formatted text as HTML
struct LaTeXHTMLView: View {
    let latexString: String
    @State private var htmlHeight: CGFloat = 100

    var body: some View {
        HTMLRendererView(
            htmlContent: LaTeXToHTMLConverter.shared.convertToHTML(latexString),
            dynamicHeight: true,
            contentHeight: $htmlHeight
        )
        .frame(height: htmlHeight)
    }
}

// MARK: - Preview

struct HTMLRendererView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Example 1: Grammar correction
            LaTeXHTMLView(
                latexString: "The student \\sout{went} \\textcolor{green}{goes} to school yesterday."
            )
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)

            // Example 2: Multiple corrections
            LaTeXHTMLView(
                latexString: "She \\sout{dont} \\textcolor{green}{doesn't} like \\sout{it} \\textcolor{green}{them}."
            )
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)

            // Example 3: With error highlighting
            LaTeXHTMLView(
                latexString: "This is \\textcolor{red}{wrong} but this is \\textcolor{green}{correct}."
            )
            .padding()
            .background(Color.blue.opacity(0.05))
            .cornerRadius(12)
        }
        .padding()
    }
}
