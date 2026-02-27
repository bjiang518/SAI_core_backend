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
                        label: NSLocalizedString("pdf.options.fontSize", comment: ""),
                        value: $draft.questionFontSize,
                        range: 6...30,
                        step: 1,
                        format: "%.0f pt"
                    )
                } header: {
                    Text(NSLocalizedString("pdf.options.section.text", comment: ""))
                }

                Section {
                    LabeledSlider(
                        label: NSLocalizedString("pdf.options.gap", comment: ""),
                        value: $draft.questionGap,
                        range: 10...150,
                        step: 5,
                        format: "%.0f pt"
                    )
                } header: {
                    Text(NSLocalizedString("pdf.options.section.spacing", comment: ""))
                }

                if hasImages {
                    Section {
                        LabeledSlider(
                            label: NSLocalizedString("pdf.options.maxImageSize", comment: ""),
                            value: $draft.maxImageSize,
                            range: 80...520,
                            step: 20,
                            format: "%.0f pt"
                        )
                        LabeledSlider(
                            label: NSLocalizedString("pdf.options.maxSubImageSize", comment: ""),
                            value: $draft.maxSubImageSize,
                            range: 60...400,
                            step: 20,
                            format: "%.0f pt"
                        )
                    } header: {
                        Text(NSLocalizedString("pdf.options.section.images", comment: ""))
                    }
                }

                Section {
                    Button(NSLocalizedString("pdf.options.reset", comment: "")) {
                        draft = PDFExportOptions()
                    }
                    .foregroundColor(.orange)
                } footer: {
                    Text(NSLocalizedString("pdf.options.footer", comment: ""))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(NSLocalizedString("pdf.options.title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.apply", comment: "")) {
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
