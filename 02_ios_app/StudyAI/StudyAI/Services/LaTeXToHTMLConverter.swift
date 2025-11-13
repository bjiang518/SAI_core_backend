//
//  LaTeXToHTMLConverter.swift
//  StudyAI
//
//  Created by Claude Code on 11/10/25.
//

import Foundation
import SwiftUI

/// Converts LaTeX-formatted grammar corrections to HTML for rendering
/// Supports \sout{}, \textcolor{}{}, and other LaTeX commands for essay feedback
class LaTeXToHTMLConverter {
    static let shared = LaTeXToHTMLConverter()

    private init() {}

    /// Convert LaTeX string to HTML string suitable for WKWebView rendering
    /// - Parameter latexString: LaTeX formatted string (e.g., "This \\sout{is} \\textcolor{green}{was} correct.")
    /// - Returns: HTML string with CSS styling
    func convertToHTML(_ latexString: String) -> String {
        var html = latexString

        // Step 1: Replace \sout{text} with <del>text</del> (strikethrough)
        html = replaceLaTeXCommand(
            in: html,
            command: "sout",
            replacement: { text in
                "<del style='color: #FF3B30; text-decoration: line-through; text-decoration-thickness: 2px;'>\(text)</del>"
            }
        )

        // Step 2: Replace \textcolor{color}{text} with <span style="color: ...">text</span>
        html = replaceTextColor(in: html)

        // Step 3: Replace \textbf{text} with <strong>text</strong> (bold)
        html = replaceLaTeXCommand(
            in: html,
            command: "textbf",
            replacement: { text in
                "<strong>\(text)</strong>"
            }
        )

        // Step 4: Replace \textit{text} with <em>text</em> (italic)
        html = replaceLaTeXCommand(
            in: html,
            command: "textit",
            replacement: { text in
                "<em>\(text)</em>"
            }
        )

        // Step 5: Replace \underline{text} with <u>text</u> (underline)
        html = replaceLaTeXCommand(
            in: html,
            command: "underline",
            replacement: { text in
                "<u>\(text)</u>"
            }
        )

        // Step 6: Wrap in complete HTML document with mobile-optimized CSS
        return wrapInHTMLDocument(html)
    }

    /// Generate complete HTML document with mobile-friendly styling
    /// - Parameter bodyHTML: The HTML content for the body
    /// - Returns: Complete HTML document string
    func wrapInHTMLDocument(_ bodyHTML: String) -> String {
        return """
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif;
            font-size: 17px;
            line-height: 1.6;
            color: #000000;
            background-color: #FFFFFF;
            margin: 0;
            padding: 16px;
            -webkit-text-size-adjust: none;
        }

        /* Strikethrough styling (errors) */
        del {
            color: #FF3B30;
            text-decoration: line-through;
            text-decoration-thickness: 2px;
            text-decoration-color: #FF3B30;
        }

        /* Corrected text styling */
        .correction {
            font-weight: 600;
            padding: 2px 4px;
            border-radius: 3px;
        }

        /* Color-specific styles */
        .text-green {
            color: #34C759;
            background-color: rgba(52, 199, 89, 0.1);
        }

        .text-red {
            color: #FF3B30;
            background-color: rgba(255, 59, 48, 0.1);
        }

        .text-blue {
            color: #007AFF;
            background-color: rgba(0, 122, 255, 0.1);
        }

        .text-orange {
            color: #FF9500;
            background-color: rgba(255, 149, 0, 0.1);
        }

        .text-purple {
            color: #AF52DE;
            background-color: rgba(175, 82, 222, 0.1);
        }

        /* Mobile-specific */
        @media (prefers-color-scheme: dark) {
            body {
                color: #FFFFFF;
                background-color: #000000;
            }

            .text-green {
                color: #30D158;
                background-color: rgba(48, 209, 88, 0.15);
            }

            .text-red {
                color: #FF453A;
                background-color: rgba(255, 69, 58, 0.15);
            }

            .text-blue {
                color: #0A84FF;
                background-color: rgba(10, 132, 255, 0.15);
            }

            .text-orange {
                color: #FF9F0A;
                background-color: rgba(255, 159, 10, 0.15);
            }

            .text-purple {
                color: #BF5AF2;
                background-color: rgba(191, 90, 242, 0.15);
            }
        }

        /* Text formatting */
        strong {
            font-weight: 700;
        }

        em {
            font-style: italic;
        }

        u {
            text-decoration: underline;
        }

        /* Selection styling */
        ::selection {
            background-color: rgba(0, 122, 255, 0.3);
        }

        /* Prevent text wrapping issues */
        p {
            margin: 0;
            padding: 0;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
    </style>
</head>
<body>
    \(bodyHTML)
</body>
</html>
"""
    }

    // MARK: - Private Helper Methods

    /// Replace LaTeX command with single argument: \command{text}
    /// - Parameters:
    ///   - string: Input string with LaTeX commands
    ///   - command: LaTeX command name (without backslash)
    ///   - replacement: Closure that takes the text and returns HTML
    /// - Returns: String with LaTeX commands replaced by HTML
    private func replaceLaTeXCommand(
        in string: String,
        command: String,
        replacement: (String) -> String
    ) -> String {
        // Pattern: \\command{content}
        let pattern = "\\\\\\(command)\\{([^}]+)\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }

        var result = string
        let nsString = result as NSString

        // Process matches in reverse to avoid index issues
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            if match.numberOfRanges == 2 {
                let fullMatchRange = match.range(at: 0)
                let contentRange = match.range(at: 1)

                if let contentSwiftRange = Range(contentRange, in: result) {
                    let content = String(result[contentSwiftRange])
                    let htmlReplacement = replacement(content)

                    if let fullSwiftRange = Range(fullMatchRange, in: result) {
                        result.replaceSubrange(fullSwiftRange, with: htmlReplacement)
                    }
                }
            }
        }

        return result
    }

    /// Replace \textcolor{color}{text} with colored span
    /// - Parameter string: Input string with \textcolor commands
    /// - Returns: String with HTML spans
    private func replaceTextColor(in string: String) -> String {
        // Pattern: \\textcolor{color}{content}
        let pattern = "\\\\textcolor\\{([^}]+)\\}\\{([^}]+)\\}"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return string
        }

        var result = string
        let nsString = result as NSString

        // Process matches in reverse
        let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches.reversed() {
            if match.numberOfRanges == 3 {
                let fullMatchRange = match.range(at: 0)
                let colorRange = match.range(at: 1)
                let contentRange = match.range(at: 2)

                if let colorSwiftRange = Range(colorRange, in: result),
                   let contentSwiftRange = Range(contentRange, in: result) {

                    let color = String(result[colorSwiftRange])
                    let content = String(result[contentSwiftRange])

                    let htmlReplacement = "<span class='correction text-\(color.lowercased())'>\(content)</span>"

                    if let fullSwiftRange = Range(fullMatchRange, in: result) {
                        result.replaceSubrange(fullSwiftRange, with: htmlReplacement)
                    }
                }
            }
        }

        return result
    }

    /// Map LaTeX color names to HTML/CSS colors
    /// - Parameter latexColor: LaTeX color name (e.g., "green", "red")
    /// - Returns: HTML color code or name
    private func mapLaTeXColorToHTML(_ latexColor: String) -> String {
        switch latexColor.lowercased() {
        case "green":
            return "#34C759"  // iOS system green
        case "red":
            return "#FF3B30"  // iOS system red
        case "blue":
            return "#007AFF"  // iOS system blue
        case "orange":
            return "#FF9500"  // iOS system orange
        case "purple":
            return "#AF52DE"  // iOS system purple
        case "yellow":
            return "#FFCC00"  // iOS system yellow
        case "black":
            return "#000000"
        case "white":
            return "#FFFFFF"
        case "gray", "grey":
            return "#8E8E93"  // iOS system gray
        default:
            return latexColor  // Pass through if unknown
        }
    }

    // MARK: - Public Utilities

    /// Test function to preview HTML rendering
    /// - Parameter latexString: LaTeX formatted string
    /// - Returns: HTML string for debugging
    func previewHTML(_ latexString: String) -> String {
        return convertToHTML(latexString)
    }

    /// Extract plain text from LaTeX string (remove all formatting)
    /// - Parameter latexString: LaTeX formatted string
    /// - Returns: Plain text without LaTeX commands
    func extractPlainText(_ latexString: String) -> String {
        var plain = latexString

        // Remove all \command{text} patterns, keeping only the text
        let singleArgPattern = "\\\\\\w+\\{([^}]+)\\}"
        if let regex = try? NSRegularExpression(pattern: singleArgPattern, options: []) {
            let nsString = plain as NSString
            let matches = regex.matches(in: plain, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() {
                if match.numberOfRanges == 2,
                   let contentRange = Range(match.range(at: 1), in: plain),
                   let fullRange = Range(match.range(at: 0), in: plain) {
                    let content = String(plain[contentRange])
                    plain.replaceSubrange(fullRange, with: content)
                }
            }
        }

        // Remove \textcolor{color}{text}, keeping only text
        let colorPattern = "\\\\textcolor\\{[^}]+\\}\\{([^}]+)\\}"
        if let regex = try? NSRegularExpression(pattern: colorPattern, options: []) {
            let nsString = plain as NSString
            let matches = regex.matches(in: plain, options: [], range: NSRange(location: 0, length: nsString.length))

            for match in matches.reversed() {
                if match.numberOfRanges == 2,
                   let contentRange = Range(match.range(at: 1), in: plain),
                   let fullRange = Range(match.range(at: 0), in: plain) {
                    let content = String(plain[contentRange])
                    plain.replaceSubrange(fullRange, with: content)
                }
            }
        }

        return plain
    }
}
