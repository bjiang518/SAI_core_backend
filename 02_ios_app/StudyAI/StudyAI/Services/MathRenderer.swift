//
//  MathRenderer.swift
//  StudyAI
//
//  Created by Claude Code on 9/1/25.
//

import SwiftUI
import WebKit
import Foundation

/// A SwiftUI view that renders mathematical equations using MathJax
struct MathEquationView: UIViewRepresentable {
    let equation: String
    let fontSize: CGFloat
    
    init(_ equation: String, fontSize: CGFloat = 16) {
        self.equation = equation
        self.fontSize = fontSize
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.scrollView.backgroundColor = UIColor.clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        print("🔄 === MATH EQUATION VIEW UPDATE ===")
        print("📝 Equation to render: '\(equation)'")
        print("📏 Font size: \(fontSize)")
        
        let mathHTML = createMathHTML(equation: equation, fontSize: fontSize)
        print("📄 Generated HTML length: \(mathHTML.count)")
        print("📄 HTML preview: \(String(mathHTML.prefix(300)))")
        
        webView.loadHTMLString(mathHTML, baseURL: nil)
        print("✅ HTML loaded into WebKit")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("🌐 WebKit: Started loading MathJax")
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("🎉 WebKit: MathJax page loaded successfully")
            
            // Check if MathJax is loaded
            webView.evaluateJavaScript("typeof MathJax") { result, error in
                if let result = result {
                    print("🔍 MathJax object type: \(result)")
                } else {
                    print("❌ MathJax not found: \(error?.localizedDescription ?? "unknown error")")
                }
            }
            
            // Adjust height after content loads
            webView.evaluateJavaScript("document.body.scrollHeight") { result, error in
                if let height = result as? CGFloat {
                    print("📏 WebKit content height: \(height)")
                    DispatchQueue.main.async {
                        webView.frame.size.height = height
                    }
                } else {
                    print("❌ Failed to get content height: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ WebKit: Failed to load MathJax - \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ WebKit: Failed to start loading MathJax - \(error.localizedDescription)")
        }
    }
    
    private func createMathHTML(equation: String, fontSize: CGFloat) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <script src="https://polyfill.io/v3/polyfill.min.js?features=es6"></script>
            <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
            <script>
                window.MathJax = {
                    tex: {
                        // Prioritize $ delimiters for iOS compatibility
                        inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                        displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                        processEscapes: true,
                        processEnvironments: true,
                        processRefs: true,
                        autoload: {
                            color: [],
                            colorV2: ['color']
                        }
                    },
                    options: {
                        skipHtmlTags: ['script', 'noscript', 'style', 'textarea', 'pre'],
                        ignoreHtmlClass: 'tex2jax_ignore',
                        processHtmlClass: 'tex2jax_process'
                    },
                    svg: {
                        fontCache: 'global'
                    },
                    startup: {
                        ready: () => {
                            MathJax.startup.defaultReady();
                            // Auto-resize after rendering
                            MathJax.startup.promise.then(() => {
                                setTimeout(() => {
                                    const height = Math.max(document.body.scrollHeight, document.body.offsetHeight);
                                    document.body.style.height = height + 'px';
                                }, 100);
                            });
                        }
                    }
                };
            </script>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    font-size: \(fontSize)px;
                    line-height: 1.6;
                    margin: 8px;
                    padding: 0;
                    background-color: transparent;
                    color: #000000;
                    overflow-x: hidden;
                }
                .math-container {
                    text-align: center;
                    margin: 10px 0;
                    width: 100%;
                    box-sizing: border-box;
                }
                mjx-container {
                    overflow-x: auto;
                    overflow-y: hidden;
                }
                @media (prefers-color-scheme: dark) {
                    body {
                        color: #ffffff;
                    }
                }
            </style>
        </head>
        <body>
            <div class="math-container">
                \(equation)
            </div>
        </body>
        </html>
        """
    }
}

/// Service to handle math equation formatting and detection
class MathFormattingService {
    static let shared = MathFormattingService()
    
    private init() {}
    
    /// Detect if text contains mathematical expressions
    func containsMathExpressions(_ text: String) -> Bool {
        let mathPatterns = [
            // ChatGPT-recommended delimiters (prioritized)
            "\\\\\\(.*?\\\\\\)", // LaTeX inline math \(...\) - NEW PRIMARY
            "\\\\\\[.*?\\\\\\]", // LaTeX display math \[...\] - NEW PRIMARY
            "\\$.*?\\$", // LaTeX inline math $...$ - FALLBACK
            "\\$\\$.*?\\$\\$", // LaTeX display math $$...$$ - FALLBACK
            
            // LaTeX commands and functions
            "\\\\sqrt\\{.*?\\}", // LaTeX square root
            "\\\\frac\\{.*?\\}\\{.*?\\}", // LaTeX fractions
            "\\\\lim_\\{.*?\\}", // Limit with subscript
            "\\\\int_\\{.*?\\}", // Integral with bounds
            "\\\\sum_\\{.*?\\}", // Summation
            "\\\\[a-zA-Z]+\\{.*?\\}", // Generic LaTeX commands
            
            // Mathematical symbols and patterns
            "\\d+[x-z]", // Variables like 2x, 3y
            "[x-z]\\s*[+\\-*/=]", // Variables with operators
            "\\^\\{?\\d+\\}?", // Exponents like ^2 or ^{10}
            "\\d+/\\d+", // Fractions like 3/4
            "[+\\-*/=]\\s*\\d", // Basic math operations
            "\\([^)]*[+\\-*/][^)]*\\)", // Expressions in parentheses
            
            // Greek letters (common in math)
            "\\\\(alpha|beta|gamma|delta|epsilon|theta|phi|psi|omega|sigma)", // LaTeX Greek
            "[αβγδεθφψωσ]", // Unicode Greek
        ]
        
        for pattern in mathPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        
        return false
    }
    
    /// Convert common math notation to LaTeX format
    func formatMathForDisplay(_ text: String) -> String {
        var formattedText = text
        
        // Don't re-process text that already has proper LaTeX formatting (prioritize new delimiters)
        if formattedText.contains("\\[") && formattedText.contains("\\]") {
            // Text already has ChatGPT-recommended display math formatting
            return formattedText
        }
        
        if formattedText.contains("\\(") && formattedText.contains("\\)") {
            // Text already has ChatGPT-recommended inline math formatting  
            return formattedText
        }
        
        // Fallback: check legacy delimiters
        if formattedText.contains("$$") && (formattedText.hasPrefix("$$") || formattedText.hasSuffix("$$")) {
            // Convert legacy display math to new format
            let converted = formattedText.replacingOccurrences(of: "$$", with: "\\[")
                .replacingOccurrences(of: "$$", with: "\\]")
            return converted
        }
        
        if formattedText.contains("$") && (formattedText.hasPrefix("$") || formattedText.hasSuffix("$")) {
            // Convert legacy inline math to new format
            let converted = formattedText.replacingOccurrences(of: "$", with: "\\(")
                .replacingOccurrences(of: "$", with: "\\)")
            return converted
        }
        
        print("🔧 Formatting text: '\(formattedText)'")
        
        // Convert simple fractions to LaTeX (only for standalone fractions)
        formattedText = formattedText.replacingOccurrences(
            of: "\\b(\\d+)/(\\d+)\\b",
            with: "\\\\frac{$1}{$2}",
            options: .regularExpression
        )
        
        // Convert exponents (x^2 -> x^{2})
        formattedText = formattedText.replacingOccurrences(
            of: "([a-zA-Z0-9])\\^(\\d+)",
            with: "$1^{$2}",
            options: .regularExpression
        )
        
        // Convert square root notation (standalone and in text)
        formattedText = formattedText.replacingOccurrences(
            of: "\\\\sqrt\\{([^}]+)\\}",
            with: "\\\\sqrt{$1}",
            options: .regularExpression
        )
        
        formattedText = formattedText.replacingOccurrences(
            of: "√([0-9]+)",
            with: "\\\\sqrt{$1}",
            options: .regularExpression
        )
        
        formattedText = formattedText.replacingOccurrences(
            of: "square root of ([0-9]+)",
            with: "\\\\sqrt{$1}",
            options: .regularExpression
        )
        
        // Ensure proper LaTeX delimiters (use ChatGPT-recommended format)
        if !formattedText.hasPrefix("\\[") && !formattedText.hasPrefix("\\(") && 
           !formattedText.hasPrefix("$$") && !formattedText.hasPrefix("$") {
            if isStandaloneEquation(formattedText) {
                formattedText = "\\[" + formattedText + "\\]"  // Display math
            } else if containsInlineMath(formattedText) {
                formattedText = "\\(" + formattedText + "\\)"  // Inline math
            }
        }
        
        print("🎨 Final formatted: '\(formattedText)'")
        return formattedText
    }
    
    /// Check if a line is a standalone mathematical equation
    private func isStandaloneEquation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't treat step headers or explanatory text as equations
        if trimmed.hasPrefix("Step ") || trimmed.contains(":") {
            return false
        }
        
        // Must contain equals sign or be a simple expression
        return trimmed.contains("=") && trimmed.split(separator: " ").count <= 10
    }
    
    /// Check if text contains inline math that should be formatted
    private func containsInlineMath(_ text: String) -> Bool {
        let inlineMathPatterns = [
            "\\d+/\\d+", // Simple fractions
            "[a-zA-Z]\\^\\d+", // Variables with exponents
            "√\\d+", // Square roots
        ]
        
        for pattern in inlineMathPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
    
    /// Wrap only the mathematical parts in LaTeX delimiters
    private func wrapInlineMath(_ text: String) -> String {
        var result = text
        
        // Wrap fractions
        result = result.replacingOccurrences(
            of: "\\b(\\d+/\\d+)\\b",
            with: "$$$1$$",
            options: .regularExpression
        )
        
        // Wrap exponents
        result = result.replacingOccurrences(
            of: "([a-zA-Z0-9])\\^\\{(\\d+)\\}",
            with: "$$1^{$2}$",
            options: .regularExpression
        )
        
        return result
    }
    
    /// Debug method to test math detection
    func debugMathDetection(_ text: String) {
        print("🧪 === DEBUGGING MATH DETECTION ===")
        print("📄 Testing text: '\(text)'")
        
        let patterns = [
            // ChatGPT-recommended delimiters (prioritized)
            ("LaTeX inline \\(...\\)", "\\\\\\(.*?\\\\\\)"),
            ("LaTeX display \\[...\\]", "\\\\\\[.*?\\\\\\]"),
            ("LaTeX inline $...$", "\\$.*?\\$"),
            ("LaTeX display $$...$$", "\\$\\$.*?\\$\\$"),
            
            // LaTeX functions
            ("LaTeX sqrt", "\\\\sqrt\\{.*?\\}"),
            ("LaTeX frac", "\\\\frac\\{.*?\\}\\{.*?\\}"),
            ("LaTeX lim", "\\\\lim_\\{.*?\\}"),
            ("LaTeX Greek", "\\\\(epsilon|delta|alpha|beta)"),
            
            // Basic patterns
            ("Variables", "\\d+[x-z]"),
            ("Operators", "[x-z]\\s*[+\\-*/=]"),
            ("Exponents", "\\^\\{?\\d+\\}?"),
            ("Simple fractions", "\\d+/\\d+"),
            ("Math ops", "[+\\-*/=]\\s*\\d"),
            ("Parentheses", "\\([^)]*[+\\-*/][^)]*\\)")
        ]
        
        for (name, pattern) in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                print("✅ Found: \(name)")
            } else {
                print("❌ Not found: \(name)")
            }
        }
        
        let hasMath = containsMathExpressions(text)
        print("🎯 Final result: \(hasMath ? "HAS MATH" : "NO MATH")")
        
        if hasMath {
            let formatted = formatMathForDisplay(text)
            print("🎨 Formatted result: '\(formatted)'")
        }
    }
    
    /// Parse mixed text with math expressions
    func parseTextWithMath(_ text: String) -> [TextComponent] {
        print("🔍 === MATH RENDERING DEBUG ===")
        print("📄 Input text length: \(text.count)")
        print("📄 Input preview: \(String(text.prefix(200)))")
        
        // First, handle multi-line LaTeX display math blocks
        var processedText = text
        
        // Replace ChatGPT-recommended display math \[ ... \] (prioritized)
        do {
            let displayMathRegex = try NSRegularExpression(
                pattern: "\\\\\\[\\s*([^]]+?)\\s*\\\\\\]",
                options: [.dotMatchesLineSeparators]
            )
            let range = NSRange(location: 0, length: processedText.utf16.count)
            processedText = displayMathRegex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: "\\\\[$1\\\\]"  // Keep as \[...\] for display
            )
        } catch {
            print("❌ Display math regex error: \(error)")
        }
        
        // Handle ChatGPT-recommended inline LaTeX \( ... \) (prioritized) 
        do {
            let inlineMathRegex = try NSRegularExpression(
                pattern: "\\\\\\(\\s*([^)]+?)\\s*\\\\\\)",
                options: [.dotMatchesLineSeparators]
            )
            let range = NSRange(location: 0, length: processedText.utf16.count)
            processedText = inlineMathRegex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: "\\\\($1\\\\)"  // Keep as \(...\) for inline
            )
        } catch {
            print("❌ Inline math regex error: \(error)")
        }
        
        // Fallback: Handle legacy $$ ... $$ display math
        do {
            let legacyDisplayRegex = try NSRegularExpression(
                pattern: "\\$\\$\\s*([^$]+?)\\s*\\$\\$",
                options: [.dotMatchesLineSeparators]
            )
            let range = NSRange(location: 0, length: processedText.utf16.count)
            processedText = legacyDisplayRegex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: "\\\\[$1\\\\]"  // Convert to \[...\] format
            )
        } catch {
            print("❌ Legacy display math regex error: \(error)")
        }
        
        // Fallback: Handle legacy $ ... $ inline math
        do {
            let legacyInlineRegex = try NSRegularExpression(
                pattern: "\\$\\s*([^$]+?)\\s*\\$",
                options: [.dotMatchesLineSeparators]
            )
            let range = NSRange(location: 0, length: processedText.utf16.count)
            processedText = legacyInlineRegex.stringByReplacingMatches(
                in: processedText,
                options: [],
                range: range,
                withTemplate: "\\\\($1\\\\)"  // Convert to \(...\) format
            )
        } catch {
            print("❌ Legacy inline math regex error: \(error)")
        }
        
        print("📝 After LaTeX preprocessing: \(String(processedText.prefix(200)))")
        
        var components: [TextComponent] = []
        let lines = processedText.components(separatedBy: .newlines)
        
        print("📊 Processing \(lines.count) lines")
        
        for (index, line) in lines.enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }
            
            // Skip empty math blocks (just $$ or $ with nothing or whitespace inside)
            if trimmedLine == "$$" || trimmedLine == "$" || 
               trimmedLine.range(of: "^\\$\\$\\s*\\$\\$$", options: .regularExpression) != nil || 
               trimmedLine.range(of: "^\\$\\s*\\$$", options: .regularExpression) != nil {
                print("📝 Line \(index): SKIPPING empty math block - '\(trimmedLine)'")
                continue
            }
            
            let hasMath = containsMathExpressions(line)
            print("📝 Line \(index): \(hasMath ? "HAS MATH" : "plain text") - '\(String(line.prefix(50)))'")
            
            if hasMath {
                let formatted = formatMathForDisplay(line)
                print("🎨 Formatted math: '\(String(formatted.prefix(100)))'")
                components.append(.math(formatted))
            } else {
                components.append(.text(line))
            }
        }
        
        print("✅ Created \(components.count) components")
        return components
    }
}

/// Represents different types of content (text or math)
enum TextComponent {
    case text(String)
    case math(String)
}

/// A view that displays mixed text and math content
struct MathFormattedText: View {
    let content: String
    let fontSize: CGFloat
    
    init(_ content: String, fontSize: CGFloat = 16) {
        self.content = content
        self.fontSize = fontSize
    }
    
    var body: some View {
        let components = MathFormattingService.shared.parseTextWithMath(content)
        
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                switch component {
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(text)
                            .font(.system(size: fontSize))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .math(let equation):
                    // Use fallback text rendering instead of WebView for better reliability
                    Text(SimpleMathRenderer.renderMathText(equation))
                        .font(.system(size: fontSize, design: .monospaced))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .frame(minHeight: 40)
                        .onAppear {
                            print("🧮 Rendering math: '\(equation)' -> '\(SimpleMathRenderer.renderMathText(equation))'")
                        }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Debug: Show the actual content being processed for this message
            if content.contains("\\") || content.contains("equation") || content.contains("=") {
                print("🧪 === MATH RENDERING DEBUG FOR CURRENT MESSAGE ===")
                print("📄 Message content: '\(content)'")
                print("📊 Components created: \(components.count)")
                for (index, component) in components.enumerated() {
                    switch component {
                    case .text(let text):
                        print("📝 Component \(index): TEXT - '\(text.prefix(50))'")
                    case .math(let equation):
                        print("🧮 Component \(index): MATH - '\(equation.prefix(50))'")
                    }
                }
                print("================================================")
            }
        }
    }
}