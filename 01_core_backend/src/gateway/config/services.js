/**
 * Service Configuration for API Gateway
 * Centralized configuration for all downstream services
 */

const services = {
  aiEngine: {
    name: 'AI Engine',
    url: process.env.AI_ENGINE_URL || 'http://localhost:8000',
    timeout: parseInt(process.env.AI_ENGINE_TIMEOUT) || 180000, // 3 minutes for complex homework with 10+ questions
    retries: parseInt(process.env.AI_ENGINE_RETRIES) || 2, // Reduce retries to avoid cascading delays
    healthEndpoint: '/health',
    enabled: process.env.AI_ENGINE_ENABLED !== 'false'
  },
  // Future services can be added here
  // visionService: {
  //   name: 'Vision Service',
  //   url: process.env.VISION_SERVICE_URL || 'http://localhost:8001',
  //   timeout: 15000,
  //   retries: 2,
  //   healthEndpoint: '/health',
  //   enabled: process.env.VISION_SERVICE_ENABLED !== 'false'
  // }
};

// Feature flags for gateway functionality
const features = {
  useGateway: process.env.USE_API_GATEWAY !== 'false',
  enableHealthChecks: process.env.ENABLE_HEALTH_CHECKS !== 'false',
  enableMetrics: process.env.ENABLE_METRICS !== 'false',
  enableLogging: process.env.ENABLE_GATEWAY_LOGGING !== 'false'
};

module.exports = {
  services,
  features
};