/**
 * Performance Analysis & Baseline Tool
 * Analyzes current API performance and identifies bottlenecks
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { performance } = require('perf_hooks');

class PerformanceAnalyzer {
  constructor() {
    this.metrics = {
      requests: [],
      memory: [],
      cpu: [],
      latency: [],
      errors: []
    };
    this.startTime = Date.now();
    this.enabled = process.env.PERFORMANCE_ANALYSIS_ENABLED !== 'false';
    
    if (this.enabled) {
      this.startMonitoring();
    }
  }

  /**
   * Start performance monitoring
   */
  startMonitoring() {
    // Monitor system resources every second
    this.resourceMonitor = setInterval(() => {
      this.collectSystemMetrics();
    }, 1000);

    // Monitor memory usage every 5 seconds
    this.memoryMonitor = setInterval(() => {
      this.collectMemoryMetrics();
    }, 5000);

    console.log('📊 Performance monitoring started');
  }

  /**
   * Stop performance monitoring
   */
  stopMonitoring() {
    if (this.resourceMonitor) {
      clearInterval(this.resourceMonitor);
    }
    if (this.memoryMonitor) {
      clearInterval(this.memoryMonitor);
    }
    console.log('📊 Performance monitoring stopped');
  }

  /**
   * Collect system performance metrics
   */
  collectSystemMetrics() {
    const cpuUsage = process.cpuUsage();
    const memoryUsage = process.memoryUsage();
    
    this.metrics.cpu.push({
      timestamp: Date.now(),
      user: cpuUsage.user,
      system: cpuUsage.system,
      loadAverage: os.loadavg()[0]
    });

    this.metrics.memory.push({
      timestamp: Date.now(),
      rss: memoryUsage.rss,
      heapUsed: memoryUsage.heapUsed,
      heapTotal: memoryUsage.heapTotal,
      external: memoryUsage.external,
      arrayBuffers: memoryUsage.arrayBuffers
    });

    // Keep only last 100 measurements
    if (this.metrics.cpu.length > 100) this.metrics.cpu.shift();
    if (this.metrics.memory.length > 100) this.metrics.memory.shift();
  }

  /**
   * Collect memory metrics
   */
  collectMemoryMetrics() {
    if (global.gc) {
      const beforeGC = process.memoryUsage();
      global.gc();
      const afterGC = process.memoryUsage();
      
      console.log(`🧹 GC: Freed ${(beforeGC.heapUsed - afterGC.heapUsed) / 1024 / 1024}MB`);
    }
  }

  /**
   * Fastify middleware for request performance tracking
   */
  getRequestTrackingMiddleware() {
    return async (request, reply) => {
      if (!this.enabled) return;

      const startTime = performance.now();
      request.performanceStart = startTime;
      
      // Hook will be handled by the preHandler/onResponse hooks in the main application
      const endTime = performance.now();
      const duration = endTime - request.performanceStart;
      
      this.recordRequest({
        method: request.method,
        url: request.url,
        statusCode: reply.statusCode || 200,
        duration,
        timestamp: Date.now(),
        payloadSize: 0, // Will be updated in response hook
        userAgent: request.headers['user-agent'],
        ip: request.ip
      });
    };
  }

  /**
   * Record request performance data
   */
  recordRequest(data) {
    this.metrics.requests.push(data);

    // Track errors
    if (data.statusCode >= 400) {
      this.metrics.errors.push(data);
    }

    // Track latency
    this.metrics.latency.push({
      timestamp: data.timestamp,
      duration: data.duration,
      endpoint: `${data.method} ${data.url}`
    });

    // Keep only last 1000 requests
    if (this.metrics.requests.length > 1000) this.metrics.requests.shift();
    if (this.metrics.errors.length > 200) this.metrics.errors.shift();
    if (this.metrics.latency.length > 1000) this.metrics.latency.shift();
  }

  /**
   * Analyze current performance and identify bottlenecks
   */
  analyzePerformance() {
    const analysis = {
      timestamp: new Date().toISOString(),
      uptime: Date.now() - this.startTime,
      requests: this.analyzeRequests(),
      memory: this.analyzeMemory(),
      cpu: this.analyzeCPU(),
      errors: this.analyzeErrors(),
      bottlenecks: [],
      recommendations: []
    };

    // Identify bottlenecks
    analysis.bottlenecks = this.identifyBottlenecks(analysis);
    analysis.recommendations = this.generateRecommendations(analysis);

    return analysis;
  }

  /**
   * Analyze request performance
   */
  analyzeRequests() {
    if (this.metrics.requests.length === 0) {
      return { totalRequests: 0, avgDuration: 0, rps: 0 };
    }

    const requests = this.metrics.requests;
    const durations = requests.map(r => r.duration);
    const last60s = requests.filter(r => Date.now() - r.timestamp < 60000);
    
    return {
      totalRequests: requests.length,
      avgDuration: durations.reduce((a, b) => a + b, 0) / durations.length,
      p95Duration: this.percentile(durations, 95),
      p99Duration: this.percentile(durations, 99),
      minDuration: Math.min(...durations),
      maxDuration: Math.max(...durations),
      rps: last60s.length / 60, // Requests per second
      endpoints: this.getEndpointStats(),
      statusCodes: this.getStatusCodeStats()
    };
  }

  /**
   * Analyze memory usage
   */
  analyzeMemory() {
    if (this.metrics.memory.length === 0) {
      return { avgHeapUsed: 0, maxHeapUsed: 0 };
    }

    const memory = this.metrics.memory;
    const heapUsed = memory.map(m => m.heapUsed);
    const rss = memory.map(m => m.rss);

    return {
      avgHeapUsed: heapUsed.reduce((a, b) => a + b, 0) / heapUsed.length,
      maxHeapUsed: Math.max(...heapUsed),
      avgRSS: rss.reduce((a, b) => a + b, 0) / rss.length,
      maxRSS: Math.max(...rss),
      currentMemory: process.memoryUsage(),
      memoryTrend: this.calculateTrend(heapUsed)
    };
  }

  /**
   * Analyze CPU usage
   */
  analyzeCPU() {
    if (this.metrics.cpu.length === 0) {
      return { avgLoadAverage: 0 };
    }

    const cpu = this.metrics.cpu;
    const loadAverages = cpu.map(c => c.loadAverage);

    return {
      avgLoadAverage: loadAverages.reduce((a, b) => a + b, 0) / loadAverages.length,
      maxLoadAverage: Math.max(...loadAverages),
      currentLoad: os.loadavg(),
      cpuCount: os.cpus().length,
      loadTrend: this.calculateTrend(loadAverages)
    };
  }

  /**
   * Analyze error patterns
   */
  analyzeErrors() {
    const errors = this.metrics.errors;
    const errorsByStatus = {};
    const errorsByEndpoint = {};

    errors.forEach(error => {
      errorsByStatus[error.statusCode] = (errorsByStatus[error.statusCode] || 0) + 1;
      const endpoint = `${error.method} ${error.url}`;
      errorsByEndpoint[endpoint] = (errorsByEndpoint[endpoint] || 0) + 1;
    });

    return {
      totalErrors: errors.length,
      errorRate: this.metrics.requests.length > 0 ? (errors.length / this.metrics.requests.length) * 100 : 0,
      errorsByStatus,
      errorsByEndpoint,
      recentErrors: errors.slice(-10)
    };
  }

  /**
   * Get endpoint performance statistics
   */
  getEndpointStats() {
    const endpointStats = {};
    
    this.metrics.requests.forEach(req => {
      const endpoint = `${req.method} ${req.url}`;
      if (!endpointStats[endpoint]) {
        endpointStats[endpoint] = {
          count: 0,
          totalDuration: 0,
          durations: []
        };
      }
      
      endpointStats[endpoint].count++;
      endpointStats[endpoint].totalDuration += req.duration;
      endpointStats[endpoint].durations.push(req.duration);
    });

    // Calculate statistics for each endpoint
    Object.keys(endpointStats).forEach(endpoint => {
      const stats = endpointStats[endpoint];
      stats.avgDuration = stats.totalDuration / stats.count;
      stats.p95Duration = this.percentile(stats.durations, 95);
      stats.minDuration = Math.min(...stats.durations);
      stats.maxDuration = Math.max(...stats.durations);
      delete stats.durations; // Remove raw data to save memory
    });

    return endpointStats;
  }

  /**
   * Get status code statistics
   */
  getStatusCodeStats() {
    const statusStats = {};
    
    this.metrics.requests.forEach(req => {
      const status = Math.floor(req.statusCode / 100) * 100; // Group by 2xx, 3xx, etc.
      statusStats[status] = (statusStats[status] || 0) + 1;
    });

    return statusStats;
  }

  /**
   * Identify performance bottlenecks
   */
  identifyBottlenecks(analysis) {
    const bottlenecks = [];

    // High response times
    if (analysis.requests.p95Duration > 500) {
      bottlenecks.push({
        type: 'high_latency',
        severity: 'high',
        description: `P95 response time is ${analysis.requests.p95Duration.toFixed(2)}ms`,
        impact: 'User experience degradation'
      });
    }

    // High memory usage
    if (analysis.memory.maxHeapUsed > 512 * 1024 * 1024) { // 512MB
      bottlenecks.push({
        type: 'high_memory',
        severity: 'medium',
        description: `Peak memory usage: ${(analysis.memory.maxHeapUsed / 1024 / 1024).toFixed(2)}MB`,
        impact: 'Potential memory leaks or inefficient memory usage'
      });
    }

    // High CPU load
    if (analysis.cpu.avgLoadAverage > analysis.cpu.cpuCount * 0.8) {
      bottlenecks.push({
        type: 'high_cpu',
        severity: 'high',
        description: `Average load: ${analysis.cpu.avgLoadAverage.toFixed(2)} (${analysis.cpu.cpuCount} CPUs)`,
        impact: 'CPU saturation affecting performance'
      });
    }

    // High error rate
    if (analysis.errors.errorRate > 5) {
      bottlenecks.push({
        type: 'high_error_rate',
        severity: 'critical',
        description: `Error rate: ${analysis.errors.errorRate.toFixed(2)}%`,
        impact: 'Service reliability issues'
      });
    }

    // Low RPS with high latency (efficiency issue)
    if (analysis.requests.rps < 10 && analysis.requests.avgDuration > 200) {
      bottlenecks.push({
        type: 'low_efficiency',
        severity: 'medium',
        description: `Low throughput (${analysis.requests.rps.toFixed(2)} RPS) with high latency`,
        impact: 'Poor resource utilization'
      });
    }

    return bottlenecks;
  }

  /**
   * Generate performance recommendations
   */
  generateRecommendations(analysis) {
    const recommendations = [];

    // Caching recommendations
    if (analysis.requests.avgDuration > 100) {
      recommendations.push({
        category: 'caching',
        priority: 'high',
        description: 'Implement Redis caching for frequently accessed data',
        expectedImpact: '30-50% latency reduction'
      });
    }

    // Compression recommendations
    if (analysis.requests.endpoints) {
      const largeResponses = Object.entries(analysis.requests.endpoints)
        .filter(([endpoint, stats]) => stats.avgDuration > 200);
      
      if (largeResponses.length > 0) {
        recommendations.push({
          category: 'compression',
          priority: 'medium',
          description: 'Enable response compression for large payloads',
          expectedImpact: '20-40% faster response times'
        });
      }
    }

    // Connection pooling
    if (analysis.requests.rps > 50) {
      recommendations.push({
        category: 'connection_pooling',
        priority: 'high',
        description: 'Implement database connection pooling',
        expectedImpact: '15-25% performance improvement'
      });
    }

    // Memory optimization
    if (analysis.memory.memoryTrend === 'increasing') {
      recommendations.push({
        category: 'memory_optimization',
        priority: 'medium',
        description: 'Optimize memory usage and implement garbage collection tuning',
        expectedImpact: 'Prevent memory leaks and improve stability'
      });
    }

    // Monitoring
    recommendations.push({
      category: 'monitoring',
      priority: 'high',
      description: 'Implement comprehensive monitoring with Prometheus and Grafana',
      expectedImpact: 'Better visibility and proactive issue detection'
    });

    return recommendations;
  }

  /**
   * Calculate percentile
   */
  percentile(arr, p) {
    if (arr.length === 0) return 0;
    
    const sorted = [...arr].sort((a, b) => a - b);
    const index = Math.ceil((p / 100) * sorted.length) - 1;
    return sorted[index];
  }

  /**
   * Calculate trend (increasing, decreasing, stable)
   */
  calculateTrend(values) {
    if (values.length < 2) return 'stable';
    
    const firstHalf = values.slice(0, Math.floor(values.length / 2));
    const secondHalf = values.slice(Math.floor(values.length / 2));
    
    const firstAvg = firstHalf.reduce((a, b) => a + b, 0) / firstHalf.length;
    const secondAvg = secondHalf.reduce((a, b) => a + b, 0) / secondHalf.length;
    
    const change = ((secondAvg - firstAvg) / firstAvg) * 100;
    
    if (change > 10) return 'increasing';
    if (change < -10) return 'decreasing';
    return 'stable';
  }

  /**
   * Generate performance report
   */
  generateReport() {
    const analysis = this.analyzePerformance();
    const report = {
      ...analysis,
      recommendations_summary: {
        high_priority: analysis.recommendations.filter(r => r.priority === 'high').length,
        medium_priority: analysis.recommendations.filter(r => r.priority === 'medium').length,
        total_bottlenecks: analysis.bottlenecks.length
      }
    };

    // Save report to file
    const reportsDir = path.join(__dirname, '../../reports');
    if (!fs.existsSync(reportsDir)) {
      fs.mkdirSync(reportsDir, { recursive: true });
    }

    const reportPath = path.join(reportsDir, 'performance-analysis.json');
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    console.log(`📊 Performance report saved: ${reportPath}`);
    return report;
  }

  /**
   * Get current performance stats
   */
  getStats() {
    return {
      enabled: this.enabled,
      uptime: Date.now() - this.startTime,
      metrics_collected: {
        requests: this.metrics.requests.length,
        memory_samples: this.metrics.memory.length,
        cpu_samples: this.metrics.cpu.length,
        errors: this.metrics.errors.length
      },
      current_performance: {
        memory: process.memoryUsage(),
        cpu: process.cpuUsage(),
        load: os.loadavg()
      }
    };
  }
}

// Export singleton instance
const performanceAnalyzer = new PerformanceAnalyzer();

// Graceful shutdown
process.on('SIGINT', () => {
  performanceAnalyzer.stopMonitoring();
  process.exit(0);
});

process.on('SIGTERM', () => {
  performanceAnalyzer.stopMonitoring();
  process.exit(0);
});

module.exports = {
  PerformanceAnalyzer,
  performanceAnalyzer
};