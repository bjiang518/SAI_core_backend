/**
 * Performance Testing & Load Testing Suite
 * Comprehensive performance validation and benchmarking
 */

const axios = require('axios');
const { performance } = require('perf_hooks');

class PerformanceTestSuite {
  constructor() {
    this.baseUrl = process.env.TEST_BASE_URL || 'http://localhost:3001';
    this.results = {
      loadTests: [],
      stressTests: [],
      enduranceTests: [],
      spikeTets: []
    };
  }

  /**
   * Run all performance tests
   */
  async runAllTests() {
    console.log('🚀 Starting Performance Testing Suite');
    console.log('====================================');

    const results = {
      baseline: await this.runBaselineTests(),
      load: await this.runLoadTests(),
      stress: await this.runStressTests(),
      endurance: await this.runEnduranceTests(),
      spike: await this.runSpikeTests()
    };

    this.generatePerformanceReport(results);
    return results;
  }

  /**
   * Run baseline performance tests
   */
  async runBaselineTests() {
    console.log('📊 Running baseline performance tests...');
    
    const endpoints = [
      { path: '/health', method: 'GET', name: 'Health Check' },
      { path: '/api/ai/process-question', method: 'POST', name: 'AI Processing', 
        data: { question: 'What is 2+2?', subject: 'mathematics', student_id: 'test123' } },
      { path: '/metrics', method: 'GET', name: 'Metrics Endpoint' },
      { path: '/cache/stats', method: 'GET', name: 'Cache Stats' }
    ];

    const results = [];

    for (const endpoint of endpoints) {
      console.log(`  Testing ${endpoint.name}...`);
      
      const measurements = [];
      const errorCount = 0;

      // Run 10 requests per endpoint
      for (let i = 0; i < 10; i++) {
        try {
          const startTime = performance.now();
          const response = await this.makeRequest(endpoint.path, endpoint.method, endpoint.data);
          const endTime = performance.now();
          
          measurements.push({
            duration: endTime - startTime,
            statusCode: response.status,
            responseSize: JSON.stringify(response.data).length
          });
        } catch (error) {
          measurements.push({
            duration: 0,
            statusCode: error.response?.status || 0,
            responseSize: 0,
            error: error.message
          });
        }
      }

      const avgDuration = measurements.reduce((sum, m) => sum + m.duration, 0) / measurements.length;
      const minDuration = Math.min(...measurements.map(m => m.duration));
      const maxDuration = Math.max(...measurements.map(m => m.duration));
      const successRate = measurements.filter(m => m.statusCode >= 200 && m.statusCode < 400).length / measurements.length * 100;

      results.push({
        endpoint: endpoint.name,
        path: endpoint.path,
        avgDuration: Math.round(avgDuration),
        minDuration: Math.round(minDuration),
        maxDuration: Math.round(maxDuration),
        successRate: successRate.toFixed(1) + '%',
        requests: measurements.length
      });
    }

    return results;
  }

  /**
   * Run load tests (normal expected load)
   */
  async runLoadTests() {
    console.log('⚡ Running load tests...');
    
    const testConfigs = [
      { concurrent: 10, duration: 30, name: 'Low Load' },
      { concurrent: 50, duration: 30, name: 'Medium Load' },
      { concurrent: 100, duration: 30, name: 'High Load' }
    ];

    const results = [];

    for (const config of testConfigs) {
      console.log(`  Testing ${config.name}: ${config.concurrent} concurrent users for ${config.duration}s`);
      
      const result = await this.runConcurrentTest(config.concurrent, config.duration);
      result.testName = config.name;
      results.push(result);
    }

    return results;
  }

  /**
   * Run stress tests (beyond normal capacity)
   */
  async runStressTests() {
    console.log('💥 Running stress tests...');
    
    const testConfigs = [
      { concurrent: 200, duration: 20, name: 'Breaking Point Test' },
      { concurrent: 500, duration: 10, name: 'Extreme Stress Test' }
    ];

    const results = [];

    for (const config of testConfigs) {
      console.log(`  Testing ${config.name}: ${config.concurrent} concurrent users for ${config.duration}s`);
      
      const result = await this.runConcurrentTest(config.concurrent, config.duration);
      result.testName = config.name;
      results.push(result);
    }

    return results;
  }

  /**
   * Run endurance tests (sustained load)
   */
  async runEnduranceTests() {
    console.log('🏃 Running endurance tests...');
    
    console.log('  Testing sustained load: 25 concurrent users for 2 minutes');
    const result = await this.runConcurrentTest(25, 120);
    result.testName = 'Endurance Test';
    
    return [result];
  }

  /**
   * Run spike tests (sudden load increases)
   */
  async runSpikeTests() {
    console.log('📈 Running spike tests...');
    
    console.log('  Testing traffic spike: 10 -> 100 -> 10 users');
    
    // Start with low load
    const phase1 = await this.runConcurrentTest(10, 15);
    phase1.phase = 'Normal Load';
    
    // Spike to high load
    const phase2 = await this.runConcurrentTest(100, 15);
    phase2.phase = 'Traffic Spike';
    
    // Return to normal
    const phase3 = await this.runConcurrentTest(10, 15);
    phase3.phase = 'Recovery';
    
    return [phase1, phase2, phase3];
  }

  /**
   * Run concurrent test with specified parameters
   */
  async runConcurrentTest(concurrentUsers, durationSeconds) {
    const startTime = Date.now();
    const endTime = startTime + (durationSeconds * 1000);
    const promises = [];
    const results = [];

    // Start concurrent users
    for (let i = 0; i < concurrentUsers; i++) {
      promises.push(this.simulateUser(endTime, results));
    }

    // Wait for all users to complete
    await Promise.all(promises);

    // Calculate statistics
    const durations = results.map(r => r.duration);
    const errors = results.filter(r => r.error);
    const successCount = results.length - errors.length;

    return {
      concurrentUsers,
      durationSeconds,
      totalRequests: results.length,
      successfulRequests: successCount,
      failedRequests: errors.length,
      successRate: ((successCount / results.length) * 100).toFixed(2) + '%',
      avgResponseTime: Math.round(durations.reduce((a, b) => a + b, 0) / durations.length),
      minResponseTime: Math.min(...durations),
      maxResponseTime: Math.max(...durations),
      p95ResponseTime: this.percentile(durations, 95),
      requestsPerSecond: (results.length / durationSeconds).toFixed(2),
      errorsPerSecond: (errors.length / durationSeconds).toFixed(2)
    };
  }

  /**
   * Simulate a single user making requests
   */
  async simulateUser(endTime, results) {
    const endpoints = [
      { path: '/health', method: 'GET', weight: 20 },
      { path: '/api/ai/process-question', method: 'POST', weight: 60,
        data: () => ({ 
          question: this.generateRandomQuestion(), 
          subject: this.getRandomSubject(), 
          student_id: `user_${Math.floor(Math.random() * 1000)}` 
        }) },
      { path: '/cache/stats', method: 'GET', weight: 10 },
      { path: '/metrics', method: 'GET', weight: 10 }
    ];

    while (Date.now() < endTime) {
      const endpoint = this.selectRandomEndpoint(endpoints);
      
      try {
        const startTime = performance.now();
        const response = await this.makeRequest(
          endpoint.path, 
          endpoint.method, 
          endpoint.data ? endpoint.data() : null
        );
        const endTime = performance.now();

        results.push({
          duration: endTime - startTime,
          statusCode: response.status,
          endpoint: endpoint.path,
          success: response.status >= 200 && response.status < 400
        });
      } catch (error) {
        results.push({
          duration: 0,
          statusCode: error.response?.status || 0,
          endpoint: endpoint.path,
          error: error.message,
          success: false
        });
      }

      // Random delay between requests (100-500ms)
      await this.sleep(100 + Math.random() * 400);
    }
  }

  /**
   * Make HTTP request
   */
  async makeRequest(path, method, data = null) {
    const config = {
      method,
      url: `${this.baseUrl}${path}`,
      timeout: 10000,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'PerformanceTestSuite/1.0'
      }
    };

    if (data && (method === 'POST' || method === 'PUT')) {
      config.data = data;
    }

    return await axios(config);
  }

  /**
   * Select random endpoint based on weights
   */
  selectRandomEndpoint(endpoints) {
    const totalWeight = endpoints.reduce((sum, ep) => sum + ep.weight, 0);
    let random = Math.random() * totalWeight;
    
    for (const endpoint of endpoints) {
      random -= endpoint.weight;
      if (random <= 0) {
        return endpoint;
      }
    }
    
    return endpoints[0];
  }

  /**
   * Generate random question for testing
   */
  generateRandomQuestion() {
    const questions = [
      'What is 2 + 2?',
      'Explain photosynthesis',
      'What is the capital of France?',
      'How do you solve quadratic equations?',
      'What is Newton\'s first law?',
      'Define democracy',
      'What is the derivative of x^2?',
      'Explain DNA structure'
    ];
    
    return questions[Math.floor(Math.random() * questions.length)];
  }

  /**
   * Get random subject
   */
  getRandomSubject() {
    const subjects = ['mathematics', 'science', 'history', 'physics', 'chemistry', 'biology'];
    return subjects[Math.floor(Math.random() * subjects.length)];
  }

  /**
   * Calculate percentile
   */
  percentile(arr, p) {
    if (arr.length === 0) return 0;
    const sorted = [...arr].sort((a, b) => a - b);
    const index = Math.ceil((p / 100) * sorted.length) - 1;
    return Math.round(sorted[index]);
  }

  /**
   * Sleep utility
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Generate comprehensive performance report
   */
  generatePerformanceReport(results) {
    const report = {
      timestamp: new Date().toISOString(),
      testSuite: 'StudyAI Performance Tests',
      summary: this.generateSummary(results),
      results,
      recommendations: this.generateRecommendations(results)
    };

    // Save report
    const fs = require('fs');
    const path = require('path');
    
    const reportsDir = path.join(__dirname, '../../reports');
    if (!fs.existsSync(reportsDir)) {
      fs.mkdirSync(reportsDir, { recursive: true });
    }

    const reportPath = path.join(reportsDir, 'performance-test-results.json');
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    
    console.log('\n📋 Performance Test Summary');
    console.log('===========================');
    console.log(JSON.stringify(report.summary, null, 2));
    console.log(`\n📄 Full report saved: ${reportPath}`);
  }

  /**
   * Generate test summary
   */
  generateSummary(results) {
    const summary = {
      baseline: {
        healthCheck: results.baseline?.find(r => r.endpoint === 'Health Check'),
        aiProcessing: results.baseline?.find(r => r.endpoint === 'AI Processing')
      },
      loadTest: {
        bestPerformance: results.load?.reduce((best, current) => 
          current.avgResponseTime < best.avgResponseTime ? current : best),
        worstPerformance: results.load?.reduce((worst, current) => 
          current.avgResponseTime > worst.avgResponseTime ? current : worst)
      },
      stressTest: {
        breakingPoint: results.stress?.find(r => parseFloat(r.successRate) < 95),
        maxThroughput: results.stress?.reduce((max, current) => 
          parseFloat(current.requestsPerSecond) > parseFloat(max.requestsPerSecond) ? current : max)
      }
    };

    return summary;
  }

  /**
   * Generate performance recommendations
   */
  generateRecommendations(results) {
    const recommendations = [];

    // Check baseline performance
    const aiProcessing = results.baseline?.find(r => r.endpoint === 'AI Processing');
    if (aiProcessing && aiProcessing.avgDuration > 1000) {
      recommendations.push({
        category: 'latency',
        priority: 'high',
        issue: 'AI processing latency is high',
        suggestion: 'Consider implementing request batching or model optimization'
      });
    }

    // Check load test results
    const highLoad = results.load?.find(r => r.testName === 'High Load');
    if (highLoad && parseFloat(highLoad.successRate) < 95) {
      recommendations.push({
        category: 'reliability',
        priority: 'high',
        issue: 'High error rate under load',
        suggestion: 'Implement circuit breakers and better error handling'
      });
    }

    // Check stress test results
    const stressTest = results.stress?.[0];
    if (stressTest && stressTest.avgResponseTime > 2000) {
      recommendations.push({
        category: 'scalability',
        priority: 'medium',
        issue: 'Response time degrades significantly under stress',
        suggestion: 'Consider horizontal scaling or connection pooling'
      });
    }

    // General recommendations
    recommendations.push({
      category: 'monitoring',
      priority: 'medium',
      issue: 'Continuous performance monitoring',
      suggestion: 'Set up automated performance testing in CI/CD pipeline'
    });

    return recommendations;
  }
}

// Quick performance check utility
class QuickPerformanceCheck {
  constructor(baseUrl) {
    this.baseUrl = baseUrl || 'http://localhost:3001';
  }

  async run() {
    console.log('⚡ Quick Performance Check');
    console.log('=========================');

    try {
      // Test health endpoint
      const healthStart = performance.now();
      const healthResponse = await axios.get(`${this.baseUrl}/health`);
      const healthTime = performance.now() - healthStart;

      // Test metrics endpoint
      const metricsStart = performance.now();
      const metricsResponse = await axios.get(`${this.baseUrl}/metrics`);
      const metricsTime = performance.now() - metricsStart;

      // Test cache stats
      const cacheStart = performance.now();
      const cacheResponse = await axios.get(`${this.baseUrl}/cache/stats`);
      const cacheTime = performance.now() - cacheStart;

      const results = {
        health: { responseTime: Math.round(healthTime), status: healthResponse.status },
        metrics: { responseTime: Math.round(metricsTime), status: metricsResponse.status },
        cache: { responseTime: Math.round(cacheTime), status: cacheResponse.status }
      };

      console.log('Results:', JSON.stringify(results, null, 2));
      
      const avgTime = (healthTime + metricsTime + cacheTime) / 3;
      console.log(`Average response time: ${Math.round(avgTime)}ms`);
      
      if (avgTime < 100) {
        console.log('✅ Performance: Excellent');
      } else if (avgTime < 500) {
        console.log('✅ Performance: Good');
      } else {
        console.log('⚠️ Performance: Needs improvement');
      }

      return results;
    } catch (error) {
      console.error('❌ Performance check failed:', error.message);
      return null;
    }
  }
}

// Export components
const performanceTestSuite = new PerformanceTestSuite();

module.exports = {
  PerformanceTestSuite,
  QuickPerformanceCheck,
  performanceTestSuite
};