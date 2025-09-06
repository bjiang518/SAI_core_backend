/**
 * Response Standardization System
 * Ensures consistent response formats across all API endpoints
 */

class ResponseFormatter {
  constructor() {
    this.serviceName = process.env.SERVICE_NAME || 'api-gateway';
    this.version = process.env.SERVICE_VERSION || '1.0.0';
    this.environment = process.env.NODE_ENV || 'development';
  }

  /**
   * Create a standardized success response
   */
  success(data, meta = {}) {
    const response = {
      success: true,
      data,
      meta: {
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        version: this.version,
        ...meta
      }
    };

    // Add request tracking if available
    if (meta.request_id) {
      response.meta.request_id = meta.request_id;
    }

    // Add processing time if available
    if (meta.processing_time !== undefined) {
      response.meta.processing_time = meta.processing_time;
    }

    return response;
  }

  /**
   * Create a standardized error response
   */
  error(error, code, statusCode = 500, details = null) {
    const response = {
      success: false,
      error: {
        message: error,
        code,
        status: statusCode,
        timestamp: new Date().toISOString(),
        service: this.serviceName
      }
    };

    // Add error details in development
    if (details && (this.environment === 'development' || this.environment === 'test')) {
      response.error.details = details;
    }

    // Add stack trace in development
    if (details && details.stack && this.environment === 'development') {
      response.error.stack = details.stack;
    }

    return response;
  }

  /**
   * Create a validation error response
   */
  validationError(errors, message = 'Validation failed') {
    return {
      success: false,
      error: {
        message,
        code: 'VALIDATION_FAILED',
        status: 400,
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        validation_errors: errors.map(err => ({
          field: err.field || err.path,
          message: err.message,
          value: err.value,
          constraint: err.constraint || err.type
        }))
      }
    };
  }

  /**
   * Create a paginated response
   */
  paginated(data, pagination) {
    return this.success(data, {
      pagination: {
        page: pagination.page || 1,
        limit: pagination.limit || 10,
        total: pagination.total || data.length,
        pages: Math.ceil((pagination.total || data.length) / (pagination.limit || 10)),
        has_next: pagination.has_next || false,
        has_prev: pagination.has_prev || false
      }
    });
  }

  /**
   * Create an AI processing response
   */
  aiProcessing(result, processingTime, modelInfo = {}) {
    return this.success(result, {
      processing_time: processingTime,
      ai_processing: {
        model: modelInfo.model || 'unknown',
        version: modelInfo.version || 'unknown',
        confidence: result.confidence_score || null,
        tokens_used: modelInfo.tokens_used || null
      }
    });
  }

  /**
   * Create a health check response
   */
  health(status, checks = {}) {
    const response = {
      status,
      service: this.serviceName,
      version: this.version,
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      environment: this.environment
    };

    if (Object.keys(checks).length > 0) {
      response.checks = checks;
    }

    return response;
  }

  /**
   * Create a rate limit error response
   */
  rateLimitError(limit, window, reset) {
    return {
      success: false,
      error: {
        message: `Rate limit exceeded. Maximum ${limit} requests per ${window}`,
        code: 'RATE_LIMIT_EXCEEDED',
        status: 429,
        timestamp: new Date().toISOString(),
        service: this.serviceName,
        rate_limit: {
          limit,
          window,
          reset: new Date(reset).toISOString()
        }
      }
    };
  }

  /**
   * Create an authentication error response
   */
  authError(message = 'Authentication required') {
    return this.error(message, 'AUTHENTICATION_REQUIRED', 401);
  }

  /**
   * Create an authorization error response
   */
  authzError(message = 'Insufficient permissions') {
    return this.error(message, 'AUTHORIZATION_FAILED', 403);
  }

  /**
   * Create a not found error response
   */
  notFound(resource = 'Resource') {
    return this.error(`${resource} not found`, 'NOT_FOUND', 404);
  }

  /**
   * Create a service unavailable response
   */
  serviceUnavailable(service = 'Service', reason = 'temporarily unavailable') {
    return this.error(`${service} is ${reason}`, 'SERVICE_UNAVAILABLE', 503);
  }

  /**
   * Wrap existing response data to match standard format
   */
  wrap(data, isError = false) {
    // Check if already in standard format
    if (data && typeof data === 'object' && 'success' in data) {
      return data;
    }

    // Wrap in standard format
    if (isError) {
      return this.error(
        data.message || 'An error occurred',
        data.code || 'UNKNOWN_ERROR',
        data.status || 500,
        data
      );
    }

    return this.success(data);
  }
}

/**
 * Response formatting middleware for Fastify
 */
class ResponseMiddleware {
  constructor() {
    this.formatter = new ResponseFormatter();
  }

  /**
   * Get Fastify response decoration
   */
  getFastifyPlugin() {
    return async (fastify) => {
      // Decorate reply with formatting methods
      fastify.decorateReply('success', function(data, meta = {}) {
        // Add request ID from request context
        if (this.request && this.request.requestId) {
          meta.request_id = this.request.requestId;
        }
        
        // Add processing time if available
        if (this.request && this.request.startTime) {
          meta.processing_time = Date.now() - this.request.startTime;
        }

        const response = this.formatter.success(data, meta);
        return this.send(response);
      });

      fastify.decorateReply('error', function(error, code, statusCode = 500, details = null) {
        const response = this.formatter.error(error, code, statusCode, details);
        return this.code(statusCode).send(response);
      });

      fastify.decorateReply('validationError', function(errors, message) {
        const response = this.formatter.validationError(errors, message);
        return this.code(400).send(response);
      });

      fastify.decorateReply('aiProcessing', function(result, processingTime, modelInfo) {
        // Add request ID from request context
        const meta = {};
        if (this.request && this.request.requestId) {
          meta.request_id = this.request.requestId;
        }

        const response = this.formatter.aiProcessing(result, processingTime, modelInfo);
        // Merge meta data
        response.meta = { ...response.meta, ...meta };
        return this.send(response);
      });

      fastify.decorateReply('health', function(status, checks) {
        const response = this.formatter.health(status, checks);
        return this.send(response);
      });

      fastify.decorateReply('rateLimitError', function(limit, window, reset) {
        const response = this.formatter.rateLimitError(limit, window, reset);
        return this.code(429).send(response);
      });

      fastify.decorateReply('authError', function(message) {
        const response = this.formatter.authError(message);
        return this.code(401).send(response);
      });

      fastify.decorateReply('authzError', function(message) {
        const response = this.formatter.authzError(message);
        return this.code(403).send(response);
      });

      fastify.decorateReply('notFound', function(resource) {
        const response = this.formatter.notFound(resource);
        return this.code(404).send(response);
      });

      fastify.decorateReply('serviceUnavailable', function(service, reason) {
        const response = this.formatter.serviceUnavailable(service, reason);
        return this.code(503).send(response);
      });

      // Store formatter reference for manual use
      fastify.decorate('responseFormatter', this.formatter);
    };
  }

  /**
   * Response transformation hook
   */
  getTransformHook() {
    return async (request, reply, payload) => {
      // Skip transformation for already formatted responses
      if (payload && typeof payload === 'string') {
        try {
          const parsed = JSON.parse(payload);
          if (parsed && typeof parsed === 'object' && 'success' in parsed) {
            return payload; // Already in standard format
          }
        } catch (error) {
          // Not JSON, continue with transformation
        }
      }

      // Transform response to standard format if needed
      if (reply.statusCode >= 400) {
        // Error response
        const errorData = {
          message: payload?.message || 'An error occurred',
          code: payload?.code || 'UNKNOWN_ERROR',
          status: reply.statusCode,
          details: payload
        };
        const standardResponse = this.formatter.error(
          errorData.message,
          errorData.code,
          errorData.status,
          errorData.details
        );
        return JSON.stringify(standardResponse);
      }

      // Success response
      if (payload && typeof payload === 'object' && !('success' in payload)) {
        const meta = {};
        if (request.requestId) {
          meta.request_id = request.requestId;
        }
        if (request.startTime) {
          meta.processing_time = Date.now() - request.startTime;
        }
        
        const standardResponse = this.formatter.success(payload, meta);
        return JSON.stringify(standardResponse);
      }

      return payload;
    };
  }
}

// Response validation utilities
class ResponseValidator {
  constructor() {
    this.requiredFields = {
      success: ['success', 'data', 'meta'],
      error: ['success', 'error'],
      health: ['status', 'service', 'timestamp']
    };
  }

  /**
   * Validate response format
   */
  validate(response, type = 'success') {
    const required = this.requiredFields[type];
    if (!required) {
      return { valid: false, error: 'Unknown response type' };
    }

    const missing = required.filter(field => !(field in response));
    if (missing.length > 0) {
      return {
        valid: false,
        error: `Missing required fields: ${missing.join(', ')}`
      };
    }

    // Type-specific validation
    switch (type) {
      case 'success':
        return this.validateSuccessResponse(response);
      case 'error':
        return this.validateErrorResponse(response);
      case 'health':
        return this.validateHealthResponse(response);
      default:
        return { valid: true };
    }
  }

  validateSuccessResponse(response) {
    if (typeof response.success !== 'boolean' || !response.success) {
      return { valid: false, error: 'Success field must be true' };
    }

    if (!response.meta || typeof response.meta !== 'object') {
      return { valid: false, error: 'Meta field must be an object' };
    }

    if (!response.meta.timestamp || !response.meta.service) {
      return { valid: false, error: 'Meta must include timestamp and service' };
    }

    return { valid: true };
  }

  validateErrorResponse(response) {
    if (typeof response.success !== 'boolean' || response.success) {
      return { valid: false, error: 'Success field must be false for errors' };
    }

    if (!response.error || typeof response.error !== 'object') {
      return { valid: false, error: 'Error field must be an object' };
    }

    const requiredErrorFields = ['message', 'code', 'status', 'timestamp'];
    const missing = requiredErrorFields.filter(field => !(field in response.error));
    
    if (missing.length > 0) {
      return {
        valid: false,
        error: `Error object missing fields: ${missing.join(', ')}`
      };
    }

    return { valid: true };
  }

  validateHealthResponse(response) {
    const requiredFields = ['status', 'service', 'timestamp'];
    const missing = requiredFields.filter(field => !(field in response));
    
    if (missing.length > 0) {
      return {
        valid: false,
        error: `Health response missing fields: ${missing.join(', ')}`
      };
    }

    const validStatuses = ['ok', 'healthy', 'degraded', 'unhealthy'];
    if (!validStatuses.includes(response.status)) {
      return {
        valid: false,
        error: `Invalid status. Must be one of: ${validStatuses.join(', ')}`
      };
    }

    return { valid: true };
  }
}

// Export all components
const responseFormatter = new ResponseFormatter();
const responseMiddleware = new ResponseMiddleware();
const responseValidator = new ResponseValidator();

module.exports = {
  ResponseFormatter,
  ResponseMiddleware,
  ResponseValidator,
  responseFormatter,
  responseMiddleware,
  responseValidator
};