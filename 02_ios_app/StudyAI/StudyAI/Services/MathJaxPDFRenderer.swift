//
//  MathJaxPDFRenderer.swift
//  StudyAI
//
//  Renders a text block (possibly containing LaTeX) to a UIImage using a
//  headless WKWebView + the bundled mathjax.min.js.
//
//  Usage:
//    let renderer = MathJaxPDFRenderer()
//    let image = await renderer.render("Solve \(2x + 3 = 11\)", width: 504, fontSize: 14)
//
//  Must be called on the MainActor (WKWebView requires the main thread).
//

import UIKit
import WebKit

@MainActor
final class MathJaxPDFRenderer: NSObject {

    // MARK: - Shared pool (one WebView, serialised)

    static let shared = MathJaxPDFRenderer()

    private let log = AppLogger.forFeature("MathJaxPDF")

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var pendingWidth: CGFloat = 504
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Public API

    /// Renders `text` (may contain LaTeX / Markdown) to a UIImage at `scale` (default 2×).
    /// - Parameters:
    ///   - text:      Content to render — can contain `\(…\)`, `\[…\]`, `$$`, `$` LaTeX.
    ///   - width:     Pixel-exact content width the WebView should use (match PDF content width × scale).
    ///   - fontSize:  Base font size in points.
    ///   - scale:     Snapshot scale factor (2 = @2x, good for 144 DPI PDF).
    /// - Returns: Rendered UIImage, or nil on timeout / error.
    func render(
        _ text: String,
        width: CGFloat,
        fontSize: CGFloat = 14,
        scale: CGFloat = 2
    ) async -> UIImage? {
        pendingWidth = width * scale

        log.info("▶︎ render() called — width=\(width)pt scaled=\(pendingWidth)px fontSize=\(fontSize)pt text.prefix(80)='\(text.prefix(80))'")

        // Check mathjax.min.js bundle presence
        if let mjURL = Bundle.main.url(forResource: "mathjax.min", withExtension: "js") {
            log.info("  ✓ mathjax.min.js found in bundle: \(mjURL.path)")
        } else {
            log.warning("  ⚠️ mathjax.min.js NOT found in bundle — will fall back to CDN (network required)")
        }

        let wv = makeWebView(width: pendingWidth)
        self.webView = wv

        if wv.superview == nil {
            log.warning("  ⚠️ WebView has NO superview — takeSnapshot may fail without a window attachment")
        } else {
            log.info("  ✓ WebView attached to window superview")
        }

        let html = makeHTML(text: text, fontSize: fontSize * scale)
        let baseURL = Bundle.main.resourceURL
        log.info("  loadHTMLString() — baseURL=\(baseURL?.path ?? "nil") html.count=\(html.count)")
        wv.loadHTMLString(html, baseURL: baseURL)

        // Arm a 10-second timeout so the continuation always resumes
        let capturedLog = log
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                capturedLog.error("  ⏱️ TIMEOUT — mathJaxReady never fired after 10 s. Resuming with nil.")
                self?.cleanup()
                self?.resume(nil)
            }
        }

        // Await the mathJaxReady + resize signal, then snapshot
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    // MARK: - WebView factory

    private func makeWebView(width: CGFloat) -> WKWebView {
        let ucc = WKUserContentController()
        ucc.add(self, name: "mathJaxReady")
        ucc.add(self, name: "resize")
        ucc.add(self, name: "jsError")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc

        // Suppress GPU process crash noise on simulator
        cfg.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let wv = WKWebView(
            frame: CGRect(x: 0, y: 0, width: width, height: 100),
            configuration: cfg
        )
        wv.isOpaque = false
        wv.backgroundColor = .white
        wv.scrollView.backgroundColor = .white
        wv.scrollView.isScrollEnabled = false

        // Wire up navigation + UI delegates for diagnostics
        wv.navigationDelegate = self
        wv.uiDelegate = self

        // Must be in a window for takeSnapshot to work
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            wv.frame.origin = CGPoint(x: -width - 100, y: 0)   // offscreen
            window.addSubview(wv)
            log.info("  makeWebView — added offscreen to window (x=\(-width - 100))")
        } else {
            log.error("  makeWebView — ❌ could not find a UIWindow to attach WebView")
        }

        return wv
    }

    // MARK: - HTML template (white background, matches MathJaxRenderer's MathJax config)

    private func makeHTML(text: String, fontSize: CGFloat) -> String {
        let scriptTag: String
        if let url = Bundle.main.url(forResource: "mathjax.min", withExtension: "js") {
            scriptTag = "<script src=\"\(url.absoluteString)\"></script>"
        } else {
            scriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-chtml.min.js\"></script>"
        }

        // Escape for HTML but preserve LaTeX delimiters
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            // Restore LaTeX delimiters that got escaped
            .replacingOccurrences(of: "\\(", with: "\\(")
            .replacingOccurrences(of: "\\)", with: "\\)")
            .replacingOccurrences(of: "\\[", with: "\\[")
            .replacingOccurrences(of: "\\]", with: "\\]")
            .replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <script>
        // Forward JS errors to Swift for diagnostics
        window.onerror = function(msg, src, line, col, err) {
            try {
                window.webkit.messageHandlers.jsError.postMessage(
                    'JS error: ' + msg + ' at ' + src + ':' + line
                );
            } catch(e) {}
            return false;
        };
        MathJax = {
            tex: {
                inlineMath:  [['\\\\(','\\\\)'],['$','$']],
                displayMath: [['\\\\[','\\\\]'],['$$','$$']],
                processEscapes: true,
                processEnvironments: true
            },
            options: { skipHtmlTags: ['script','noscript','style','textarea','pre'] },
            startup: {
                ready() {
                    MathJax.startup.defaultReady();
                    MathJax.startup.promise.then(() => {
                        var h = document.body.scrollHeight;
                        window.webkit.messageHandlers.resize.postMessage(h);
                        window.webkit.messageHandlers.mathJaxReady.postMessage('ready');
                    }).catch(function(err) {
                        try {
                            window.webkit.messageHandlers.jsError.postMessage('MathJax promise rejected: ' + err);
                        } catch(e) {}
                    });
                }
            }
        };
        </script>
        \(scriptTag)
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        html, body {
            background: #ffffff !important;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
            font-size: \(fontSize)px;
            line-height: 1.5;
            color: #000000;
            word-wrap: break-word;
        }
        mjx-container { color: #000000 !important; background: transparent !important; }
        mjx-container[display="true"] { display:block !important; text-align:left; margin: 0.3em 0 !important; }
        </style>
        </head>
        <body><div id="content">\(escaped)</div></body>
        </html>
        """
    }

    // MARK: - Snapshot after MathJax is ready

    private func takeSnapshot(height: CGFloat) {
        guard let wv = webView else {
            log.error("  takeSnapshot — webView is nil, resuming nil")
            resume(nil)
            return
        }

        // Resize WebView to exact rendered height before snapshotting
        wv.frame.size.height = height
        log.info("  takeSnapshot — frame=\(wv.frame) contentSize=\(wv.scrollView.contentSize)")

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: wv.frame.width, height: height)
        config.snapshotWidth = NSNumber(value: Double(wv.frame.width) / 2.0)  // divide by scale to get pt-sized image

        wv.takeSnapshot(with: config) { [weak self] image, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log.error("  takeSnapshot callback — ❌ error: \(error)")
                } else if let image = image {
                    self?.log.info("  takeSnapshot callback — ✓ image size=\(image.size) scale=\(image.scale)")
                } else {
                    self?.log.error("  takeSnapshot callback — ❌ both image and error are nil")
                }
                self?.cleanup()
                self?.resume(image)
            }
        }
    }

    private func resume(_ image: UIImage?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: image)
        continuation = nil
        log.info("  resume() — image=\(image != nil ? "✓" : "nil")")
    }

    private func cleanup() {
        webView?.removeFromSuperview()
        webView = nil
        log.info("  cleanup() — webView removed from superview")
    }
}

// MARK: - WKScriptMessageHandler

extension MathJaxPDFRenderer: WKScriptMessageHandler {
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "mathJaxReady":
            log.info("  ✓ mathJaxReady received")
            guard let wv = webView else { resume(nil); return }
            let height = max(wv.scrollView.contentSize.height, 20)
            log.info("  → taking snapshot at height=\(height)")
            takeSnapshot(height: height)

        case "resize":
            if let h = message.body as? CGFloat {
                log.info("  resize message — h=\(h)")
                webView?.frame.size.height = max(h, 20)
            } else if let h = message.body as? Double {
                log.info("  resize message (Double) — h=\(h)")
                webView?.frame.size.height = max(CGFloat(h), 20)
            } else {
                log.warning("  resize message — unexpected body type: \(type(of: message.body)) value=\(message.body)")
            }

        case "jsError":
            log.error("  ❌ jsError from page: \(message.body)")

        default:
            log.warning("  unknown message: \(message.name)")
        }
    }
}

// MARK: - WKNavigationDelegate (diagnostics)

extension MathJaxPDFRenderer: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        log.info("  nav: didStartProvisionalNavigation")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        log.info("  nav: didCommit")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log.info("  nav: didFinish — page loaded. Waiting for mathJaxReady message…")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log.error("  nav: didFail — \(error)")
        cleanup()
        resume(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("  nav: didFailProvisionalNavigation — \(error)")
        cleanup()
        resume(nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("  ❌ webViewWebContentProcessDidTerminate — web content process crashed (likely missing entitlement: com.apple.developer.web-browser-engine.webcontent). Resuming nil.")
        cleanup()
        resume(nil)
    }
}

// MARK: - WKUIDelegate (diagnostics)

extension MathJaxPDFRenderer: WKUIDelegate {

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        log.info("  JS alert: \(message)")
        completionHandler()
    }
}
