//
//  SimpleMathRenderer.swift
//  StudyAI
//
//  Kept as a stub for source compatibility.
//  All rendering is now handled by MathJaxRenderer.swift (bundled MathJax).
//  Nothing in this file is called by live UI code.
//

import SwiftUI

// MARK: - Compatibility stubs

/// No-op post-processor — kept so any remaining call sites compile.
class LaTeXPostProcessor {
    static let shared = LaTeXPostProcessor()
    private init() {}
    func processAIOutput(_ input: String) -> String { input }
    func needsPostProcessing(_ text: String) -> Bool { false }
}

/// Simplified renderer stub — returns input unchanged.
/// All actual rendering is done by MathJax in MathJaxRenderer.swift.
class SimpleMathRenderer {
    static func renderMathText(_ input: String) -> String { input }
}

/// Stub view — delegates to MarkdownLaTeXText.
struct SmartMathRenderer: View {
    let content: String
    let fontSize: CGFloat
    init(_ content: String, fontSize: CGFloat = 16) {
        self.content = content
        self.fontSize = fontSize
    }
    var body: some View {
        MarkdownLaTeXText(content, fontSize: fontSize)
    }
}

/// Stub view — delegates to MarkdownLaTeXText.
struct EnhancedMathText: View {
    let text: String
    let fontSize: CGFloat
    init(_ text: String, fontSize: CGFloat = 16) {
        self.text = text
        self.fontSize = fontSize
    }
    var body: some View {
        MarkdownLaTeXText(text, fontSize: fontSize)
    }
}
