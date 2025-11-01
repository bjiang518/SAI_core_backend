/**
 * Encryption Utility for Sensitive Data
 * Uses AES-256-GCM for authenticated encryption
 * Ensures data confidentiality and integrity
 */

const crypto = require('crypto');

class EncryptionService {
  constructor() {
    // Get encryption key from environment (must be 32 bytes for AES-256)
    const encryptionKey = process.env.ENCRYPTION_KEY;

    if (!encryptionKey) {
      console.warn('⚠️ ENCRYPTION_KEY not set - using default (NOT SECURE FOR PRODUCTION!)');
      // Generate a random key for development (NOT for production!)
      this.masterKey = crypto.randomBytes(32);
    } else {
      // Derive 32-byte key from environment variable using SHA-256
      this.masterKey = crypto.createHash('sha256').update(encryptionKey).digest();
    }

    this.algorithm = 'aes-256-gcm';
    this.ivLength = 16;  // IV length for AES-GCM
    this.authTagLength = 16;  // Authentication tag length
  }

  /**
   * Encrypt text data using AES-256-GCM
   * @param {string} plaintext - Data to encrypt
   * @returns {string} Encrypted data in format: iv:authTag:ciphertext (base64)
   */
  encrypt(plaintext) {
    if (!plaintext || typeof plaintext !== 'string') {
      return null;
    }

    try {
      // Generate random IV (Initialization Vector)
      const iv = crypto.randomBytes(this.ivLength);

      // Create cipher
      const cipher = crypto.createCipheriv(this.algorithm, this.masterKey, iv);

      // Encrypt data
      let encrypted = cipher.update(plaintext, 'utf8', 'base64');
      encrypted += cipher.final('base64');

      // Get authentication tag
      const authTag = cipher.getAuthTag();

      // Return combined format: iv:authTag:ciphertext
      return `${iv.toString('base64')}:${authTag.toString('base64')}:${encrypted}`;

    } catch (error) {
      console.error('❌ Encryption error:', error.message);
      throw new Error('Failed to encrypt data');
    }
  }

  /**
   * Decrypt encrypted text data
   * @param {string} encryptedData - Data in format: iv:authTag:ciphertext
   * @returns {string} Decrypted plaintext
   */
  decrypt(encryptedData) {
    if (!encryptedData || typeof encryptedData !== 'string') {
      return null;
    }

    try {
      // Split into components
      const parts = encryptedData.split(':');

      if (parts.length !== 3) {
        throw new Error('Invalid encrypted data format');
      }

      const iv = Buffer.from(parts[0], 'base64');
      const authTag = Buffer.from(parts[1], 'base64');
      const ciphertext = parts[2];

      // Create decipher
      const decipher = crypto.createDecipheriv(this.algorithm, this.masterKey, iv);
      decipher.setAuthTag(authTag);

      // Decrypt data
      let decrypted = decipher.update(ciphertext, 'base64', 'utf8');
      decrypted += decipher.final('utf8');

      return decrypted;

    } catch (error) {
      console.error('❌ Decryption error:', error.message);
      // Return null on decryption failure (corrupted data or wrong key)
      return null;
    }
  }

  /**
   * Hash sensitive data (one-way, for comparison only)
   * @param {string} data - Data to hash
   * @returns {string} SHA-256 hash (hex)
   */
  hash(data) {
    if (!data || typeof data !== 'string') {
      return null;
    }

    return crypto.createHash('sha256').update(data).digest('hex');
  }

  /**
   * Generate encryption key for environment variable
   * Use this to generate a secure random key for production
   * @returns {string} Random 32-byte key (hex)
   */
  static generateKey() {
    return crypto.randomBytes(32).toString('hex');
  }

  /**
   * Encrypt conversation content (specific method for conversations)
   * @param {string} conversationContent - Conversation JSON or text
   * @returns {object} {encrypted: string, hash: string}
   */
  encryptConversation(conversationContent) {
    if (!conversationContent) {
      return { encrypted: null, hash: null };
    }

    const encrypted = this.encrypt(conversationContent);
    const hash = this.hash(conversationContent);  // For search indexing

    return {
      encrypted,
      hash
    };
  }

  /**
   * Decrypt conversation content
   * @param {string} encryptedContent - Encrypted conversation data
   * @returns {string} Decrypted conversation content
   */
  decryptConversation(encryptedContent) {
    return this.decrypt(encryptedContent);
  }

  /**
   * Check if encryption is properly configured
   * @returns {boolean} True if encryption key is set
   */
  isConfigured() {
    return process.env.ENCRYPTION_KEY !== undefined;
  }

  /**
   * Get encryption status for monitoring
   * @returns {object} Status information
   */
  getStatus() {
    return {
      algorithm: this.algorithm,
      isConfigured: this.isConfigured(),
      keySource: this.isConfigured() ? 'environment' : 'default (insecure)',
      warning: this.isConfigured() ? null : 'ENCRYPTION_KEY environment variable not set - using insecure default key'
    };
  }
}

// Export singleton instance
module.exports = new EncryptionService();
