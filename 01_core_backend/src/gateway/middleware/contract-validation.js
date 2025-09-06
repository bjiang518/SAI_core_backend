/**
 * OpenAPI Contract Validation Middleware
 * Validates requests and responses against OpenAPI specifications
 */

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');

class ContractValidator {
  constructor() {
    this.ajv = new Ajv({ 
      allErrors: true, 
      strict: false,
      removeAdditional: false,
      coerceTypes: true
    });
    addFormats(this.ajv);
    
    this.gatewaySpec = null;
    this.aiEngineSpec = null;
    this.validators = new Map();
    this.enabled = process.env.CONTRACT_VALIDATION_ENABLED !== 'false';
    
    this.init();
  }

  /**
   * Initialize OpenAPI specifications and compile validators
   */
  init() {
    try {
      // Load OpenAPI specifications
      this.loadSpecifications();
      
      // Compile validators for all endpoints
      this.compileValidators();
      
      console.log(`📋 Contract Validator initialized with ${this.validators.size} endpoint validators`);
    } catch (error) {
      console.error('Contract Validator initialization failed:', error.message);
      if (this.enabled) {
        console.warn('⚠️ Contract validation disabled due to initialization failure');
        this.enabled = false;
      }
    }
  }

  /**
   * Load OpenAPI specification files
   */
  loadSpecifications() {
    // Try multiple possible paths for the specifications
    const possibleSpecsDirs = [
      path.join(__dirname, '../../docs/api'),           // From src/gateway/middleware/ 
      path.join(__dirname, '../../../docs/api'),        // Alternative path
      path.join(process.cwd(), 'docs/api')              // From project root
    ];
    
    let specsDir = null;
    for (const dir of possibleSpecsDirs) {
      if (fs.existsSync(dir)) {
        specsDir = dir;
        break;
      }
    }
    
    if (!specsDir) {
      console.error('Could not find docs/api directory in any of these locations:');
      possibleSpecsDirs.forEach(dir => console.error(`  - ${dir}`));
      throw new Error('OpenAPI specifications directory not found');
    }
    
    // Load Gateway specification
    const gatewaySpecPath = path.join(specsDir, 'gateway-spec.yml');
    const aiEngineSpecPath = path.join(specsDir, 'ai-engine-spec.yml');
    
    console.log(`Found specifications directory: ${specsDir}`);
    
    if (fs.existsSync(gatewaySpecPath)) {
      const gatewayYaml = fs.readFileSync(gatewaySpecPath, 'utf8');
      this.gatewaySpec = yaml.load(gatewayYaml);
      console.log('✅ Gateway specification loaded');
    } else {
      console.warn(`⚠️ Gateway specification not found: ${gatewaySpecPath}`);
    }
    
    if (fs.existsSync(aiEngineSpecPath)) {
      const aiEngineYaml = fs.readFileSync(aiEngineSpecPath, 'utf8');
      this.aiEngineSpec = yaml.load(aiEngineYaml);
      console.log('✅ AI Engine specification loaded');
    } else {
      console.warn(`⚠️ AI Engine specification not found: ${aiEngineSpecPath}`);
    }
    
    if (!this.gatewaySpec && !this.aiEngineSpec) {
      console.error(`No OpenAPI specifications found in ${specsDir}`);
      console.log('Available files:', fs.readdirSync(specsDir));
      throw new Error('No OpenAPI specifications found');
    }
    
    console.log(`📋 Loaded ${this.gatewaySpec ? 1 : 0} + ${this.aiEngineSpec ? 1 : 0} specifications`);
  }

  /**
   * Compile AJV validators for all endpoints
   */
  compileValidators() {
    // Create a single AJV instance with all schemas
    this.ajv.removeSchema(); // Clear any existing schemas
    
    // Add all schemas from both specs
    const allSchemas = {};
    
    if (this.gatewaySpec && this.gatewaySpec.components && this.gatewaySpec.components.schemas) {
      Object.assign(allSchemas, this.gatewaySpec.components.schemas);
    }
    
    if (this.aiEngineSpec && this.aiEngineSpec.components && this.aiEngineSpec.components.schemas) {
      // Merge AI Engine schemas, but rename duplicates
      Object.entries(this.aiEngineSpec.components.schemas).forEach(([name, schema]) => {
        if (allSchemas[name]) {
          // Use AI Engine version for duplicates as it might be more specific
          allSchemas[`AI_${name}`] = schema;
        } else {
          allSchemas[name] = schema;
        }
      });
    }
    
    // Add all schemas to AJV
    Object.entries(allSchemas).forEach(([name, schema]) => {
      const schemaId = `#/components/schemas/${name}`;
      try {
        this.ajv.addSchema(schema, schemaId);
      } catch (error) {
        console.warn(`⚠️ Failed to add schema ${name}:`, error.message);
      }
    });
    
    // Now compile validators for both specs
    if (this.gatewaySpec) {
      this.compileSpecValidators('gateway', this.gatewaySpec);
    }
    
    if (this.aiEngineSpec) {
      this.compileSpecValidators('ai-engine', this.aiEngineSpec);
    }
  }

  /**
   * Compile validators for a specific OpenAPI specification
   */
  compileSpecValidators(serviceName, spec) {
    // Don't add schemas here anymore - they're already added in compileValidators()
    
    // Compile validators for each path and method
    if (spec.paths) {
      Object.entries(spec.paths).forEach(([path, pathItem]) => {
        Object.entries(pathItem).forEach(([method, operation]) => {
          if (method === 'parameters') return; // Skip path-level parameters
          
          const validatorKey = `${serviceName}:${method.toUpperCase()}:${path}`;
          
          // Request body validator
          if (operation.requestBody && operation.requestBody.content) {
            const contentType = 'application/json';
            const content = operation.requestBody.content[contentType];
            if (content && content.schema) {
              try {
                const requestValidator = this.ajv.compile(content.schema);
                this.validators.set(`${validatorKey}:request`, requestValidator);
              } catch (error) {
                console.warn(`⚠️ Failed to compile request validator for ${validatorKey}:`, error.message);
              }
            }
          }
          
          // Response validators
          if (operation.responses) {
            Object.entries(operation.responses).forEach(([statusCode, response]) => {
              let responseSchema = null;
              
              // Handle direct response or reference to components/responses
              if (response.$ref) {
                // Handle $ref to components/responses
                const refPath = response.$ref.replace('#/', '').split('/');
                if (refPath[0] === 'components' && refPath[1] === 'responses') {
                  const responseName = refPath[2];
                  const referencedResponse = spec.components?.responses?.[responseName];
                  if (referencedResponse && referencedResponse.content && referencedResponse.content['application/json']) {
                    responseSchema = referencedResponse.content['application/json'].schema;
                  }
                }
              } else if (response.content && response.content['application/json']) {
                responseSchema = response.content['application/json'].schema;
              }
              
              if (responseSchema) {
                try {
                  const responseValidator = this.ajv.compile(responseSchema);
                  this.validators.set(`${validatorKey}:response:${statusCode}`, responseValidator);
                } catch (error) {
                  console.warn(`⚠️ Failed to compile response validator for ${validatorKey}:${statusCode}:`, error.message);
                }
              }
            });
          }
        });
      });
    }
  }

  /**
   * Fastify middleware for request validation
   */
  getRequestValidationMiddleware() {
    return async (request, reply) => {
      if (!this.enabled) return;

      try {
        const serviceName = this.getServiceName(request);
        const validatorKey = `${serviceName}:${request.method}:${this.normalizePath(request.url)}`;
        const requestValidatorKey = `${validatorKey}:request`;
        
        const validator = this.validators.get(requestValidatorKey);
        if (!validator) {
          // No validator found - endpoint might not be documented
          if (process.env.CONTRACT_VALIDATION_STRICT === 'true') {
            reply.code(501).send({
              error: 'Contract Violation',
              message: `No contract defined for ${request.method} ${request.url}`,
              code: 'NO_CONTRACT_DEFINED',
              timestamp: new Date().toISOString()
            });
            return;
          }
          return; // Allow undocumented endpoints in non-strict mode
        }

        // Validate request body
        if (request.body) {
          const valid = validator(request.body);
          if (!valid) {
            const errors = this.formatValidationErrors(validator.errors);
            reply.code(400).send({
              error: 'Request Validation Failed',
              message: 'Request body does not match API contract',
              code: 'REQUEST_VALIDATION_FAILED',
              timestamp: new Date().toISOString(),
              details: errors
            });
            return;
          }
        }

        // Add validation metadata to request
        request.contractValidation = {
          service: serviceName,
          endpoint: validatorKey,
          requestValidated: true
        };

      } catch (error) {
        console.error('Request validation error:', error);
        if (process.env.CONTRACT_VALIDATION_STRICT === 'true') {
          reply.code(500).send({
            error: 'Validation Error',
            message: 'Internal validation error',
            code: 'VALIDATION_INTERNAL_ERROR',
            timestamp: new Date().toISOString()
          });
        }
      }
    };
  }

  /**
   * Fastify hook for response validation
   */
  getResponseValidationHook() {
    return async (request, reply, payload) => {
      if (!this.enabled || !request.contractValidation) return payload;

      try {
        const { service, endpoint } = request.contractValidation;
        const statusCode = reply.statusCode.toString();
        const responseValidatorKey = `${endpoint}:response:${statusCode}`;
        
        const validator = this.validators.get(responseValidatorKey);
        if (!validator) {
          // Check for default response validator
          const defaultValidatorKey = `${endpoint}:response:default`;
          const defaultValidator = this.validators.get(defaultValidatorKey);
          if (!defaultValidator) {
            if (process.env.CONTRACT_VALIDATION_STRICT === 'true') {
              console.warn(`No response contract defined for ${endpoint} status ${statusCode}`);
            }
            return payload;
          }
        }

        // Parse payload if it's a string
        let responseData = payload;
        if (typeof payload === 'string') {
          try {
            responseData = JSON.parse(payload);
          } catch (error) {
            console.warn('Could not parse response payload for validation:', error.message);
            return payload;
          }
        }

        // Validate response
        const valid = validator(responseData);
        if (!valid) {
          const errors = this.formatValidationErrors(validator.errors);
          console.error(`Response validation failed for ${endpoint}:`, errors);
          
          if (process.env.CONTRACT_VALIDATION_LOG_ONLY !== 'true') {
            // In strict mode, return error response
            reply.code(500).send({
              error: 'Response Validation Failed',
              message: 'Response does not match API contract',
              code: 'RESPONSE_VALIDATION_FAILED',
              timestamp: new Date().toISOString(),
              details: errors
            });
            return;
          }
        }

        // Add validation headers
        reply.header('X-Contract-Validated', 'true');
        reply.header('X-Contract-Service', service);

        return payload;

      } catch (error) {
        console.error('Response validation error:', error);
        return payload;
      }
    };
  }

  /**
   * Validate request manually (for testing)
   */
  validateRequest(method, path, body, serviceName = 'gateway') {
    const validatorKey = `${serviceName}:${method.toUpperCase()}:${path}`;
    const requestValidatorKey = `${validatorKey}:request`;
    
    const validator = this.validators.get(requestValidatorKey);
    if (!validator) {
      return {
        valid: false,
        error: 'No validator found for endpoint',
        code: 'NO_VALIDATOR'
      };
    }

    const valid = validator(body);
    if (!valid) {
      return {
        valid: false,
        errors: this.formatValidationErrors(validator.errors),
        code: 'VALIDATION_FAILED'
      };
    }

    return { valid: true };
  }

  /**
   * Validate response manually (for testing)
   */
  validateResponse(method, path, statusCode, body, serviceName = 'gateway') {
    const validatorKey = `${serviceName}:${method.toUpperCase()}:${path}`;
    const responseValidatorKey = `${validatorKey}:response:${statusCode}`;
    
    const validator = this.validators.get(responseValidatorKey);
    if (!validator) {
      return {
        valid: false,
        error: 'No validator found for response',
        code: 'NO_VALIDATOR'
      };
    }

    const valid = validator(body);
    if (!valid) {
      return {
        valid: false,
        errors: this.formatValidationErrors(validator.errors),
        code: 'VALIDATION_FAILED'
      };
    }

    return { valid: true };
  }

  /**
   * Format AJV validation errors
   */
  formatValidationErrors(errors) {
    return errors.map(error => ({
      field: error.instancePath || error.schemaPath,
      message: error.message,
      value: error.data,
      allowedValues: error.schema,
      constraint: error.keyword
    }));
  }

  /**
   * Determine service name from request
   */
  getServiceName(request) {
    // Check for service header or default to gateway
    return request.headers['x-service-name'] || 'gateway';
  }

  /**
   * Normalize URL path for validator lookup
   */
  normalizePath(url) {
    // Remove query parameters
    const path = url.split('?')[0];
    
    // Replace path parameters with OpenAPI format
    // e.g., /api/sessions/123 -> /api/sessions/{sessionId}
    return path.replace(/\/[0-9a-f-]+$/i, '/{id}')
               .replace(/\/sessions\/[^\/]+/, '/sessions/{sessionId}');
  }

  /**
   * Get validation statistics
   */
  getStats() {
    return {
      enabled: this.enabled,
      validators_count: this.validators.size,
      gateway_spec_loaded: !!this.gatewaySpec,
      ai_engine_spec_loaded: !!this.aiEngineSpec,
      strict_mode: process.env.CONTRACT_VALIDATION_STRICT === 'true',
      log_only_mode: process.env.CONTRACT_VALIDATION_LOG_ONLY === 'true'
    };
  }

  /**
   * Reload specifications and validators
   */
  reload() {
    this.validators.clear();
    this.ajv = new Ajv({ 
      allErrors: true, 
      strict: false,
      removeAdditional: false,
      coerceTypes: true
    });
    addFormats(this.ajv);
    
    this.init();
  }

  /**
   * Enable/disable validation
   */
  setEnabled(enabled) {
    this.enabled = enabled;
    console.log(`Contract validation ${enabled ? 'enabled' : 'disabled'}`);
  }
}

// Export singleton instance
const contractValidator = new ContractValidator();

module.exports = {
  ContractValidator,
  contractValidator
};