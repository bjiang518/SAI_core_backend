//
//  DiagramDebugView.swift
//  StudyAI
//
//  Created for debugging Swift Task Continuation Misuse in diagram rendering
//

import SwiftUI

struct DiagramDebugView: View {
    @State private var testResults: [DiagramTestResult] = []
    @State private var isRunningTests = false
    @State private var selectedTest = 0

    private let testCases = [
        DiagramTestCase(
            name: "Simple Circle",
            svgCode: """
            <svg width="200" height="200" xmlns="http://www.w3.org/2000/svg">
                <circle cx="100" cy="100" r="50" fill="blue" stroke="black" stroke-width="2"/>
            </svg>
            """,
            expectedToWork: true
        ),
        DiagramTestCase(
            name: "Rectangle with Text",
            svgCode: """
            <svg width="300" height="150" xmlns="http://www.w3.org/2000/svg">
                <rect x="50" y="50" width="200" height="50" fill="green" stroke="black"/>
                <text x="150" y="80" text-anchor="middle" fill="white">Test Rectangle</text>
            </svg>
            """,
            expectedToWork: true
        ),
        DiagramTestCase(
            name: "Invalid SVG (Missing Tag)",
            svgCode: """
            <div>This is not SVG</div>
            """,
            expectedToWork: false
        ),
        DiagramTestCase(
            name: "Complex SVG",
            svgCode: """
            <svg width="400" height="300" xmlns="http://www.w3.org/2000/svg">
                <defs>
                    <linearGradient id="grad1" x1="0%" y1="0%" x2="100%" y2="0%">
                        <stop offset="0%" style="stop-color:rgb(255,255,0);stop-opacity:1" />
                        <stop offset="100%" style="stop-color:rgb(255,0,0);stop-opacity:1" />
                    </linearGradient>
                </defs>
                <ellipse cx="200" cy="150" rx="100" ry="80" fill="url(#grad1)" />
            </svg>
            """,
            expectedToWork: true
        ),
        DiagramTestCase(
            name: "Empty SVG",
            svgCode: """
            <svg width="200" height="200" xmlns="http://www.w3.org/2000/svg">
            </svg>
            """,
            expectedToWork: true
        )
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Test Selection
                Picker("Test Case", selection: $selectedTest) {
                    ForEach(testCases.indices, id: \.self) { index in
                        Text(testCases[index].name).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())

                // Current Test Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Test: \(testCases[selectedTest].name)")
                        .font(.headline)

                    Text("Expected to work: \(testCases[selectedTest].expectedToWork ? "✅ Yes" : "❌ No")")
                        .foregroundColor(testCases[selectedTest].expectedToWork ? .green : .red)

                    Text("SVG Code Preview:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ScrollView {
                        Text(testCases[selectedTest].svgCode)
                            .font(.system(size: 10, family: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(12)

                // Test Button
                Button(action: runSingleTest) {
                    HStack {
                        Image(systemName: isRunningTests ? "arrow.clockwise" : "play.circle")
                            .rotationEffect(.degrees(isRunningTests ? 360 : 0))
                            .animation(isRunningTests ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRunningTests)

                        Text(isRunningTests ? "Testing..." : "Run Test")
                            .fontWeight(.medium)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isRunningTests ? Color.orange : Color.blue)
                .cornerRadius(12)
                .disabled(isRunningTests)

                // Run All Tests Button
                Button(action: runAllTests) {
                    Text("Run All Tests")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(12)
                }
                .disabled(isRunningTests)

                // Test Results
                if !testResults.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Test Results:")
                            .font(.headline)

                        ForEach(testResults, id: \.id) { result in
                            DiagramTestResultCard(result: result)
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("🔍 Diagram Debug")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func runSingleTest() {
        guard !isRunningTests else { return }

        let testCase = testCases[selectedTest]
        print("🧪 === STARTING SINGLE DIAGRAM TEST ===")
        print("🧪 Test: \(testCase.name)")
        print("🧪 Expected to work: \(testCase.expectedToWork)")

        isRunningTests = true

        Task {
            let result = await performDiagramTest(testCase)

            await MainActor.run {
                // Remove any existing result for this test
                testResults.removeAll { $0.testName == testCase.name }
                testResults.insert(result, at: 0)
                isRunningTests = false
            }
        }
    }

    private func runAllTests() {
        guard !isRunningTests else { return }

        print("🧪 === STARTING ALL DIAGRAM TESTS ===")
        isRunningTests = true
        testResults.removeAll()

        Task {
            for testCase in testCases {
                let result = await performDiagramTest(testCase)

                await MainActor.run {
                    testResults.append(result)
                }

                // Small delay between tests
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }

            await MainActor.run {
                isRunningTests = false
                print("🧪 === ALL TESTS COMPLETED ===")
            }
        }
    }

    private func performDiagramTest(_ testCase: DiagramTestCase) async -> DiagramTestResult {
        let startTime = Date()

        print("🧪 [Test: \(testCase.name)] Starting test...")

        do {
            let image = try await SVGRenderer.shared.renderSVG(
                testCase.svgCode,
                hint: NetworkService.DiagramRenderingHint(
                    width: 300,
                    height: 200,
                    background: "white",
                    scaleFactor: 1.0
                )
            )

            let duration = Date().timeIntervalSince(startTime)
            print("🧪 [Test: \(testCase.name)] ✅ SUCCESS in \(Int(duration * 1000))ms")

            return DiagramTestResult(
                id: UUID(),
                testName: testCase.name,
                success: true,
                duration: duration,
                imageSize: image.size,
                errorMessage: nil
            )

        } catch {
            let duration = Date().timeIntervalSince(startTime)
            let errorMsg = error.localizedDescription
            print("🧪 [Test: \(testCase.name)] ❌ FAILED in \(Int(duration * 1000))ms: \(errorMsg)")

            return DiagramTestResult(
                id: UUID(),
                testName: testCase.name,
                success: false,
                duration: duration,
                imageSize: nil,
                errorMessage: errorMsg
            )
        }
    }
}

// MARK: - Supporting Types

struct DiagramTestCase {
    let name: String
    let svgCode: String
    let expectedToWork: Bool
}

struct DiagramTestResult {
    let id: UUID
    let testName: String
    let success: Bool
    let duration: TimeInterval
    let imageSize: CGSize?
    let errorMessage: String?
}

// MARK: - Test Result Card

struct DiagramTestResultCard: View {
    let result: DiagramTestResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(result.success ? .green : .red)

                Text(result.testName)
                    .fontWeight(.medium)

                Spacer()

                Text("\(Int(result.duration * 1000))ms")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if result.success {
                if let size = result.imageSize {
                    Text("Image: \(Int(size.width))×\(Int(size.height))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                if let error = result.errorMessage {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding()
        .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(result.success ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

struct DiagramDebugView_Previews: PreviewProvider {
    static var previews: some View {
        DiagramDebugView()
    }
}