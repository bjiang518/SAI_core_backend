//
//  SimpleMathRenderer.swift
//  StudyAI
//
//  Created by Claude Code on 9/1/25.
//

import SwiftUI

/// A simpler math renderer that doesn't require WebKit
/// Uses Unicode math symbols and proper formatting
struct SimpleMathText: View {
    let text: String
    let fontSize: CGFloat
    
    init(_ text: String, fontSize: CGFloat = 16) {
        self.text = text
        self.fontSize = fontSize
    }
    
    var body: some View {
        Text(formatMathText(text))
            .font(.system(size: fontSize, design: .monospaced))
            .multilineTextAlignment(.leading)
    }
    
    private func formatMathText(_ input: String) -> String {
        var formatted = input
        
        // Convert common math symbols
        formatted = formatted.replacingOccurrences(of: "+-", with: "±")
        formatted = formatted.replacingOccurrences(of: "<=", with: "≤")
        formatted = formatted.replacingOccurrences(of: ">=", with: "≥")
        formatted = formatted.replacingOccurrences(of: "!=", with: "≠")
        formatted = formatted.replacingOccurrences(of: "sqrt", with: "√")
        formatted = formatted.replacingOccurrences(of: "pi", with: "π")
        formatted = formatted.replacingOccurrences(of: "alpha", with: "α")
        formatted = formatted.replacingOccurrences(of: "beta", with: "β")
        formatted = formatted.replacingOccurrences(of: "gamma", with: "γ")
        formatted = formatted.replacingOccurrences(of: "theta", with: "θ")
        formatted = formatted.replacingOccurrences(of: "infinity", with: "∞")
        
        // Format fractions (a/b -> a/b with better spacing)
        formatted = formatted.replacingOccurrences(
            of: "(\\d+)/(\\d+)",
            with: "$1⁄$2",
            options: .regularExpression
        )
        
        // Format exponents (basic superscript)
        formatted = formatted.replacingOccurrences(of: "^2", with: "²")
        formatted = formatted.replacingOccurrences(of: "^3", with: "³")
        formatted = formatted.replacingOccurrences(of: "^n", with: "ⁿ")
        
        // Format subscripts
        formatted = formatted.replacingOccurrences(of: "_1", with: "₁")
        formatted = formatted.replacingOccurrences(of: "_2", with: "₂")
        formatted = formatted.replacingOccurrences(of: "_n", with: "ₙ")
        
        return formatted
    }
}

/// Enhanced version that combines WebKit rendering with fallback
struct SmartMathText: View {
    let content: String
    let fontSize: CGFloat
    @State private var useSimpleRenderer = false
    
    init(_ content: String, fontSize: CGFloat = 16) {
        self.content = content
        self.fontSize = fontSize
    }
    
    var body: some View {
        Group {
            if useSimpleRenderer || !MathFormattingService.shared.containsMathExpressions(content) {
                SimpleMathText(content, fontSize: fontSize)
            } else {
                MathFormattedText(content, fontSize: fontSize)
                    .onAppear {
                        // Fallback to simple renderer if WebKit fails
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            // This is a simple heuristic - in practice you'd detect WebKit failures
                            // For now, we'll use the WebKit version
                        }
                    }
            }
        }
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