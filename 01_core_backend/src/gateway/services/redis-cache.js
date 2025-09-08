/**
 * Redis Caching Layer
 * High-performance caching for API responses and frequently accessed data
 */

const redis = require('redis');
const crypto = require('crypto');

class RedisCacheManager {
  constructor() {
    this.client = null;
    this.connected = false;
    this.enabled = process.env.REDIS_CACHING_ENABLED !== 'false';
    this.redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
    this.defaultTTL = parseInt(process.env.CACHE_DEFAULT_TTL) || 300; // 5 minutes
    this.keyPrefix = process.env.CACHE_KEY_PREFIX || 'studyai:';
    
    // Cache statistics
    this.stats = {
      hits: 0,
      misses: 0,
      sets: 0,
      deletes: 0,
      errors: 0
    };
    
    if (this.enabled) {
      this.connect();
    }
  }

  /**
   * Connect to Redis
   */
  async connect() {
    try {
      this.client = redis.createClient({
        url: this.redisUrl,
        retry_strategy: (options) => {
          if (options.error && options.error.code === 'ECONNREFUSED') {
            console.warn('⚠️ Redis connection refused, caching will be disabled');
            this.enabled = false;
            return false; // Don't retry
          }
          if (options.total_retry_time > 1000 * 60 * 60) {
            return new Error('Redis retry time exhausted');
          }
          if (options.attempt > 10) {
            return undefined;
          }
          return Math.min(options.attempt * 100, 3000);
        }
      });

      this.client.on('connect', () => {
        console.log('✅ Redis connected successfully');
        this.connected = true;
      });

      this.client.on('error', (err) => {
        console.error('❌ Redis error:', err.message);
        this.stats.errors++;
        if (err.code === 'ECONNREFUSED') {
          console.warn('⚠️ Redis unavailable, falling back to memory cache');
          this.enabled = false;
        }
      });

      this.client.on('end', () => {
        console.log('⚠️ Redis connection ended');
        this.connected = false;
      });

      await this.client.connect();
      
      // Test connection
      await this.client.ping();
      console.log('🔄 Redis cache manager initialized');
      
    } catch (error) {
      console.error('❌ Failed to connect to Redis:', error.message);
      this.enabled = false;
      this.initializeMemoryCache();
    }
  }

  /**
   * Initialize in-memory cache fallback
   */
  initializeMemoryCache() {
    this.memoryCache = new Map();
    this.memoryTTL = new Map();
    
    // Clean up expired entries every minute
    setInterval(() => {
      const now = Date.now();
      for (const [key, expiry] of this.memoryTTL.entries()) {
        if (now > expiry) {
          this.memoryCache.delete(key);
          this.memoryTTL.delete(key);
        }
      }
    }, 60000);
    
    console.log('💾 Memory cache fallback initialized');
  }

  /**
   * Generate cache key
   */
  generateKey(namespace, identifier) {
    const keyData = typeof identifier === 'object' ? JSON.stringify(identifier) : identifier;
    const hash = crypto.createHash('md5').update(keyData).digest('hex');
    return `${this.keyPrefix}${namespace}:${hash}`;
  }

  /**
   * Get value from cache
   */
  async get(namespace, identifier) {
    if (!this.enabled) return null;

    const key = this.generateKey(namespace, identifier);
    
    try {
      let value;
      
      if (this.connected && this.client) {
        // Use Redis
        value = await this.client.get(key);
      } else {
        // Use memory cache
        const now = Date.now();
        const expiry = this.memoryTTL.get(key);
        if (expiry && now <= expiry) {
          value = this.memoryCache.get(key);
        } else {
          this.memoryCache.delete(key);
          this.memoryTTL.delete(key);
        }
      }
      
      if (value) {
        this.stats.hits++;
        return JSON.parse(value);
      } else {
        this.stats.misses++;
        return null;
      }
    } catch (error) {
      console.error('Cache get error:', error.message);
      this.stats.errors++;
      return null;
    }
  }

  /**
   * Set value in cache
   */
  async set(namespace, identifier, value, ttl = null) {
    if (!this.enabled) return false;

    const key = this.generateKey(namespace, identifier);
    const serializedValue = JSON.stringify(value);
    const expiry = ttl || this.defaultTTL;
    
    try {
      if (this.connected && this.client) {
        // Use Redis
        await this.client.setEx(key, expiry, serializedValue);
      } else {
        // Use memory cache
        this.memoryCache.set(key, serializedValue);
        this.memoryTTL.set(key, Date.now() + (expiry * 1000));
      }
      
      this.stats.sets++;
      return true;
    } catch (error) {
      console.error('Cache set error:', error.message);
      this.stats.errors++;
      return false;
    }
  }

  /**
   * Delete value from cache
   */
  async delete(namespace, identifier) {
    if (!this.enabled) return false;

    const key = this.generateKey(namespace, identifier);
    
    try {
      if (this.connected && this.client) {
        await this.client.del(key);
      } else {
        this.memoryCache.delete(key);
        this.memoryTTL.delete(key);
      }
      
      this.stats.deletes++;
      return true;
    } catch (error) {
      console.error('Cache delete error:', error.message);
      this.stats.errors++;
      return false;
    }
  }

  /**
   * Clear namespace or entire cache
   */
  async clear(namespace = null) {
    if (!this.enabled) return false;

    try {
      if (namespace) {
        const pattern = `${this.keyPrefix}${namespace}:*`;
        
        if (this.connected && this.client) {
          const keys = await this.client.keys(pattern);
          if (keys.length > 0) {
            await this.client.del(keys);
          }
        } else {
          for (const key of this.memoryCache.keys()) {
            if (key.startsWith(`${this.keyPrefix}${namespace}:`)) {
              this.memoryCache.delete(key);
              this.memoryTTL.delete(key);
            }
          }
        }
      } else {
        if (this.connected && this.client) {
          await this.client.flushDb();
        } else {
          this.memoryCache.clear();
          this.memoryTTL.clear();
        }
      }
      
      return true;
    } catch (error) {
      console.error('Cache clear error:', error.message);
      this.stats.errors++;
      return false;
    }
  }

  /**
   * Check if key exists in cache
   */
  async exists(namespace, identifier) {
    if (!this.enabled) return false;

    const key = this.generateKey(namespace, identifier);
    
    try {
      if (this.connected && this.client) {
        return await this.client.exists(key) === 1;
      } else {
        const now = Date.now();
        const expiry = this.memoryTTL.get(key);
        return expiry && now <= expiry;
      }
    } catch (error) {
      console.error('Cache exists error:', error.message);
      this.stats.errors++;
      return false;
    }
  }

  /**
   * Get cache statistics
   */
  getStats() {
    const hitRate = this.stats.hits + this.stats.misses > 0 
      ? (this.stats.hits / (this.stats.hits + this.stats.misses)) * 100 
      : 0;

    return {
      enabled: this.enabled,
      connected: this.connected,
      backend: this.connected ? 'redis' : 'memory',
      stats: {
        ...this.stats,
        hitRate: hitRate.toFixed(2) + '%'
      },
      memory_cache_size: this.memoryCache ? this.memoryCache.size : 0,
      configuration: {
        redis_url: this.redisUrl,
        default_ttl: this.defaultTTL,
        key_prefix: this.keyPrefix
      }
    };
  }

  /**
   * Fastify middleware for response caching
   */
  getCachingMiddleware() {
    return async (request, reply) => {
      if (!this.enabled || request.method !== 'GET') {
        return; // Only cache GET requests
      }

      // Skip caching for specific endpoints
      const skipPatterns = ['/health', '/metrics', '/docs'];
      if (skipPatterns.some(pattern => request.url.includes(pattern))) {
        return;
      }

      const cacheKey = {
        url: request.url,
        method: request.method,
        headers: {
          authorization: request.headers.authorization ? 'present' : 'none'
        }
      };

      // Try to get from cache
      const cached = await this.get('responses', cacheKey);
      if (cached) {
        reply.header('X-Cache', 'HIT');
        reply.header('X-Cache-TTL', cached.ttl);
        return reply.send(cached.data);
      }

      // Hook to cache the response
      // Note: reply.addHook doesn't exist, we'll handle caching differently
      reply.header('X-Cache', 'MISS');
    };
  }

  /**
   * Get TTL based on endpoint type
   */
  getTTLForEndpoint(url) {
    // AI processing results - cache for 1 hour
    if (url.includes('/api/ai/')) {
      return 3600;
    }
    
    // Health checks - cache for 30 seconds
    if (url.includes('/health')) {
      return 30;
    }
    
    // Static content - cache for 24 hours
    if (url.includes('/docs') || url.includes('.js') || url.includes('.css')) {
      return 86400;
    }
    
    // Default TTL
    return this.defaultTTL;
  }

  /**
   * Cache warming for frequently accessed data
   */
  async warmCache() {
    console.log('🔥 Starting cache warming...');
    
    const warmupData = [
      // Health endpoint
      { namespace: 'health', key: 'basic', data: { status: 'ok', warmed: true } },
      
      // Common AI subjects
      { namespace: 'subjects', key: 'list', data: ['mathematics', 'science', 'physics', 'chemistry'] },
      
      // Configuration data
      { namespace: 'config', key: 'features', data: { caching: true, validation: true } }
    ];

    for (const item of warmupData) {
      await this.set(item.namespace, item.key, item.data, 3600); // 1 hour TTL
    }
    
    console.log(`🔥 Cache warmed with ${warmupData.length} items`);
  }

  /**
   * Disconnect from Redis
   */
  async disconnect() {
    if (this.client) {
      await this.client.quit();
      this.connected = false;
      console.log('🔌 Redis disconnected');
    }
  }
}

// Specialized cache managers for different data types
class AIResponseCache extends RedisCacheManager {
  constructor() {
    super();
    this.namespace = 'ai_responses';
    this.defaultTTL = 3600; // 1 hour for AI responses
  }

  async cacheAIResponse(question, subject, response) {
    const key = { question, subject };
    return await this.set(this.namespace, key, response, this.defaultTTL);
  }

  async getAIResponse(question, subject) {
    const key = { question, subject };
    return await this.get(this.namespace, key);
  }
}

class SessionCache extends RedisCacheManager {
  constructor() {
    super();
    this.namespace = 'sessions';
    this.defaultTTL = 1800; // 30 minutes for sessions
  }

  async cacheSession(sessionId, sessionData) {
    return await this.set(this.namespace, sessionId, sessionData, this.defaultTTL);
  }

  async getSession(sessionId) {
    return await this.get(this.namespace, sessionId);
  }

  async invalidateSession(sessionId) {
    return await this.delete(this.namespace, sessionId);
  }
}

// Export instances
const redisCacheManager = new RedisCacheManager();
const aiResponseCache = new AIResponseCache();
const sessionCache = new SessionCache();

// Graceful shutdown
process.on('SIGINT', async () => {
  await redisCacheManager.disconnect();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  await redisCacheManager.disconnect();
  process.exit(0);
});

module.exports = {
  RedisCacheManager,
  AIResponseCache,
  SessionCache,
  redisCacheManager,
  aiResponseCache,
  sessionCache
};