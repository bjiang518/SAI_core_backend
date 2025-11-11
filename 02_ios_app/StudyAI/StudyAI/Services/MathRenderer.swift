//
//  MathRenderer.swift
//  StudyAI
//
//  Created by Claude Code on 9/1/25.
//

import SwiftUI
import Foundation

/// Service to handle math equation formatting and detection
class MathFormattingService {
    static let shared = MathFormattingService()
    
    private init() {}
    
    /// Detect if text contains mathematical expressions
    func containsMathExpressions(_ text: String) -> Bool {
        let mathPatterns = [
            // LaTeX environments (PRIORITIZED)
            "\\\\begin\\{(align|equation|gather|split|multline|cases)\\*?\\}", // LaTeX environments
            "\\\\end\\{(align|equation|gather|split|multline|cases)\\*?\\}", // LaTeX environment ends

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

            // Subscripts (PHASE 1 ENHANCEMENT)
            "_\\d+", // Simple subscripts: _2, _10
            "_\\{[^}]+\\}", // Braced subscripts: _{10}, _{i+1}
            "[a-zA-Z]+_\\d+", // Function subscripts: log_2, x_1
            "[a-zA-Z]+_\\{[^}]+\\}", // Braced function subscripts: log_{10}

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

            // Alignment and line breaks in LaTeX
            "\\\\\\\\", // LaTeX line break \\
            "&", // LaTeX alignment character
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

    /// Parse mixed text with math expressions and markdown formatting
    func parseTextWithMath(_ text: String) -> [TextComponent] {
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
            // Silently fail on regex error
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
            // Silently fail on regex error
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
            // Silently fail on regex error
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
            // Silently fail on regex error
        }

        var components: [TextComponent] = []
        let lines = processedText.components(separatedBy: .newlines)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmedLine.isEmpty {
                continue
            }

            // Skip empty math blocks (just $$ or $ with nothing or whitespace inside)
            if trimmedLine == "$$" || trimmedLine == "$" ||
               trimmedLine.range(of: "^\\$\\$\\s*\\$\\$$", options: .regularExpression) != nil ||
               trimmedLine.range(of: "^\\$\\s*\\$$", options: .regularExpression) != nil {
                continue
            }

            // Check for markdown first (prioritize markdown over math)
            let hasMarkdown = containsMarkdown(line)
            let hasMath = containsMathExpressions(line)

            if hasMarkdown {
                components.append(.markdown(line))
            } else if hasMath {
                let formatted = formatMathForDisplay(line)
                components.append(.math(formatted))
            } else {
                components.append(.text(line))
            }
        }

        return components
    }

    /// Detect if text contains markdown formatting
    private func containsMarkdown(_ text: String) -> Bool {
        let markdownPatterns = [
            "^#{1,6}\\s+", // Headers: # Header, ## Header, etc.
            "\\*\\*[^*]+\\*\\*", // Bold: **text**
            "__[^_]+__", // Bold alt: __text__
            "\\*[^*]+\\*", // Italic: *text*
            "_[^_]+_", // Italic alt: _text_
            "^[-*+]\\s+", // Unordered list: - item, * item, + item
            "^\\d+\\.\\s+", // Ordered list: 1. item, 2. item
            "`[^`]+`", // Inline code: `code`
            "^```", // Code block: ```
            "\\[[^]]+\\]\\([^)]+\\)", // Link: [text](url)
        ]

        for pattern in markdownPatterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}

/// Represents different types of content (text, math, or markdown)
enum TextComponent {
    case text(String)
    case math(String)
    case markdown(String)
}

/// A view that displays mixed text, markdown, and math content
/// Legacy MathFormattedText - now uses MarkdownLaTeXText renderer by default
/// This provides full markdown AND LaTeX support with automatic rendering
struct MathFormattedText: View {
    let content: String
    let fontSize: CGFloat
    let mathBackgroundColor: Color

    init(_ content: String, fontSize: CGFloat = 16, mathBackgroundColor: Color = Color.blue.opacity(0.1)) {
        self.content = content
        self.fontSize = fontSize
        self.mathBackgroundColor = mathBackgroundColor
    }

    var body: some View {
        // Use the new MarkdownLaTeXText renderer for all content
        // This provides full markdown formatting AND LaTeX math support
        MarkdownLaTeXText(content, fontSize: fontSize, isStreaming: false)
    }
}

/// View for rendering markdown text using AttributedString with custom styling
struct MarkdownTextView: View {
    let markdownText: String
    let fontSize: CGFloat

    init(_ markdownText: String, fontSize: CGFloat = 16) {
        self.markdownText = markdownText
        self.fontSize = fontSize
    }

    var body: some View {
        // Check if this is a header line
        if let headerLevel = detectHeaderLevel(markdownText) {
            renderHeaderText(markdownText, level: headerLevel)
        } else if let attributedString = try? AttributedString(markdown: markdownText, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            // Use AttributedString for other markdown (bold, italic, lists, links)
            Text(attributedString)
                .font(.system(size: fontSize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            // Fallback if markdown parsing fails
            Text(markdownText)
                .font(.system(size: fontSize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Detect markdown header level (1-6 for #-######)
    private func detectHeaderLevel(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            let headerRegex = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: [])
            if let match = headerRegex?.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)),
               let hashRange = Range(match.range(at: 1), in: trimmed) {
                let hashes = String(trimmed[hashRange])
                return hashes.count
            }
        }
        return nil
    }

    /// Render header text with appropriate font size
    private func renderHeaderText(_ text: String, level: Int) -> some View {
        // Remove the header markers (e.g., "### " from "### Header Text")
        let cleanText = text.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)

        // Calculate font size based on header level
        // Level 1 (# Header) = largest, Level 6 (###### Header) = smallest
        let headerFontSize: CGFloat = {
            switch level {
            case 1: return fontSize + 12  // # - Largest
            case 2: return fontSize + 8   // ##
            case 3: return fontSize + 6   // ###
            case 4: return fontSize + 4   // ####
            case 5: return fontSize + 2   // #####
            case 6: return fontSize + 1   // ###### - Smallest
            default: return fontSize
            }
        }()

        return Text(cleanText)
            .font(.system(size: headerFontSize, weight: .bold))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)  // Add some vertical spacing around headers
    }
}