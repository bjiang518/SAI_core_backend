/**
 * Service Authentication Middleware
 * JWT-based authentication for service-to-service communication
 */

const jwt = require('jsonwebtoken');
const crypto = require('crypto');

class ServiceAuthenticator {
  constructor() {
    this.serviceSecret = process.env.SERVICE_JWT_SECRET || this.generateDefaultSecret();
    this.serviceName = process.env.SERVICE_NAME || 'api-gateway';
    this.tokenExpiry = process.env.SERVICE_TOKEN_EXPIRY || '15m';
    this.enabled = process.env.SERVICE_AUTH_ENABLED !== 'false';
    
    // Cache for active tokens to avoid regenerating
    this.tokenCache = new Map();
    this.cacheTimeout = 5 * 60 * 1000; // 5 minutes
    
    console.log(`🔐 Service Authentication: ${this.enabled ? 'ENABLED' : 'DISABLED'}`);
  }

  generateDefaultSecret() {
    // Generate a secure random secret for development
    const secret = crypto.randomBytes(64).toString('hex');
    console.warn('⚠️ Using generated JWT secret. Set SERVICE_JWT_SECRET in production!');
    return secret;
  }

  /**
   * Generate a service JWT token for API calls
   */
  generateServiceToken(targetService, payload = {}) {
    if (!this.enabled) {
      return null;
    }

    const cacheKey = `${targetService}:${JSON.stringify(payload)}`;
    const cached = this.tokenCache.get(cacheKey);
    
    // Return cached token if still valid
    if (cached && Date.now() < cached.expires) {
      return cached.token;
    }

    const tokenPayload = {
      iss: this.serviceName, // Issuer
      aud: targetService,     // Audience
      sub: 'service-auth',    // Subject
      iat: Math.floor(Date.now() / 1000),
      jti: crypto.randomUUID(), // Unique token ID
      ...payload
    };

    const token = jwt.sign(tokenPayload, this.serviceSecret, {
      expiresIn: this.tokenExpiry,
      algorithm: 'HS256'
    });

    // Cache the token
    const expiresAt = Date.now() + (this.getExpirySeconds() * 1000) - 30000; // 30s buffer
    this.tokenCache.set(cacheKey, {
      token,
      expires: expiresAt
    });

    return token;
  }

  /**
   * Validate incoming service JWT token
   */
  validateServiceToken(token, expectedAudience = null) {
    if (!this.enabled) {
      return { valid: true, bypass: true };
    }

    if (!token) {
      return { 
        valid: false, 
        error: 'No service token provided',
        code: 'MISSING_TOKEN'
      };
    }

    try {
      const decoded = jwt.verify(token, this.serviceSecret, {
        algorithms: ['HS256']
      });

      // Validate audience if specified
      if (expectedAudience && decoded.aud !== expectedAudience) {
        return {
          valid: false,
          error: `Invalid token audience. Expected: ${expectedAudience}, Got: ${decoded.aud}`,
          code: 'INVALID_AUDIENCE'
        };
      }

      // Validate issuer is from known services
      const validIssuers = ['api-gateway', 'ai-engine', 'vision-service'];
      if (!validIssuers.includes(decoded.iss)) {
        return {
          valid: false,
          error: `Unknown service issuer: ${decoded.iss}`,
          code: 'UNKNOWN_ISSUER'
        };
      }

      return {
        valid: true,
        payload: decoded,
        issuer: decoded.iss,
        audience: decoded.aud
      };

    } catch (error) {
      let errorCode = 'TOKEN_VALIDATION_ERROR';
      let errorMessage = error.message;

      if (error.name === 'TokenExpiredError') {
        errorCode = 'TOKEN_EXPIRED';
        errorMessage = 'Service token has expired';
      } else if (error.name === 'JsonWebTokenError') {
        errorCode = 'INVALID_TOKEN';
        errorMessage = 'Invalid service token format';
      }

      return {
        valid: false,
        error: errorMessage,
        code: errorCode
      };
    }
  }

  /**
   * Middleware for validating incoming service requests
   */
  createValidationMiddleware(expectedAudience = null) {
    return async (request, reply) => {
      if (!this.enabled) {
        // Add bypass flag for logging
        request.serviceAuth = { bypass: true };
        return;
      }

      const token = this.extractToken(request);
      const validation = this.validateServiceToken(token, expectedAudience);

      if (!validation.valid) {
        return reply.status(401).send({
          error: 'Service Authentication Failed',
          message: validation.error,
          code: validation.code,
          timestamp: new Date().toISOString()
        });
      }

      // Attach service info to request
      request.serviceAuth = {
        valid: true,
        issuer: validation.issuer,
        audience: validation.audience,
        payload: validation.payload
      };
    };
  }

  /**
   * Extract token from request headers
   */
  extractToken(request) {
    const authHeader = request.headers.authorization;
    
    if (authHeader && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }
    
    // Also check custom service header
    return request.headers['x-service-token'];
  }

  /**
   * Add service authentication headers to outgoing requests
   */
  addServiceHeaders(targetService, existingHeaders = {}) {
    if (!this.enabled) {
      return existingHeaders;
    }

    const token = this.generateServiceToken(targetService);
    
    return {
      ...existingHeaders,
      'Authorization': `Bearer ${token}`,
      'X-Service-Token': token,
      'X-Service-Name': this.serviceName,
      'X-Request-ID': crypto.randomUUID()
    };
  }

  /**
   * Get token expiry in seconds
   */
  getExpirySeconds() {
    const expiry = this.tokenExpiry;
    if (typeof expiry === 'number') return expiry;
    
    // Parse string format like '15m', '1h', '30s'
    const match = expiry.match(/^(\\d+)([smhd])$/);
    if (!match) return 900; // Default 15 minutes
    
    const value = parseInt(match[1]);
    const unit = match[2];
    
    switch (unit) {
      case 's': return value;
      case 'm': return value * 60;
      case 'h': return value * 3600;
      case 'd': return value * 86400;
      default: return 900;
    }
  }

  /**
   * Clear token cache (useful for testing)
   */
  clearTokenCache() {
    this.tokenCache.clear();
  }

  /**
   * Get authentication status
   */
  getStatus() {
    return {
      enabled: this.enabled,
      serviceName: this.serviceName,
      tokenExpiry: this.tokenExpiry,
      cachedTokens: this.tokenCache.size,
      hasSecret: !!this.serviceSecret
    };
  }
}

// Export singleton instance
const serviceAuth = new ServiceAuthenticator();

module.exports = {
  ServiceAuthenticator,
  serviceAuth
};