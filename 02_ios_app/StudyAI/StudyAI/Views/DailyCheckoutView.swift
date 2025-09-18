//
//  DailyCheckoutView.swift
//  StudyAI
//
//  Daily checkout system for collecting points
//

import SwiftUI

struct DailyCheckoutView: View {
    @ObservedObject private var pointsManager = PointsEarningManager.shared
    @State private var showingCheckoutAnimation = false
    @State private var checkoutResult: DailyCheckout?
    @State private var animationScale: CGFloat = 1.0
    @State private var showingPointsBreakdown = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        if showingCheckoutAnimation, let result = checkoutResult {
                            // Success animation and results
                            checkoutSuccessView(result)
                        } else {
                            // Pre-checkout overview
                            checkoutPreviewView
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(showingCheckoutAnimation ? "Points Earned!" : "Daily Checkout")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Checkout Preview View
    
    private var checkoutPreviewView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Ready to Checkout?")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Collect your points for today's achievements!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Goals Completion Overview
            goalsOverviewSection
            
            // Points Preview
            pointsPreviewSection
            
            // Weekend Bonus
            if Calendar.current.isDateInWeekend(Date()) {
                weekendBonusSection
            }
            
            // Checkout Button
            Button(action: performCheckout) {
                HStack {
                    Image(systemName: "creditcard.fill")
                    Text("Checkout Now")
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
            .scaleEffect(animationScale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    animationScale = 1.05
                }
            }
            .disabled(!canCheckoutToday())
            
            if !canCheckoutToday() {
                Text("You've already checked out today!\nCome back tomorrow for more points.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .italic()
            }
            
            // Checkout History
            if !pointsManager.dailyCheckoutHistory.isEmpty {
                checkoutHistorySection
            }
        }
    }
    
    // MARK: - Goals Overview Section
    
    private var goalsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Today's Goals")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(pointsManager.learningGoals.filter { $0.isDaily }) { goal in
                    GoalCheckoutCard(goal: goal)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Points Preview Section
    
    private var pointsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Points Summary")
                .font(.headline)
            
            VStack(spacing: 8) {
                ForEach(pointsManager.learningGoals.filter { $0.isDaily && $0.isCompleted }) { goal in
                    HStack {
                        Image(systemName: goal.type.icon)
                            .foregroundColor(goal.type.color)
                        Text(goal.title)
                        Spacer()
                        Text("+\(goal.pointsEarned)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
                
                // Weekly streak bonus
                if let weeklyGoal = pointsManager.learningGoals.first(where: { $0.type == .weeklyStreak }),
                   weeklyGoal.isCompleted {
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundColor(.orange)
                        Text("Weekly Streak Bonus")
                        Spacer()
                        Text("+\(weeklyGoal.pointsEarned)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("Total Points")
                        .font(.headline)
                    Spacer()
                    Text("+\(calculateTotalPoints())")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Weekend Bonus Section
    
    private var weekendBonusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.orange)
                Text("Weekend Bonus!")
                    .font(.headline)
                    .foregroundColor(.orange)
                Spacer()
            }
            
            Text("Your points will be doubled because it's the weekend!")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Final Points:")
                    .font(.headline)
                Spacer()
                Text("+\(calculateTotalPoints() * 2)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
        )
    }
    
    // MARK: - Checkout Success View
    
    private func checkoutSuccessView(_ result: DailyCheckout) -> some View {
        VStack(spacing: 24) {
            // Success Animation
            VStack(spacing: 16) {
                // Animated checkmark or celebration icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                    .scaleEffect(showingCheckoutAnimation ? 1.2 : 0.8)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showingCheckoutAnimation)
                
                Text("Checkout Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                
                Text("You earned \(result.finalPoints) points today!")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
            }
            
            // Results Breakdown
            VStack(alignment: .leading, spacing: 16) {
                Text("Breakdown")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Goals Completed:")
                        Spacer()
                        Text("\(result.goalsCompleted)")
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Base Points:")
                        Spacer()
                        Text("\(result.pointsEarned)")
                            .fontWeight(.semibold)
                    }
                    
                    if result.isWeekend {
                        HStack {
                            Text("Weekend Bonus:")
                            Spacer()
                            Text("×2")
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Total Points:")
                            .font(.headline)
                        Spacer()
                        Text("\(result.finalPoints)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(16)
            
            // Current Stats
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Stats")
                    .font(.headline)
                
                HStack {
                    VStack {
                        Text("\(pointsManager.currentPoints)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        Text("Total Points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack {
                        Text("\(result.streak)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        Text("Day Streak")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack {
                        Text("\(pointsManager.totalPointsEarned)")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        Text("Lifetime Total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(16)
            
            // Next Steps
            VStack(spacing: 12) {
                Text("Come Back Tomorrow!")
                    .font(.headline)
                
                Text("Keep studying and complete your goals to earn even more points tomorrow.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color.purple.opacity(0.1))
            .cornerRadius(16)
        }
    }
    
    // MARK: - Checkout History Section
    
    private var checkoutHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Checkouts")
                .font(.headline)
            
            LazyVStack(spacing: 8) {
                ForEach(pointsManager.dailyCheckoutHistory.suffix(5).reversed(), id: \.id) { checkout in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(checkout.displayDate)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("\(checkout.goalsCompleted) goals completed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("+\(checkout.finalPoints)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                            
                            if checkout.isWeekend {
                                Text("Weekend 2x")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(16)
    }
    
    // MARK: - Helper Methods
    
    private func performCheckout() {
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            let result = pointsManager.performDailyCheckout()
            checkoutResult = result
            showingCheckoutAnimation = true
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        // Success notification feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
        }
    }
    
    private func calculateTotalPoints() -> Int {
        var total = 0
        
        for goal in pointsManager.learningGoals {
            if goal.isDaily && goal.isCompleted {
                total += goal.pointsEarned
            }
        }
        
        // Add weekly streak bonus if applicable
        if let weeklyGoal = pointsManager.learningGoals.first(where: { $0.type == .weeklyStreak }),
           weeklyGoal.isCompleted {
            total += weeklyGoal.pointsEarned
        }
        
        return total
    }
    
    private func canCheckoutToday() -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        
        if let lastCheckout = pointsManager.dailyCheckoutHistory.last {
            let lastCheckoutDay = Calendar.current.startOfDay(for: lastCheckout.date)
            return today > lastCheckoutDay
        }
        return true
    }
}

// MARK: - Goal Checkout Card

struct GoalCheckoutCard: View {
    let goal: LearningGoal
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: goal.type.icon)
                    .foregroundColor(goal.type.color)
                    .font(.title3)
                
                Spacer()
                
                if goal.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                Text("\(goal.currentProgress)/\(goal.targetValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                        .cornerRadius(2)
                    
                    Rectangle()
                        .fill(goal.type.color)
                        .frame(
                            width: geometry.size.width * min(goal.progressPercentage / 100, 1.0),
                            height: 4
                        )
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)
            
            if goal.isCompleted {
                Text("+\(goal.pointsEarned) pts")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            } else {
                Text("\(goal.basePoints) pts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            goal.isCompleted ? 
            goal.type.color.opacity(0.1) : 
            Color.gray.opacity(0.05)
        )
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    goal.isCompleted ? 
                    goal.type.color.opacity(0.3) : 
                    Color.gray.opacity(0.2), 
                    lineWidth: 1
                )
        )
    }
}

#Preview {
    DailyCheckoutView()
}