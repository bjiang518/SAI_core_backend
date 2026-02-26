//
//  PDFOptionsSheet.swift
//  StudyAI
//
//  Shared customisation sheet used by all four PDF export preview views.
//  Pass hasImages: false to automatically hide the image-size section
//  (used by text-only paths such as Practice Questions and Mistake Review).
//

import SwiftUI

// MARK: - Options Sheet

struct PDFOptionsSheet: View {
    @Binding var options: PDFExportOptions
    /// Whether the PDF being generated contains images.
    /// When false the Images section is hidden automatically.
    let hasImages: Bool
    let onApply: () -> Void

    @State private var draft: PDFExportOptions
    @Environment(\.dismiss) private var dismiss

    init(options: Binding<PDFExportOptions>, hasImages: Bool, onApply: @escaping () -> Void) {
        self._options = options
        self.hasImages = hasImages
        self.onApply = onApply
        self._draft = State(initialValue: options.wrappedValue)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    LabeledSlider(
                        label: "Font Size",
                        value: $draft.questionFontSize,
                        range: 10...20,
                        step: 1,
                        format: "%.0f pt"
                    )
                } header: {
                    Text("Text")
                }

                Section {
                    LabeledSlider(
                        label: "Gap Between Questions",
                        value: $draft.questionGap,
                        range: 16...64,
                        step: 4,
                        format: "%.0f pt"
                    )
                } header: {
                    Text("Spacing")
                }

                if hasImages {
                    Section {
                        LabeledSlider(
                            label: "Max Image Height",
                            value: $draft.maxImageHeight,
                            range: 100...500,
                            step: 25,
                            format: "%.0f pt"
                        )
                        LabeledSlider(
                            label: "Max Sub-image Height",
                            value: $draft.maxSubImageHeight,
                            range: 80...300,
                            step: 25,
                            format: "%.0f pt"
                        )
                    } header: {
                        Text("Images")
                    }
                }

                Section {
                    Button("Reset to Defaults") {
                        draft = PDFExportOptions()
                    }
                    .foregroundColor(.orange)
                } footer: {
                    Text("Tap Apply to regenerate the PDF with these settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") {
                        options = draft
                        dismiss()
                        onApply()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Slider helper (internal to this module)

struct LabeledSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let step: CGFloat
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: format, value))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(.blue)
        }
        .padding(.vertical, 4)
    }
}
