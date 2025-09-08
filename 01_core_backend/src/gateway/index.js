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
  bodyLimit: 15 * 1024 * 1024, // 15MB body limit for large image uploads
  requestTimeout: 120000 // 2 minute timeout for AI processing
});

// Import our enhanced components
const { features } = require('./config/services');
const AIProxyRoutes = require('./routes/ai-proxy');
const ArchiveRoutes = require('./routes/archive-routes');
const AuthRoutes = require('./routes/auth-routes');
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

// Register multipart support for file uploads
fastify.register(require('@fastify/multipart'), {
  limits: {
    fileSize: 15 * 1024 * 1024, // 15MB limit to match bodyLimit
    files: 1,
    fieldNameSize: 100,
    fieldSize: 15 * 1024 * 1024, // Allow large base64 fields
    fields: 10
  }
});

// Register compression for better performance
fastify.register(require('@fastify/compress'), {
  encodings: ['gzip', 'deflate'],
  threshold: 1024 // Only compress responses > 1KB
});

// Register CORS if needed
fastify.register(require('@fastify/cors'), {
  origin: true,
  credentials: true
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

// Add security headers
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
  
  // Documentation server
  const docServer = new DocumentationServer();
  fastify.register(docServer.getFastifyPlugin());
  
  // Health and monitoring routes
  new HealthRoutes(fastify);
  
  // Authentication routes
  new AuthRoutes(fastify);
  
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
    const port = process.env.PORT || 3001;
    const host = process.env.HOST || '127.0.0.1';
    
    await fastify.listen({ 
      port: parseInt(port), 
      host: host 
    });
    
    fastify.log.info(`🚀 API Gateway started on http://${host}:${port}`);
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();