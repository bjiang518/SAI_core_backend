//
//  MathJaxRenderer.swift
//  StudyAI
//
//  Unified math + markdown rendering using bundled MathJax.
//
//  Architecture (simple):
//  - Static content  → MathWebView (WKWebView + local mathjax.min.js)
//  - Streaming       → plain Text() — no math rendering while AI is typing
//  - On stream end   → swap to MathWebView once, cleanly
//
//  Public API (all call sites unchanged):
//    SmartLaTeXView(text, fontSize:, colorScheme:, strategy:)
//    FullLaTeXText(text, fontSize:, strategy:, isStreaming:)
//    MarkdownLaTeXText(text, fontSize:, isStreaming:)
//    MathRenderStrategy  (enum — kept for source compatibility, value ignored)
//    MathJaxConfig       (struct — kept for source compatibility)
//    FullLaTeXRenderer   (class — kept for source compatibility)
//

import SwiftUI
import WebKit
import Combine

// MARK: - Source-compatibility stubs (kept so existing call sites compile unchanged)

public struct MathJaxConfig {}

public enum MathRenderStrategy {
    case mathjax, simplified, auto
}

@MainActor
public class FullLaTeXRenderer: ObservableObject {
    public static let shared = FullLaTeXRenderer()
    @Published public var isReady = true
    private init() {}
}

// MARK: - Bundled MathJax HTML generator

private enum MathHTML {

    /// Returns the full HTML page string for rendering `content` with the
    /// locally-bundled mathjax.min.js.  Falls back to CDN if the bundle file
    /// is missing (should never happen in production).
    static func page(content: String, fontSize: CGFloat, colorScheme: ColorScheme) -> String {
        let textColor  = colorScheme == .dark ? "#FFFFFF" : "#000000"
        let scriptTag: String
        if let url = Bundle.main.url(forResource: "mathjax.min", withExtension: "js") {
            scriptTag = "<script src=\"\(url.absoluteString)\"></script>"
        } else {
            // CDN fallback — only used if bundle file is missing
            scriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mathjax@3.2.2/es5/tex-chtml.min.js\"></script>"
        }

        // Protect LaTeX blocks, convert markdown to HTML, then restore LaTeX
        let bodyHTML = convertToHTML(content)

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <script>
        MathJax = {
            tex: {
                inlineMath:  [['\\\\(','\\\\)'],['$','$']],
                displayMath: [['\\\\[','\\\\]'],['$$','$$']],
                processEscapes: true,
                processEnvironments: true
            },
            options: {
                skipHtmlTags: ['script','noscript','style','textarea','pre']
            },
            startup: {
                ready() {
                    MathJax.startup.defaultReady();
                    MathJax.startup.promise.then(() => {
                        window.webkit.messageHandlers.mathJaxReady.postMessage('ready');
                    });
                }
            }
        };
        </script>
        \(scriptTag)
        <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        html, body { background:transparent !important; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
            font-size: \(fontSize)px;
            line-height: 1.6;
            color: \(textColor) !important;
            word-wrap: break-word;
        }
        h1,h2,h3,h4,h5,h6 { color:\(textColor) !important; font-weight:bold; margin:0.4em 0 0.2em 0; }
        h1{font-size:1.8em} h2{font-size:1.5em} h3{font-size:1.3em}
        h4{font-size:1.1em} h5,h6{font-size:1em}
        strong { font-weight:bold; }
        em     { font-style:italic; }
        ul,ol  { padding-left:1.4em; margin:0.3em 0; }
        li     { margin:0.15em 0; }
        mjx-container { color:\(textColor) !important; background:transparent !important; }
        mjx-container[display="true"] { display:block !important; text-align:center; margin:0.3em 0 !important; }
        </style>
        </head>
        <body>
        <div id="content">\(bodyHTML)</div>
        <script>
        function updateHeight() {
            var h = document.getElementById('content').scrollHeight;
            window.webkit.messageHandlers.resize.postMessage(h);
        }
        // Measure only after MathJax finishes typesetting.
        // Avoids reading scrollHeight during intermediate render passes
        // where MathJax inserts temporary elements that inflate the height.
        MathJax.startup.promise.then(function() {
            setTimeout(updateHeight, 50);
        });
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Markdown → HTML (LaTeX delimiters protected throughout)

    private static func convertToHTML(_ input: String) -> String {
        var text = input

        // 1. Extract and protect LaTeX blocks with placeholders
        var latexBlocks: [String] = []
        let placeholder = "LATEX_BLOCK_"

        let latexPatterns: [(String, NSRegularExpression.Options)] = [
            ("\\$\\$[\\s\\S]*?\\$\\$",              .init()),     // $$...$$
            ("\\\\\\[[\\s\\S]*?\\\\\\]",             .init()),     // \[...\]
            ("\\\\\\([\\s\\S]*?\\\\\\)",             .init()),     // \(...\)
            ("\\$(?!\\$)[^$\n]+?(?<!\\$)\\$",        .init()),     // $...$
        ]

        for (pattern, opts) in latexPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: opts) else { continue }
            let ns = NSRange(location: 0, length: text.utf16.count)
            let matches = regex.matches(in: text, options: [], range: ns).reversed()
            for match in matches {
                guard let range = Range(match.range, in: text) else { continue }
                latexBlocks.insert(String(text[range]), at: 0)
                let idx = latexBlocks.count - 1
                text.replaceSubrange(range, with: "\(placeholder)\(idx)END")
            }
        }

        // 2. Convert markdown to HTML
        // Headers
        for level in (1...6).reversed() {
            let hashes = String(repeating: "#", count: level)
            if let re = try? NSRegularExpression(pattern: "^\(hashes)\\s+(.+)$", options: .anchorsMatchLines) {
                text = re.stringByReplacingMatches(
                    in: text, range: NSRange(location: 0, length: text.utf16.count),
                    withTemplate: "<h\(level)>$1</h\(level)>")
            }
        }
        // Bold
        if let re = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            text = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: "<strong>$1</strong>")
        }
        // Italic
        if let re = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)") {
            text = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: "<em>$1</em>")
        }
        // Unordered list items
        if let re = try? NSRegularExpression(pattern: "^[-*+]\\s+(.+)$", options: .anchorsMatchLines) {
            text = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: text.utf16.count),
                withTemplate: "<li>$1</li>")
        }
        // Newlines to <br>
        text = text.replacingOccurrences(of: "\n", with: "<br>")

        // 3. Restore LaTeX blocks
        for (idx, block) in latexBlocks.enumerated() {
            text = text.replacingOccurrences(of: "\(placeholder)\(idx)END", with: block)
        }

        return text
    }
}

// MARK: - WKWebView component

struct MathWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    @Binding var isReady: Bool

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MathWebView
        var loadedHTML = ""
        init(_ parent: MathWebView) { self.parent = parent }

        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            DispatchQueue.main.async {
                if message.name == "resize", let h = message.body as? CGFloat, abs(h - self.parent.height) > 1 {
                    self.parent.height = h
                } else if message.name == "mathJaxReady" {
                    self.parent.isReady = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("📐 [MathJax] ❌ \(error.localizedDescription)")
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "resize")
        ucc.add(context.coordinator, name: "mathJaxReady")
        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        return wv
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard html != context.coordinator.loadedHTML else { return }
        context.coordinator.loadedHTML = html
        // Load from bundle baseURL so local file:// mathjax.min.js script src resolves
        let baseURL = Bundle.main.resourceURL
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}

// MARK: - Core rendering view

/// Internal view used by all public wrappers.
/// - `isStreaming = true`  → plain Text, no WebView allocated
/// - `isStreaming = false` → MathJax WebView
private struct MathContentView: View {
    let content: String
    let fontSize: CGFloat
    let isStreaming: Bool

    @Environment(\.colorScheme) var colorScheme
    @State private var webViewHeight: CGFloat = 50
    @State private var mathReady = false

    var body: some View {
        if isStreaming {
            // Plain text while AI is typing — no WebView overhead
            Text(content)
                .font(.system(size: fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            // Single WebView, loaded once when streaming ends
            ZStack(alignment: .topLeading) {
                // Invisible placeholder keeps layout stable while MathJax typsets
                if !mathReady {
                    Text(content)
                        .font(.system(size: fontSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(0.35)
                }
                MathWebView(
                    html: MathHTML.page(content: content, fontSize: fontSize, colorScheme: colorScheme),
                    height: $webViewHeight,
                    isReady: $mathReady
                )
                .frame(height: mathReady ? max(webViewHeight, 20) : 0)
                .opacity(mathReady ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Public API  (all existing call sites work unchanged)

/// Used in: MistakeReviewView, QuestionDetailView, GeneratedQuestionsListView, MistakeGroupDetailView, WeaknessPracticeView
public struct SmartLaTeXView: View {
    let content: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme
    let strategy: MathRenderStrategy   // kept for API compatibility, not used

    public init(_ content: String, fontSize: CGFloat = 16,
                colorScheme: ColorScheme = .light,
                strategy: MathRenderStrategy = .auto) {
        self.content = content
        self.fontSize = fontSize
        self.colorScheme = colorScheme
        self.strategy = strategy
    }

    public var body: some View {
        MathContentView(content: content, fontSize: fontSize, isStreaming: false)
    }
}

/// Used in: DigitalHomeworkView, UnifiedLibraryView, SavedDigitalHomeworkView, MessageBubbles
public struct FullLaTeXText: View {
    let content: String
    let fontSize: CGFloat
    let strategy: MathRenderStrategy   // kept for API compatibility, not used
    let isStreaming: Bool

    public init(_ content: String, fontSize: CGFloat = 16,
                strategy: MathRenderStrategy = .auto,
                isStreaming: Bool = false) {
        self.content = content
        self.fontSize = fontSize
        self.strategy = strategy
        self.isStreaming = isStreaming
    }

    /// Returns true if content contains any LaTeX math markers.
    /// If false, a plain Text() is used instead — no WKWebView spawned.
    private var containsLatex: Bool {
        content.contains("$") ||
        content.contains("\\[") ||
        content.contains("\\(") ||
        content.contains("\\frac") ||
        content.contains("\\sqrt") ||
        content.contains("\\sum")
    }

    public var body: some View {
        if containsLatex {
            MathContentView(content: content, fontSize: fontSize, isStreaming: isStreaming)
        } else {
            Text(content)
                .font(.system(size: fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Used in: HomeworkResultsView, MessageBubbles, DiagramMessageView
public struct MarkdownLaTeXText: View {
    let content: String
    let fontSize: CGFloat
    let isStreaming: Bool

    public init(_ content: String, fontSize: CGFloat = 16, isStreaming: Bool = false) {
        self.content = content
        self.fontSize = fontSize
        self.isStreaming = isStreaming
    }

    private var containsLatexOrMarkdown: Bool {
        content.contains("$") ||
        content.contains("\\[") ||
        content.contains("\\(") ||
        content.contains("\\frac") ||
        content.contains("\\sqrt") ||
        content.contains("**") ||
        content.contains("##") ||
        content.contains("- ")
    }

    public var body: some View {
        if containsLatexOrMarkdown {
            MathContentView(content: content, fontSize: fontSize, isStreaming: isStreaming)
        } else {
            Text(content)
                .font(.system(size: fontSize))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Legacy aliases (kept so any remaining MathFormattedText / MixedLaTeXView references compile)

typealias MixedLaTeXView     = FullLaTeXText
typealias MathJaxWebView     = MathWebView
enum MixedContentComponent { case text(String), math(String, isDisplay: Bool) }
