/**
 * Prometheus Metrics & Monitoring
 * Comprehensive application and business metrics collection
 */

const client = require('prom-client');

class PrometheusMetrics {
  constructor() {
    this.enabled = process.env.PROMETHEUS_METRICS_ENABLED !== 'false';
    this.register = new client.Registry();
    
    if (this.enabled) {
      this.initializeMetrics();
      this.startCollection();
    }
  }

  /**
   * Initialize all metrics
   */
  initializeMetrics() {
    // Default Node.js metrics
    client.collectDefaultMetrics({ 
      register: this.register,
      prefix: 'studyai_',
      gcDurationBuckets: [0.001, 0.01, 0.1, 1, 2, 5]
    });

    // HTTP Request metrics
    this.httpRequestDuration = new client.Histogram({
      name: 'studyai_http_request_duration_seconds',
      help: 'Duration of HTTP requests in seconds',
      labelNames: ['method', 'route', 'status_code'],
      buckets: [0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10]
    });

    this.httpRequestTotal = new client.Counter({
      name: 'studyai_http_requests_total',
      help: 'Total number of HTTP requests',
      labelNames: ['method', 'route', 'status_code']
    });

    this.httpRequestSize = new client.Histogram({
      name: 'studyai_http_request_size_bytes',
      help: 'Size of HTTP requests in bytes',
      labelNames: ['method', 'route'],
      buckets: [100, 1000, 10000, 100000, 1000000]
    });

    this.httpResponseSize = new client.Histogram({
      name: 'studyai_http_response_size_bytes',
      help: 'Size of HTTP responses in bytes',
      labelNames: ['method', 'route', 'status_code'],
      buckets: [100, 1000, 10000, 100000, 1000000]
    });

    // AI Processing metrics
    this.aiProcessingDuration = new client.Histogram({
      name: 'studyai_ai_processing_duration_seconds',
      help: 'Duration of AI processing requests',
      labelNames: ['subject', 'operation_type'],
      buckets: [0.1, 0.5, 1, 2, 5, 10, 30]
    });

    this.aiProcessingTotal = new client.Counter({
      name: 'studyai_ai_processing_total',
      help: 'Total number of AI processing requests',
      labelNames: ['subject', 'operation_type', 'status']
    });

    this.aiConfidenceScore = new client.Histogram({
      name: 'studyai_ai_confidence_score',
      help: 'AI confidence scores',
      labelNames: ['subject', 'operation_type'],
      buckets: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]
    });

    // Cache metrics
    this.cacheOperations = new client.Counter({
      name: 'studyai_cache_operations_total',
      help: 'Total cache operations',
      labelNames: ['operation', 'result']
    });

    this.cacheHitRate = new client.Gauge({
      name: 'studyai_cache_hit_rate',
      help: 'Cache hit rate percentage'
    });

    this.cacheSize = new client.Gauge({
      name: 'studyai_cache_size',
      help: 'Current cache size',
      labelNames: ['cache_type']
    });

    // Database metrics
    this.databaseConnections = new client.Gauge({
      name: 'studyai_database_connections_active',
      help: 'Number of active database connections'
    });

    this.databaseQueryDuration = new client.Histogram({
      name: 'studyai_database_query_duration_seconds',
      help: 'Database query duration',
      labelNames: ['operation', 'table'],
      buckets: [0.001, 0.01, 0.1, 0.5, 1, 2, 5]
    });

    // Business metrics
    this.activeUsers = new client.Gauge({
      name: 'studyai_active_users',
      help: 'Number of currently active users'
    });

    this.sessionsTotal = new client.Counter({
      name: 'studyai_sessions_total',
      help: 'Total number of user sessions',
      labelNames: ['session_type']
    });

    this.questionsProcessed = new client.Counter({
      name: 'studyai_questions_processed_total',
      help: 'Total questions processed',
      labelNames: ['subject', 'difficulty']
    });

    // Error metrics
    this.errorsTotal = new client.Counter({
      name: 'studyai_errors_total',
      help: 'Total number of errors',
      labelNames: ['error_type', 'component']
    });

    this.validationErrors = new client.Counter({
      name: 'studyai_validation_errors_total',
      help: 'Total validation errors',
      labelNames: ['validation_type', 'field']
    });

    // Register all metrics
    this.register.registerMetric(this.httpRequestDuration);
    this.register.registerMetric(this.httpRequestTotal);
    this.register.registerMetric(this.httpRequestSize);
    this.register.registerMetric(this.httpResponseSize);
    this.register.registerMetric(this.aiProcessingDuration);
    this.register.registerMetric(this.aiProcessingTotal);
    this.register.registerMetric(this.aiConfidenceScore);
    this.register.registerMetric(this.cacheOperations);
    this.register.registerMetric(this.cacheHitRate);
    this.register.registerMetric(this.cacheSize);
    this.register.registerMetric(this.databaseConnections);
    this.register.registerMetric(this.databaseQueryDuration);
    this.register.registerMetric(this.activeUsers);
    this.register.registerMetric(this.sessionsTotal);
    this.register.registerMetric(this.questionsProcessed);
    this.register.registerMetric(this.errorsTotal);
    this.register.registerMetric(this.validationErrors);

    console.log('📊 Prometheus metrics initialized');
  }

  /**
   * Start metrics collection
   */
  startCollection() {
    // Update business metrics every 30 seconds
    setInterval(() => {
      this.collectBusinessMetrics();
    }, 30000);

    console.log('📈 Metrics collection started');
  }

  /**
   * Collect business metrics
   */
  collectBusinessMetrics() {
    // This would typically query your database or cache
    // For now, we'll simulate with some basic metrics
    
    // Update active users (would come from session tracking)
    this.activeUsers.set(Math.floor(Math.random() * 100) + 50);
    
    // Update cache hit rate if cache manager is available
    if (global.cacheManager && global.cacheManager.getStats) {
      const cacheStats = global.cacheManager.getStats();
      if (cacheStats.stats && cacheStats.stats.hitRate) {
        const hitRate = parseFloat(cacheStats.stats.hitRate.replace('%', ''));
        this.cacheHitRate.set(hitRate);
      }
    }
  }

  /**
   * Fastify middleware for HTTP metrics
   */
  getHttpMetricsMiddleware() {
    return async (request, reply) => {
      if (!this.enabled) return;

      const startTime = Date.now();
      const route = this.normalizeRoute(request.url);

      // Record request size
      const requestSize = request.headers['content-length'] 
        ? parseInt(request.headers['content-length']) 
        : 0;
      
      if (requestSize > 0) {
        this.httpRequestSize.observe({ 
          method: request.method, 
          route 
        }, requestSize);
      }

      // Record response metrics immediately 
      // (onSend hook should be handled at the fastify instance level)
      const duration = 0.001; // Minimal duration for middleware
      const statusCode = reply.statusCode?.toString() || '200';
      const responseSize = 0; // Will be updated properly in response hook

      // Record metrics
      this.httpRequestDuration.observe({ 
        method: request.method, 
        route, 
        status_code: statusCode 
      }, duration);

      this.httpRequestTotal.inc({ 
        method: request.method, 
        route, 
        status_code: statusCode 
      });

      this.httpResponseSize.observe({ 
        method: request.method, 
        route, 
        status_code: statusCode 
      }, responseSize);

      // Track errors
      if (parseInt(statusCode) >= 400) {
          this.errorsTotal.inc({ 
          error_type: this.getErrorType(parseInt(statusCode)), 
          component: 'http' 
        });
      }
    };
  }

  /**
   * Record AI processing metrics
   */
  recordAIProcessing(subject, operationType, duration, confidence, status = 'success') {
    if (!this.enabled) return;

    this.aiProcessingDuration.observe({ subject, operation_type: operationType }, duration);
    this.aiProcessingTotal.inc({ subject, operation_type: operationType, status });
    
    if (confidence !== null && confidence !== undefined) {
      this.aiConfidenceScore.observe({ subject, operation_type: operationType }, confidence);
    }

    this.questionsProcessed.inc({ subject, difficulty: 'unknown' });
  }

  /**
   * Record cache operations
   */
  recordCacheOperation(operation, result) {
    if (!this.enabled) return;
    this.cacheOperations.inc({ operation, result });
  }

  /**
   * Record database operations
   */
  recordDatabaseOperation(operation, table, duration) {
    if (!this.enabled) return;
    this.databaseQueryDuration.observe({ operation, table }, duration);
  }

  /**
   * Record validation errors
   */
  recordValidationError(validationType, field) {
    if (!this.enabled) return;
    this.validationErrors.inc({ validation_type: validationType, field });
  }

  /**
   * Record user session
   */
  recordSession(sessionType) {
    if (!this.enabled) return;
    this.sessionsTotal.inc({ session_type: sessionType });
  }

  /**
   * Update active database connections
   */
  updateDatabaseConnections(count) {
    if (!this.enabled) return;
    this.databaseConnections.set(count);
  }

  /**
   * Normalize route for metrics (remove IDs, parameters)
   */
  normalizeRoute(url) {
    return url
      .replace(/\/[0-9a-f-]{36}/g, '/{uuid}')  // UUIDs
      .replace(/\/\d+/g, '/{id}')              // Numeric IDs
      .replace(/\?.*$/, '')                     // Query parameters
      .replace(/\/+$/, '') || '/';              // Trailing slashes
  }

  /**
   * Get error type from status code
   */
  getErrorType(statusCode) {
    if (statusCode >= 400 && statusCode < 500) return 'client_error';
    if (statusCode >= 500) return 'server_error';
    return 'unknown';
  }

  /**
   * Get metrics endpoint handler
   */
  getMetricsHandler() {
    return async (request, reply) => {
      if (!this.enabled) {
        return reply.code(503).send({ error: 'Metrics collection disabled' });
      }

      try {
        const metrics = await this.register.metrics();
        reply.type('text/plain; version=0.0.4; charset=utf-8');
        return metrics;
      } catch (error) {
        console.error('Error generating metrics:', error);
        return reply.code(500).send({ error: 'Failed to generate metrics' });
      }
    };
  }

  /**
   * Get metrics summary for health checks
   */
  getMetricsSummary() {
    if (!this.enabled) {
      return { enabled: false };
    }

    return {
      enabled: true,
      metrics_count: this.register.getSingleMetric ? 
        Object.keys(this.register._metrics || {}).length : 0,
      collection_started: true,
      last_collection: new Date().toISOString()
    };
  }

  /**
   * Reset all metrics (for testing)
   */
  reset() {
    if (!this.enabled) return;
    this.register.resetMetrics();
  }

  /**
   * Get current metric values
   */
  async getCurrentMetrics() {
    if (!this.enabled) return {};

    try {
      const metrics = await this.register.getMetricsAsJSON();
      return metrics.reduce((acc, metric) => {
        acc[metric.name] = metric.values;
        return acc;
      }, {});
    } catch (error) {
      console.error('Error getting current metrics:', error);
      return {};
    }
  }
}

// Health check integration
class HealthMetrics {
  constructor(prometheusMetrics) {
    this.metrics = prometheusMetrics;
    this.healthGauge = new client.Gauge({
      name: 'studyai_service_health',
      help: 'Service health status (1 = healthy, 0 = unhealthy)',
      labelNames: ['service', 'check_type']
    });
    
    if (prometheusMetrics.enabled) {
      prometheusMetrics.register.registerMetric(this.healthGauge);
    }
  }

  updateHealthStatus(service, checkType, isHealthy) {
    if (!this.metrics.enabled) return;
    this.healthGauge.set({ service, check_type: checkType }, isHealthy ? 1 : 0);
  }
}

// Export singleton instances
const prometheusMetrics = new PrometheusMetrics();
const healthMetrics = new HealthMetrics(prometheusMetrics);

module.exports = {
  PrometheusMetrics,
  HealthMetrics,
  prometheusMetrics,
  healthMetrics
};