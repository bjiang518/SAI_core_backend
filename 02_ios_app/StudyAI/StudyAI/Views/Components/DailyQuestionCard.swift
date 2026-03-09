//
//  DailyQuestionCard.swift
//  StudyAI
//
//  Simple full-screen card shown when the user taps the "Did you know?" daily question todo.
//

import SwiftUI

struct DailyQuestionCard: View {
    let question: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.gray.opacity(0.35))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "FFD700"))
                .padding(.bottom, 16)

            Text(NSLocalizedString("todo.dailyQuestion.title", value: "你知道吗？", comment: ""))
                .font(.headline)
                .foregroundColor(themeManager.secondaryText)

            Text(question)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .foregroundColor(themeManager.primaryText)
                .padding(.horizontal, 28)
                .padding(.top, 12)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text(NSLocalizedString("common.close", value: "关闭", comment: ""))
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "FFD700"))
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
            }
            .padding(.bottom, 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.cardBackground.ignoresSafeArea())
    }
}
