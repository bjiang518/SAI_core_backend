//
//  AssistantLogger.swift
//  StudyAI
//
//  Created by Claude Code on 2025-11-12.
//  OpenAI Assistants API Performance Monitoring & A/B Testing
//

import Foundation
import Combine
import OSLog

/// OpenAI Assistants API 专用日志服务
/// 用于性能监控、成本追踪、A/B测试对比
@MainActor
class AssistantLogger: ObservableObject {
    static let shared = AssistantLogger()

    // MARK: - OSLog Categories
    private let performanceLogger = Logger(subsystem: "com.studyai.app", category: "AssistantPerformance")
    private let costLogger = Logger(subsystem: "com.studyai.app", category: "AssistantCost")
    private let errorLogger = Logger(subsystem: "com.studyai.app", category: "AssistantError")
    private let abTestLogger = Logger(subsystem: "com.studyai.app", category: "AssistantABTest")

    // MARK: - Published Properties
    @Published var recentMetrics: [AssistantMetric] = []
    @Published var dailyCostEstimate: Decimal = 0.0
    @Published var todayRequestCount: Int = 0

    // MARK: - Private Properties
    private var metricsBuffer: [AssistantMetric] = []
    private let bufferLimit = 100
    private let persistThreshold = 50 // 批量写入阈值

    private init() {
        loadTodayMetrics()
    }

    // MARK: - Assistant Metric Model

    struct AssistantMetric: Identifiable, Codable {
        let id: UUID
        let timestamp: Date

        // Request Info
        let assistantType: AssistantType
        let endpoint: String
        let userId: String

        // Performance
        let totalLatency: TimeInterval
        let firstTokenLatency: TimeInterval?
        let apiLatency: TimeInterval?

        // Cost (estimated)
        let inputTokens: Int
        let outputTokens: Int
        let estimatedCost: Decimal

        // Quality
        let wasSuccessful: Bool
        let errorCode: String?
        let errorMessage: String?

        // A/B Testing
        let useAssistantsAPI: Bool
        let experimentGroup: String?

        // Context
        let threadId: String?
        let runId: String?
        let model: String?
        let messageCount: Int?

        enum AssistantType: String, Codable {
            case homeworkTutor = "homework_tutor"
            case imageAnalyzer = "image_analyzer"
            case questionEvaluator = "question_evaluator"
            case practiceGenerator = "practice_generator"
            case essayGrader = "essay_grader"
            case parentReportAnalyst = "parent_report_analyst"
            case legacyAIEngine = "legacy_ai_engine"
        }
    }

    // MARK: - Request Tracking

    /// 开始追踪一个 Assistant 请求
    func startTracking(
        assistantType: AssistantMetric.AssistantType,
        endpoint: String,
        userId: String,
        useAssistantsAPI: Bool,
        experimentGroup: String? = nil
    ) -> AssistantRequestTracker {
        return AssistantRequestTracker(
            assistantType: assistantType,
            endpoint: endpoint,
            userId: userId,
            useAssistantsAPI: useAssistantsAPI,
            experimentGroup: experimentGroup,
            logger: self
        )
    }

    /// 记录完成的请求
    func logMetric(_ metric: AssistantMetric) {
        // 1. 添加到内存缓冲区
        metricsBuffer.append(metric)
        recentMetrics.append(metric)
        todayRequestCount += 1

        // 2. 保持最近 100 条记录
        if recentMetrics.count > bufferLimit {
            recentMetrics.removeFirst(recentMetrics.count - bufferLimit)
        }

        // 3. 记录到系统日志
        performanceLogger.info("""
            [\(metric.assistantType.rawValue)] \(metric.endpoint)
            Latency: \(String(format: "%.2f", metric.totalLatency))s
            Tokens: \(metric.inputTokens) in / \(metric.outputTokens) out
            Cost: $\(String(describing: metric.estimatedCost))
            Success: \(metric.wasSuccessful)
            API: \(metric.useAssistantsAPI ? "Assistants" : "AI Engine")
            """)

        // 4. 更新每日成本估算
        updateDailyCost(metric.estimatedCost)

        // 5. 错误记录
        if !metric.wasSuccessful, let error = metric.errorMessage {
            errorLogger.error("""
                [\(metric.assistantType.rawValue)] ERROR
                Endpoint: \(metric.endpoint)
                Code: \(metric.errorCode ?? "UNKNOWN")
                Message: \(error)
                """)
        }

        // 6. A/B 测试记录
        if let group = metric.experimentGroup {
            abTestLogger.info("""
                AB_TEST: \(group)
                Assistant: \(metric.assistantType.rawValue)
                Latency: \(String(format: "%.2f", metric.totalLatency))s
                Success: \(metric.wasSuccessful)
                """)
        }

        // 7. 批量持久化
        if metricsBuffer.count >= persistThreshold {
            Task {
                await persistMetrics()
            }
        }
    }

    // MARK: - Cost Tracking

    private func updateDailyCost(_ cost: Decimal) {
        dailyCostEstimate += cost
    }

    func resetDailyCost() {
        dailyCostEstimate = 0.0
        todayRequestCount = 0
    }

    /// 计算 token 成本（基于模型）
    static func calculateCost(
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> Decimal {
        let pricing: [String: (input: Decimal, output: Decimal)] = [
            "gpt-4o-mini": (Decimal(0.000150) / 1000, Decimal(0.000600) / 1000),
            "gpt-4o": (Decimal(0.00250) / 1000, Decimal(0.01000) / 1000),
            "gpt-3.5-turbo": (Decimal(0.000500) / 1000, Decimal(0.001500) / 1000)
        ]

        guard let price = pricing[model] else {
            return 0.0
        }

        let inputCost = price.input * Decimal(inputTokens)
        let outputCost = price.output * Decimal(outputTokens)

        return inputCost + outputCost
    }

    // MARK: - Analytics

    /// 获取性能统计
    func getPerformanceStats(for assistantType: AssistantMetric.AssistantType? = nil) -> PerformanceStats {
        let filteredMetrics = assistantType == nil
            ? recentMetrics
            : recentMetrics.filter { $0.assistantType == assistantType }

        guard !filteredMetrics.isEmpty else {
            return PerformanceStats.empty
        }

        let latencies = filteredMetrics.map { $0.totalLatency }
        let successCount = filteredMetrics.filter { $0.wasSuccessful }.count
        let totalCost = filteredMetrics.reduce(Decimal(0)) { $0 + $1.estimatedCost }

        return PerformanceStats(
            requestCount: filteredMetrics.count,
            successRate: Double(successCount) / Double(filteredMetrics.count),
            avgLatency: latencies.reduce(0.0, +) / Double(latencies.count),
            p50Latency: percentile(latencies, 50),
            p95Latency: percentile(latencies, 95),
            p99Latency: percentile(latencies, 99),
            totalCost: totalCost,
            avgCostPerRequest: totalCost / Decimal(filteredMetrics.count)
        )
    }

    /// A/B 测试对比
    func getABTestComparison() -> ABTestComparison? {
        let assistantsMetrics = recentMetrics.filter { $0.useAssistantsAPI }
        let engineMetrics = recentMetrics.filter { !$0.useAssistantsAPI }

        guard !assistantsMetrics.isEmpty && !engineMetrics.isEmpty else {
            return nil
        }

        let assistantsStats = getStatsForMetrics(assistantsMetrics)
        let engineStats = getStatsForMetrics(engineMetrics)

        let latencyReduction = ((engineStats.avgLatency - assistantsStats.avgLatency) / engineStats.avgLatency) * 100
        let costChange = ((Double(truncating: assistantsStats.avgCostPerRequest as NSNumber) - Double(truncating: engineStats.avgCostPerRequest as NSNumber)) / Double(truncating: engineStats.avgCostPerRequest as NSNumber)) * 100
        let successRateChange = (assistantsStats.successRate - engineStats.successRate) * 100

        return ABTestComparison(
            assistantsAPI: assistantsStats,
            aiEngine: engineStats,
            improvement: ABTestComparison.ImprovementMetrics(
                latencyReduction: latencyReduction,
                costChange: costChange,
                successRateChange: successRateChange
            )
        )
    }

    private func getStatsForMetrics(_ metrics: [AssistantMetric]) -> PerformanceStats {
        let latencies = metrics.map { $0.totalLatency }
        let successCount = metrics.filter { $0.wasSuccessful }.count
        let totalCost = metrics.reduce(Decimal(0)) { $0 + $1.estimatedCost }

        return PerformanceStats(
            requestCount: metrics.count,
            successRate: Double(successCount) / Double(metrics.count),
            avgLatency: latencies.reduce(0.0, +) / Double(latencies.count),
            p50Latency: percentile(latencies, 50),
            p95Latency: percentile(latencies, 95),
            p99Latency: percentile(latencies, 99),
            totalCost: totalCost,
            avgCostPerRequest: totalCost / Decimal(metrics.count)
        )
    }

    // MARK: - Persistence

    private func persistMetrics() async {
        let metricsToSave = metricsBuffer
        metricsBuffer.removeAll()

        let fileURL = getMetricsFileURL()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(metricsToSave)
            try data.write(to: fileURL)

            performanceLogger.info("Persisted \(metricsToSave.count) metrics to disk")
        } catch {
            errorLogger.error("Failed to persist metrics: \(error.localizedDescription)")
        }
    }

    private func loadTodayMetrics() {
        let fileURL = getMetricsFileURL()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metrics = try decoder.decode([AssistantMetric].self, from: data)

            recentMetrics = Array(metrics.suffix(bufferLimit))
            dailyCostEstimate = metrics.reduce(Decimal(0)) { $0 + $1.estimatedCost }
            todayRequestCount = metrics.count

            performanceLogger.info("Loaded \(metrics.count) metrics from disk")
        } catch {
            errorLogger.error("Failed to load metrics: \(error.localizedDescription)")
        }
    }

    private func getMetricsFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return documentsPath.appendingPathComponent("assistant_metrics_\(dateString).json")
    }

    // MARK: - Helper Structs

    struct PerformanceStats {
        let requestCount: Int
        let successRate: Double
        let avgLatency: TimeInterval
        let p50Latency: TimeInterval
        let p95Latency: TimeInterval
        let p99Latency: TimeInterval
        let totalCost: Decimal
        let avgCostPerRequest: Decimal

        static let empty = PerformanceStats(
            requestCount: 0, successRate: 0, avgLatency: 0,
            p50Latency: 0, p95Latency: 0, p99Latency: 0,
            totalCost: 0, avgCostPerRequest: 0
        )
    }

    struct ABTestComparison {
        let assistantsAPI: PerformanceStats
        let aiEngine: PerformanceStats
        let improvement: ImprovementMetrics

        struct ImprovementMetrics {
            let latencyReduction: Double // 百分比，如 -35.5 表示降低 35.5%
            let costChange: Double
            let successRateChange: Double
        }
    }

    // MARK: - Helper Functions

    private func percentile(_ values: [TimeInterval], _ p: Int) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count) * Double(p) / 100.0)
        return sorted[min(index, sorted.count - 1)]
    }
}

// MARK: - Request Tracker

/// 追踪单个请求的辅助类
class AssistantRequestTracker {
    private let startTime: Date
    private var firstTokenTime: Date?
    private var apiCallStart: Date?
    private var apiCallEnd: Date?

    let assistantType: AssistantLogger.AssistantMetric.AssistantType
    let endpoint: String
    let userId: String
    let useAssistantsAPI: Bool
    let experimentGroup: String?
    let logger: AssistantLogger

    var threadId: String?
    var runId: String?
    var messageCount: Int?

    init(
        assistantType: AssistantLogger.AssistantMetric.AssistantType,
        endpoint: String,
        userId: String,
        useAssistantsAPI: Bool,
        experimentGroup: String?,
        logger: AssistantLogger
    ) {
        self.startTime = Date()
        self.assistantType = assistantType
        self.endpoint = endpoint
        self.userId = userId
        self.useAssistantsAPI = useAssistantsAPI
        self.experimentGroup = experimentGroup
        self.logger = logger
    }

    func markFirstToken() {
        if firstTokenTime == nil {
            firstTokenTime = Date()
        }
    }

    func markAPICallStart() {
        apiCallStart = Date()
    }

    func markAPICallEnd() {
        apiCallEnd = Date()
    }

    func complete(
        inputTokens: Int,
        outputTokens: Int,
        model: String,
        success: Bool,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        let endTime = Date()
        let totalLatency = endTime.timeIntervalSince(startTime)
        let firstTokenLatency = firstTokenTime?.timeIntervalSince(startTime)
        let apiLatency = apiCallEnd != nil && apiCallStart != nil
            ? apiCallEnd!.timeIntervalSince(apiCallStart!)
            : nil

        let estimatedCost = AssistantLogger.calculateCost(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )

        let metric = AssistantLogger.AssistantMetric(
            id: UUID(),
            timestamp: startTime,
            assistantType: assistantType,
            endpoint: endpoint,
            userId: userId,
            totalLatency: totalLatency,
            firstTokenLatency: firstTokenLatency,
            apiLatency: apiLatency,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCost: estimatedCost,
            wasSuccessful: success,
            errorCode: errorCode,
            errorMessage: errorMessage,
            useAssistantsAPI: useAssistantsAPI,
            experimentGroup: experimentGroup,
            threadId: threadId,
            runId: runId,
            model: model,
            messageCount: messageCount
        )

        Task { @MainActor in
            logger.logMetric(metric)
        }
    }
}
