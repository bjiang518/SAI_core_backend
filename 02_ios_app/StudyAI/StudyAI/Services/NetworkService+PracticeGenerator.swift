//
//  NetworkService+PracticeGenerator.swift
//  StudyAI
//
//  Integration example for AssistantLogger with Practice Generator
//

import Foundation

extension NetworkService {

    /// Generate practice questions with Assistants API monitoring
    func generatePracticeQuestions(
        subject: String,
        topic: String? = nil,
        difficulty: Int? = nil,
        count: Int = 5,
        language: String = "en"
    ) async throws -> [PracticeQuestion] {

        // Get auth token
        guard let token = AuthenticationService.shared.getAuthToken() else {
            throw NetworkError.authenticationRequired
        }

        // Get user ID from UserDefaults (same pattern as existing NetworkService methods)
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            throw NetworkError.authenticationRequired
        }

        // 开始追踪
        let useAssistantsAPI = UserDefaults.standard.bool(forKey: "useAssistantsAPI")
        let tracker = AssistantLogger.shared.startTracking(
            assistantType: .practiceGenerator,
            endpoint: "/api/ai/generate-questions/practice",
            userId: userId,
            useAssistantsAPI: useAssistantsAPI,
            experimentGroup: getExperimentGroup() // A/B 测试分组
        )

        // 标记 API 调用开始
        tracker.markAPICallStart()

        do {
            // 构建请求
            let requestBody: [String: Any] = [
                "subject": subject,
                "topic": topic as Any,
                "difficulty": difficulty as Any,
                "count": count,
                "language": language
            ]

            guard let url = URL(string: "\(apiBaseURL)/api/ai/generate-questions/practice") else {
                throw NetworkError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            // 发起请求
            let (data, response) = try await URLSession.shared.data(for: request)

            // 标记 API 调用结束
            tracker.markAPICallEnd()

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw NetworkError.serverError(httpResponse.statusCode)
            }

            // 解析响应
            let jsonResponse = try JSONDecoder().decode(PracticeQuestionResponse.self, from: data)

            // 提取 token 信息和 metadata
            let metadata = jsonResponse.metadata ?? [:]
            let inputTokens = (metadata["input_tokens"] as? Int) ?? 0
            let outputTokens = (metadata["output_tokens"] as? Int) ?? 0
            let model = (metadata["model"] as? String) ?? "gpt-4o-mini"
            let threadId = metadata["thread_id"] as? String
            let runId = metadata["run_id"] as? String

            // 更新 tracker
            tracker.threadId = threadId
            tracker.runId = runId

            // 完成追踪
            tracker.complete(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                model: model,
                success: true
            )

            return jsonResponse.questions

        } catch {
            // 错误处理
            tracker.complete(
                inputTokens: 0,
                outputTokens: 0,
                model: "gpt-4o-mini",
                success: false,
                errorCode: (error as NSError).domain,
                errorMessage: error.localizedDescription
            )

            throw error
        }
    }

    // MARK: - A/B Testing Helpers

    private func getExperimentGroup() -> String {
        // 基于用户 ID 的确定性分组
        guard let userId = UserDefaults.standard.string(forKey: "userId") else {
            return "unknown"
        }

        // 使用 hash 来分组
        let hash = userId.hash
        return hash % 2 == 0 ? "control" : "treatment"
    }
}

// MARK: - Response Models

struct PracticeQuestionResponse: Codable {
    let success: Bool
    let questions: [PracticeQuestion]
    let metadata: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case success, questions, metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success)
        questions = try container.decode([PracticeQuestion].self, forKey: .questions)

        // Metadata 是动态 JSON，需要特殊处理
        if let metadataDict = try? container.decode([String: AnyCodable].self, forKey: .metadata) {
            metadata = metadataDict.mapValues { $0.value }
        } else {
            metadata = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(questions, forKey: .questions)

        if let metadata = metadata {
            let encodableMetadata = metadata.mapValues { AnyCodable($0) }
            try container.encode(encodableMetadata, forKey: .metadata)
        }
    }
}

struct PracticeQuestion: Codable, Identifiable {
    let id: String
    let question: String
    let questionType: String
    let difficulty: Int
    let estimatedTimeMinutes: Int
    let subject: String
    let topic: String
    let hints: [String]
    let correctAnswer: String?
    let explanation: String
    let multipleChoiceOptions: [MultipleChoiceOption]?
    let tags: [String]
    let learningObjectives: [String]
    let latexRendering: String?

    enum CodingKeys: String, CodingKey {
        case id, question, difficulty, subject, topic, hints, explanation, tags
        case questionType = "question_type"
        case estimatedTimeMinutes = "estimated_time_minutes"
        case correctAnswer = "correct_answer"
        case multipleChoiceOptions = "multiple_choice_options"
        case learningObjectives = "learning_objectives"
        case latexRendering = "latex_rendering"
    }
}

struct MultipleChoiceOption: Codable {
    let label: String
    let text: String
    let isCorrect: Bool

    enum CodingKeys: String, CodingKey {
        case label, text
        case isCorrect = "is_correct"
    }
}

// MARK: - Helper for Any Codable
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
