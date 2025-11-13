//
//  MathJaxRenderer.swift
//  StudyAI
//
//  Full LaTeX math rendering using MathJax with fallback to simplified renderer
//  Created by Claude Code
//

import SwiftUI
import WebKit
import Combine

// MARK: - MathJax Configuration

/// Configuration for MathJax rendering
struct MathJaxConfig {
    /// MathJax version to use (recommend latest stable)
    let mathjaxVersion = "3.2.2"

    /// Delimiters for inline and display math
    let inlineDelimiters: [(String, String)] = [
        ("\\(", "\\)"),  // LaTeX inline (primary)
        ("$", "$")       // Legacy inline (fallback)
    ]

    let displayDelimiters: [(String, String)] = [
        ("\\[", "\\]"),  // LaTeX display (primary)
        ("$$", "$$")     // Legacy display (fallback)
    ]

    /// CDN URL for MathJax
    var mathjaxURL: String {
        "https://cdn.jsdelivr.net/npm/mathjax@\(mathjaxVersion)/es5/tex-mml-chtml.js"
    }

    /// Timeout for rendering (seconds)
    let renderTimeout: TimeInterval = 3.0

    /// Font size for math rendering
    let fontSize: CGFloat = 16
}

// MARK: - Math Renderer Strategy

/// Strategy pattern for math rendering with fallback
enum MathRenderStrategy {
    case mathjax       // Full LaTeX via MathJax (primary)
    case simplified    // Unicode conversion (fallback)
    case auto          // Auto-detect and choose best strategy
}

// MARK: - Full LaTeX Renderer with MathJax

@MainActor
class FullLaTeXRenderer: ObservableObject {
    static let shared = FullLaTeXRenderer()

    @Published var isReady = false
    @Published var renderingStrategy: MathRenderStrategy = .auto

    private let config = MathJaxConfig()
    private var mathjaxAvailable = true

    private init() {
        print("📐 [MathJax] FullLaTeXRenderer initialized")
        // Check if MathJax is available (network connectivity)
        checkMathJaxAvailability()
    }

    /// Check if MathJax CDN is accessible
    private func checkMathJaxAvailability() {
        print("📐 [MathJax] Checking CDN availability...")
        Task {
            do {
                let url = URL(string: "https://cdn.jsdelivr.net")!
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    mathjaxAvailable = (200...299).contains(httpResponse.statusCode)
                    print("📐 [MathJax] CDN check: status \(httpResponse.statusCode), available: \(mathjaxAvailable)")
                }
            } catch {
                mathjaxAvailable = false
                print("📐 [MathJax] CDN check failed: \(error.localizedDescription)")
            }
            isReady = true
            print("📐 [MathJax] Renderer ready, MathJax available: \(mathjaxAvailable)")
        }
    }

    // MARK: - Optimized Pattern Detection

    // Pre-compiled regex pattern (compiled once, reused for all detections)
    // Match LaTeX that's PROPERLY DELIMITED or uses LaTeX environments/commands
    private static let latexPattern: NSRegularExpression? = {
        // Match: display math delimiters, inline math delimiters, or LaTeX environments
        // This ensures we only trigger MathJax when LaTeX is properly formatted
        let pattern = """
        \\\\\\[.*?\\\\\\]|\
        \\$\\$.*?\\$\\$|\
        \\\\\\(.*?\\\\\\)|\
        \\$(?!\\$).*?(?<!\\$)\\$|\
        \\\\begin\\{[^}]+\\}.*?\\\\end\\{[^}]+\\}|\
        \\\\frac\\{|\\\\sqrt\\{|\\\\int|\\\\sum|\\\\prod|\\\\lim
        """
        return try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }()

    /// Determine best rendering strategy based on content complexity
    func determineStrategy(for content: String) -> MathRenderStrategy {
        // Fast path: check forced strategy first
        if renderingStrategy != .auto {
            return renderingStrategy
        }

        // Optimized: single regex test instead of 68 separate tests
        guard let regex = FullLaTeXRenderer.latexPattern else {
            print("📐 [MathJax] ⚠️ Regex compilation failed, using simplified")
            return .simplified
        }

        let range = NSRange(location: 0, length: content.utf16.count)
        let hasLaTeX = regex.firstMatch(in: content, options: [], range: range) != nil

        let strategy: MathRenderStrategy = hasLaTeX && mathjaxAvailable ? .mathjax : .simplified

        #if DEBUG
        // Only log in debug builds
        if hasLaTeX {
            print("📐 [MathJax] ✅ LaTeX detected (length: \(content.count)) → Strategy: \(strategy)")
        }
        #endif

        return strategy
    }

    /// Generate HTML for MathJax rendering
    func generateMathJaxHTML(
        content: String,
        fontSize: CGFloat = 16,
        colorScheme: ColorScheme = .light
    ) -> String {
        #if DEBUG
        // Only log in debug builds, and only minimal info
        print("📐 [MathJax] Generating HTML (length: \(content.count), size: \(fontSize))")
        #endif

        // Force white text in dark mode, black in light mode
        let textColor = colorScheme == .dark ? "#FFFFFF" : "#000000"

        // Preserve line breaks by converting \n to <br>
        // Escape HTML but preserve LaTeX delimiters and line breaks
        var escapedContent = content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Convert newlines to <br> for proper line breaks
        escapedContent = escapedContent.replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <script>
                MathJax = {
                    tex: {
                        inlineMath: [['\\\\(', '\\\\)'], ['$', '$']],
                        displayMath: [['\\\\[', '\\\\]'], ['$$', '$$']],
                        processEscapes: true,
                        processEnvironments: true,
                        tags: 'none'
                    },
                    options: {
                        skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre'],
                        ignoreHtmlClass: 'tex2jax_ignore',
                        processHtmlClass: 'tex2jax_process'
                    },
                    svg: {
                        fontCache: 'global',
                        scale: 1.2
                    },
                    startup: {
                        ready: () => {
                            MathJax.startup.defaultReady();
                            MathJax.startup.promise.then(() => {
                                window.webkit.messageHandlers.mathJaxReady.postMessage('ready');
                            });
                        }
                    }
                };
            </script>
            <script id="MathJax-script" async src="\(config.mathjaxURL)"></script>
            <style>
                * {
                    margin: 0;
                    padding: 0;
                    box-sizing: border-box;
                }
                html, body {
                    background-color: transparent !important;
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
                    font-size: \(fontSize)px;
                    line-height: 1.4;
                    color: \(textColor) !important;
                    padding: 0;
                    margin: 0;
                    -webkit-text-size-adjust: none;
                    -webkit-user-select: text;
                    user-select: text;
                    white-space: pre-wrap;
                    word-wrap: break-word;
                }
                .math-content {
                    overflow-x: auto;
                    overflow-y: hidden;
                    -webkit-overflow-scrolling: touch;
                    color: \(textColor) !important;
                    background-color: transparent !important;
                    padding: 0;
                    margin: 0;
                }
                mjx-container {
                    overflow-x: auto;
                    overflow-y: hidden;
                    display: inline-block !important;
                    max-width: 100%;
                    color: \(textColor) !important;
                    margin: 0.1em 0;
                    vertical-align: middle;
                }
                mjx-container[display="true"] {
                    display: block !important;
                    text-align: center;
                    margin: 0.2em 0;
                }
                /* Force text color in all elements */
                mjx-math, mjx-mtext, mjx-mi, mjx-mn, mjx-mo {
                    color: \(textColor) !important;
                }
                /* Ensure SVG elements use correct color */
                svg {
                    color: \(textColor) !important;
                }
                /* Make sure all backgrounds are transparent */
                mjx-container, mjx-math {
                    background-color: transparent !important;
                }
            </style>
        </head>
        <body>
            <div class="math-content">
                \(escapedContent)
            </div>
            <script>
                // Auto-resize when content changes
                function updateHeight() {
                    const height = document.body.scrollHeight;
                    window.webkit.messageHandlers.resize.postMessage(height);
                }

                // Observer for content changes
                const observer = new MutationObserver(updateHeight);
                observer.observe(document.body, {
                    childList: true,
                    subtree: true,
                    attributes: true,
                    characterData: true
                });

                // Initial height update
                setTimeout(updateHeight, 100);
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - MathJax WebView Component

struct MathJaxWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat
    @Binding var isLoading: Bool
    @Binding var error: String?

    let onReady: (() -> Void)?

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MathJaxWebView
        var lastLoadedHTML: String = "" // Track last loaded HTML to prevent re-rendering loops

        init(_ parent: MathJaxWebView) {
            self.parent = parent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "resize", let height = message.body as? CGFloat {
                // Optimization: only update if height changed significantly (avoid micro-updates)
                if abs(height - self.parent.height) > 1.0 {
                    DispatchQueue.main.async {
                        self.parent.height = height
                    }
                }
            } else if message.name == "mathJaxReady" {
                #if DEBUG
                print("📐 [MathJax] ✅ Ready")
                #endif
                DispatchQueue.main.async {
                    self.parent.isLoading = false
                    self.parent.onReady?()
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            didFinish navigation: WKNavigation!
        ) {
            // MathJax will call mathJaxReady when finished - no logging needed
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            // Only log errors
            print("📐 [MathJax] ❌ Error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.parent.error = error.localizedDescription
                self.parent.isLoading = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "resize")
        userContentController.add(context.coordinator, name: "mathJaxReady")
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only load HTML if it's different from what's currently loaded
        // This prevents infinite re-rendering loops
        if html != context.coordinator.lastLoadedHTML {
            webView.loadHTMLString(html, baseURL: nil)
            context.coordinator.lastLoadedHTML = html
        }
    }
}

// MARK: - Smart Math Renderer View with Fallback

struct SmartLaTeXView: View {
    let content: String
    let fontSize: CGFloat
    let colorScheme: ColorScheme
    let strategy: MathRenderStrategy

    @StateObject private var renderer = FullLaTeXRenderer.shared
    @State private var webViewHeight: CGFloat = 100
    @State private var isLoading = true
    @State private var renderError: String? = nil
    @State private var usesFallback = false
    @State private var actualStrategy: MathRenderStrategy = .mathjax

    init(
        _ content: String,
        fontSize: CGFloat = 16,
        colorScheme: ColorScheme = .light,
        strategy: MathRenderStrategy = .auto
    ) {
        self.content = content
        self.fontSize = fontSize
        self.colorScheme = colorScheme
        self.strategy = strategy
    }

    var body: some View {
        Group {
            if usesFallback {
                // Fallback to simplified renderer
                fallbackView
            } else if actualStrategy == .mathjax {
                // Primary MathJax renderer
                mathjaxView
            } else {
                // Direct simplified renderer (for simple equations)
                fallbackView
            }
        }
        .onAppear {
            determineRenderingStrategy()
        }
    }

    private var mathjaxView: some View {
        VStack {
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Rendering math...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 40)
            }

            // Generate HTML once (not during streaming since we removed onChange)
            let generatedHTML = renderer.generateMathJaxHTML(
                content: content,
                fontSize: fontSize,
                colorScheme: colorScheme
            )

            MathJaxWebView(
                html: generatedHTML,
                height: $webViewHeight,
                isLoading: $isLoading,
                error: $renderError,
                onReady: {
                    // Successfully rendered
                }
            )
            .frame(height: max(webViewHeight, 40))
            .opacity(isLoading ? 0 : 1)
        }
        .onAppear {
            // Set timeout for MathJax rendering
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                if isLoading {
                    // Timeout - fallback to simplified
                    usesFallback = true
                    isLoading = false
                }
            }
        }
        .onChange(of: renderError) { oldValue, newValue in
            if newValue != nil {
                usesFallback = true
            }
        }
    }

    private var fallbackView: some View {
        VStack(alignment: .leading) {
            if renderError != nil && !usesFallback {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("Using simplified renderer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 4)
            }

            // Use existing SimpleMathRenderer
            Text(SimpleMathRenderer.renderMathText(content))
                .font(.system(size: fontSize))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func determineRenderingStrategy() {
        actualStrategy = renderer.determineStrategy(for: content)

        // If strategy is simplified, skip MathJax entirely
        if actualStrategy == .simplified {
            usesFallback = true
            isLoading = false
        }
    }
}

// MARK: - Convenience SwiftUI View

/// Drop-in replacement for MathFormattedText with full LaTeX support
struct FullLaTeXText: View {
    let content: String
    let fontSize: CGFloat
    let strategy: MathRenderStrategy
    let isStreaming: Bool  // Track streaming state

    @Environment(\.colorScheme) var colorScheme
    @State private var hasDetectedLatex = false
    @State private var lastCheckedContent = ""  // Cache: avoid re-checking same content

    init(
        _ content: String,
        fontSize: CGFloat = 16,
        strategy: MathRenderStrategy = .auto,
        isStreaming: Bool = false
    ) {
        self.content = content
        self.fontSize = fontSize
        self.strategy = strategy
        self.isStreaming = isStreaming
    }

    var body: some View {
        // Remove expensive print from hot path
        Group {
            if isStreaming {
                streamingView
            } else if hasDetectedLatex {
                mathjaxView
            } else {
                simplifiedViewWithFinalCheck
            }
        }
    }

    @ViewBuilder
    private var streamingView: some View {
        Text(SimpleMathRenderer.renderMathText(content))
            .font(.system(size: fontSize))
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                detectLatexInContent()
            }
            .onChange(of: content) { oldValue, newValue in
                // Optimization: only check if content actually changed
                if newValue != lastCheckedContent {
                    detectLatexInContent()
                }
            }
    }

    @ViewBuilder
    private var mathjaxView: some View {
        SmartLaTeXView(
            content,
            fontSize: fontSize,
            colorScheme: colorScheme,
            strategy: strategy
        )
    }

    @ViewBuilder
    private var simplifiedViewWithFinalCheck: some View {
        Text(SimpleMathRenderer.renderMathText(content))
            .font(.system(size: fontSize))
            .foregroundColor(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear {
                // Final check only if content wasn't already checked
                if content != lastCheckedContent {
                    detectLatexInContent()
                }
            }
    }

    private func detectLatexInContent() {
        // Optimization: cache check to avoid redundant detection
        guard content != lastCheckedContent else { return }
        lastCheckedContent = content

        let renderer = FullLaTeXRenderer.shared
        let detectedStrategy = renderer.determineStrategy(for: content)

        if detectedStrategy == .mathjax {
            hasDetectedLatex = true
        }
    }
}

// MARK: - Mixed Content Parser (Text + Math)

extension FullLaTeXRenderer {
    /// Parse mixed content and render each component appropriately
    func parseMixedContent(_ text: String) -> [MixedContentComponent] {
        var components: [MixedContentComponent] = []
        let currentText = text

        // Find all math blocks (display and inline)
        let mathPattern = #"(\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)|\$\$[\s\S]*?\$\$|\$[^\$]+\$)"#

        guard let regex = try? NSRegularExpression(pattern: mathPattern, options: []) else {
            return [.text(text)]
        }

        let range = NSRange(location: 0, length: currentText.utf16.count)
        let matches = regex.matches(in: currentText, options: [], range: range)

        var lastIndex = currentText.startIndex

        for match in matches {
            guard let matchRange = Range(match.range, in: currentText) else { continue }

            // Add text before math
            if lastIndex < matchRange.lowerBound {
                let textPart = String(currentText[lastIndex..<matchRange.lowerBound])
                if !textPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    components.append(.text(textPart))
                }
            }

            // Add math component
            let mathPart = String(currentText[matchRange])
            let isDisplay = mathPart.hasPrefix("\\[") || mathPart.hasPrefix("$$")
            components.append(.math(mathPart, isDisplay: isDisplay))

            lastIndex = matchRange.upperBound
        }

        // Add remaining text
        if lastIndex < currentText.endIndex {
            let textPart = String(currentText[lastIndex...])
            if !textPart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                components.append(.text(textPart))
            }
        }

        return components.isEmpty ? [.text(text)] : components
    }
}

enum MixedContentComponent {
    case text(String)
    case math(String, isDisplay: Bool)
}

/// View for rendering mixed text and math content
struct MixedLaTeXView: View {
    let content: String
    let fontSize: CGFloat

    @StateObject private var renderer = FullLaTeXRenderer.shared

    init(_ content: String, fontSize: CGFloat = 16) {
        self.content = content
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(renderer.parseMixedContent(content).enumerated()), id: \.offset) { index, component in
                switch component {
                case .text(let text):
                    Text(text)
                        .font(.system(size: fontSize))
                        .fixedSize(horizontal: false, vertical: true)
                case .math(let math, let isDisplay):
                    FullLaTeXText(math, fontSize: fontSize)
                        .frame(maxWidth: .infinity, alignment: isDisplay ? .center : .leading)
                }
            }
        }
    }
}

// MARK: - Comprehensive Markdown + LaTeX Renderer

/// A view that renders both markdown formatting AND LaTeX math expressions
/// Supports:
/// - Markdown: **bold**, *italic*, ## headers, lists, links
/// - LaTeX: $math$, $$display math$$, \[...\], \(...\), Greek letters, equations
struct MarkdownLaTeXText: View {
    let content: String
    let fontSize: CGFloat
    let isStreaming: Bool

    @Environment(\.colorScheme) var colorScheme
    @State private var hasLaTeX = false
    @State private var lastCheckedContent = ""

    init(_ content: String, fontSize: CGFloat = 16, isStreaming: Bool = false) {
        self.content = content
        self.fontSize = fontSize
        self.isStreaming = isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // During streaming: show simplified view
            if isStreaming {
                streamingView
            }
            // Has LaTeX: render with MathJax
            else if hasLaTeX {
                mathjaxWithMarkdownView
            }
            // No LaTeX: pure markdown rendering
            else {
                markdownOnlyView
            }
        }
        .onAppear {
            if !isStreaming {
                detectLaTeX()
            }
        }
        .onChange(of: content) { oldValue, newValue in
            if !isStreaming && newValue != lastCheckedContent {
                detectLaTeX()
            }
        }
        .onChange(of: isStreaming) { oldValue, newValue in
            // When streaming completes, detect LaTeX in the final content
            if !newValue && oldValue {
                detectLaTeX()
            }
        }
    }

    // MARK: - Streaming View (Simple + Fast)

    @ViewBuilder
    private var streamingView: some View {
        // During streaming: use simple text with SimpleMathRenderer
        // NO MathJax, NO AttributedString markdown (which can fail on LaTeX delimiters)
        // Parse markdown manually for headers and lists
        let components = parseMarkdownComponents(content)

        ForEach(Array(components.enumerated()), id: \.offset) { index, component in
            renderStreamingComponent(component)
        }
    }

    @ViewBuilder
    private func renderStreamingComponent(_ component: MarkdownComponent) -> some View {
        switch component {
        case .header(let text, let level):
            renderHeader(text, level: level)
        case .text(let text):
            // Use SimpleMathRenderer for basic math rendering during streaming
            Text(SimpleMathRenderer.renderMathText(text))
                .font(.system(size: fontSize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            renderStreamingList(items)
        }
    }

    @ViewBuilder
    private func renderStreamingList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: fontSize))
                    Text(SimpleMathRenderer.renderMathText(item))
                        .font(.system(size: fontSize))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Markdown-Only View (No LaTeX Detected)

    @ViewBuilder
    private var markdownOnlyView: some View {
        // Parse and render full markdown (including headers, lists, etc.)
        let components = parseMarkdownComponents(content)

        ForEach(Array(components.enumerated()), id: \.offset) { index, component in
            renderMarkdownComponent(component)
        }
    }

    // MARK: - Markdown + LaTeX View (Both Detected)

    @ViewBuilder
    private var mathjaxWithMarkdownView: some View {
        // When LaTeX is detected, render the entire content with MathJax
        // MathJax can handle both markdown and LaTeX together
        SmartLaTeXView(content, fontSize: fontSize, colorScheme: colorScheme, strategy: .mathjax)
    }

    // MARK: - Component Rendering

    @ViewBuilder
    private func renderMarkdownComponent(_ component: MarkdownComponent) -> some View {
        switch component {
        case .header(let text, let level):
            renderHeader(text, level: level)
        case .text(let text):
            renderMarkdownText(text)
        case .list(let items):
            renderList(items)
        }
    }

    @ViewBuilder
    private func renderHeader(_ text: String, level: Int) -> some View {
        let headerSize: CGFloat = {
            switch level {
            case 1: return fontSize + 12  // # Largest
            case 2: return fontSize + 8   // ##
            case 3: return fontSize + 6   // ###
            case 4: return fontSize + 4   // ####
            case 5: return fontSize + 2   // #####
            case 6: return fontSize + 1   // ###### Smallest
            default: return fontSize
            }
        }()

        if let attributedString = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributedString)
                .font(.system(size: headerSize, weight: .bold))
                .multilineTextAlignment(.leading)
                .padding(.vertical, 4)
        } else {
            Text(text)
                .font(.system(size: headerSize, weight: .bold))
                .multilineTextAlignment(.leading)
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func renderMarkdownText(_ text: String) -> some View {
        if let attributedString = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributedString)
                .font(.system(size: fontSize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.system(size: fontSize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func renderList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: fontSize))
                    if let attributedString = try? AttributedString(markdown: item, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributedString)
                            .font(.system(size: fontSize))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(item)
                            .font(.system(size: fontSize))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Parsing Logic

    private func detectLaTeX() {
        guard content != lastCheckedContent else { return }
        lastCheckedContent = content

        let renderer = FullLaTeXRenderer.shared
        let detectedStrategy = renderer.determineStrategy(for: content)
        hasLaTeX = (detectedStrategy == .mathjax)
    }

    enum MarkdownComponent {
        case header(String, Int)  // text, level (1-6)
        case text(String)
        case list([String])  // list items
    }

    private func parseMarkdownComponents(_ text: String) -> [MarkdownComponent] {
        var components: [MarkdownComponent] = []
        let lines = text.components(separatedBy: .newlines)

        var currentListItems: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty {
                // End current list if any
                if !currentListItems.isEmpty {
                    components.append(.list(currentListItems))
                    currentListItems = []
                }
                continue
            }

            // Check for header (# to ######)
            if let _ = trimmed.range(of: "^(#{1,6})\\s+(.+)$", options: .regularExpression),
               let hashRange = trimmed.range(of: "^#{1,6}", options: .regularExpression) {
                // End current list if any
                if !currentListItems.isEmpty {
                    components.append(.list(currentListItems))
                    currentListItems = []
                }

                let level = trimmed[hashRange].count
                let text = trimmed.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
                components.append(.header(text, level))
            }
            // Check for list item (- or * at start)
            else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let item = String(trimmed.dropFirst(2))
                currentListItems.append(item)
            }
            // Regular text
            else {
                // End current list if any
                if !currentListItems.isEmpty {
                    components.append(.list(currentListItems))
                    currentListItems = []
                }
                components.append(.text(line))
            }
        }

        // Add remaining list items
        if !currentListItems.isEmpty {
            components.append(.list(currentListItems))
        }

        return components
    }

    enum ContentBlock {
        case markdown(MarkdownComponent)
        case latex(String)
    }

    private func parseMarkdownAndLaTeX(_ text: String) -> [ContentBlock] {
        // This is a simplified version - you can enhance it to handle interleaved LaTeX and markdown
        // For now, treat each line as either markdown or LaTeX
        var blocks: [ContentBlock] = []
        let components = parseMarkdownComponents(text)

        for component in components {
            blocks.append(.markdown(component))
        }

        return blocks
    }
}
