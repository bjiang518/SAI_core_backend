//
//  MathRenderer.swift
//  StudyAI
//
//  Kept as a compatibility shim.
//  MathFormattedText delegates directly to MarkdownLaTeXText (MathJaxRenderer.swift).
//  All other types in this file were internal and are no longer needed.
//

import SwiftUI

/// Legacy view — kept so all existing call sites compile unchanged.
/// Delegates to MarkdownLaTeXText which uses bundled MathJax for rendering.
struct MathFormattedText: View {
    let content: String
    let fontSize: CGFloat

    init(_ content: String, fontSize: CGFloat = 16, mathBackgroundColor: Color = Color.blue.opacity(0.1)) {
        self.content = content
        self.fontSize = fontSize
    }

    var body: some View {
        MarkdownLaTeXText(content, fontSize: fontSize, isStreaming: false)
    }
}

/// Legacy view — kept for source compatibility.
struct MarkdownTextView: View {
    let markdownText: String
    let fontSize: CGFloat
    init(_ markdownText: String, fontSize: CGFloat = 16) {
        self.markdownText = markdownText
        self.fontSize = fontSize
    }
    var body: some View {
        MarkdownLaTeXText(markdownText, fontSize: fontSize)
    }
}
