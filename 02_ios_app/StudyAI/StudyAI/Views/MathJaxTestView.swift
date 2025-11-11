//
//  MathJaxTestView.swift
//  StudyAI
//
//  Test view to verify MathJax rendering is working
//  Add this to your app temporarily to test
//

import SwiftUI

struct MathJaxTestView: View {
    @State private var selectedTest = 0

    let testCases: [(title: String, latex: String)] = [
        (
            title: "Simple Equation",
            latex: "x^2 + 3x + 2 = 0"
        ),
        (
            title: "Quadratic Formula",
            latex: "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}"
        ),
        (
            title: "Integral",
            latex: "\\int_{0}^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}"
        ),
        (
            title: "Multi-line (Aligned)",
            latex: """
            \\begin{align}
            f'(x) &= \\lim_{h \\to 0} \\frac{f(x+h) - f(x)}{h} \\\\
            &= \\frac{d}{dx}(x^2) \\\\
            &= 2x
            \\end{align}
            """
        ),
        (
            title: "Matrix",
            latex: """
            \\begin{pmatrix}
            1 & 2 & 3 \\\\
            4 & 5 & 6 \\\\
            7 & 8 & 9
            \\end{pmatrix}
            """
        ),
        (
            title: "System of Equations",
            latex: """
            \\begin{align}
            2x + 3y &= 7 \\\\
            x - y &= 2
            \\end{align}
            """
        ),
        (
            title: "Summation",
            latex: "\\sum_{i=1}^{n} i^2 = \\frac{n(n+1)(2n+1)}{6}"
        ),
        (
            title: "Limit",
            latex: "\\lim_{x \\to \\infty} \\frac{1}{x} = 0"
        )
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Test case picker
                Picker("Select Test", selection: $selectedTest) {
                    ForEach(0..<testCases.count, id: \.self) { index in
                        Text(testCases[index].title)
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                .background(Color(.systemGray6))

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // LaTeX source
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LaTeX Source:")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Text(testCases[selectedTest].latex)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }

                        Divider()

                        // OLD Renderer (SimpleMathRenderer)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("OLD: SimpleMathRenderer")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.orange)
                                Text("Instant")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }

                            Text(SimpleMathRenderer.renderMathText(testCases[selectedTest].latex))
                                .font(.system(size: 18))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange, lineWidth: 2)
                                )
                        }

                        Divider()

                        // NEW Renderer (MathJax with fallback)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("NEW: FullLaTeXText (Auto)")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "sparkles")
                                    .foregroundColor(.blue)
                                Text("Smart")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }

                            FullLaTeXText(
                                testCases[selectedTest].latex,
                                fontSize: 18,
                                strategy: .auto
                            )
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.blue, lineWidth: 2)
                            )
                        }

                        Divider()

                        // Strategy comparison
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Strategy Comparison")
                                .font(.headline)

                            // Auto strategy
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto Strategy:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(strategyDescription)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }

                            // Force MathJax
                            HStack {
                                Text("Force MathJax:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            FullLaTeXText(
                                testCases[selectedTest].latex,
                                fontSize: 16,
                                strategy: .mathjax
                            )
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)

                            // Force Simplified
                            HStack {
                                Text("Force Simplified:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            FullLaTeXText(
                                testCases[selectedTest].latex,
                                fontSize: 16,
                                strategy: .simplified
                            )
                            .padding()
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("MathJax Renderer Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var strategyDescription: String {
        let latex = testCases[selectedTest].latex
        let strategy = FullLaTeXRenderer.shared.determineStrategy(for: latex)

        switch strategy {
        case .mathjax:
            return "✨ Complex equation detected → Using MathJax for high-quality rendering"
        case .simplified:
            return "⚡ Simple equation → Using SimpleMathRenderer for instant rendering"
        case .auto:
            return "🤖 Auto-detecting..."
        }
    }
}

#Preview {
    MathJaxTestView()
}
