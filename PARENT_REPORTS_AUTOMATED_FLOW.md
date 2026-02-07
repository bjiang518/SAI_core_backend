# Parent Reports - Automated Generation Flow with Privacy Controls
**Date**: February 7, 2026
**Type**: Passive/Automated System Design

---

## System Architecture Reminder

### Backend (Already Implemented)
- **Cron Job**: Runs hourly, checks for users at Sunday 9 PM local time
- **Auto-Generation**: Server generates 4 reports (Activity, Improvement, Mental Health, Summary)
- **Database Flag**: `profiles.parent_reports_enabled` controls who gets reports

### The Challenge
Since reports are **server-generated automatically**, we can't show a consent dialog "before report generation". We need:
1. **Onboarding consent** for first-time users
2. **Data sync** before first report
3. **Notification** when reports are ready
4. **Privacy controls** to enable/disable

---

## Recommended Flow: Onboarding + Automated Sync

### Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ FIRST TIME USER OPENS APP (After Registration)                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Onboarding Screen - "Welcome to Parent Reports"         │
│                                                                  │
│ 📊 Get Weekly Learning Insights                                 │
│                                                                  │
│ • Automatic weekly summaries of your child's progress           │
│ • AI-powered recommendations and insights                       │
│ • Track improvements and areas needing support                  │
│                                                                  │
│ To enable Parent Reports, we need to:                           │
│ 1. Sync homework data to our secure server                      │
│ 2. Generate reports every Sunday at 9 PM                        │
│                                                                  │
│ Your data is encrypted and never shared.                        │
│                                                                  │
│ [Maybe Later]          [Enable Parent Reports]                  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
         User taps "Enable Parent Reports"
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Data Sync Consent                                       │
│                                                                  │
│ 🔄 Sync Your Homework Data                                      │
│                                                                  │
│ To generate your first report, we'll sync:                      │
│ • All homework questions and answers                            │
│ • Chat conversations with AI tutor                              │
│ • Learning progress data                                        │
│                                                                  │
│ This is a one-time sync. Future homework will sync              │
│ automatically in the background.                                │
│                                                                  │
│ Data transfer: ~2 MB | Encrypted with HTTPS                     │
│                                                                  │
│ [Cancel]              [Start Sync]                              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
         User taps "Start Sync"
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Syncing Progress                                        │
│                                                                  │
│ 🔄 Syncing to Server...                                         │
│                                                                  │
│ ████████████████████░░░░ 80%                                    │
│                                                                  │
│ ✓ Synced 115 homework questions                                 │
│ ✓ Synced 12 chat conversations                                  │
│ → Syncing progress data...                                      │
│                                                                  │
│ Estimated: 30 seconds remaining                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
         Sync completes
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Step 4: Setup Complete                                          │
│                                                                  │
│ ✅ Parent Reports Enabled!                                      │
│                                                                  │
│ Your first report will be generated this Sunday at 9 PM.        │
│ You'll receive a notification when it's ready.                  │
│                                                                  │
│ What happens next:                                              │
│ • Weekly reports every Sunday at 9 PM                           │
│ • Homework syncs automatically in background                    │
│ • Notifications when reports are ready                          │
│                                                                  │
│ You can disable Parent Reports anytime in Settings.             │
│                                                                  │
│ [View Settings]           [Done]                                │
└─────────────────────────────────────────────────────────────────┘
                            ↓
         User taps "Done"
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Backend: Database Updated                                       │
│                                                                  │
│ UPDATE profiles SET                                             │
│   parent_reports_enabled = true,                                │
│   auto_sync_enabled = true,                                     │
│   report_day_of_week = 0,        -- Sunday                      │
│   report_time_hour = 21,         -- 9 PM                        │
│   timezone = 'America/Los_Angeles'                              │
│ WHERE user_id = 'xxx'                                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Subsequent Weeks (Automated Flow)

### Weekly Automated Process

```
┌─────────────────────────────────────────────────────────────────┐
│ THROUGHOUT THE WEEK (Monday-Saturday)                           │
└─────────────────────────────────────────────────────────────────┘
                            ↓
         Student does homework
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Background Sync (After Each Homework Session)                   │
│                                                                  │
│ When homework completed:                                        │
│ 1. Save to local storage                                        │
│ 2. Check if auto_sync_enabled = true                            │
│ 3. If yes, silently sync to server in background                │
│ 4. Show subtle success notification                             │
│                                                                  │
│ User sees (optional banner):                                    │
│ ┌─────────────────────────────────┐                             │
│ │ ✓ Homework synced to server     │                             │
│ └─────────────────────────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
                            ↓
         Data accumulates on server
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ SUNDAY 9 PM (User's Local Time)                                 │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Backend Cron Job (Hourly Check)                                 │
│                                                                  │
│ 1. Query users where:                                           │
│    - parent_reports_enabled = true                              │
│    - Current local time = Sunday 9 PM                           │
│                                                                  │
│ 2. For each user:                                               │
│    - Generate Activity Report                                   │
│    - Generate Improvement Report                                │
│    - Generate Mental Health Report                              │
│    - Generate Summary Report                                    │
│    - Store in database                                          │
│                                                                  │
│ 3. Send push notification to iOS app                            │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ iOS Receives Push Notification                                  │
│                                                                  │
│ 📊 Your Weekly Report is Ready                                  │
│ See how you did this week!                                      │
│                                                                  │
│ [Dismiss]  [View Report]                                        │
└─────────────────────────────────────────────────────────────────┘
                            ↓
         User taps "View Report" (or opens app later)
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ Parent Reports View                                             │
│                                                                  │
│ 🆕 New Report Available!                                        │
│                                                                  │
│ Week of Feb 1-7, 2026                                           │
│                                                                  │
│ [View Activity Report]                                          │
│ [View Areas for Improvement]                                    │
│ [View Mental Health Summary]                                    │
│ [View Executive Summary]                                        │
│                                                                  │
│ Previous Reports ▼                                              │
│ • Week of Jan 25-31, 2026                                       │
│ • Week of Jan 18-24, 2026                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Privacy Controls in Settings

### PrivacySettingsView.swift Enhancement

```swift
Section {
    // Toggle for automated reports
    Toggle(isOn: $parentReportsEnabled) {
        VStack(alignment: .leading, spacing: 4) {
            Text("Automated Weekly Reports")
                .font(.headline)
            Text("Generate parent reports every Sunday at 9 PM")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .onChange(of: parentReportsEnabled) { newValue in
        updateReportSettings(enabled: newValue)
    }

    if parentReportsEnabled {
        // Auto-sync toggle (must be enabled for reports)
        Toggle(isOn: $autoSyncEnabled) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Background Homework Sync")
                    .font(.subheadline)
                Text("Automatically sync homework after each session")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(!parentReportsEnabled)

        // Sync status
        HStack {
            Image(systemName: lastSyncStatus == .synced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(lastSyncStatus == .synced ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Last Sync")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(lastSyncTimestamp?.formatted() ?? "Never")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Sync Now") {
                Task { await manualSync() }
            }
            .font(.caption)
        }

        // Report schedule
        VStack(alignment: .leading, spacing: 4) {
            Text("Next Report")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(nextReportDate?.formatted() ?? "Sunday 9 PM")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
} header: {
    Text("Parent Reports")
} footer: {
    Text(parentReportsEnabled ?
         "Reports are generated every Sunday at 9 PM using homework data synced throughout the week. You can disable this anytime." :
         "Enable automated weekly parent reports to track learning progress and receive AI-powered insights.")
}
```

---

## First-Time User Onboarding Implementation

### New File: ParentReportsOnboardingView.swift

```swift
import SwiftUI

struct ParentReportsOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var isSyncing = false
    @State private var syncProgress: Double = 0
    @State private var syncStatus = ""

    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            switch currentStep {
            case 0:
                welcomeScreen
            case 1:
                syncConsentScreen
            case 2:
                syncingScreen
            case 3:
                completionScreen
            default:
                EmptyView()
            }
        }
    }

    private var welcomeScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            // Title
            VStack(spacing: 8) {
                Text("Get Weekly Learning Insights")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Automated parent reports every Sunday")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Features
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "chart.line.uptrend.xyaxis",
                          title: "Progress Tracking",
                          description: "See how your child improves each week")

                FeatureRow(icon: "lightbulb.fill",
                          title: "AI-Powered Insights",
                          description: "Get personalized recommendations")

                FeatureRow(icon: "heart.text.square.fill",
                          title: "Mental Wellbeing",
                          description: "Monitor engagement and confidence")

                FeatureRow(icon: "lock.shield.fill",
                          title: "Private & Secure",
                          description: "Your data is encrypted and protected")
            }
            .padding(.horizontal)

            Spacer()

            // What's needed
            VStack(spacing: 12) {
                Text("To enable Parent Reports, we need to:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    SmallFeature(icon: "arrow.triangle.2.circlepath", text: "Sync homework data")
                    SmallFeature(icon: "calendar", text: "Weekly reports")
                }
                .font(.caption2)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Buttons
            VStack(spacing: 12) {
                Button(action: {
                    currentStep = 1
                }) {
                    Text("Enable Parent Reports")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: {
                    onSkip()
                    dismiss()
                }) {
                    Text("Maybe Later")
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private var syncConsentScreen: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 70))
                .foregroundColor(.blue)

            VStack(spacing: 8) {
                Text("Sync Your Homework Data")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("One-time initial sync")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("To generate your first report, we'll sync:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                DataItem(icon: "questionmark.circle.fill",
                        title: "Homework Questions",
                        count: getLocalQuestionCount())
                DataItem(icon: "bubble.left.and.bubble.right.fill",
                        title: "AI Chat Conversations",
                        count: getLocalConversationCount())
                DataItem(icon: "chart.bar.fill",
                        title: "Learning Progress",
                        count: "All subjects")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("Encrypted with HTTPS")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Future homework will sync automatically in the background")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    startSync()
                }) {
                    Text("Start Sync")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: {
                    currentStep = 0
                }) {
                    Text("Go Back")
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
    }

    private var syncingScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated sync icon
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: syncProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear, value: syncProgress)

                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                Text("Syncing to Server...")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(Int(syncProgress * 100))% Complete")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                SyncStatusRow(icon: "checkmark.circle.fill",
                             text: "Synced homework questions",
                             isComplete: syncProgress > 0.3)
                SyncStatusRow(icon: "checkmark.circle.fill",
                             text: "Synced chat conversations",
                             isComplete: syncProgress > 0.6)
                SyncStatusRow(icon: "checkmark.circle.fill",
                             text: "Synced progress data",
                             isComplete: syncProgress > 0.9)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            if syncProgress < 1.0 {
                Text(syncStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private var completionScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)

            VStack(spacing: 8) {
                Text("Parent Reports Enabled!")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Your first report will be generated this Sunday at 9 PM")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("What happens next:")
                    .font(.headline)

                NextStepRow(icon: "calendar.badge.clock",
                           text: "Weekly reports every Sunday at 9 PM")
                NextStepRow(icon: "arrow.triangle.2.circlepath",
                           text: "Homework syncs automatically in background")
                NextStepRow(icon: "bell.badge.fill",
                           text: "You'll get notifications when reports are ready")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.blue)
                    Text("You can disable Parent Reports anytime in Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: {
                onComplete()
                dismiss()
            }) {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.bottom, 32)
        }
        .padding(.horizontal)
    }

    // MARK: - Helper Methods

    private func startSync() {
        currentStep = 2
        isSyncing = true

        Task {
            do {
                // Perform actual sync
                let result = try await StorageSyncService.shared.syncAllToServer()

                // Simulate progress for smooth UX
                for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                    await MainActor.run {
                        syncProgress = progress

                        if progress < 0.3 {
                            syncStatus = "Syncing questions..."
                        } else if progress < 0.6 {
                            syncStatus = "Syncing conversations..."
                        } else if progress < 0.9 {
                            syncStatus = "Syncing progress..."
                        } else {
                            syncStatus = "Finalizing..."
                        }
                    }
                    try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                }

                // Enable parent reports on backend
                await enableParentReports()

                // Move to completion
                await MainActor.run {
                    currentStep = 3
                }

            } catch {
                await MainActor.run {
                    // Show error and go back
                    syncStatus = "Sync failed: \(error.localizedDescription)"
                    // TODO: Show error alert and allow retry
                }
            }
        }
    }

    private func enableParentReports() async {
        // Call backend to enable automated reports
        // UPDATE profiles SET parent_reports_enabled = true, auto_sync_enabled = true
        _ = await NetworkService.shared.enableParentReports()
    }

    private func getLocalQuestionCount() -> String {
        let count = QuestionLocalStorage.shared.getLocalQuestions().count
        return "\(count) questions"
    }

    private func getLocalConversationCount() -> String {
        let count = ConversationLocalStorage.shared.getLocalConversations().count
        return "\(count) conversations"
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct SmallFeature: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .foregroundColor(.secondary)
    }
}

struct DataItem: View {
    let icon: String
    let title: String
    let count: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(count)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SyncStatusRow: View {
    let icon: String
    let text: String
    let isComplete: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isComplete ? .green : .gray)
            Text(text)
                .font(.subheadline)
                .foregroundColor(isComplete ? .primary : .secondary)
            Spacer()
        }
    }
}

struct NextStepRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}
```

---

## Backend API Addition

### New Endpoint: Enable Parent Reports

```javascript
// src/gateway/routes/parent-reports.js

fastify.post('/api/parent-reports/enable', {
  preHandler: authPreHandler,
  schema: {
    description: 'Enable automated weekly parent reports for user',
    tags: ['Parent Reports'],
    body: {
      type: 'object',
      properties: {
        timezone: { type: 'string', default: 'UTC' },
        reportDay: { type: 'integer', default: 0 },  // 0 = Sunday
        reportHour: { type: 'integer', default: 21 }  // 9 PM
      }
    }
  }
}, async (request, reply) => {
  const userId = getUserId(request);
  const { timezone = 'UTC', reportDay = 0, reportHour = 21 } = request.body;

  try {
    await db.query(`
      UPDATE profiles
      SET
        parent_reports_enabled = true,
        auto_sync_enabled = true,
        report_day_of_week = $1,
        report_time_hour = $2,
        timezone = $3,
        updated_at = NOW()
      WHERE user_id = $4
    `, [reportDay, reportHour, timezone, userId]);

    fastify.log.info(`✅ Enabled parent reports for user ${userId}`);

    return {
      success: true,
      message: 'Parent reports enabled successfully',
      nextReportTime: calculateNextReportTime(timezone, reportDay, reportHour)
    };

  } catch (error) {
    fastify.log.error('Failed to enable parent reports:', error);
    return reply.status(500).send({
      success: false,
      error: 'Failed to enable parent reports'
    });
  }
});

fastify.post('/api/parent-reports/disable', {
  preHandler: authPreHandler
}, async (request, reply) => {
  const userId = getUserId(request);

  try {
    await db.query(`
      UPDATE profiles
      SET
        parent_reports_enabled = false,
        auto_sync_enabled = false,
        updated_at = NOW()
      WHERE user_id = $1
    `, [userId]);

    return { success: true, message: 'Parent reports disabled' };
  } catch (error) {
    return reply.status(500).send({ success: false, error: 'Failed to disable' });
  }
});
```

---

## When to Show Onboarding

### AppDelegate / SceneDelegate Integration

```swift
// Check if should show onboarding
func application(_ application: UIApplication, didFinishLaunchingWithOptions...) -> Bool {

    // After user logs in successfully
    if AuthenticationService.shared.isLoggedIn {
        checkParentReportsOnboarding()
    }

    return true
}

private func checkParentReportsOnboarding() {
    let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "HasSeenParentReportsOnboarding")
    let isReportsEnabled = UserDefaults.standard.bool(forKey: "ParentReportsEnabled")

    if !hasSeenOnboarding && !isReportsEnabled {
        // Show onboarding after a delay (don't overwhelm user on first launch)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            NotificationCenter.default.post(
                name: NSNotification.Name("ShowParentReportsOnboarding"),
                object: nil
            )
        }
    }
}

// In main ContentView
struct ContentView: View {
    @State private var showingParentReportsOnboarding = false

    var body: some View {
        // Main app content
        TabView {
            // ...
        }
        .sheet(isPresented: $showingParentReportsOnboarding) {
            ParentReportsOnboardingView(
                onComplete: {
                    UserDefaults.standard.set(true, forKey: "HasSeenParentReportsOnboarding")
                    UserDefaults.standard.set(true, forKey: "ParentReportsEnabled")
                },
                onSkip: {
                    UserDefaults.standard.set(true, forKey: "HasSeenParentReportsOnboarding")
                    // Can show again later from Settings
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowParentReportsOnboarding"))) { _ in
            showingParentReportsOnboarding = true
        }
    }
}
```

---

## Summary

### For First-Time Users (Onboarding)
1. **Welcome screen**: Explain benefits of parent reports
2. **Consent screen**: Show what data will be synced
3. **Sync progress**: One-time upload of all historical data
4. **Completion**: Confirm reports enabled, next report Sunday 9 PM

### For Ongoing Usage (Automated)
1. **Background sync**: After each homework session (if auto-sync enabled)
2. **Server generation**: Sunday 9 PM (automated, no user action)
3. **Push notification**: "Your weekly report is ready"
4. **User views**: Opens app and reads reports at their convenience

### Privacy Controls
- **Settings toggle**: Enable/disable automated reports
- **Auto-sync toggle**: Enable/disable background sync
- **Manual sync**: "Sync Now" button in Settings
- **Transparency**: Always show what's being synced
- **Consent**: Explicit opt-in during onboarding

This design respects privacy while ensuring reports have complete data!
