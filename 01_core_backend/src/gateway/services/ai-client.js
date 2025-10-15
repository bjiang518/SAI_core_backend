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

        // Skip verbose logging for health checks
        const isHealthCheck = config.url && config.url.includes('/health');

        if (!isHealthCheck) {
          // Debug logging for AI Engine requests (sanitized for security)
          console.log(`🚀 AI Engine → ${config.method.toUpperCase()} ${config.url}`);

          // Log payload size for non-health requests
          const payloadSize = config.data ? JSON.stringify(config.data).length : 0;
          if (payloadSize > 0) {
            console.log(`   📦 Payload: ${(payloadSize / 1024).toFixed(2)} KB`);
          }
        }

        return config;
      },
      (error) => Promise.reject(error)
    );

    // Response interceptor
    this.client.interceptors.response.use(
      (response) => {
        const duration = Date.now() - response.config.metadata.startTime;
        const isHealthCheck = response.config.url && response.config.url.includes('/health');

        if (!isHealthCheck) {
          const responseSize = response.data ? JSON.stringify(response.data).length : 0;
          console.log(`✅ AI Engine ← ${response.status} (${duration}ms, ${(responseSize / 1024).toFixed(2)} KB)`);
        }

        return response;
      },
      (error) => {
        const duration = Date.now() - (error.config?.metadata?.startTime || Date.now());
        console.error(`❌ AI Engine error (${duration}ms): ${error.message}`);
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
    const maxRetries = this.config.retries;
    let lastError;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Don't add service authentication headers since AI Engine doesn't support them yet
        // const authHeaders = serviceAuth.addServiceHeaders('ai-engine', headers);

        // Remove sensitive headers that shouldn't be forwarded
        const cleanHeaders = secretsManager.maskHeaders(headers);

        // Increase timeout for retries (give more time on subsequent attempts)
        const attemptTimeout = this.config.timeout * attempt;

        console.log(`🔄 AI Engine request attempt ${attempt}/${maxRetries} (timeout: ${attemptTimeout}ms)`);

        const response = await this.client.request({
          method,
          url: path,
          data,
          timeout: attemptTimeout, // Progressive timeout increase
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

        console.log(`✅ AI Engine request succeeded on attempt ${attempt}`);

        return {
          success: true,
          data: response.data,
          status: response.status,
          headers: response.headers
        };
      } catch (error) {
        lastError = error;
        const isTimeout = error.code === 'ECONNABORTED' || error.message.includes('timeout');
        const isServerError = error.response?.status >= 500;
        const isClientError = error.response?.status >= 400 && error.response?.status < 500;

        console.error(`❌ AI Engine request attempt ${attempt}/${maxRetries} failed: ${error.message}`);

        // Log detailed error info for debugging
        if (error.response) {
          console.error(`   Response status: ${error.response.status}`);
        } else if (error.request) {
          console.error(`   No response received (timeout or connection error)`);
        }

        // Retry logic: retry timeouts, connection errors, and 5xx server errors
        // Don't retry 4xx client errors (bad request, auth, etc.)
        const shouldRetry = isTimeout || isServerError || !error.response;

        if (!shouldRetry && isClientError) {
          console.log(`⚠️ Not retrying - client error (${error.response?.status})`);
          break;
        }

        // Don't retry if this was the last attempt
        if (attempt >= maxRetries) {
          console.error(`❌ AI Engine request failed after ${maxRetries} attempts`);
          break;
        }

        // Exponential backoff: 1s, 2s, 4s...
        const backoffDelay = Math.min(1000 * Math.pow(2, attempt - 1), 5000);
        console.log(`⏳ Waiting ${backoffDelay}ms before retry...`);
        await new Promise(resolve => setTimeout(resolve, backoffDelay));
      }
    }

    return {
      success: false,
      error: lastError,
      status: lastError?.response?.status || 500
    };
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