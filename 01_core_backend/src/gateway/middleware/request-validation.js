/**
 * Request Validation Middleware
 * Validates incoming requests using Joi schemas
 */

const Joi = require('joi');
const schemas = require('../schemas/validation-schemas');

class RequestValidator {
  constructor() {
    this.enabled = process.env.REQUEST_VALIDATION_ENABLED !== 'false';
    this.strictMode = process.env.VALIDATION_STRICT_MODE === 'true';
    
    console.log(`✅ Request Validation: ${this.enabled ? 'ENABLED' : 'DISABLED'}`);
    if (this.strictMode) {
      console.log('🔒 Strict validation mode enabled');
    }
  }

  /**
   * Create validation middleware for a specific schema
   */
  createMiddleware(schemaConfig) {
    return async (request, reply) => {
      if (!this.enabled) {
        return;
      }

      try {
        // Validate different parts of the request
        const validationResults = {};

        // Validate request body
        if (schemaConfig.body) {
          const schema = this.getSchema(schemaConfig.body);
          const { error, value } = schema.validate(request.body, {
            abortEarly: false,
            stripUnknown: !this.strictMode,
            allowUnknown: !this.strictMode
          });

          if (error) {
            return this.handleValidationError(reply, 'body', error);
          }

          validationResults.body = value;
          request.body = value; // Use validated/sanitized data
        }

        // Validate query parameters
        if (schemaConfig.query) {
          const schema = this.getSchema(schemaConfig.query);
          const { error, value } = schema.validate(request.query, {
            abortEarly: false,
            stripUnknown: true
          });

          if (error) {
            return this.handleValidationError(reply, 'query', error);
          }

          validationResults.query = value;
          request.query = value;
        }

        // Validate URL parameters
        if (schemaConfig.params) {
          const schema = this.getSchema(schemaConfig.params);
          const { error, value } = schema.validate(request.params, {
            abortEarly: false
          });

          if (error) {
            return this.handleValidationError(reply, 'params', error);
          }

          validationResults.params = value;
          request.params = value;
        }

        // Validate headers
        if (schemaConfig.headers) {
          const schema = this.getSchema(schemaConfig.headers);
          const { error, value } = schema.validate(request.headers, {
            abortEarly: false,
            stripUnknown: true,
            allowUnknown: true // Headers often have many unknown fields
          });

          if (error) {
            return this.handleValidationError(reply, 'headers', error);
          }

          validationResults.headers = value;
        }

        // Attach validation results to request
        request.validation = {
          passed: true,
          results: validationResults,
          timestamp: Date.now()
        };

      } catch (error) {
        console.error('Validation middleware error:', error);
        
        return reply.status(500).send({
          error: 'Validation Configuration Error',
          message: 'Request validation failed due to configuration issue',
          code: 'VALIDATION_CONFIG_ERROR'
        });
      }
    };
  }

  /**
   * Get schema by string reference or return if already a Joi schema
   */
  getSchema(schemaRef) {
    if (Joi.isSchema(schemaRef)) {
      return schemaRef;
    }

    if (typeof schemaRef === 'string') {
      // Parse string format like 'ai.processQuestion' or 'auth.login'
      const [category, schemaName] = schemaRef.split('.');
      return schemas.getSchema(category, schemaName);
    }

    throw new Error('Invalid schema reference');
  }

  /**
   * Handle validation errors
   */
  handleValidationError(reply, section, error) {
    const details = error.details.map(detail => ({
      field: detail.path.join('.'),
      message: detail.message,
      value: detail.context?.value,
      type: detail.type
    }));

    return reply.status(400).send({
      error: 'Validation Error',
      message: `Invalid ${section} data`,
      code: 'VALIDATION_FAILED',
      section,
      details,
      timestamp: new Date().toISOString()
    });
  }

  /**
   * Validate data manually (for testing or custom validation)
   */
  validate(data, schemaRef, options = {}) {
    const schema = this.getSchema(schemaRef);
    
    const defaultOptions = {
      abortEarly: false,
      stripUnknown: !this.strictMode,
      allowUnknown: !this.strictMode
    };

    return schema.validate(data, { ...defaultOptions, ...options });
  }

  /**
   * Sanitize data (remove dangerous characters)
   */
  sanitizeData(data) {
    if (typeof data === 'string') {
      return data
        .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '') // Remove script tags
        .replace(/javascript:/gi, '') // Remove javascript: URLs
        .replace(/on\w+\s*=/gi, '') // Remove event handlers
        .trim();
    }

    if (Array.isArray(data)) {
      return data.map(item => this.sanitizeData(item));
    }

    if (data && typeof data === 'object') {
      const sanitized = {};
      for (const [key, value] of Object.entries(data)) {
        sanitized[key] = this.sanitizeData(value);
      }
      return sanitized;
    }

    return data;
  }

  /**
   * Content-Type validation middleware
   */
  validateContentType(expectedTypes = ['application/json']) {
    return async (request, reply) => {
      if (!this.enabled) {
        return;
      }

      // Skip validation for GET requests
      if (request.method === 'GET') {
        return;
      }

      const contentType = request.headers['content-type'];
      
      if (!contentType) {
        return reply.status(400).send({
          error: 'Missing Content-Type',
          message: 'Content-Type header is required',
          code: 'MISSING_CONTENT_TYPE',
          expectedTypes
        });
      }

      // Check if content type matches expected types
      const isValidType = expectedTypes.some(type => 
        contentType.toLowerCase().includes(type.toLowerCase())
      );

      if (!isValidType) {
        return reply.status(415).send({
          error: 'Unsupported Media Type',
          message: `Content-Type '${contentType}' is not supported`,
          code: 'UNSUPPORTED_CONTENT_TYPE',
          expectedTypes,
          receivedType: contentType
        });
      }
    };
  }

  /**
   * Rate limiting based on validated data
   */
  createRateLimitMiddleware(options = {}) {
    const limits = new Map();
    const defaultOptions = {
      windowMs: 15 * 60 * 1000, // 15 minutes
      maxRequests: 100,
      keyGenerator: (request) => request.ip
    };

    const config = { ...defaultOptions, ...options };

    return async (request, reply) => {
      if (!this.enabled) {
        return;
      }

      const key = config.keyGenerator(request);
      const now = Date.now();
      const windowStart = now - config.windowMs;

      // Get or create limit data for this key
      let limitData = limits.get(key);
      if (!limitData) {
        limitData = { requests: [], firstRequest: now };
        limits.set(key, limitData);
      }

      // Remove old requests outside the window
      limitData.requests = limitData.requests.filter(time => time > windowStart);

      // Check if limit exceeded
      if (limitData.requests.length >= config.maxRequests) {
        const resetTime = new Date(limitData.requests[0] + config.windowMs);
        
        return reply.status(429).send({
          error: 'Rate Limit Exceeded',
          message: `Too many requests. Limit: ${config.maxRequests} per ${config.windowMs / 1000}s`,
          code: 'RATE_LIMIT_EXCEEDED',
          limit: config.maxRequests,
          remaining: 0,
          resetTime: resetTime.toISOString()
        });
      }

      // Add current request
      limitData.requests.push(now);

      // Add rate limit headers
      reply.header('X-RateLimit-Limit', config.maxRequests);
      reply.header('X-RateLimit-Remaining', config.maxRequests - limitData.requests.length);
      reply.header('X-RateLimit-Reset', new Date(now + config.windowMs).toISOString());
    };
  }

  /**
   * Get validation status
   */
  getStatus() {
    return {
      enabled: this.enabled,
      strictMode: this.strictMode,
      availableSchemas: {
        ai: Object.keys(schemas.ai),
        auth: Object.keys(schemas.auth),
        upload: Object.keys(schemas.upload),
        params: Object.keys(schemas.params),
        query: Object.keys(schemas.query)
      }
    };
  }
}

// Export singleton instance
const requestValidator = new RequestValidator();

module.exports = {
  RequestValidator,
  requestValidator
};