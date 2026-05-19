//
//  StorageSyncService.swift
//  StudyAI
//
//  Handles syncing all local storage to server with deduplication
//

import Foundation

class StorageSyncService {
    static let shared = StorageSyncService()

    private let baseURL = "https://sai-backend-production.up.railway.app"

    private init() {}

    // MARK: - Main Sync Method

    func syncAllToServer() async throws -> SyncResult {
        guard AuthenticationService.shared.getAuthToken() != nil else {
            debugPrint("❌ [Sync] Authentication failed - no token")
            throw SyncError.notAuthenticated
        }

        debugPrint("🚀 [Sync] Starting full sync to server...")
        var result = SyncResult()

        // 1. Sync Archived Questions
        debugPrint("\n📚 [Sync] === SYNCING ARCHIVED QUESTIONS ===")
        do {
            let questionResult = try await syncArchivedQuestions()
            result.questionsSynced = questionResult.synced
            result.questionsDuplicates = questionResult.duplicates
            debugPrint("✅ [Sync] Questions sync completed: \(questionResult.synced) synced, \(questionResult.duplicates) duplicates")
        } catch {
            debugPrint("❌ [Sync] Questions sync failed: \(error.localizedDescription)")
            result.errors.append("Questions: \(error.localizedDescription)")
        }

        // 2. Sync Archived Conversations
        debugPrint("\n💬 [Sync] === SYNCING ARCHIVED CONVERSATIONS ===")
        do {
            let conversationResult = try await syncArchivedConversations()
            result.conversationsSynced = conversationResult.synced
            result.conversationsDuplicates = conversationResult.duplicates
            debugPrint("✅ [Sync] Conversations sync completed: \(conversationResult.synced) synced, \(conversationResult.duplicates) duplicates")
        } catch {
            debugPrint("❌ [Sync] Conversations sync failed: \(error.localizedDescription)")
            result.errors.append("Conversations: \(error.localizedDescription)")
        }

        // 3. Sync Progress Data
        debugPrint("\n📊 [Sync] === SYNCING PROGRESS DATA ===")
        do {
            try await syncProgressData()
            result.progressSynced = true
            debugPrint("✅ [Sync] Progress sync completed successfully")
        } catch {
            debugPrint("❌ [Sync] Progress sync failed: \(error.localizedDescription)")
            result.errors.append("Progress: \(error.localizedDescription)")
        }

        debugPrint("\n🏁 [Sync] === SYNC SUMMARY ===")
        debugPrint("📈 Total synced: \(result.totalSynced)")
        debugPrint("🔄 Total duplicates: \(result.totalDuplicates)")
        debugPrint("❌ Errors: \(result.errors.count)")
        if !result.errors.isEmpty {
            result.errors.forEach { debugPrint("   - \($0)") }
        }

        // ✅ POST NOTIFICATION TO REFRESH LIBRARY
        debugPrint("📢 [Sync] Posting StorageSyncCompleted notification...")
        NotificationCenter.default.post(name: NSNotification.Name("StorageSyncCompleted"), object: nil)

        return result
    }

    // MARK: - Sync Archived Questions

    private func syncArchivedQuestions() async throws -> (synced: Int, duplicates: Int) {
        guard let token = AuthenticationService.shared.getAuthToken() else {
            throw SyncError.notAuthenticated
        }

        let localStorage = currentUserQuestionStorage()
        let localQuestions = localStorage.getLocalQuestions()
        guard !localQuestions.isEmpty else { return (0, 0) }

        // Separate already-synced from pending
        let serverQuestions = (try? await fetchQuestionsFromServer(token: token)) ?? []
        let serverIds = Set(serverQuestions.compactMap { $0["id"] as? String })

        let pending = localQuestions.filter { q in
            guard let id = q["id"] as? String, id.count > 10 else { return true }
            return !serverIds.contains(id)
        }

        guard !pending.isEmpty else {
            debugPrint("✅ [Sync] All \(localQuestions.count) questions already on server")
            return (0, localQuestions.count)
        }

        debugPrint("📦 [Sync] Uploading \(pending.count) questions in batch (skipping \(localQuestions.count - pending.count) already synced)")

        // Send in batches of 100 to stay within the 200-item server limit
        let batchSize = 100
        var totalSynced = 0
        var totalDuplicates = 0

        for batchStart in stride(from: 0, to: pending.count, by: batchSize) {
            let batch = Array(pending[batchStart..<min(batchStart + batchSize, pending.count)])
            let (synced, dupes, serverResults) = try await uploadBatchToServer(batch, token: token)
            totalSynced += synced
            totalDuplicates += dupes

            // Update local storage with server-assigned IDs
            for (i, result) in serverResults.enumerated() {
                guard let serverId = result["id"] as? String else { continue }
                var updated = batch[i]
                updated["id"] = serverId
                _ = localStorage.saveQuestions([updated])
            }
        }

        debugPrint("✅ [Sync] Batch complete: \(totalSynced) synced, \(totalDuplicates) duplicates")
        return (totalSynced, totalDuplicates)
    }

    private func uploadBatchToServer(_ questions: [[String: Any]], token: String) async throws -> (synced: Int, duplicates: Int, results: [[String: Any]]) {
        guard let url = URL(string: "\(baseURL)/api/archived-questions/sync/batch") else {
            throw SyncError.invalidURL
        }

        let body: [String: Any] = ["questions": questions.map { q -> [String: Any] in
            let rawGrade = (q["grade"] as? String ?? "").uppercased()
            return [
                "subject":          q["subject"] as? String ?? "Unknown",
                "questionText":     q["questionText"] as? String ?? "",
                "rawQuestionText":  q["rawQuestionText"] as? String ?? q["questionText"] as? String ?? "",
                "answerText":       q["answerText"] as? String ?? "",
                "studentAnswer":    q["studentAnswer"] as? String ?? "",
                "confidence":       q["confidence"] as? Float ?? 0,
                "hasVisualElements":q["hasVisualElements"] as? Bool ?? false,
                "tags":             q["tags"] as? [String] ?? [],
                "notes":            q["notes"] as? String ?? "",
                "grade":            rawGrade.isEmpty ? "EMPTY" : rawGrade,
                "points":           q["points"] as? Float ?? 0,
                "maxPoints":        q["maxPoints"] as? Float ?? 1,
                "feedback":         q["feedback"] as? String ?? "",
                "isCorrect":        q["isCorrect"] as? Bool ?? false,
                "archivedAt":       q["archivedAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
            ]
        }]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SyncError.syncFailed("Batch upload failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.invalidResponse
        }

        let synced = json["synced"] as? Int ?? 0
        let dupes = json["duplicates"] as? Int ?? 0
        let results = json["results"] as? [[String: Any]] ?? []
        return (synced, dupes, results)
    }

    // MARK: - Fetch Questions from Server

    private func fetchQuestionsFromServer(token: String) async throws -> [[String: Any]] {
        guard let url = URL(string: "\(baseURL)/api/archived-questions?limit=1000") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        debugPrint("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let questionsArray = json["data"] as? [[String: Any]] {
                debugPrint("   ✅ [Sync] Server returned \(questionsArray.count) questions")
                return questionsArray
            }
        }

        // Return empty array if no data
        return []
    }

    // MARK: - Fetch Conversations from Server

    private func fetchConversationsFromServer(token: String) async throws -> [[String: Any]] {
        guard let url = URL(string: "\(baseURL)/api/ai/conversations") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        debugPrint("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let conversationsArray = json["data"] as? [[String: Any]] {
                debugPrint("   ✅ [Sync] Server returned \(conversationsArray.count) conversations")
                return conversationsArray
            }
        }

        // Return empty array if no data
        return []
    }

    // MARK: - Sync Archived Conversations

    private func syncArchivedConversations() async throws -> (synced: Int, duplicates: Int) {
        guard let token = AuthenticationService.shared.getAuthToken() else {
            debugPrint("❌ [Sync] No auth token for conversations sync")
            throw SyncError.notAuthenticated
        }

        debugPrint("💬 [Sync] === SYNCING ARCHIVED CONVERSATIONS ===")

        // STEP 1: Fetch server conversations
        debugPrint("📥 [Sync] Step 1: Fetching server conversations...")
        let serverConversations = try await fetchConversationsFromServer(token: token)
        debugPrint("   ✅ [Sync] Fetched \(serverConversations.count) conversations from server")

        // STEP 2: Get local conversations
        debugPrint("📱 [Sync] Step 2: Getting local conversations...")
        let localStorage = currentUserConversationStorage()
        let localConversations = localStorage.getLocalConversations()
        debugPrint("   ✅ [Sync] Found \(localConversations.count) local conversations")

        var syncedToServerCount = 0
        var duplicateCount = 0

        // STEP 3: Build server ID set for dedup check
        debugPrint("🔍 [Sync] Step 3: Building server ID set for dedup check...")
        var serverConversationIds = Set<String>()
        for serverConv in serverConversations {
            if let id = serverConv["id"] as? String {
                serverConversationIds.insert(id)
            }
        }
        debugPrint("   📊 [Sync] Server IDs: \(serverConversationIds.count), Local IDs: \(localConversations.count)")

        // STEP 4: Upload local conversations that don't exist on server
        debugPrint("\n📤 [Sync] Step 5: Uploading local conversations to server...")

        guard !localConversations.isEmpty else {
            debugPrint("   ℹ️ [Sync] No local conversations to upload")
            return (0, 0)
        }

        for (index, conversationData) in localConversations.enumerated() {
            debugPrint("\n   💬 [Sync] Conversation \(index + 1)/\(localConversations.count):")

            do {
                // Check if already exists on server by checking if it has server ID
                if let id = conversationData["id"] as? String, id.count > 10 {
                    if serverConversationIds.contains(id) {
                        debugPrint("   ⏭️  [Sync] Already on server with ID: \(id) - SKIPPING (duplicate)")
                        duplicateCount += 1
                        continue
                    } else {
                        debugPrint("   ❓ [Sync] Has ID but not on server - will upload")
                    }
                } else {
                    debugPrint("   🆕 [Sync] No server ID found - will upload to server")
                }

                let subject = conversationData["subject"] as? String ?? "General"
                let topic = conversationData["topic"] as? String ?? "Chat Session"
                let content = conversationData["conversationContent"] as? String ?? ""

                debugPrint("   📋 [Sync] Subject: \(subject), Topic: \(topic)")
                debugPrint("   📏 [Sync] Content length: \(content.count) chars")

                // Archive conversation to server
                guard let url = URL(string: "\(baseURL)/api/ai/conversations") else {
                    debugPrint("   ❌ [Sync] Invalid URL")
                    throw SyncError.invalidURL
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                // Prepare conversation data
                let requestData: [String: Any] = [
                    "subject": subject,
                    "topic": topic,
                    "conversationContent": content,
                    "archivedDate": ISO8601DateFormatter().string(from: Date())
                ]

                request.httpBody = try JSONSerialization.data(withJSONObject: requestData)

                debugPrint("   📤 [Sync] Sending POST to /api/ai/conversations...")
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    debugPrint("   ❌ [Sync] Invalid response")
                    throw SyncError.invalidResponse
                }

                debugPrint("   📡 [Sync] Server response: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                    syncedToServerCount += 1
                    debugPrint("   ✅ [Sync] Successfully uploaded conversation")
                } else if httpResponse.statusCode == 409 {
                    duplicateCount += 1
                    debugPrint("   🔄 [Sync] Server detected duplicate (409) - skipping")
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    debugPrint("   ❌ [Sync] Failed with status \(httpResponse.statusCode): \(errorMessage)")
                }

            } catch {
                debugPrint("   ❌ [Sync] Failed to upload conversation: \(error)")
            }
        }

        debugPrint("\n📊 [Sync] Conversations summary: \(syncedToServerCount) uploaded, \(duplicateCount) duplicates")
        return (syncedToServerCount, duplicateCount)
    }

    // MARK: - Sync Progress Data

    private func syncProgressData() async throws {
        guard let token = AuthenticationService.shared.getAuthToken() else {
            debugPrint("❌ [Sync] No auth token for progress sync")
            throw SyncError.notAuthenticated
        }

        debugPrint("📊 [Sync] === SYNCING PROGRESS DATA ===")

        // STEP 1: Fetch server data
        debugPrint("📥 [Sync] Step 1: Fetching server progress data...")
        let serverProgress = try await fetchProgressFromServer(token: token)

        // STEP 2: Get local progress data
        debugPrint("📱 [Sync] Step 2: Getting local progress data...")
        let pointsManager = PointsEarningManager.shared

        let localProgress: [String: Any] = [
            "currentPoints": pointsManager.currentPoints,
            "totalPoints": pointsManager.totalPointsEarned,
            "currentStreak": pointsManager.currentStreak,
            "learningGoals": pointsManager.learningGoals.map { goal in
                [
                    "type": goal.type.rawValue,
                    "title": goal.title,
                    "currentProgress": goal.currentProgress,
                    "targetValue": goal.targetValue,
                    "isCompleted": goal.isCompleted
                ] as [String: Any]
            },
            "weeklyProgress": pointsManager.currentWeeklyProgress.map { weeklyProgress in
                [
                    "weekStart": weeklyProgress.weekStart,
                    "weekEnd": weeklyProgress.weekEnd,
                    "dailyActivities": weeklyProgress.dailyActivities.map { activity in
                        [
                            "date": activity.date,
                            "dayOfWeek": activity.dayOfWeek,
                            "questionCount": activity.questionCount,
                            "timezone": activity.timezone
                        ] as [String: Any]
                    },
                    "totalQuestionsThisWeek": weeklyProgress.totalQuestionsThisWeek,
                    "timezone": weeklyProgress.timezone,
                    "serverTimestamp": ISO8601DateFormatter().string(from: weeklyProgress.serverTimestamp)
                ] as [String: Any]
            } as Any
        ]

        // STEP 3: Merge local and server data
        debugPrint("🔄 [Sync] Step 3: Merging local and server data...")
        let mergedProgress = mergeProgressData(local: localProgress, server: serverProgress)

        // STEP 4: Compare merged with server
        debugPrint("🔍 [Sync] Step 4: Comparing merged data with server...")
        let hasChanges = progressHasChanges(merged: mergedProgress, server: serverProgress)

        if hasChanges {
            debugPrint("📤 [Sync] Step 5: Changes detected, updating server...")
            try await updateProgressOnServer(progress: mergedProgress, token: token)
            debugPrint("✅ [Sync] Progress data synced successfully")
        } else {
            debugPrint("✅ [Sync] No changes detected, server already up to date")
        }
    }

    // MARK: - Fetch from Server

    private func fetchProgressFromServer(token: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/api/progress/sync") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        debugPrint("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverData = json["data"] as? [String: Any] {
                debugPrint("   ✅ [Sync] Server progress data retrieved")
                debugPrint("   📊 [Sync] Server Points: \(serverData["currentPoints"] ?? 0)")
                debugPrint("   📊 [Sync] Server Streak: \(serverData["currentStreak"] ?? 0)")
                return serverData
            }
        }

        // Return empty if no data
        return [
            "currentPoints": 0,
            "totalPoints": 0,
            "currentStreak": 0,
            "learningGoals": [],
            "weeklyProgress": NSNull()
        ]
    }

    // MARK: - Merge Logic

    private func mergeProgressData(local: [String: Any], server: [String: Any]) -> [String: Any] {
        var merged: [String: Any] = [:]

        // Merge points: take maximum
        let localPoints = local["currentPoints"] as? Int ?? 0
        let serverPoints = server["currentPoints"] as? Int ?? 0
        merged["currentPoints"] = max(localPoints, serverPoints)
        debugPrint("   🔀 [Sync] Points: local=\(localPoints), server=\(serverPoints), merged=\(merged["currentPoints"] ?? 0)")

        let localTotalPoints = local["totalPoints"] as? Int ?? 0
        let serverTotalPoints = server["totalPoints"] as? Int ?? 0
        merged["totalPoints"] = max(localTotalPoints, serverTotalPoints)
        debugPrint("   🔀 [Sync] Total Points: local=\(localTotalPoints), server=\(serverTotalPoints), merged=\(merged["totalPoints"] ?? 0)")

        // Merge streak: take maximum
        let localStreak = local["currentStreak"] as? Int ?? 0
        let serverStreak = server["currentStreak"] as? Int ?? 0
        merged["currentStreak"] = max(localStreak, serverStreak)
        debugPrint("   🔀 [Sync] Streak: local=\(localStreak), server=\(serverStreak), merged=\(merged["currentStreak"] ?? 0)")

        // Merge learning goals: prefer local (most recent)
        merged["learningGoals"] = local["learningGoals"] ?? []

        // Merge weekly progress: prefer local (most recent)
        if let localWeekly = local["weeklyProgress"], !(localWeekly is NSNull) {
            merged["weeklyProgress"] = localWeekly
        } else if let serverWeekly = server["weeklyProgress"], !(serverWeekly is NSNull) {
            merged["weeklyProgress"] = serverWeekly
        }

        return merged
    }

    private func progressHasChanges(merged: [String: Any], server: [String: Any]) -> Bool {
        let mergedPoints = merged["currentPoints"] as? Int ?? 0
        let serverPoints = server["currentPoints"] as? Int ?? 0

        let mergedTotalPoints = merged["totalPoints"] as? Int ?? 0
        let serverTotalPoints = server["totalPoints"] as? Int ?? 0

        let mergedStreak = merged["currentStreak"] as? Int ?? 0
        let serverStreak = server["currentStreak"] as? Int ?? 0

        let pointsChanged = mergedPoints != serverPoints
        let totalPointsChanged = mergedTotalPoints != serverTotalPoints
        let streakChanged = mergedStreak != serverStreak

        debugPrint("   🔍 [Sync] Points changed: \(pointsChanged) (\(mergedPoints) vs \(serverPoints))")
        debugPrint("   🔍 [Sync] Total points changed: \(totalPointsChanged) (\(mergedTotalPoints) vs \(serverTotalPoints))")
        debugPrint("   🔍 [Sync] Streak changed: \(streakChanged) (\(mergedStreak) vs \(serverStreak))")

        return pointsChanged || totalPointsChanged || streakChanged
    }

    private func updateProgressOnServer(progress: [String: Any], token: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/progress/sync") else {
            debugPrint("   ❌ [Sync] Invalid URL")
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: progress)

        debugPrint("   📤 [Sync] Sending POST to /api/progress/sync...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugPrint("   ❌ [Sync] Invalid response")
            throw SyncError.invalidResponse
        }

        debugPrint("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            debugPrint("   ✅ [Sync] Progress data updated successfully")
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            debugPrint("   ❌ [Sync] Failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw SyncError.syncFailed(errorMessage)
        }
    }

    // MARK: - Helper Methods

    private func checkConversationExists(id: String) async -> Bool {
        guard let token = AuthenticationService.shared.getAuthToken(),
              let url = URL(string: "\(baseURL)/api/ai/conversations/\(id)") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Sync Result

struct SyncResult {
    var questionsSynced: Int = 0
    var questionsDuplicates: Int = 0
    var conversationsSynced: Int = 0
    var conversationsDuplicates: Int = 0
    var progressSynced: Bool = false
    var errors: [String] = []

    var isSuccess: Bool {
        return errors.isEmpty
    }

    var totalSynced: Int {
        return questionsSynced + conversationsSynced
    }

    var totalDuplicates: Int {
        return questionsDuplicates + conversationsDuplicates
    }

    var summary: String {
        var lines: [String] = []

        if questionsSynced > 0 || questionsDuplicates > 0 {
            lines.append("Questions: \(questionsSynced) synced, \(questionsDuplicates) duplicates")
        }

        if conversationsSynced > 0 || conversationsDuplicates > 0 {
            lines.append("Conversations: \(conversationsSynced) synced, \(conversationsDuplicates) duplicates")
        }

        if progressSynced {
            lines.append("Progress: synced successfully")
        }

        if !errors.isEmpty {
            lines.append("\nErrors:")
            lines.append(contentsOf: errors)
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case syncFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .syncFailed(let message):
            return "Sync failed: \(message)"
        }
    }
}
