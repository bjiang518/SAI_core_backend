//
//  CompactSubjectSelector.swift
//  StudyAI
//
//  Compact horizontal subject selector with center focus design,
//  subject-specific icon watermarks, and glow on selected card.
//

import SwiftUI

struct CompactSubjectSelector: View {
    let subjects: [SubjectMistakeCount]
    @Binding var selectedSubject: String?
    @Namespace private var animation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(subjects, id: \.subject) { subject in
                        let isSelected = selectedSubject == subject.subject

                        Button(action: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedSubject = subject.subject
                                proxy.scrollTo(subject.subject, anchor: .center)
                            }
                        }) {
                            subjectCard(subject: subject, isSelected: isSelected)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(subject.subject)
                    }
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedSubject) { newValue in
                if let newValue = newValue {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .onAppear {
                if let selected = selectedSubject {
                    proxy.scrollTo(selected, anchor: .center)
                }
            }
        }
    }

    // MARK: - Subject Card

    private func subjectCard(subject: SubjectMistakeCount, isSelected: Bool) -> some View {
        subjectCardContent(subject: subject, isSelected: isSelected)
            .padding(.horizontal, isSelected ? 22 : 14)
            .padding(.vertical, isSelected ? 18 : 12)
            .background(cardBackground(isSelected: isSelected))
            .shadow(
                color: isSelected ? Color.blue.opacity(0.45) : Color.black.opacity(0.05),
                radius: isSelected ? 14 : 4,
                x: 0, y: isSelected ? 0 : 2
            )
            .scaleEffect(isSelected ? 1.1 : 0.88)
            .opacity(isSelected ? 1.0 : 0.65)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
    }

    @ViewBuilder
    private func subjectCardContent(subject: SubjectMistakeCount, isSelected: Bool) -> some View {
        ZStack {
            // Icon fills the full card as background
            Image(systemName: subject.icon)
                .resizable()
                .scaledToFit()
                .frame(width: isSelected ? 54 : 42, height: isSelected ? 54 : 42)
                .foregroundColor(isSelected ? Color.blue.opacity(0.15) : Color.gray.opacity(0.10))

            // Text content — centered on top
            VStack(spacing: 6) {
                subjectLabel(subject: subject, isSelected: isSelected)
                countBadge(count: subject.mistakeCount, isSelected: isSelected)
            }
        }
    }

    @ViewBuilder
    private func subjectLabel(subject: SubjectMistakeCount, isSelected: Bool) -> some View {
        let displayName: String = {
            let raw = subject.subject
            if raw.hasPrefix("Others: ") {
                // Strip prefix, localize just the suffix: "Others: French" → "French" / "法语"
                return BranchLocalizer.localized(String(raw.dropFirst("Others: ".count)))
            }
            return NSLocalizedString(
                "subject.\(raw.lowercased().replacingOccurrences(of: " ", with: ""))",
                value: raw, comment: ""
            )
        }()
        Text(displayName)
            .font(isSelected ? .title3 : .subheadline)
            .fontWeight(isSelected ? .bold : .medium)
            .foregroundColor(isSelected ? .primary : .secondary)
    }

    @ViewBuilder
    private func countBadge(count: Int, isSelected: Bool) -> some View {
        Text("\(count)")
            .font(isSelected ? .caption : .caption2)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, isSelected ? 8 : 6)
            .padding(.vertical, isSelected ? 4 : 3)
            .background(Capsule().fill(isSelected ? Color.blue : Color.red))
    }

    private func cardBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(isSelected ? Color.blue.opacity(0.08) : Color(uiColor: .systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.blue.opacity(0.7) : Color.clear, lineWidth: 2)
            )
    }
}
