/**
 * Secrets Manager
 * Centralized management of API keys, secrets, and sensitive configuration
 */

const crypto = require('crypto');

class SecretsManager {
  constructor() {
    this.secrets = new Map();
    this.encryptionKey = this.getOrCreateEncryptionKey();
    this.initialized = false;
    
    this.init();
  }

  /**
   * Initialize secrets from environment variables
   */
  init() {
    if (this.initialized) return;

    // Core service secrets
    this.setSecret('SERVICE_JWT_SECRET', process.env.SERVICE_JWT_SECRET);
    this.setSecret('USER_JWT_SECRET', process.env.JWT_SECRET || process.env.USER_JWT_SECRET);
    
    // External API keys
    this.setSecret('OPENAI_API_KEY', process.env.OPENAI_API_KEY);
    
    // Database credentials
    this.setSecret('SUPABASE_URL', process.env.SUPABASE_URL);
    this.setSecret('SUPABASE_ANON_KEY', process.env.SUPABASE_ANON_KEY);
    this.setSecret('SUPABASE_SERVICE_KEY', process.env.SUPABASE_SERVICE_KEY);
    
    // Service URLs (not secret but centralized)
    this.setSecret('AI_ENGINE_URL', process.env.AI_ENGINE_URL, false);
    this.setSecret('VISION_SERVICE_URL', process.env.VISION_SERVICE_URL, false);
    
    this.initialized = true;
    
    const secretCount = Array.from(this.secrets.values()).filter(s => s.isSecret).length;
    console.log(`🔑 Secrets Manager initialized with ${secretCount} secrets`);
  }

  /**
   * Get or create encryption key for sensitive data
   */
  getOrCreateEncryptionKey() {
    const envKey = process.env.ENCRYPTION_KEY;
    if (envKey) {
      // Ensure key is 32 bytes for AES-256
      const keyBuffer = Buffer.from(envKey, 'hex');
      if (keyBuffer.length === 32) {
        return keyBuffer;
      } else {
        // Hash the key to get exactly 32 bytes
        return crypto.createHash('sha256').update(envKey).digest();
      }
    }
    
    // Generate key for development
    const key = crypto.randomBytes(32);
    console.warn('⚠️ Using generated encryption key. Set ENCRYPTION_KEY in production!');
    return key;
  }

  /**
   * Set a secret value
   */
  setSecret(name, value, isSecret = true) {
    if (!value) {
      if (isSecret) {
        console.warn(`⚠️ Secret '${name}' is not set`);
      }
      return;
    }

    const secretData = {
      value: isSecret ? this.encrypt(value) : value,
      isSecret,
      setAt: Date.now(),
      accessCount: 0
    };

    this.secrets.set(name, secretData);
  }

  /**
   * Get a secret value
   */
  getSecret(name) {
    const secretData = this.secrets.get(name);
    if (!secretData) {
      return null;
    }

    secretData.accessCount++;
    secretData.lastAccess = Date.now();

    return secretData.isSecret ? this.decrypt(secretData.value) : secretData.value;
  }

  /**
   * Check if a secret exists
   */
  hasSecret(name) {
    return this.secrets.has(name);
  }

  /**
   * Get OpenAI API key with validation
   */
  getOpenAIKey() {
    const key = this.getSecret('OPENAI_API_KEY');
    if (!key) {
      throw new Error('OpenAI API key not configured. Set OPENAI_API_KEY environment variable.');
    }
    return key;
  }

  /**
   * Get service JWT secret
   */
  getServiceJWTSecret() {
    let secret = this.getSecret('SERVICE_JWT_SECRET');
    if (!secret) {
      // Generate a secure secret for development
      secret = crypto.randomBytes(64).toString('hex');
      this.setSecret('SERVICE_JWT_SECRET', secret);
      console.warn('⚠️ Generated SERVICE_JWT_SECRET. Set explicit value in production!');
    }
    return secret;
  }

  /**
   * Get user JWT secret (for client authentication)
   */
  getUserJWTSecret() {
    const secret = this.getSecret('USER_JWT_SECRET');
    if (!secret) {
      throw new Error('User JWT secret not configured. Set JWT_SECRET or USER_JWT_SECRET environment variable.');
    }
    return secret;
  }

  /**
   * Get database configuration
   */
  getDatabaseConfig() {
    return {
      supabaseUrl: this.getSecret('SUPABASE_URL'),
      supabaseAnonKey: this.getSecret('SUPABASE_ANON_KEY'),
      supabaseServiceKey: this.getSecret('SUPABASE_SERVICE_KEY')
    };
  }

  /**
   * Get service URLs
   */
  getServiceUrls() {
    return {
      aiEngine: this.getSecret('AI_ENGINE_URL') || 'http://localhost:8000',
      visionService: this.getSecret('VISION_SERVICE_URL') || 'http://localhost:8001'
    };
  }

  /**
   * Encrypt sensitive data
   */
  encrypt(text) {
    try {
      const iv = crypto.randomBytes(16);
      const cipher = crypto.createCipheriv('aes-256-cbc', this.encryptionKey, iv);
      
      let encrypted = cipher.update(text, 'utf8', 'hex');
      encrypted += cipher.final('hex');
      
      return {
        iv: iv.toString('hex'),
        encrypted,
        algorithm: 'aes-256-cbc'
      };
    } catch (error) {
      console.warn('Encryption failed, storing in plain text:', error.message);
      return {
        plaintext: text,
        encrypted: false
      };
    }
  }

  /**
   * Decrypt sensitive data
   */
  decrypt(encryptedData) {
    try {
      if (encryptedData.encrypted === false) {
        // Plain text fallback
        return encryptedData.plaintext;
      }
      
      const iv = Buffer.from(encryptedData.iv, 'hex');
      const decipher = crypto.createDecipheriv('aes-256-cbc', this.encryptionKey, iv);
      
      let decrypted = decipher.update(encryptedData.encrypted, 'hex', 'utf8');
      decrypted += decipher.final('utf8');
      
      return decrypted;
    } catch (error) {
      console.warn('Decryption failed, returning encrypted data as-is:', error.message);
      return encryptedData.encrypted || encryptedData.plaintext || '';
    }
  }

  /**
   * Rotate a secret (generate new value)
   */
  rotateSecret(name) {
    if (!this.secrets.has(name)) {
      throw new Error(`Secret '${name}' does not exist`);
    }

    const newValue = crypto.randomBytes(32).toString('hex');
    this.setSecret(name, newValue);
    
    console.log(`🔄 Secret '${name}' rotated`);
    return newValue;
  }

  /**
   * Validate all required secrets are present
   */
  validateSecrets() {
    const requiredSecrets = [
      'SERVICE_JWT_SECRET',
      'USER_JWT_SECRET'
    ];

    const missing = requiredSecrets.filter(name => !this.hasSecret(name));
    
    if (missing.length > 0) {
      const warnings = missing.map(name => `⚠️ Required secret '${name}' is missing`);
      console.warn(warnings.join('\\n'));
      return false;
    }

    return true;
  }

  /**
   * Get secrets status (without revealing values)
   */
  getStatus() {
    const secretsList = Array.from(this.secrets.entries()).map(([name, data]) => ({
      name,
      isSecret: data.isSecret,
      setAt: new Date(data.setAt).toISOString(),
      accessCount: data.accessCount,
      lastAccess: data.lastAccess ? new Date(data.lastAccess).toISOString() : null,
      hasValue: !!data.value
    }));

    return {
      initialized: this.initialized,
      secretsCount: secretsList.filter(s => s.isSecret).length,
      configCount: secretsList.filter(s => !s.isSecret).length,
      secrets: secretsList
    };
  }

  /**
   * Clear all secrets (for testing)
   */
  clearSecrets() {
    this.secrets.clear();
    this.initialized = false;
  }

  /**
   * Create masked headers for logging (remove sensitive data)
   */
  maskHeaders(headers) {
    const masked = { ...headers };
    const sensitiveHeaders = [
      'authorization',
      'x-api-key',
      'x-service-token',
      'cookie',
      'x-auth-token'
    ];

    sensitiveHeaders.forEach(header => {
      if (masked[header]) {
        const value = masked[header];
        if (typeof value === 'string' && value.length > 8) {
          masked[header] = value.substring(0, 8) + '*'.repeat(value.length - 8);
        } else {
          masked[header] = '***';
        }
      }
    });

    return masked;
  }
}

// Export singleton instance
const secretsManager = new SecretsManager();

module.exports = {
  SecretsManager,
  secretsManager
};