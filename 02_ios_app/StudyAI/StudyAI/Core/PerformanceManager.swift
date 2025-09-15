//
//  PerformanceManager.swift
//  StudyAI
//
//  Performance monitoring and optimization manager
//

import Foundation
import UIKit
import os.log

class PerformanceManager: ObservableObject {
    static let shared = PerformanceManager()
    
    // MARK: - Performance Metrics
    @Published var memoryUsage: Double = 0.0
    @Published var cpuUsage: Double = 0.0
    @Published var networkLatency: TimeInterval = 0.0
    @Published var renderingFPS: Double = 60.0
    
    // MARK: - Monitoring
    private var performanceTimer: Timer?
    private let logger = Logger(subsystem: "com.studyai", category: "Performance")
    
    // MARK: - Memory Pressure Handling
    private var memoryWarningObserver: NSObjectProtocol?
    
    // MARK: - Performance Thresholds
    private let memoryWarningThreshold: Double = 0.8 // 80% of available memory
    private let cpuThrottleThreshold: Double = 0.9 // 90% CPU usage
    private let lowFPSThreshold: Double = 30.0
    
    private init() {
        setupPerformanceMonitoring()
        setupMemoryWarningHandler()
    }
    
    // MARK: - Setup Methods
    
    private func setupPerformanceMonitoring() {
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updatePerformanceMetrics()
        }
    }
    
    private func setupMemoryWarningHandler() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }\n    }\n    \n    // MARK: - Performance Monitoring\n    \n    private func updatePerformanceMetrics() {\n        Task {\n            let memory = await measureMemoryUsage()\n            let cpu = measureCPUUsage()\n            \n            await MainActor.run {\n                self.memoryUsage = memory\n                self.cpuUsage = cpu\n                \n                self.checkPerformanceThresholds()\n            }\n        }\n    }\n    \n    private func measureMemoryUsage() async -> Double {\n        var info = mach_task_basic_info()\n        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4\n        \n        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {\n            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {\n                task_info(mach_task_self_,\n                         task_flavor_t(MACH_TASK_BASIC_INFO),\n                         $0,\n                         &count)\n            }\n        }\n        \n        if kerr == KERN_SUCCESS {\n            let memoryUsageBytes = Double(info.resident_size)\n            let memoryUsageMB = memoryUsageBytes / (1024 * 1024)\n            return memoryUsageMB\n        }\n        \n        return 0.0\n    }\n    \n    private func measureCPUUsage() -> Double {\n        var info = proc_taskinfo()\n        let size = MemoryLayout<proc_taskinfo>.stride\n        \n        let result = proc_pidinfo(getpid(), PROC_PIDTASKINFO, 0, &info, Int32(size))\n        \n        if result == Int32(size) {\n            let totalTime = info.pti_total_user + info.pti_total_system\n            // This is a simplified calculation - in production you'd want to track deltas\n            return Double(totalTime) / 1000000.0 // Convert to percentage\n        }\n        \n        return 0.0\n    }\n    \n    // MARK: - Memory Management\n    \n    private func handleMemoryWarning() {\n        logger.warning(\"Memory warning received - initiating cleanup\")\n        \n        // Notify other services to clean up\n        NotificationCenter.default.post(name: .performanceMemoryWarning, object: nil)\n        \n        // Clear caches\n        clearNonEssentialCaches()\n        \n        // Force garbage collection\n        autoreleasepool {\n            // Empty pool to encourage deallocation\n        }\n    }\n    \n    private func clearNonEssentialCaches() {\n        // Clear NetworkService cache\n        if let networkCache = URLCache.shared as? URLCache {\n            networkCache.removeAllCachedResponses()\n        }\n        \n        // Clear image caches (if any)\n        // This would depend on your image caching implementation\n    }\n    \n    // MARK: - Performance Optimization\n    \n    private func checkPerformanceThresholds() {\n        if memoryUsage > memoryWarningThreshold * 1024 { // Convert to MB\n            logger.warning(\"High memory usage detected: \\(memoryUsage)MB\")\n            handleHighMemoryUsage()\n        }\n        \n        if cpuUsage > cpuThrottleThreshold {\n            logger.warning(\"High CPU usage detected: \\(cpuUsage)%\")\n            handleHighCPUUsage()\n        }\n    }\n    \n    private func handleHighMemoryUsage() {\n        // Implement memory optimization strategies\n        clearNonEssentialCaches()\n        \n        // Reduce cache sizes\n        AppStateManager.shared.appSettings.cacheSize = max(10, AppStateManager.shared.appSettings.cacheSize / 2)\n        \n        // Notify user if necessary\n        if memoryUsage > memoryWarningThreshold * 1.2 * 1024 {\n            notifyUserOfPerformanceIssue(.memory)\n        }\n    }\n    \n    private func handleHighCPUUsage() {\n        // Implement CPU optimization strategies\n        // This could include reducing animation complexity, throttling updates, etc.\n        \n        logger.info(\"Implementing CPU throttling measures\")\n    }\n    \n    private func notifyUserOfPerformanceIssue(_ type: PerformanceIssueType) {\n        // This could trigger a user-facing alert or notification\n        logger.error(\"Performance issue detected: \\(type)\")\n    }\n    \n    // MARK: - Public Interface\n    \n    func startMonitoring() {\n        setupPerformanceMonitoring()\n        logger.info(\"Performance monitoring started\")\n    }\n    \n    func stopMonitoring() {\n        performanceTimer?.invalidate()\n        performanceTimer = nil\n        logger.info(\"Performance monitoring stopped\")\n    }\n    \n    func getPerformanceReport() -> PerformanceReport {\n        return PerformanceReport(\n            memoryUsage: memoryUsage,\n            cpuUsage: cpuUsage,\n            networkLatency: networkLatency,\n            renderingFPS: renderingFPS,\n            timestamp: Date()\n        )\n    }\n    \n    deinit {\n        performanceTimer?.invalidate()\n        if let observer = memoryWarningObserver {\n            NotificationCenter.default.removeObserver(observer)\n        }\n    }\n}\n\n// MARK: - Supporting Types\n\nenum PerformanceIssueType {\n    case memory, cpu, network, rendering\n}\n\nstruct PerformanceReport {\n    let memoryUsage: Double\n    let cpuUsage: Double\n    let networkLatency: TimeInterval\n    let renderingFPS: Double\n    let timestamp: Date\n}\n\n// MARK: - Notifications\n\nextension Notification.Name {\n    static let performanceMemoryWarning = Notification.Name(\"PerformanceMemoryWarning\")\n}