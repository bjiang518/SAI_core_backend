/**
 * Test Helper for Gateway Tests
 * Provides common test utilities and app building
 */

const Fastify = require('fastify');

// Mock environment for testing
process.env.NODE_ENV = 'test';
process.env.AI_ENGINE_URL = 'http://localhost:8000';
process.env.USE_API_GATEWAY = 'true';
process.env.ENABLE_HEALTH_CHECKS = 'true';
process.env.ENABLE_LOGGING = 'false'; // Reduce noise in tests

// Import the main gateway setup
function build(t) {
  const app = Fastify({
    logger: false // Disable logging in tests
  });

  // Register the same plugins as the main gateway
  app.register(require('@fastify/multipart'), {
    limits: {
      fileSize: 10 * 1024 * 1024
    }
  });

  app.register(require('@fastify/cors'), {
    origin: true,
    credentials: true
  });

  // Import our enhanced components
  const { features } = require('../src/gateway/config/services');
  const AIProxyRoutes = require('../src/gateway/routes/ai-proxy');
  const HealthRoutes = require('../src/gateway/routes/health');

  // Request timing
  app.addHook('onRequest', async (request, reply) => {
    request.startTime = Date.now();
  });

  // Error handler
  app.setErrorHandler((error, request, reply) => {
    reply.status(error.statusCode || 500).send({
      error: 'Internal Server Error',
      message: error.message,
      code: error.code || 'INTERNAL_ERROR'
    });
  });

  // Not found handler
  app.setNotFoundHandler((request, reply) => {
    reply.status(404).send({
      error: 'Not Found',
      message: `Route ${request.method} ${request.url} not found`,
      code: 'ROUTE_NOT_FOUND'
    });
  });

  // Initialize routes
  new HealthRoutes(app);
  new AIProxyRoutes(app);

  // Clean up after test
  t.teardown(() => app.close());

  return app;
}

module.exports = {
  build
};