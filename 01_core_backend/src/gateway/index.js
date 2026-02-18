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
const AIModularRoutes = require('./routes/ai'); // NEW: Modular AI routes with Assistants API
const ArchiveRoutes = require('./routes/archive-routes');
const AuthRoutes = require('./routes/auth-routes');
const ProgressRoutes = require('./routes/progress-routes');
const HealthRoutes = require('./routes/health');
const MusicRoutes = require('./routes/music-routes'); // NEW: Focus music library management
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
const dataRetentionService = require('../services/data-retention-service');  // GDPR/COPPA compliance
const questionCacheService = require('../services/question-cache-service');  // COST OPTIMIZATION: Question caching

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

// Register WebSocket support for Gemini Live API
fastify.register(require('@fastify/websocket'), {
  options: {
    maxPayload: 5 * 1024 * 1024, // 5MB - allow large audio chunks
    verifyClient: false // We handle auth via JWT in route handler
  }
});
fastify.log.info('✅ WebSocket support registered (Gemini Live voice chat)');

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

// Register static file serving for privacy policy and legal documents
const path = require('path');
fastify.register(require('@fastify/static'), {
  root: path.join(__dirname, '../../public'),
  prefix: '/legal/',
  decorateReply: false // Don't override reply.sendFile
});
fastify.log.info('✅ Static file serving registered (privacy policy at /legal/)');

// Register CORS with strict origin whitelist for security
fastify.register(require('@fastify/cors'), {
  origin: [
    'https://sai-backend-production.up.railway.app',
    // Admin Dashboard
    'https://studyai-admin-dashboard-production.up.railway.app',
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
  fastify.log.warn(`⚠️ Route not found: ${request.method} ${request.url}`);

  // In development, show available routes for debugging
  const isDev = process.env.NODE_ENV !== 'production';
  const similarRoutes = [];

  if (isDev) {
    const requestPath = request.url.split('?')[0]; // Remove query params
    fastify.getRoutes().forEach(route => {
      if (route.url && route.url.includes('/auth/consent')) {
        similarRoutes.push(`${route.method} ${route.url}`);
      }
    });
  }

  reply.status(404).send({
    error: 'Not Found',
    message: `Route ${request.method} ${request.url} not found`,
    code: 'ROUTE_NOT_FOUND',
    ...(isDev && similarRoutes.length > 0 && {
      hint: 'Similar routes available',
      similarRoutes
    })
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

  // Data Retention Service management endpoints (GDPR/COPPA compliance)
  fastify.get('/admin/data-retention/status', async (request, reply) => {
    const status = dataRetentionService.getStats();
    return reply.send({
      success: true,
      data: status,
      timestamp: new Date().toISOString()
    });
  });

  fastify.post('/admin/data-retention/trigger', async (request, reply) => {
    try {
      const result = await dataRetentionService.triggerManual();
      return reply.send({
        success: true,
        message: 'Manual data retention policy executed successfully',
        data: result,
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      fastify.log.error('Manual data retention failed:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to trigger data retention policy',
        message: error.message,
        timestamp: new Date().toISOString()
      });
    }
  });

  // User data deletion endpoint (GDPR Article 17 - Right to be forgotten)
  fastify.post('/api/user/delete-my-data', async (request, reply) => {
    try {
      // Get authenticated user ID from token
      const token = request.headers.authorization?.replace('Bearer ', '');
      if (!token) {
        return reply.status(401).send({
          success: false,
          error: 'Authentication required'
        });
      }

      const { db } = require('../utils/railway-database');
      const sessionData = await db.verifySessionToken(token);

      if (!sessionData || !sessionData.user_id) {
        return reply.status(401).send({
          success: false,
          error: 'Invalid or expired token'
        });
      }

      const result = await dataRetentionService.deleteUserData(sessionData.user_id);

      return reply.send({
        success: true,
        message: 'Your data has been marked for deletion',
        details: 'All your data will be permanently deleted in 30 days. You can contact support within 30 days to recover your data.',
        timestamp: new Date().toISOString()
      });

    } catch (error) {
      fastify.log.error('User data deletion failed:', error);
      return reply.status(500).send({
        success: false,
        error: 'Failed to delete user data',
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

  // Debug endpoint to list all routes
  fastify.get('/api/debug/routes', async (request, reply) => {
    const routes = [];
    fastify.getRoutes().forEach(route => {
      routes.push({
        method: route.method,
        url: route.url,
        path: route.path
      });
    });
    return {
      success: true,
      totalRoutes: routes.length,
      routes: routes.sort((a, b) => a.url.localeCompare(b.url))
    };
  });
  fastify.log.info('✅ Debug routes endpoint registered at /api/debug/routes');

  // Progress tracking routes
  new ProgressRoutes(fastify);

  // ========================================================================
  // PASSIVE REPORTS: Weekly/Monthly automated parent reports
  // ========================================================================
  // The passive reports system generates 4 specialized report types:
  // - activity: Learning activity and engagement metrics
  // - areas_of_improvement: Identified knowledge gaps and improvement areas
  // - mental_health: Emotional wellbeing and learning mindset assessment
  // - summary: Executive summary combining all insights
  //
  // Features:
  // - Automated weekly/monthly generation
  // - Batch-based management for easy retrieval
  // - HTML narrative content with data visualizations
  // - Parent-friendly language and actionable recommendations
  // ========================================================================

  // Passive Reports routes - ACTIVE: Scheduled weekly/monthly reports
  fastify.register(require('./routes/passive-reports'));

  // AI Engine proxy routes - NEW: Use modular routes with Assistants API support
  fastify.register(AIModularRoutes);

  // OLD: Commented out for migration to modular routes
  // new AIProxyRoutes(fastify);

  // Archive routes for session management
  new ArchiveRoutes(fastify);

  // Music library routes for focus music
  fastify.register(MusicRoutes);

  // Admin dashboard routes - NEW: Admin panel API endpoints
  fastify.register(require('./routes/admin-routes'));

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

    // Initialize Data Retention Service for GDPR/COPPA compliance
    try {
      await dataRetentionService.initialize();
      fastify.log.info('✅ Data Retention Service initialized successfully (90-day auto-delete)');
    } catch (retentionError) {
      fastify.log.error('❌ Failed to initialize Data Retention Service:', retentionError);
      // Don't crash the server if retention service fails to initialize
    }

    // Initialize Question Cache Service for cost optimization
    try {
      await questionCacheService.initialize();
      fastify.log.info('✅ Question Cache Service initialized successfully (7-day Redis cache)');
    } catch (cacheError) {
      fastify.log.error('❌ Failed to initialize Question Cache Service:', cacheError);
      fastify.log.info('ℹ️ Question caching disabled - will make direct API calls');
      // Don't crash the server if cache service fails to initialize
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

      // Stop data retention service
      try {
        dataRetentionService.stop();
        fastify.log.info('✅ Data Retention Service stopped');
      } catch (e) {
        fastify.log.error('⚠️ Error stopping Data Retention Service:', e);
      }

      // Close question cache service
      try {
        await questionCacheService.close();
        fastify.log.info('✅ Question Cache Service closed');
      } catch (e) {
        fastify.log.error('⚠️ Error closing Question Cache Service:', e);
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