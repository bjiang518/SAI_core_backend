//
//  LearningGoalsSettingsView.swift
//  StudyAI
//
//  Learning goals configuration view for settings
//

import SwiftUI

struct LearningGoalsSettingsView: View {
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var dailyQuestionsTarget: Double = 5
    @State private var studyConsistencyTarget: Double = 5
    @State private var accuracyTarget: Double = 80
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Current Points Section
                currentPointsSection
                
                // Learning Goals Section
                learningGoalsSection
                
                Spacer()
                
                // Save Button
                saveButton
            }
            .padding()
            .navigationTitle(NSLocalizedString("goals.learningGoalsTitle", comment: ""))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("common.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                print("🎯 DEBUG: LearningGoalsSettingsView appeared - using PointsEarningManager instance")
                print("🎯 DEBUG: Current learning goals in settings view:")
                for (index, goal) in pointsManager.learningGoals.enumerated() {
                    print("🎯 DEBUG:   Goal \(index): \(goal.type.displayName) - Progress: \(goal.currentProgress)/\(goal.targetValue)")
                }
                loadCurrentValues()
            }
        }
    }
    
    // MARK: - Current Points Section
    
    private var currentPointsSection: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("goals.currentPoints", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(pointsManager.currentPoints)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(NSLocalizedString("goals.streak", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(pointsManager.currentStreak) \(NSLocalizedString("goals.days", comment: ""))")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    // MARK: - Learning Goals Section

    private var learningGoalsSection: some View {
        VStack(spacing: 20) {
            // Daily Questions Goal
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("goals.dailyQuestions", comment: ""))
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(NSLocalizedString("goals.dailyQuestionsDescription", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack {
                    Text(NSLocalizedString("goals.target", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(Int(dailyQuestionsTarget))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text(NSLocalizedString("goals.questionsPerDay", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Slider(value: $dailyQuestionsTarget, in: 1...20, step: 1)
                    .tint(.blue)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Accuracy Goal
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "target")
                        .foregroundColor(.green)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("goals.accuracyGoal", comment: ""))
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(NSLocalizedString("goals.accuracyGoalDescription", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack {
                    Text(NSLocalizedString("goals.target", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(Int(accuracyTarget))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    Text(NSLocalizedString("goals.percentAccuracy", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Slider(value: $accuracyTarget, in: 50...100, step: 5)
                    .tint(.green)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            // Study Consistency Goal (Replaces Weekly Streak to avoid duplication)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundColor(.orange)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(NSLocalizedString("goals.studyConsistency", comment: ""))
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(NSLocalizedString("goals.studyConsistencyDescription", comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack {
                    Text(NSLocalizedString("goals.target", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("\(Int(studyConsistencyTarget))")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("goals.daysPerWeek", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                Slider(value: $studyConsistencyTarget, in: 3...7, step: 1)
                    .tint(.orange)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Save Button
    
    private var saveButton: some View {
        Button(action: saveGoals) {
            HStack {
                Image(systemName: "icloud.and.arrow.up.fill")
                Text(NSLocalizedString("goals.saveToDatabase", comment: ""))
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadCurrentValues() {
        // Load current target values from existing goals
        for goal in pointsManager.learningGoals {
            switch goal.type {
            case .dailyQuestions:
                dailyQuestionsTarget = Double(goal.targetValue)
            case .weeklyStreak:
                studyConsistencyTarget = Double(goal.targetValue)
            case .accuracyGoal:
                accuracyTarget = Double(goal.targetValue)
            default:
                break
            }
        }
    }

    private func saveGoals() {
        print("🎯 DEBUG: Saving goals to database...")
        print("🎯 DEBUG: Daily Questions Target: \(Int(dailyQuestionsTarget))")
        print("🎯 DEBUG: Study Consistency Target: \(Int(studyConsistencyTarget))")
        print("🎯 DEBUG: Accuracy Target: \(Int(accuracyTarget))")

        // Update the goals in PointsEarningManager
        for goal in pointsManager.learningGoals {
            switch goal.type {
            case .dailyQuestions:
                pointsManager.updateLearningGoal(goal.id, targetValue: Int(dailyQuestionsTarget))
            case .weeklyStreak:
                pointsManager.updateLearningGoal(goal.id, targetValue: Int(studyConsistencyTarget))
            case .accuracyGoal:
                pointsManager.updateLearningGoal(goal.id, targetValue: Int(accuracyTarget))
            default:
                break
            }
        }

        // TODO: Add actual database sync logic here
        print("🎯 DEBUG: Goals saved successfully!")

        // Show success feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

#Preview {
    LearningGoalsSettingsView()
}