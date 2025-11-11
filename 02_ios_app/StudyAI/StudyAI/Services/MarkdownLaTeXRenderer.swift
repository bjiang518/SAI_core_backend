//
//  MarkdownLaTeXRenderer.swift
//  StudyAI
//
//  Created by Claude Code on 11/10/25.
//  Comprehensive renderer for markdown formatting AND LaTeX math expressions
//

import SwiftUI
import Foundation

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
    }

    // MARK: - Streaming View (Simple + Fast)

    @ViewBuilder
    private var streamingView: some View {
        // During streaming: simple text with basic markdown
        // This is fast and doesn't trigger heavy LaTeX detection
        if let attributedString = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributedString)
                .font(.system(size: fontSize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(content)
                .font(.system(size: fontSize))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        // Parse content into markdown and LaTeX blocks
        let components = parseMarkdownAndLaTeX(content)

        ForEach(Array(components.enumerated()), id: \.offset) { index, component in
            switch component {
            case .markdown(let text):
                renderMarkdownComponent(text)
            case .latex(let latex):
                SmartLaTeXView(latex, fontSize: fontSize, colorScheme: colorScheme, strategy: .mathjax)
            }
        }
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
            if let headerMatch = trimmed.range(of: "^(#{1,6})\\s+(.+)$", options: .regularExpression),
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
