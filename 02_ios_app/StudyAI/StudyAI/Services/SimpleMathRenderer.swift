//
//  SimpleMathRenderer.swift
//  StudyAI
//
//  Created by Claude Code on 9/1/25.
//

import SwiftUI

/// LaTeX Post-Processing Service for AI Output
class LaTeXPostProcessor {
    static let shared = LaTeXPostProcessor()
    
    private init() {}
    
    /// Post-process AI output to convert backslash delimiters to readable math
    /// AI uses \( \) and \[ \] (safer), we convert them to more readable format
    func processAIOutput(_ input: String) -> String {
        var processed = input

        // STEP 0: Preserve LaTeX environments (don't strip delimiters from environments)
        // Check if the input contains LaTeX environments
        let hasLaTeXEnvironment = input.range(of: "\\\\begin\\{", options: .regularExpression) != nil

        if hasLaTeXEnvironment {
            // For LaTeX environments, we want to keep them intact and let SimpleMathRenderer handle them
            // Just clean up the display math delimiters around the environment if present
            processed = processed.replacingOccurrences(
                of: "\\\\\\[(\\s*\\\\begin\\{.*?\\}[\\s\\S]*?\\\\end\\{.*?\\}\\s*)\\\\\\]",
                with: "$1",
                options: .regularExpression
            )
            return processed
        }

        // Step 1: Handle mixed dollar sign format (legacy cleanup)
        // Fix cases like: "function$f$(x) = 2x$^2" → "function \\(f(x) = 2x^2\\)"

        // First, handle isolated dollar signs with variables/expressions
        processed = processed.replacingOccurrences(
            of: "\\$([a-zA-Z0-9_]+)\\$",
            with: "\\\\($1\\\\)",
            options: .regularExpression
        )

        // Handle dollar signs with exponents like $^2
        processed = processed.replacingOccurrences(
            of: "\\$\\^([0-9]+)",
            with: "^$1",
            options: .regularExpression
        )

        // Handle complex mixed cases like "function$f$(x) = 2x$^2"
        processed = processed.replacingOccurrences(
            of: "([a-zA-Z]+)\\$([a-zA-Z]+)\\$\\(([^)]+)\\)\\s*=\\s*([^$]+)\\$\\^([0-9]+)",
            with: "$1 \\\\($2($3) = $4^$5\\\\)",
            options: .regularExpression
        )

        // Step 1b: Convert display math \[ ... \] to clean format with line breaks
        processed = processed.replacingOccurrences(
            of: "\\\\\\[([\\s\\S]*?)\\\\\\]",
            with: "\n\n$1\n\n",
            options: .regularExpression
        )

        // Step 2: Convert inline math \( ... \) to clean format
        processed = processed.replacingOccurrences(
            of: "\\\\\\(([^\\)]*?)\\\\\\)",
            with: "$1",
            options: .regularExpression
        )

        // Step 3: Convert common LaTeX symbols to Unicode equivalents
        let mathSymbols: [String: String] = [
            "\\\\frac\\{([^}]+)\\}\\{([^}]+)\\}": "($1)/($2)",
            "\\\\sqrt\\{([^}]+)\\}": "√($1)",
            "\\\\pm": "±",
            "\\\\cdot": "·",
            "\\\\times": "×",
            "\\\\div": "÷",
            "\\\\leq": "≤",
            "\\\\geq": "≥",
            "\\\\neq": "≠",
            "\\\\approx": "≈",
            "\\\\infty": "∞",
            "x\\^2": "x²",
            "x\\^3": "x³",
            "\\^2": "²",
            "\\^3": "³"
        ]

        for (pattern, replacement) in mathSymbols {
            processed = processed.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        // Clean up remaining braces and backslashes
        processed = processed.replacingOccurrences(of: "\\{", with: "")
        processed = processed.replacingOccurrences(of: "\\}", with: "")
        processed = processed.replacingOccurrences(of: "\\\\", with: "")

        return processed
    }
    
    /// Detect if text contains LaTeX that needs post-processing
    func needsPostProcessing(_ text: String) -> Bool {
        let patterns = [
            "\\\\\\[", "\\\\\\]", // Display math \[ \]
            "\\\\\\(", "\\\\\\)", // Inline math \( \)
            "\\\\\\\\frac", "\\\\\\\\sqrt", // Double-escaped commands
            "\\\\begin\\{", "\\\\end\\{", // LaTeX environments
        ]

        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}

/// Enhanced math renderer using AttributedString for better formatting
struct EnhancedMathText: View {
    let text: String
    let fontSize: CGFloat
    
    init(_ text: String, fontSize: CGFloat = 16) {
        self.text = text
        self.fontSize = fontSize
    }
    
    var body: some View {
        Text(createAttributedText())
            .multilineTextAlignment(.leading)
    }
    
    private func createAttributedText() -> AttributedString {
        var attributedText = AttributedString(formatMathText(text))
        
        // Apply base font to entire text
        attributedText.font = .system(size: fontSize)
        
        // Simple enhancement: make the entire text slightly larger if it contains math symbols
        let mathSymbols = ["√", "±", "≤", "≥", "≠", "≈", "∞", "π", "α", "β", "γ", "θ", "="]
        let containsMath = mathSymbols.contains { symbol in
            attributedText.characters.contains(symbol)
        }
        
        if containsMath {
            // Apply math styling to entire text if it contains math
            attributedText.font = .system(size: fontSize + 1, weight: .medium, design: .monospaced)
            attributedText.foregroundColor = .primary
        }
        
        return attributedText
    }
    
    private func formatMathText(_ input: String) -> String {
        var formatted = input
        
        // Better LaTeX conversion
        formatted = formatted.replacingOccurrences(of: "\\[", with: "\n\n")
        formatted = formatted.replacingOccurrences(of: "\\]", with: "\n\n")
        formatted = formatted.replacingOccurrences(of: "\\(", with: "")
        formatted = formatted.replacingOccurrences(of: "\\)", with: "")
        
        // Improved fraction handling
        formatted = formatted.replacingOccurrences(
            of: "\\\\frac\\{([^}]+)\\}\\{([^}]+)\\}",
            with: "($1)/($2)",
            options: .regularExpression
        )
        
        // Better square root handling
        formatted = formatted.replacingOccurrences(
            of: "\\\\sqrt\\{([^}]+)\\}",
            with: "√($1)",
            options: .regularExpression
        )
        
        // LaTeX symbols to Unicode
        let latexToUnicode = [
            "\\\\pm": "±",
            "\\\\cdot": "·",
            "\\\\times": "×",
            "\\\\div": "÷",
            "\\\\leq": "≤",
            "\\\\geq": "≥",
            "\\\\neq": "≠",
            "\\\\approx": "≈",
            "\\\\infty": "∞",
            "\\\\pi": "π",
            "\\\\alpha": "α",
            "\\\\beta": "β",
            "\\\\gamma": "γ",
            "\\\\theta": "θ"
        ]
        
        for (latex, unicode) in latexToUnicode {
            formatted = formatted.replacingOccurrences(of: latex, with: unicode)
        }
        
        // Clean up remaining braces
        formatted = formatted.replacingOccurrences(of: "{", with: "")
        formatted = formatted.replacingOccurrences(of: "}", with: "")
        
        // Superscript conversion
        let superscripts = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
        for (_, sup) in superscripts.enumerated() {
            // Note: index not used because this appears to be placeholder/buggy code
            formatted = formatted.replacingOccurrences(of: "^\\(index)", with: sup)
        }
        
        return formatted
    }
}

/// Smart Math Text with post-processing and reliable rendering
struct SmartMathRenderer: View {
    let content: String
    let fontSize: CGFloat
    
    init(_ content: String, fontSize: CGFloat = 16) {
        self.content = content
        self.fontSize = fontSize
    }
    
    var body: some View {
        let processedContent = LaTeXPostProcessor.shared.processAIOutput(content)
        
        // Use the original MathFormattedText with post-processed content
        MathFormattedText(processedContent, fontSize: fontSize)
    }
}

extension MathFormattingService {
    /// Enhanced math detection with more patterns
    func enhancedMathDetection(_ text: String) -> Bool {
        let advancedPatterns = [
            "∫", "∑", "∏", "∂", // Calculus symbols
            "α", "β", "γ", "θ", "π", "λ", "μ", "σ", // Greek letters
            "≤", "≥", "≠", "≈", "∞", // Math symbols
            "√", "∛", // Roots
            "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹", // Superscripts
            "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉", // Subscripts
            "\\log", "\\ln", "\\sin", "\\cos", "\\tan", // Functions
            "\\lim", "\\max", "\\min", // Limits and optimization
        ]
        
        for pattern in advancedPatterns {
            if text.contains(pattern) {
                return true
            }
        }
        
        return containsMathExpressions(text)
    }
}

/// Simple Math Renderer for reliable math display without WebView dependencies
class SimpleMathRenderer {

    // MARK: - Helper Functions for Unicode Conversion

    /// Convert a string of digits to Unicode subscript characters
    /// Example: "10" → "₁₀", "2" → "₂"
    private static func convertToSubscriptDigits(_ input: String) -> String {
        let subscriptMap: [Character: String] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"
        ]

        return input.map { char in
            subscriptMap[char] ?? String(char)
        }.joined()
    }

    /// Convert a string of digits to Unicode superscript characters
    /// Example: "10" → "¹⁰", "2" → "²"
    private static func convertToSuperscriptDigits(_ input: String) -> String {
        let superscriptMap: [Character: String] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]

        return input.map { char in
            superscriptMap[char] ?? String(char)
        }.joined()
    }

    // MARK: - Main Rendering Function

    static func renderMathText(_ input: String) -> String {
        var rendered = input

        // PHASE 0: Handle LaTeX environments FIRST (before removing delimiters)

        // Handle \begin{align} ... \end{align} environments
        do {
            let alignRegex = try NSRegularExpression(
                pattern: "\\\\begin\\{align\\*?\\}([\\s\\S]*?)\\\\end\\{align\\*?\\}",
                options: []
            )
            let range = NSRange(location: 0, length: rendered.utf16.count)
            let matches = alignRegex.matches(in: rendered, options: [], range: range)

            for match in matches.reversed() {
                if let contentRange = Range(match.range(at: 1), in: rendered),
                   let fullRange = Range(match.range(at: 0), in: rendered) {
                    let alignContent = String(rendered[contentRange])

                    // Process align content: split by \\, handle & alignment
                    let lines = alignContent.components(separatedBy: "\\\\")
                        .map { line in
                            // Replace & with spacing for alignment
                            line.replacingOccurrences(of: "&", with: "  ")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .filter { !$0.isEmpty }

                    let processedAlign = "\n" + lines.joined(separator: "\n") + "\n"
                    rendered.replaceSubrange(fullRange, with: processedAlign)
                }
            }
        } catch {
            // Silently fail on regex error
        }

        // Handle \begin{equation} ... \end{equation} environments
        do {
            let equationRegex = try NSRegularExpression(
                pattern: "\\\\begin\\{equation\\*?\\}([\\s\\S]*?)\\\\end\\{equation\\*?\\}",
                options: []
            )
            let range = NSRange(location: 0, length: rendered.utf16.count)
            let matches = equationRegex.matches(in: rendered, options: [], range: range)

            for match in matches.reversed() {
                if let contentRange = Range(match.range(at: 1), in: rendered),
                   let fullRange = Range(match.range(at: 0), in: rendered) {
                    let eqContent = String(rendered[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let processedEq = "\n" + eqContent + "\n"
                    rendered.replaceSubrange(fullRange, with: processedEq)
                }
            }
        } catch {
            // Silently fail on regex error
        }

        // Handle \begin{gather} ... \end{gather} environments
        do {
            let gatherRegex = try NSRegularExpression(
                pattern: "\\\\begin\\{gather\\*?\\}([\\s\\S]*?)\\\\end\\{gather\\*?\\}",
                options: []
            )
            let range = NSRange(location: 0, length: rendered.utf16.count)
            let matches = gatherRegex.matches(in: rendered, options: [], range: range)

            for match in matches.reversed() {
                if let contentRange = Range(match.range(at: 1), in: rendered),
                   let fullRange = Range(match.range(at: 0), in: rendered) {
                    let gatherContent = String(rendered[contentRange])

                    // Process gather content: split by \\
                    let lines = gatherContent.components(separatedBy: "\\\\")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    let processedGather = "\n" + lines.joined(separator: "\n") + "\n"
                    rendered.replaceSubrange(fullRange, with: processedGather)
                }
            }
        } catch {
            // Silently fail on regex error
        }

        // Remove LaTeX delimiters FIRST (before handling \\ line breaks)
        // This prevents \\( and \\) from being split by the line break conversion

        // Display math delimiters (keep line breaks for display equations)
        rendered = rendered.replacingOccurrences(of: "\\[", with: "\n\n")
        rendered = rendered.replacingOccurrences(of: "\\]", with: "\n\n")

        // Inline math delimiters - handle double-escaped versions
        rendered = rendered.replacingOccurrences(of: "\\\\(", with: "")
        rendered = rendered.replacingOccurrences(of: "\\\\)", with: "")

        // Then handle single-escaped versions
        rendered = rendered.replacingOccurrences(of: "\\(", with: "")
        rendered = rendered.replacingOccurrences(of: "\\)", with: "")

        // Handle remaining \\ line breaks in equations (outside of environments)
        rendered = rendered.replacingOccurrences(of: "\\\\", with: "\n")

        // Handle remaining & alignment signs (convert to spacing)
        rendered = rendered.replacingOccurrences(of: "&", with: "  ")

        // PHASE 1: Handle subscripts FIRST (before superscripts to support combined notation like x_i^2)

        // Subscript with braces: _{10} → ₁₀, _{i+1} → ᵢ₊₁
        do {
            let bracedSubscriptRegex = try NSRegularExpression(pattern: "_\\{([0-9]+)\\}", options: [])
            let range = NSRange(location: 0, length: rendered.utf16.count)
            let matches = bracedSubscriptRegex.matches(in: rendered, options: [], range: range)

            // Process matches in reverse to avoid index shifting
            for match in matches.reversed() {
                if let matchRange = Range(match.range(at: 1), in: rendered) {
                    let digits = String(rendered[matchRange])
                    let subscriptStr = convertToSubscriptDigits(digits)

                    if let fullRange = Range(match.range(at: 0), in: rendered) {
                        rendered.replaceSubrange(fullRange, with: subscriptStr)
                    }
                }
            }
        } catch {
            // Silently fail on regex error
        }

        // Simple subscripts: _2 → ₂, _0 → ₀, log_2 → log₂
        let simpleSubscripts: [(String, String)] = [
            ("_0", "₀"), ("_1", "₁"), ("_2", "₂"), ("_3", "₃"), ("_4", "₄"),
            ("_5", "₅"), ("_6", "₆"), ("_7", "₇"), ("_8", "₈"), ("_9", "₉")
        ]

        for (pattern, replacement) in simpleSubscripts {
            rendered = rendered.replacingOccurrences(of: pattern, with: replacement)
        }

        // PHASE 2: Enhanced superscript support (multi-digit)

        // Superscript with braces: ^{10} → ¹⁰
        do {
            let bracedSuperscriptRegex = try NSRegularExpression(pattern: "\\^\\{([0-9]+)\\}", options: [])
            let range = NSRange(location: 0, length: rendered.utf16.count)
            let matches = bracedSuperscriptRegex.matches(in: rendered, options: [], range: range)

            // Process matches in reverse to avoid index shifting
            for match in matches.reversed() {
                if let matchRange = Range(match.range(at: 1), in: rendered) {
                    let digits = String(rendered[matchRange])
                    let superscriptStr = convertToSuperscriptDigits(digits)

                    if let fullRange = Range(match.range(at: 0), in: rendered) {
                        rendered.replaceSubrange(fullRange, with: superscriptStr)
                    }
                }
            }
        } catch {
            // Silently fail on regex error
        }

        // Convert LaTeX commands to Unicode
        let conversions: [String: String] = [
            // Fractions
            "\\\\frac\\{([^}]+)\\}\\{([^}]+)\\}": "($1)/($2)",

            // Square roots
            "\\\\sqrt\\{([^}]+)\\}": "√($1)",

            // Math operators
            "\\\\cdot": "·",
            "\\\\times": "×",
            "\\\\div": "÷",
            "\\\\pm": "±",

            // Inequalities
            "\\\\leq": "≤",
            "\\\\geq": "≥",
            "\\\\neq": "≠",
            "\\\\approx": "≈",

            // Special symbols
            "\\\\infty": "∞",
            "\\\\pi": "π",
            "\\\\alpha": "α",
            "\\\\beta": "β",
            "\\\\gamma": "γ",
            "\\\\theta": "θ",

            // LaTeX function names (keep as text)
            "\\\\log": "log",
            "\\\\ln": "ln",
            "\\\\sin": "sin",
            "\\\\cos": "cos",
            "\\\\tan": "tan",
            "\\\\lim": "lim",
            "\\\\max": "max",
            "\\\\min": "min",

            // Simple exponents (single digit, already handled above for multi-digit)
            "\\^2": "²",
            "\\^3": "³",

            // Clean up remaining braces and backslashes
            "\\{": "",
            "\\}": "",
            "\\\\": ""
        ]

        for (pattern, replacement) in conversions {
            rendered = rendered.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }

        return rendered
    }
}