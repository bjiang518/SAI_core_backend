/**
 * Health Check Middleware
 * Provides health monitoring for the gateway and downstream services
 */

const { services, features } = require('../config/services');
const AIServiceClient = require('../services/ai-client');

class HealthCheckService {
  constructor() {
    this.aiClient = new AIServiceClient();
    this.healthCache = new Map();
    this.cacheTimeout = 30000; // 30 seconds cache
    
    // Start periodic health checks if enabled
    if (features.enableHealthChecks) {
      this.startPeriodicChecks();
    }
  }

  async checkAllServices() {
    const checks = {};
    const overall = {
      status: 'healthy',
      timestamp: new Date().toISOString(),
      services: checks
    };

    // Check AI Engine
    if (services.aiEngine.enabled) {
      const cached = this.getCachedHealth('aiEngine');
      if (cached) {
        checks.aiEngine = cached;
      } else {
        const health = await this.checkAIEngine();
        checks.aiEngine = health;
        this.setCachedHealth('aiEngine', health);
      }

      if (!checks.aiEngine.healthy) {
        overall.status = 'degraded';
      }
    }

    // Add gateway self-check
    checks.gateway = {
      healthy: true,
      status: 'operational',
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      pid: process.pid
    };

    return overall;
  }

  async checkAIEngine() {
    const startTime = Date.now();
    
    try {
      const result = await this.aiClient.healthCheck();
      const responseTime = Date.now() - startTime;
      
      return {
        healthy: result.healthy,
        status: result.healthy ? 'operational' : 'down',
        responseTime,
        lastCheck: new Date().toISOString(),
        details: result.data || result.error
      };
    } catch (error) {
      return {
        healthy: false,
        status: 'down',
        responseTime: Date.now() - startTime,
        lastCheck: new Date().toISOString(),
        error: error.message
      };
    }
  }

  getCachedHealth(service) {
    const cached = this.healthCache.get(service);
    if (cached && Date.now() - cached.timestamp < this.cacheTimeout) {
      return cached.data;
    }
    return null;
  }

  setCachedHealth(service, data) {
    this.healthCache.set(service, {
      data,
      timestamp: Date.now()
    });
  }

  startPeriodicChecks() {
    // Check every 60 seconds
    setInterval(async () => {
      try {
        const health = await this.checkAllServices();
        console.log(`Health check completed: ${health.status}`);
        
        // Log any unhealthy services
        Object.entries(health.services).forEach(([name, status]) => {
          if (!status.healthy) {
            console.warn(`Service ${name} is unhealthy:`, status);
          }
        });
      } catch (error) {
        console.error('Health check failed:', error);
      }
    }, 60000);
  }
}

// Middleware for health check routes
const setupHealthRoutes = (fastify) => {
  const healthService = new HealthCheckService();

  // Basic health endpoint
  fastify.get('/health', async (request, reply) => {
    return { 
      status: 'ok', 
      service: 'api-gateway',
      timestamp: new Date().toISOString()
    };
  });

  // Detailed health check with downstream services
  fastify.get('/health/detailed', async (request, reply) => {
    const health = await healthService.checkAllServices();
    
    const statusCode = health.status === 'healthy' ? 200 : 
                      health.status === 'degraded' ? 207 : 503;
    
    return reply.status(statusCode).send(health);
  });

  // Readiness probe (for Kubernetes)
  fastify.get('/ready', async (request, reply) => {
    const health = await healthService.checkAllServices();
    
    if (health.status === 'healthy') {
      return reply.send({ ready: true });
    } else {
      return reply.status(503).send({ 
        ready: false,
        reason: 'Downstream services unavailable'
      });
    }
  });

  // Liveness probe (for Kubernetes)
  fastify.get('/live', async (request, reply) => {
    return { alive: true, uptime: process.uptime() };
  });

  return healthService;
};

module.exports = {
  HealthCheckService,
  setupHealthRoutes
};