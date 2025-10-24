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
            print("❌ [Sync] Authentication failed - no token")
            throw SyncError.notAuthenticated
        }

        print("🚀 [Sync] Starting full sync to server...")
        var result = SyncResult()

        // 1. Sync Archived Questions
        print("\n📚 [Sync] === SYNCING ARCHIVED QUESTIONS ===")
        do {
            let questionResult = try await syncArchivedQuestions()
            result.questionsSynced = questionResult.synced
            result.questionsDuplicates = questionResult.duplicates
            print("✅ [Sync] Questions sync completed: \(questionResult.synced) synced, \(questionResult.duplicates) duplicates")
        } catch {
            print("❌ [Sync] Questions sync failed: \(error.localizedDescription)")
            result.errors.append("Questions: \(error.localizedDescription)")
        }

        // 2. Sync Archived Conversations
        print("\n💬 [Sync] === SYNCING ARCHIVED CONVERSATIONS ===")
        do {
            let conversationResult = try await syncArchivedConversations()
            result.conversationsSynced = conversationResult.synced
            result.conversationsDuplicates = conversationResult.duplicates
            print("✅ [Sync] Conversations sync completed: \(conversationResult.synced) synced, \(conversationResult.duplicates) duplicates")
        } catch {
            print("❌ [Sync] Conversations sync failed: \(error.localizedDescription)")
            result.errors.append("Conversations: \(error.localizedDescription)")
        }

        // 3. Sync Progress Data
        print("\n📊 [Sync] === SYNCING PROGRESS DATA ===")
        do {
            try await syncProgressData()
            result.progressSynced = true
            print("✅ [Sync] Progress sync completed successfully")
        } catch {
            print("❌ [Sync] Progress sync failed: \(error.localizedDescription)")
            result.errors.append("Progress: \(error.localizedDescription)")
        }

        print("\n🏁 [Sync] === SYNC SUMMARY ===")
        print("📈 Total synced: \(result.totalSynced)")
        print("🔄 Total duplicates: \(result.totalDuplicates)")
        print("❌ Errors: \(result.errors.count)")
        if !result.errors.isEmpty {
            result.errors.forEach { print("   - \($0)") }
        }

        // ✅ POST NOTIFICATION TO REFRESH LIBRARY
        print("📢 [Sync] Posting StorageSyncCompleted notification...")
        NotificationCenter.default.post(name: NSNotification.Name("StorageSyncCompleted"), object: nil)

        return result
    }

    // MARK: - Sync Archived Questions

    private func syncArchivedQuestions() async throws -> (synced: Int, duplicates: Int) {
        guard let token = AuthenticationService.shared.getAuthToken() else {
            print("❌ [Sync] No auth token for questions sync")
            throw SyncError.notAuthenticated
        }

        print("📚 [Sync] === SYNCING ARCHIVED QUESTIONS ===")

        // STEP 1: Fetch server questions
        print("📥 [Sync] Step 1: Fetching server questions...")
        let serverQuestions = try await fetchQuestionsFromServer(token: token)
        print("   ✅ [Sync] Fetched \(serverQuestions.count) questions from server")

        // STEP 2: Get local questions
        print("📱 [Sync] Step 2: Getting local questions...")
        let localStorage = QuestionLocalStorage.shared
        let localQuestions = localStorage.getLocalQuestions()
        print("   ✅ [Sync] Found \(localQuestions.count) local questions")

        var syncedToServerCount = 0
        var duplicateCount = 0
        var downloadedFromServerCount = 0

        // STEP 3: Build Sets for efficient comparison
        print("🔍 [Sync] Step 3: Building ID sets for comparison...")
        var serverQuestionIds = Set<String>()
        for serverQ in serverQuestions {
            if let id = serverQ["id"] as? String {
                serverQuestionIds.insert(id)
            }
        }

        var localQuestionIds = Set<String>()
        for localQ in localQuestions {
            if let id = localQ["id"] as? String, id.count > 10 {
                localQuestionIds.insert(id)
            }
        }
        print("   📊 [Sync] Server IDs: \(serverQuestionIds.count), Local IDs: \(localQuestionIds.count)")

        // STEP 4: Download server questions that don't exist locally
        print("\n📥 [Sync] Step 4: Downloading server questions to local storage...")
        for (index, serverQuestion) in serverQuestions.enumerated() {
            guard let id = serverQuestion["id"] as? String else {
                print("   ⚠️ [Sync] Server question \(index + 1) has no ID - skipping")
                continue
            }

            // Check if this server question exists locally
            if localQuestionIds.contains(id) {
                print("   ⏭️ [Sync] Question \(index + 1) already exists locally (ID: \(id)) - skipping")
                continue
            }

            // Download this question to local storage
            print("   📥 [Sync] Downloading question \(index + 1)/\(serverQuestions.count) (ID: \(id))...")

            // Convert server question to local format
            // Backend returns camelCase keys (questionText, answerText, etc.)
            let questionText = serverQuestion["questionText"] as? String ?? ""
            let answerText = serverQuestion["answerText"] as? String ?? ""

            print("   📝 [Sync] Question text: '\(questionText.prefix(100))...'")
            print("   📝 [Sync] Answer text: '\(answerText.prefix(100))...'")

            if questionText.isEmpty {
                print("   ⚠️ [Sync] WARNING: Question text is EMPTY!")
            }

            // ✅ NORMALIZE: Ensure grade is in uppercase format for enum compatibility
            let rawGrade = serverQuestion["grade"] as? String ?? "EMPTY"
            let normalizedGrade: String = {
                let uppercased = rawGrade.uppercased()
                switch uppercased {
                case "CORRECT": return "CORRECT"
                case "INCORRECT": return "INCORRECT"
                case "EMPTY": return "EMPTY"
                case "PARTIAL_CREDIT", "PARTIAL CREDIT", "PARTIALCREDIT": return "PARTIAL_CREDIT"
                default: return uppercased
                }
            }()

            let localQuestion: [String: Any] = [
                "id": id,
                "subject": serverQuestion["subject"] as? String ?? "Unknown",
                "questionText": questionText,
                "rawQuestionText": serverQuestion["rawQuestionText"] as? String ?? questionText,  // Include raw question
                "answerText": answerText,
                "confidence": serverQuestion["confidence"] as? Float ?? 0.0,
                "hasVisualElements": serverQuestion["hasVisualElements"] as? Bool ?? false,
                "tags": serverQuestion["tags"] as? [String] ?? [],
                "notes": serverQuestion["notes"] as? String ?? "",
                "studentAnswer": serverQuestion["studentAnswer"] as? String ?? "",
                "grade": normalizedGrade,  // ✅ Store normalized grade
                "points": serverQuestion["points"] as? Float ?? 0.0,
                "maxPoints": serverQuestion["maxPoints"] as? Float ?? 1.0,
                "feedback": serverQuestion["feedback"] as? String ?? "",
                "isCorrect": ((serverQuestion["isCorrect"] as? Bool) ?? (serverQuestion["is_correct"] as? Bool)) as Any,  // ✅ Include for mistake tracking
                "archivedAt": serverQuestion["archivedAt"] as? String ?? ISO8601DateFormatter().string(from: Date())
            ]

            print("   📊 [Sync] Grade: \(rawGrade) → \(normalizedGrade), isCorrect: \(localQuestion["isCorrect"] ?? "nil")")

            // Save to local storage
            localStorage.saveQuestions([localQuestion])
            downloadedFromServerCount += 1
            print("   ✅ [Sync] Downloaded question to local storage")
        }

        if downloadedFromServerCount > 0 {
            print("\n📥 [Sync] Downloaded \(downloadedFromServerCount) questions from server to local storage")
        } else {
            print("\n📥 [Sync] No new questions to download from server")
        }

        // STEP 5: Upload local questions that don't exist on server
        print("\n📤 [Sync] Step 5: Uploading local questions to server...")

        guard !localQuestions.isEmpty else {
            print("   ℹ️ [Sync] No local questions to upload")
            print("\n📊 [Sync] Questions summary: \(downloadedFromServerCount) downloaded, 0 uploaded, 0 duplicates")
            return (downloadedFromServerCount, 0)
        }

        for (index, questionData) in localQuestions.enumerated() {
            print("\n   📝 [Sync] Question \(index + 1)/\(localQuestions.count):")

            do {
                // Check if already exists on server by checking if it has server ID
                if let id = questionData["id"] as? String, id.count > 10 {
                    if serverQuestionIds.contains(id) {
                        print("   ⏭️  [Sync] Already on server with ID: \(id) - SKIPPING (duplicate)")
                        duplicateCount += 1
                        continue
                    } else {
                        print("   ❓ [Sync] Has ID but not on server - will upload")
                    }
                } else {
                    print("   🆕 [Sync] No server ID found - will upload to server")
                }

                // Prepare question for archiving
                guard let subject = questionData["subject"] as? String,
                      let questionText = questionData["questionText"] as? String,
                      let _ = questionData["answerText"] as? String else {
                    print("   ⚠️  [Sync] Missing required fields - skipping")
                    continue
                }

                // Extract only the fields we need for logging
                let grade = questionData["grade"] as? String
                let isCorrect = questionData["isCorrect"] as? Bool  // ✅ Extract for logging

                print("   📋 [Sync] Subject: \(subject), Question: \(questionText.prefix(50))...")
                print("   📊 [Sync] Grade: \(grade ?? "N/A"), isCorrect: \(isCorrect?.description ?? "nil")")

                // Upload directly to server using new method
                print("   📤 [Sync] Uploading to server API...")
                let serverId = try await QuestionArchiveService.shared.uploadQuestionToServer(questionData)

                // Update local storage with server ID
                var updatedQuestion = questionData
                updatedQuestion["id"] = serverId
                QuestionLocalStorage.shared.saveQuestions([updatedQuestion])

                syncedToServerCount += 1
                print("   ✅ [Sync] Successfully uploaded question (Server ID: \(serverId))")

            } catch {
                print("   ❌ [Sync] Failed to upload question: \(error)")
            }
        }

        let totalSynced = downloadedFromServerCount + syncedToServerCount
        print("\n📊 [Sync] Questions summary: \(downloadedFromServerCount) downloaded, \(syncedToServerCount) uploaded, \(duplicateCount) duplicates")
        return (totalSynced, duplicateCount)
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

        print("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let questionsArray = json["data"] as? [[String: Any]] {
                print("   ✅ [Sync] Server returned \(questionsArray.count) questions")
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

        print("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let conversationsArray = json["data"] as? [[String: Any]] {
                print("   ✅ [Sync] Server returned \(conversationsArray.count) conversations")
                return conversationsArray
            }
        }

        // Return empty array if no data
        return []
    }

    // MARK: - Sync Archived Conversations

    private func syncArchivedConversations() async throws -> (synced: Int, duplicates: Int) {
        guard let token = AuthenticationService.shared.getAuthToken() else {
            print("❌ [Sync] No auth token for conversations sync")
            throw SyncError.notAuthenticated
        }

        print("💬 [Sync] === SYNCING ARCHIVED CONVERSATIONS ===")

        // STEP 1: Fetch server conversations
        print("📥 [Sync] Step 1: Fetching server conversations...")
        let serverConversations = try await fetchConversationsFromServer(token: token)
        print("   ✅ [Sync] Fetched \(serverConversations.count) conversations from server")

        // STEP 2: Get local conversations
        print("📱 [Sync] Step 2: Getting local conversations...")
        let localStorage = ConversationLocalStorage.shared
        let localConversations = localStorage.getLocalConversations()
        print("   ✅ [Sync] Found \(localConversations.count) local conversations")

        var syncedToServerCount = 0
        var duplicateCount = 0
        var downloadedFromServerCount = 0

        // STEP 3: Build Sets for efficient comparison
        print("🔍 [Sync] Step 3: Building ID sets for comparison...")
        var serverConversationIds = Set<String>()
        for serverConv in serverConversations {
            if let id = serverConv["id"] as? String {
                serverConversationIds.insert(id)
            }
        }

        var localConversationIds = Set<String>()
        for localConv in localConversations {
            if let id = localConv["id"] as? String, id.count > 10 {
                localConversationIds.insert(id)
            }
        }
        print("   📊 [Sync] Server IDs: \(serverConversationIds.count), Local IDs: \(localConversationIds.count)")

        // STEP 4: Download server conversations that don't exist locally
        print("\n📥 [Sync] Step 4: Downloading server conversations to local storage...")
        for (index, serverConversation) in serverConversations.enumerated() {
            guard let id = serverConversation["id"] as? String else {
                print("   ⚠️ [Sync] Server conversation \(index + 1) has no ID - skipping")
                continue
            }

            // Check if this server conversation exists locally
            if localConversationIds.contains(id) {
                print("   ⏭️ [Sync] Conversation \(index + 1) already exists locally (ID: \(id)) - skipping")
                continue
            }

            // Download this conversation to local storage
            print("   📥 [Sync] Downloading conversation \(index + 1)/\(serverConversations.count) (ID: \(id))...")

            // Convert server conversation to local format
            // Backend returns conversationContent (camelCase)
            let conversationContent = serverConversation["conversationContent"] as? String ?? ""
            print("   📝 [Sync] Conversation content length: \(conversationContent.count) chars")
            if conversationContent.isEmpty {
                print("   ⚠️ [Sync] WARNING: Conversation content is EMPTY!")
            } else {
                print("   ✅ [Sync] Conversation has content: \(conversationContent.prefix(100))...")
            }

            let localConversation: [String: Any] = [
                "id": id,
                "subject": serverConversation["subject"] as? String ?? "General",
                "topic": serverConversation["topic"] as? String ?? "Chat Session",
                "conversationContent": conversationContent,
                "archivedDate": serverConversation["archivedDate"] as? String ?? ISO8601DateFormatter().string(from: Date())
            ]

            // Save to local storage
            localStorage.saveConversation(localConversation)
            downloadedFromServerCount += 1
            print("   ✅ [Sync] Downloaded conversation to local storage")
        }

        if downloadedFromServerCount > 0 {
            print("\n📥 [Sync] Downloaded \(downloadedFromServerCount) conversations from server to local storage")
        } else {
            print("\n📥 [Sync] No new conversations to download from server")
        }

        // STEP 5: Upload local conversations that don't exist on server
        print("\n📤 [Sync] Step 5: Uploading local conversations to server...")

        guard !localConversations.isEmpty else {
            print("   ℹ️ [Sync] No local conversations to upload")
            print("\n📊 [Sync] Conversations summary: \(downloadedFromServerCount) downloaded, 0 uploaded, 0 duplicates")
            return (downloadedFromServerCount, 0)
        }

        for (index, conversationData) in localConversations.enumerated() {
            print("\n   💬 [Sync] Conversation \(index + 1)/\(localConversations.count):")

            do {
                // Check if already exists on server by checking if it has server ID
                if let id = conversationData["id"] as? String, id.count > 10 {
                    if serverConversationIds.contains(id) {
                        print("   ⏭️  [Sync] Already on server with ID: \(id) - SKIPPING (duplicate)")
                        duplicateCount += 1
                        continue
                    } else {
                        print("   ❓ [Sync] Has ID but not on server - will upload")
                    }
                } else {
                    print("   🆕 [Sync] No server ID found - will upload to server")
                }

                let subject = conversationData["subject"] as? String ?? "General"
                let topic = conversationData["topic"] as? String ?? "Chat Session"
                let content = conversationData["conversationContent"] as? String ?? ""

                print("   📋 [Sync] Subject: \(subject), Topic: \(topic)")
                print("   📏 [Sync] Content length: \(content.count) chars")

                // Archive conversation to server
                guard let url = URL(string: "\(baseURL)/api/ai/conversations") else {
                    print("   ❌ [Sync] Invalid URL")
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

                print("   📤 [Sync] Sending POST to /api/ai/conversations...")
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("   ❌ [Sync] Invalid response")
                    throw SyncError.invalidResponse
                }

                print("   📡 [Sync] Server response: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 201 || httpResponse.statusCode == 200 {
                    syncedToServerCount += 1
                    print("   ✅ [Sync] Successfully uploaded conversation")
                } else if httpResponse.statusCode == 409 {
                    duplicateCount += 1
                    print("   🔄 [Sync] Server detected duplicate (409) - skipping")
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("   ❌ [Sync] Failed with status \(httpResponse.statusCode): \(errorMessage)")
                }

            } catch {
                print("   ❌ [Sync] Failed to upload conversation: \(error)")
            }
        }

        let totalSynced = downloadedFromServerCount + syncedToServerCount
        print("\n📊 [Sync] Conversations summary: \(downloadedFromServerCount) downloaded, \(syncedToServerCount) uploaded, \(duplicateCount) duplicates")
        return (totalSynced, duplicateCount)
    }

    // MARK: - Sync Progress Data

    private func syncProgressData() async throws {
        guard let token = AuthenticationService.shared.getAuthToken() else {
            print("❌ [Sync] No auth token for progress sync")
            throw SyncError.notAuthenticated
        }

        print("📊 [Sync] === SYNCING PROGRESS DATA ===")

        // STEP 1: Fetch server data
        print("📥 [Sync] Step 1: Fetching server progress data...")
        let serverProgress = try await fetchProgressFromServer(token: token)

        // STEP 2: Get local progress data
        print("📱 [Sync] Step 2: Getting local progress data...")
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
        print("🔄 [Sync] Step 3: Merging local and server data...")
        let mergedProgress = mergeProgressData(local: localProgress, server: serverProgress)

        // STEP 4: Compare merged with server
        print("🔍 [Sync] Step 4: Comparing merged data with server...")
        let hasChanges = progressHasChanges(merged: mergedProgress, server: serverProgress)

        if hasChanges {
            print("📤 [Sync] Step 5: Changes detected, updating server...")
            try await updateProgressOnServer(progress: mergedProgress, token: token)
            print("✅ [Sync] Progress data synced successfully")
        } else {
            print("✅ [Sync] No changes detected, server already up to date")
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

        print("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let serverData = json["data"] as? [String: Any] {
                print("   ✅ [Sync] Server progress data retrieved")
                print("   📊 [Sync] Server Points: \(serverData["currentPoints"] ?? 0)")
                print("   📊 [Sync] Server Streak: \(serverData["currentStreak"] ?? 0)")
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
        print("   🔀 [Sync] Points: local=\(localPoints), server=\(serverPoints), merged=\(merged["currentPoints"] ?? 0)")

        let localTotalPoints = local["totalPoints"] as? Int ?? 0
        let serverTotalPoints = server["totalPoints"] as? Int ?? 0
        merged["totalPoints"] = max(localTotalPoints, serverTotalPoints)
        print("   🔀 [Sync] Total Points: local=\(localTotalPoints), server=\(serverTotalPoints), merged=\(merged["totalPoints"] ?? 0)")

        // Merge streak: take maximum
        let localStreak = local["currentStreak"] as? Int ?? 0
        let serverStreak = server["currentStreak"] as? Int ?? 0
        merged["currentStreak"] = max(localStreak, serverStreak)
        print("   🔀 [Sync] Streak: local=\(localStreak), server=\(serverStreak), merged=\(merged["currentStreak"] ?? 0)")

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

        print("   🔍 [Sync] Points changed: \(pointsChanged) (\(mergedPoints) vs \(serverPoints))")
        print("   🔍 [Sync] Total points changed: \(totalPointsChanged) (\(mergedTotalPoints) vs \(serverTotalPoints))")
        print("   🔍 [Sync] Streak changed: \(streakChanged) (\(mergedStreak) vs \(serverStreak))")

        return pointsChanged || totalPointsChanged || streakChanged
    }

    private func updateProgressOnServer(progress: [String: Any], token: String) async throws {
        guard let url = URL(string: "\(baseURL)/api/progress/sync") else {
            print("   ❌ [Sync] Invalid URL")
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: progress)

        print("   📤 [Sync] Sending POST to /api/progress/sync...")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("   ❌ [Sync] Invalid response")
            throw SyncError.invalidResponse
        }

        print("   📡 [Sync] Server response: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
            print("   ✅ [Sync] Progress data updated successfully")
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("   ❌ [Sync] Failed with status \(httpResponse.statusCode): \(errorMessage)")
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
