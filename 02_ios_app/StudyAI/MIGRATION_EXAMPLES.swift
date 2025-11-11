//
//  MathRendererMigrationExamples.swift
//  StudyAI
//
//  Examples showing how to migrate from SimpleMathRenderer to FullLaTeXText
//  This file is for reference only - copy patterns to your actual views
//

import SwiftUI

// MARK: - Example 1: Simple Migration (SessionChat/MessageBubbles.swift)

struct MessageBubbleView_BEFORE: View {
    let message: [String: String]
    let isUser: Bool

    var body: some View {
        VStack {
            // OLD: Using MathFormattedText
            MathFormattedText(
                message["content"] ?? "",
                fontSize: 20,
                mathBackgroundColor: isUser ? Color.green.opacity(0.15) : Color.blue.opacity(0.15)
            )
            .textSelection(.enabled)
        }
    }
}

struct MessageBubbleView_AFTER: View {
    let message: [String: String]
    let isUser: Bool

    var body: some View {
        VStack {
            // NEW: Using FullLaTeXText with auto-strategy
            FullLaTeXText(
                message["content"] ?? "",
                fontSize: 20,
                strategy: .auto  // Automatically chooses best renderer
            )
            .textSelection(.enabled)
        }
    }
}

// MARK: - Example 2: Question Display with Strategy Selection

struct QuestionView_BEFORE: View {
    let question: String
    let complexity: QuestionComplexity

    var body: some View {
        // OLD: Always uses simplified renderer
        MathFormattedText(question, fontSize: 16)
    }
}

struct QuestionView_AFTER: View {
    let question: String
    let complexity: QuestionComplexity

    var body: some View {
        // NEW: Strategy based on complexity
        FullLaTeXText(
            question,
            fontSize: 16,
            strategy: complexity.renderStrategy
        )
    }
}

enum QuestionComplexity {
    case simple    // Basic algebra
    case moderate  // Fractions, exponents
    case advanced  // Integrals, matrices

    var renderStrategy: MathRenderStrategy {
        switch self {
        case .simple:
            return .simplified  // Fast, offline
        case .moderate:
            return .auto       // Let system decide
        case .advanced:
            return .mathjax    // Full LaTeX support
        }
    }
}

// MARK: - Example 3: Mixed Content (Text + Math)

struct ExplanationView_BEFORE: View {
    let explanation: String

    var body: some View {
        // OLD: MathFormattedText tries to parse mixed content
        MathFormattedText(explanation, fontSize: 14)
    }
}

struct ExplanationView_AFTER: View {
    let explanation: String

    var body: some View {
        // NEW: MixedLaTeXView handles text and math separately
        MixedLaTeXView(explanation, fontSize: 14)
    }
}

// MARK: - Example 4: List of Equations

struct EquationListView_BEFORE: View {
    let equations: [String]

    var body: some View {
        List(equations, id: \.self) { equation in
            MathFormattedText(equation, fontSize: 16)
        }
    }
}

struct EquationListView_AFTER: View {
    let equations: [String]

    var body: some View {
        List(equations, id: \.self) { equation in
            // Auto-strategy optimizes each equation individually
            FullLaTeXText(equation, fontSize: 16, strategy: .auto)
                .padding(.vertical, 4)
        }
    }
}

// MARK: - Example 5: Conditional Rendering (Performance Critical)

struct PerformanceCriticalView_AFTER: View {
    let content: String
    let isOfflineMode: Bool
    let isPowerSavingMode: Bool

    var body: some View {
        FullLaTeXText(
            content,
            fontSize: 16,
            strategy: renderStrategy
        )
    }

    private var renderStrategy: MathRenderStrategy {
        // Offline or power saving? Use simplified
        if isOfflineMode || isPowerSavingMode {
            return .simplified
        }

        // Online and not power saving? Use auto
        return .auto
    }
}

// MARK: - Example 6: Chat Message with Streaming

struct StreamingMessageView_AFTER: View {
    let streamingMessage: String
    let isComplete: Bool

    var body: some View {
        VStack(alignment: .leading) {
            if isComplete {
                // Complete message: Use full LaTeX
                FullLaTeXText(streamingMessage, fontSize: 18, strategy: .auto)
            } else {
                // Streaming: Use simplified for instant updates
                Text(SimpleMathRenderer.renderMathText(streamingMessage))
                    .font(.system(size: 18))
                    .foregroundColor(.primary.opacity(0.7))
            }
        }
    }
}

// MARK: - Example 7: With Loading State

struct MathWithLoadingView: View {
    let content: String
    @State private var isRendered = false

    var body: some View {
        ZStack {
            // Show simplified version while loading
            if !isRendered {
                Text(SimpleMathRenderer.renderMathText(content))
                    .opacity(0.6)
            }

            // Full LaTeX (will auto-hide simplified when ready)
            FullLaTeXText(content, fontSize: 16, strategy: .mathjax)
                .opacity(isRendered ? 1 : 0)
                .onAppear {
                    // Mark as rendered after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            isRendered = true
                        }
                    }
                }
        }
    }
}

// MARK: - Example 8: Adaptive Font Size

struct AdaptiveMathView: View {
    let content: String
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        FullLaTeXText(
            content,
            fontSize: adaptiveFontSize,
            strategy: .auto
        )
    }

    private var adaptiveFontSize: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small:
            return 14
        case .medium, .large:
            return 16
        case .xLarge, .xxLarge:
            return 18
        default:
            return 20
        }
    }
}

// MARK: - Example 9: Batch Processing (QuestionArchive)

struct QuestionArchiveView_AFTER: View {
    let questions: [ArchivedQuestion]

    var body: some View {
        List(questions) { question in
            VStack(alignment: .leading, spacing: 12) {
                // Question text
                FullLaTeXText(
                    question.questionText,
                    fontSize: 16,
                    strategy: .auto
                )

                // Student answer
                if let studentAnswer = question.studentAnswer {
                    HStack {
                        Text("Your answer:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    FullLaTeXText(
                        studentAnswer,
                        fontSize: 14,
                        strategy: .simplified  // Simple answers
                    )
                }

                // Correct answer
                HStack {
                    Text("Correct answer:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                FullLaTeXText(
                    question.correctAnswer,
                    fontSize: 14,
                    strategy: .auto
                )
            }
            .padding(.vertical, 8)
        }
    }
}

struct ArchivedQuestion: Identifiable {
    let id: UUID
    let questionText: String
    let studentAnswer: String?
    let correctAnswer: String
}

// MARK: - Example 10: Global Replacement Helper

/// Helper to create a unified math text view that can be switched globally
struct AppMathText: View {
    let content: String
    let fontSize: CGFloat
    let useNewRenderer: Bool  // Feature flag

    init(
        _ content: String,
        fontSize: CGFloat = 16,
        useNewRenderer: Bool = true  // Default to new renderer
    ) {
        self.content = content
        self.fontSize = fontSize
        self.useNewRenderer = useNewRenderer
    }

    var body: some View {
        if useNewRenderer {
            FullLaTeXText(content, fontSize: fontSize, strategy: .auto)
        } else {
            // Fallback to old renderer
            MathFormattedText(content, fontSize: fontSize)
        }
    }
}

// MARK: - Migration Checklist

/*
 ✅ Step-by-Step Migration:

 1. Add MathJaxRenderer.swift to project
 2. Update Info.plist for CDN access
 3. Start with non-critical views (testing):
    - ArchivedQuestionsView
    - QuestionDetailView
 4. Move to critical views (after testing):
    - SessionChatView
    - MessageBubbles
 5. Add feature flag for easy rollback:
    @AppStorage("useFullLaTeX") var useFullLaTeX = true
 6. Monitor performance and fallback usage
 7. Adjust AI prompts for better LaTeX output
 8. Full rollout after 1 week of testing

 📊 Testing Matrix:

 Simple Equations:
 - ✓ "x^2 + 3x + 2 = 0"
 - ✓ "\\frac{1}{2} + \\frac{1}{3}"
 - ✓ "\\sqrt{16} = 4"

 Moderate Equations:
 - ✓ Nested fractions
 - ✓ Multi-variable expressions
 - ✓ Greek letters

 Complex Equations:
 - ✓ align environments
 - ✓ Matrices
 - ✓ Integrals with limits
 - ✓ Summations

 Edge Cases:
 - ✓ Offline mode
 - ✓ Network timeout
 - ✓ Malformed LaTeX
 - ✓ Empty content
 - ✓ Very long equations
 */

// MARK: - Performance Monitoring

struct MathRenderingStats {
    static var mathjaxUsageCount = 0
    static var simplifiedUsageCount = 0
    static var fallbackCount = 0
    static var averageRenderTime: TimeInterval = 0

    static func logRendering(strategy: MathRenderStrategy, renderTime: TimeInterval) {
        switch strategy {
        case .mathjax:
            mathjaxUsageCount += 1
        case .simplified:
            simplifiedUsageCount += 1
        case .auto:
            break
        }

        averageRenderTime = (averageRenderTime + renderTime) / 2

        print("""
        📊 Math Rendering Stats:
        MathJax: \(mathjaxUsageCount)
        Simplified: \(simplifiedUsageCount)
        Fallbacks: \(fallbackCount)
        Avg render time: \(String(format: "%.2f", averageRenderTime))ms
        """)
    }
}
