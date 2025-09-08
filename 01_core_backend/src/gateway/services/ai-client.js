/**
 * AI Service Client for Gateway
 * Handles communication with AI Engine service with service authentication
 */

const axios = require('axios');
const { services } = require('../config/services');
const { serviceAuth } = require('../middleware/service-auth');
const { secretsManager } = require('./secrets-manager');

class AIServiceClient {
  constructor() {
    this.config = services.aiEngine;
    this.client = axios.create({
      baseURL: this.config.url,
      timeout: this.config.timeout,
      headers: {
        'User-Agent': 'StudyAI-Gateway/1.0',
        'X-Service': 'api-gateway'
      }
    });

    // Add request/response interceptors for logging and error handling
    this.setupInterceptors();
  }

  setupInterceptors() {
    // Request interceptor
    this.client.interceptors.request.use(
      (config) => {
        config.metadata = { startTime: Date.now() };
        
        // Debug logging for AI Engine requests
        console.log(`🚀 === AI ENGINE REQUEST DEBUG ===`);
        console.log(`🔗 URL: ${config.baseURL}${config.url}`);
        console.log(`📡 Method: ${config.method.toUpperCase()}`);
        console.log(`📦 Request payload:`, JSON.stringify(config.data, null, 2));
        console.log(`🎯 Headers:`, config.headers);
        console.log(`=====================================`);
        
        return config;
      },
      (error) => Promise.reject(error)
    );

    // Response interceptor  
    this.client.interceptors.response.use(
      (response) => {
        const duration = Date.now() - response.config.metadata.startTime;
        
        console.log(`✅ === AI ENGINE RESPONSE DEBUG ===`);
        console.log(`⏱️ Duration: ${duration}ms`);
        console.log(`📊 Status: ${response.status}`);
        console.log(`📦 Response data:`, JSON.stringify(response.data, null, 2));
        console.log(`=====================================`);
        
        return response;
      },
      (error) => {
        const duration = Date.now() - (error.config?.metadata?.startTime || Date.now());
        console.error(`❌ AI Engine request failed after ${duration}ms:`, error.message);
        return Promise.reject(this.formatError(error));
      }
    );
  }

  formatError(error) {
    if (error.response) {
      // Server responded with error status
      return {
        type: 'SERVICE_ERROR',
        status: error.response.status,
        message: error.response.data?.message || error.message,
        data: error.response.data,
        service: 'ai-engine'
      };
    } else if (error.request) {
      // Request was made but no response received
      return {
        type: 'CONNECTION_ERROR', 
        message: 'AI Engine service unavailable',
        service: 'ai-engine'
      };
    } else {
      // Something else happened
      return {
        type: 'UNKNOWN_ERROR',
        message: error.message,
        service: 'ai-engine'
      };
    }
  }

  async proxyRequest(method, path, data = null, headers = {}) {
    try {
      // Don't add service authentication headers since AI Engine doesn't support them yet
      // const authHeaders = serviceAuth.addServiceHeaders('ai-engine', headers);
      
      // Remove sensitive headers that shouldn't be forwarded
      const cleanHeaders = secretsManager.maskHeaders(headers);
      
      const response = await this.client.request({
        method,
        url: path,
        data,
        headers: {
          ...headers,
          // Remove hop-by-hop headers
          connection: undefined,
          'keep-alive': undefined,
          'proxy-authenticate': undefined,
          'proxy-authorization': undefined,
          te: undefined,
          trailers: undefined,
          'transfer-encoding': undefined,
          upgrade: undefined
        }
      });

      return {
        success: true,
        data: response.data,
        status: response.status,
        headers: response.headers
      };
    } catch (error) {
      return {
        success: false,
        error: error,
        status: error.status || 500
      };
    }
  }

  async healthCheck() {
    try {
      // Always use the regular health endpoint since AI Engine doesn't support authentication yet
      const endpoint = this.config.healthEndpoint;
      const headers = {};
      
      const response = await this.client.get(endpoint, { headers });
      return {
        healthy: true,
        status: response.status,
        data: response.data
      };
    } catch (error) {
      return {
        healthy: false,
        error: error.message
      };
    }
  }
}

module.exports = AIServiceClient;