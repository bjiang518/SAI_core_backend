/**
 * Question Caching Service
 * Caches AI-generated questions to reduce OpenAI API costs
 * Saves ~$300-600/month by avoiding duplicate question generation
 */

const redis = require('redis');
const crypto = require('crypto');

class QuestionCacheService {
  constructor() {
    this.client = null;
    this.isConnected = false;
    this._errorLogged = false;
    this.defaultTTL = 7 * 24 * 60 * 60; // 7 days in seconds
    this.stats = {
      hits: 0,
      misses: 0,
      errors: 0,
      totalSaved: 0  // Estimated cost savings
    };
  }

  /**
   * Initialize Redis connection
   */
  async initialize() {
    try {
      const redisUrl = process.env.REDIS_URL;

      if (!redisUrl) {
        console.warn('⚠️ REDIS_URL not set - Question caching disabled');
        return this;
      }

      this.client = redis.createClient({
        url: redisUrl,
        socket: {
          reconnectStrategy: (retries) => {
            if (retries >= 1) {
              return false; // Stop retrying after first failure
            }
            return 500;
          }
        }
      });

      this.client.on('error', (err) => {
        this.stats.errors++;
        this.isConnected = false;
        if (!this._errorLogged) {
          this._errorLogged = true;
          console.warn(`⚠️ Question cache Redis unavailable (${err.message}), caching disabled`);
        }
      });

      this.client.on('connect', () => {
        console.log('🔌 Redis connected for question caching');
        this.isConnected = true;
        this._errorLogged = false;
      });

      await this.client.connect();

      console.log('✅ Question Cache Service initialized');
      return this;

    } catch (error) {
      if (!this._errorLogged) {
        this._errorLogged = true;
        console.warn(`⚠️ Question cache Redis unavailable (${error.message}), caching disabled`);
      }
      return this;
    }
  }

  /**
   * Generate cache key from question parameters
   * @param {object} params - Question generation parameters
   * @returns {string} Cache key
   */
  generateCacheKey(params) {
    // Create a deterministic hash of parameters
    const sortedParams = JSON.stringify(params, Object.keys(params).sort());
    const hash = crypto.createHash('sha256').update(sortedParams).digest('hex');
    return `question:${hash.substring(0, 16)}`;
  }

  /**
   * Get cached questions
   * @param {object} params - Question generation parameters
   * @returns {object|null} Cached questions or null
   */
  async get(params) {
    if (!this.isConnected) {
      this.stats.misses++;
      return null;
    }

    try {
      const key = this.generateCacheKey(params);
      const cached = await this.client.get(key);

      if (cached) {
        this.stats.hits++;
        this.stats.totalSaved += 0.50; // Estimate $0.50 saved per cache hit
        console.log(`💰 Cache HIT: ${key.substring(0, 20)}... (saved ~$0.50)`);
        return JSON.parse(cached);
      }

      this.stats.misses++;
      console.log(`⚠️  Cache MISS: ${key.substring(0, 20)}...`);
      return null;

    } catch (error) {
      console.error('❌ Cache get error:', error.message);
      this.stats.errors++;
      return null;
    }
  }

  /**
   * Set cached questions
   * @param {object} params - Question generation parameters
   * @param {object} questions - Generated questions to cache
   * @param {number} ttl - Time to live in seconds (default 7 days)
   */
  async set(params, questions, ttl = this.defaultTTL) {
    if (!this.isConnected) {
      return false;
    }

    try {
      const key = this.generateCacheKey(params);
      const value = JSON.stringify(questions);

      await this.client.setEx(key, ttl, value);
      console.log(`✅ Cached questions: ${key.substring(0, 20)}... (TTL: ${ttl}s = ${Math.floor(ttl / 86400)} days)`);
      return true;

    } catch (error) {
      console.error('❌ Cache set error:', error.message);
      this.stats.errors++;
      return false;
    }
  }

  /**
   * Invalidate cache for specific parameters
   * @param {object} params - Question parameters
   */
  async invalidate(params) {
    if (!this.isConnected) {
      return false;
    }

    try {
      const key = this.generateCacheKey(params);
      await this.client.del(key);
      console.log(`🗑️  Invalidated cache: ${key.substring(0, 20)}...`);
      return true;

    } catch (error) {
      console.error('❌ Cache invalidation error:', error.message);
      this.stats.errors++;
      return false;
    }
  }

  /**
   * Clear all question caches
   */
  async clearAll() {
    if (!this.isConnected) {
      return false;
    }

    try {
      const keys = await this.client.keys('question:*');
      if (keys.length > 0) {
        await this.client.del(keys);
        console.log(`🗑️  Cleared ${keys.length} question caches`);
      }
      return true;

    } catch (error) {
      console.error('❌ Cache clear error:', error.message);
      this.stats.errors++;
      return false;
    }
  }

  /**
   * Get cache statistics
   */
  getStats() {
    const totalRequests = this.stats.hits + this.stats.misses;
    const hitRate = totalRequests > 0 ? (this.stats.hits / totalRequests * 100).toFixed(2) : 0;

    return {
      isConnected: this.isConnected,
      hits: this.stats.hits,
      misses: this.stats.misses,
      errors: this.stats.errors,
      totalRequests,
      hitRate: `${hitRate}%`,
      estimatedSavings: `$${this.stats.totalSaved.toFixed(2)}`,
      monthlySavingsProjection: `$${(this.stats.totalSaved / Math.max(1, totalRequests) * 30 * 100).toFixed(2)}`
    };
  }

  /**
   * Close Redis connection
   */
  async close() {
    if (this.client && this.isConnected) {
      await this.client.quit();
      this.isConnected = false;
      console.log('🛑 Question Cache Service closed');
    }
  }
}

// Export singleton instance
module.exports = new QuestionCacheService();
