//
//  CompactSubjectSelector.swift
//  StudyAI
//
//  Compact horizontal subject selector with center focus design
//

import SwiftUI

struct CompactSubjectSelector: View {
    let subjects: [SubjectMistakeCount]
    @Binding var selectedSubject: String?
    @Namespace private var animation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subjects")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal)

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
                                VStack(spacing: 8) {
                                    Text(subject.subject)
                                        .font(isSelected ? .title3 : .subheadline)
                                        .fontWeight(isSelected ? .bold : .medium)
                                        .foregroundColor(isSelected ? .primary : .secondary)

                                    // Badge with mistake count
                                    Text("\(subject.mistakeCount)")
                                        .font(isSelected ? .caption : .caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, isSelected ? 8 : 6)
                                        .padding(.vertical, isSelected ? 4 : 3)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color.blue : Color.red)
                                        )
                                }
                                .padding(.horizontal, isSelected ? 20 : 12)
                                .padding(.vertical, isSelected ? 16 : 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                                        )
                                )
                                .scaleEffect(isSelected ? 1.1 : 0.85)
                                .opacity(isSelected ? 1.0 : 0.6)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .id(subject.subject)
                        }
                    }
                    .padding(.horizontal, 100) // Add padding to allow centering
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
    }
}
