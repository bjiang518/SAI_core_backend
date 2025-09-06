/**
 * Health Routes
 * Dedicated routes for health monitoring and service status
 */

const { setupHealthRoutes } = require('../middleware/health-check');

class HealthRoutes {
  constructor(fastify) {
    this.fastify = fastify;
    this.healthService = setupHealthRoutes(fastify);
    this.setupAdditionalRoutes();
  }

  setupAdditionalRoutes() {
    // Service status endpoint
    this.fastify.get('/status', async (request, reply) => {
      const services = await this.healthService.checkAllServices();
      
      return {
        gateway: {
          version: '1.0.0',
          environment: process.env.NODE_ENV || 'development',
          uptime: process.uptime(),
          timestamp: new Date().toISOString()
        },
        services: services.services
      };
    });

    // Note: /metrics endpoint is handled by Prometheus metrics service
  }
}

module.exports = HealthRoutes;