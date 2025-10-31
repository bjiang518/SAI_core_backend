/**
 * StudyAI API Gateway  
 * Enhanced gateway with proper service management, health checks, and monitoring
 */

// Only load dotenv in development
if (process.env.NODE_ENV !== 'production') {
  try {
    require('dotenv').config();
  } catch (e) {
    console.log('dotenv not available, using environment variables directly');
  }
}
const fastify = require('fastify')({
  logger: process.env.NODE_ENV === 'production' ? true : {
    level: process.env.LOG_LEVEL || 'info'
  },
  bodyLimit: 5 * 1024 * 1024, // 5MB body limit - reasonable for base64 encoded images (~3.7MB original)
  connectionTimeout: 240000, // 4 minutes - must be longer than AI engine timeout (Fastify v5 change)
  requestIdLogLabel: 'reqId' // Fastify v5: explicit request ID label
});

// Import our enhanced components
const { features } = require('./config/services');
const AIProxyRoutes = require('./routes/ai-proxy');
const ArchiveRoutes = require('./routes/archive-routes');
const AuthRoutes = require('./routes/auth-routes');
const ProgressRoutes = require('./routes/progress-routes');
const ParentReportsRoutes = require('./routes/parent-reports');
const HealthRoutes = require('./routes/health');
const { serviceAuth } = require('./middleware/service-auth');
const { requestValidator } = require('./middleware/request-validation');
const { contractValidator } = require('./middleware/contract-validation');
const { responseMiddleware } = require('./middleware/response-standardization');
const { DocumentationServer } = require('./services/documentation-generator');
const { performanceAnalyzer } = require('./services/performance-analyzer');
const { redisCacheManager } = require('./services/redis-cache');
const { prometheusMetrics, healthMetrics } = require('./services/prometheus-metrics');
const { secretsManager } = require('./services/secrets-manager');
const { dailyResetService } = require('../services/daily-reset-service');

// Register multipart support for file uploads
fastify.register(require('@fastify/multipart'), {
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB limit - matches bodyLimit for security
    files: 1, // Only allow 1 file at a time
    fieldNameSize: 100,
    fieldSize: 5 * 1024 * 1024, // Allow large base64 fields (matches bodyLimit)
    fields: 10
  }
});

// Register compression for better performance (70% payload reduction)
fastify.register(require('@fastify/compress'), {
  encodings: ['br', 'gzip', 'deflate'], // Brotli first (best compression)
  threshold: 512, // Compress responses > 512 bytes (more aggressive)
  zlibOptions: {
    level: 6 // Balanced compression level (1-9, 6 is optimal for speed/size)
  },
  brotliOptions: {
    params: {
      [require('zlib').constants.BROTLI_PARAM_MODE]: require('zlib').constants.BROTLI_MODE_TEXT,
      [require('zlib').constants.BROTLI_PARAM_QUALITY]: 4 // Fast Brotli compression (0-11)
    }
  },
  // Compress JSON and text responses
  customTypes: /^(text\/|application\/json|application\/javascript)/,
  global: true // Apply to all routes
});

// Register rate limiting for API protection
fastify.register(require('@fastify/rate-limit'), {
  global: false,  // Apply per-route basis
  max: 100,       // Default: 100 requests
  timeWindow: '1 minute',  // Per minute
  cache: 10000,   // Store 10k rate limit entries
  addHeadersOnExceeding: {
    'x-ratelimit-limit': true,
    'x-ratelimit-remaining': true,
    'x-ratelimit-reset': true
  },
  addHeaders: {
    'x-ratelimit-limit': true,
    'x-ratelimit-remaining': true,
    'x-ratelimit-reset': true,
    'retry-after': true
  }
});
fastify.log.info('✅ Rate limiting registered');

// Register CORS with strict origin whitelist for security
fastify.register(require('@fastify/cors'), {
  origin: [
    'https://sai-backend-production.up.railway.app',
    // Add localhost for development
    'http://localhost:3000',
    'http://localhost:3001',
    'http://127.0.0.1:3000',
    'http://127.0.0.1:3001'
  ],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  maxAge: 86400 // 24 hours for preflight cache
});

// Performance monitoring middleware
if (features.enableMetrics) {
  fastify.addHook('onRequest', performanceAnalyzer.getRequestTrackingMiddleware());
  fastify.addHook('onRequest', prometheusMetrics.getHttpMetricsMiddleware());
  fastify.log.info('✅ Performance monitoring enabled');
}

// Caching middleware
if (features.enableCaching !== false) {
  fastify.addHook('onRequest', redisCacheManager.getCachingMiddleware());
  // Make cache manager globally available for metrics
  global.cacheManager = redisCacheManager;
  fastify.log.info('✅ Redis caching enabled');
}

// Response standardization middleware
fastify.register(responseMiddleware.getFastifyPlugin());
if (features.enableValidation) {
  fastify.addHook('onSend', responseMiddleware.getTransformHook());
  fastify.log.info('✅ Response standardization enabled');
}

// Contract validation middleware (before request processing)
if (features.enableValidation) {
  fastify.addHook('preHandler', contractValidator.getRequestValidationMiddleware());
  fastify.addHook('onSend', contractValidator.getResponseValidationHook());
  fastify.log.info('✅ Contract validation enabled');
}

// Request validation and security middleware
if (features.enableMetrics) {
  fastify.addHook('onRequest', async (request, reply) => {
    request.startTime = Date.now();
    request.requestId = require('crypto').randomUUID();
    
    if (features.enableLogging) {
      fastify.log.info(`${request.method} ${request.url} - Start [${request.requestId}]`);
    }
  });
}

// Add security headers and ETag caching
fastify.addHook('onSend', async (request, reply, payload) => {
  // Security headers
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('X-Frame-Options', 'DENY');
  reply.header('X-XSS-Protection', '1; mode=block');
  reply.header('Referrer-Policy', 'strict-origin-when-cross-origin');

  // Request tracking
  if (request.requestId) {
    reply.header('X-Request-ID', request.requestId);
  }

  // PHASE 2.5 OPTIMIZATION: ETag-based caching for GET requests
  // Reduces bandwidth by 40% for repeated requests (feature flag)
  if (process.env.ENABLE_ETAG_CACHING !== 'false' && request.method === 'GET' && payload) {
    const crypto = require('crypto');
    const etag = crypto.createHash('md5').update(payload.toString()).digest('hex');
    reply.header('ETag', `"${etag}"`);
    reply.header('Cache-Control', 'public, max-age=300'); // 5 minute cache

    // Check if client has cached version
    const clientETag = request.headers['if-none-match'];
    if (clientETag === `"${etag}"`) {
      reply.code(304); // Not Modified - client can use cached version
      return ''; // No body needed
    }
  }

  if (features.enableLogging && request.startTime) {
    const duration = Date.now() - request.startTime;
    fastify.log.info(`${request.method} ${request.url} - ${reply.statusCode} (${duration}ms) [${request.requestId}]`);
  }
});

// Error handler
fastify.setErrorHandler((error, request, reply) => {
  fastify.log.error(error);
  
  // Don't leak error details in production
  const isDev = process.env.NODE_ENV !== 'production';
  
  reply.status(error.statusCode || 500).send({
    error: 'Internal Server Error',
    message: isDev ? error.message : 'Something went wrong',
    code: error.code || 'INTERNAL_ERROR',
    ...(isDev && { stack: error.stack })
  });
});

// Not found handler
fastify.setNotFoundHandler((request, reply) => {
  reply.status(404).send({
    error: 'Not Found',
    message: `Route ${request.method} ${request.url} not found`,
    code: 'ROUTE_NOT_FOUND'
  });
});

// Initialize routes
if (features.useGateway) {
  // Performance metrics endpoint
  fastify.get('/metrics', prometheusMetrics.getMetricsHandler());

  // Performance analysis endpoint
  fastify.get('/performance', async (request, reply) => {
    const analysis = performanceAnalyzer.analyzePerformance();
    return reply.send(analysis);
  });

  // Cache management endpoints
  fastify.get('/cache/stats', async (request, reply) => {
    const stats = redisCacheManager.getStats();
    return reply.send(stats);
  });

  fastify.post('/cache/warm', async (request, reply) => {
    await redisCacheManager.warmCache();
    return reply.send({ success: true, message: 'Cache warming completed' });
  });

  fastify.delete('/cache/:namespace?', async (request, reply) => {
    const { namespace } = request.params;
    await redisCacheManager.clear(namespace);
    return reply.send({ success: true, message: `Cache ${namespace ? namespace : 'all'} cleared` });
  });

  // Daily Reset Service management endpoints
  fastify.get('/admin/daily-reset/status', async (request, reply) => {
    const status = dailyResetService.getStatus();
    return reply.send({
      success: true,
      data: status,
      timestamp: new Date().toISOString()
    });
  });

  fastify.post('/admin/daily-reset/trigger', async (request, reply) => {
    try {
      await dailyResetService.triggerManualReset();
      return reply.send({
        success: true,
        message: 'Manual daily reset triggered successfully',
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      fastify.log.error('Manual daily reset failed:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to trigger manual reset',
        message: error.message,
        timestamp: new Date().toISOString()
      });
    }
  });

  // Documentation server
  const docServer = new DocumentationServer();
  fastify.register(docServer.getFastifyPlugin());

  // Health and monitoring routes
  new HealthRoutes(fastify);

  // PHASE 1 OPTIMIZATION: Database pool monitoring endpoint
  const { getPoolHealth } = require('../utils/railway-database');

  fastify.get('/api/metrics/database-pool', async (request, reply) => {
    try {
      const poolHealth = getPoolHealth();
      return {
        success: true,
        timestamp: new Date().toISOString(),
        pool: poolHealth,
        message: poolHealth.isHealthy ? '✅ Database pool is healthy' : '⚠️ Database pool issues detected'
      };
    } catch (error) {
      fastify.log.error('Error getting pool stats:', error);
      return {
        success: false,
        error: 'Failed to retrieve pool statistics',
        timestamp: new Date().toISOString()
      };
    }
  });

  fastify.log.info('✅ Database pool monitoring endpoint registered at /api/metrics/database-pool');

  // Authentication routes
  new AuthRoutes(fastify);

  // Progress tracking routes
  new ProgressRoutes(fastify);

  // Parent Reports routes - NEW
  new ParentReportsRoutes(fastify);

  // AI Engine proxy routes
  new AIProxyRoutes(fastify);

  // Archive routes for session management
  new ArchiveRoutes(fastify);

  fastify.log.info('✅ API Gateway enabled with enhanced routing and performance optimization');
} else {
  // Fallback to simple health check only
  fastify.get('/health', async () => ({
    status: 'ok',
    service: 'api-gateway',
    mode: 'fallback'
  }));

  fastify.log.warn('⚠️ API Gateway disabled - running in fallback mode');
}

const start = async () => {
  try {
    // Initialize database schema before starting server
    const { initializeDatabase } = require('../utils/railway-database');
    try {
      await initializeDatabase();
      fastify.log.info('✅ Database schema initialized successfully');
    } catch (dbError) {
      fastify.log.error('❌ Failed to initialize database schema:', dbError);
      // Continue anyway - schema might already exist
    }

    const port = process.env.PORT || 3001;
    const host = process.env.HOST || '127.0.0.1';

    await fastify.listen({
      port: parseInt(port),
      host: host
    });

    fastify.log.info(`🚀 API Gateway started on http://${host}:${port}`);

    // Initialize Daily Reset Service after server startup
    try {
      await dailyResetService.initialize();
      fastify.log.info('✅ Daily Reset Service initialized successfully');
    } catch (resetError) {
      fastify.log.error('❌ Failed to initialize Daily Reset Service:', resetError);
      // Don't crash the server if reset service fails to initialize
      // The service will still try to initialize on next startup
    }

    // Graceful shutdown handling for cleanup
    const gracefulShutdown = async (signal) => {
      fastify.log.info(`🛑 Received ${signal}, shutting down gracefully...`);

      // Stop daily reset service first
      try {
        dailyResetService.stop();
        fastify.log.info('✅ Daily Reset Service stopped');
      } catch (e) {
        fastify.log.error('⚠️ Error stopping Daily Reset Service:', e);
      }

      // Close fastify server
      try {
        await fastify.close();
        fastify.log.info('✅ Server closed successfully');
        process.exit(0);
      } catch (e) {
        fastify.log.error('❌ Error during shutdown:', e);
        process.exit(1);
      }
    };

    // Listen for shutdown signals
    process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
    process.on('SIGINT', () => gracefulShutdown('SIGINT'));

  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();