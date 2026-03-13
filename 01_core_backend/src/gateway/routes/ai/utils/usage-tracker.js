/**
 * Usage Tracker
 * Redis-backed per-user feature usage counters with DB fallback.
 *
 * Key strategy:
 *   Guest (is_anonymous=true):  "usage_lifetime:{userId}:{featureKey}"  — no TTL
 *   Others (monthly):           "usage:{userId}:{featureKey}:{YYYY-MM}" — TTL to end of month
 */

const redis = require('redis');
const { db } = require('../../../../utils/railway-database');

// ============================================
// TIER LIMITS
// ============================================

const TIER_LIMITS = {
  guest: {
    homework_single: 3,   // lifetime
    chat_messages:   10,  // lifetime
    homework_batch:  0,
    questions:       0,
    error_analysis:  0,
    reports:         0,
    voice_minutes:   0,
  },
  free: {
    homework_single: 10,
    homework_batch:  0,
    chat_messages:   50,
    questions:       30,
    error_analysis:  5,
    reports:         0,
    voice_minutes:   0,
  },
  premium: {
    homework_single: 50,
    homework_batch:  20,
    chat_messages:   500,
    questions:       200,
    error_analysis:  Infinity,
    reports:         2,
    voice_minutes:   300,
  },
  premium_plus: {
    // Empty = all features unlimited. usageTracker.check() handles missing key → unlimited.
  },
};

// ============================================
// REDIS CLIENT (lazy init, graceful fallback)
// ============================================

let redisClient = null;
let redisReady = false;
let _errorLogged = false;

function getRedis() {
  if (redisClient) return redisClient;
  try {
    redisClient = redis.createClient({
      url: process.env.REDIS_URL || 'redis://localhost:6379',
      socket: {
        reconnectStrategy: (retries) => {
          if (retries >= 2) {
            redisReady = false;
            return false;
          }
          return 500;
        },
      },
    });
    redisClient.on('connect', () => { redisReady = true; _errorLogged = false; });
    redisClient.on('error', () => {
      redisReady = false;
      if (!_errorLogged) {
        _errorLogged = true;
        console.warn('⚠️ [usage-tracker] Redis unavailable, falling back to DB usage counters');
      }
    });
    redisClient.connect().catch(() => { redisReady = false; });
  } catch (_) {
    redisReady = false;
  }
  return redisClient;
}

// ============================================
// HELPERS
// ============================================

function redisKey(userId, featureKey, isAnonymous) {
  if (isAnonymous) {
    return `usage_lifetime:${userId}:${featureKey}`;
  }
  const now = new Date();
  const month = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  return `usage:${userId}:${featureKey}:${month}`;
}

/**
 * Seconds until midnight on the last day of the current month (for Redis TTL)
 */
function ttlToEndOfMonth() {
  const now = new Date();
  const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1, 0, 0, 0, 0);
  return Math.ceil((endOfMonth - now) / 1000);
}

/**
 * Date of first day of next month (for resets_at field in responses)
 */
function nextMonthStart() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth() + 1, 1);
}

// ============================================
// PUBLIC API
// ============================================

const usageTracker = {
  /**
   * Check whether a user is allowed to use a feature.
   * Returns: { allowed: bool, remaining: int, limit: int, resets_at: Date|null }
   */
  async check(userId, featureKey, tier, isAnonymous) {
    const effectiveTier = isAnonymous ? 'guest' : tier;
    const limits = TIER_LIMITS[effectiveTier] ?? {};

    const limit = limits[featureKey];

    // premium_plus (or unknown future tier) — undefined key means unlimited
    if (limit === undefined) {
      return { allowed: true, remaining: Infinity, limit: Infinity, resets_at: null };
    }

    // Feature explicitly blocked for this tier
    if (limit === 0) {
      return { allowed: false, remaining: 0, limit: 0, resets_at: null };
    }

    // Infinite limit (e.g. premium error_analysis)
    if (!isFinite(limit)) {
      return { allowed: true, remaining: Infinity, limit: Infinity, resets_at: null };
    }

    // Read current count from Redis, fall back to DB
    let current = 0;
    const key = redisKey(userId, featureKey, isAnonymous);
    try {
      const rc = getRedis();
      if (redisReady && rc) {
        const val = await rc.get(key);
        current = val ? parseInt(val, 10) : 0;
      } else {
        throw new Error('redis not ready');
      }
    } catch (_) {
      // DB fallback: read from users.monthly_usage
      try {
        const tierData = await db.getUserTier(userId);
        const usage = tierData.monthly_usage || {};
        const resetDate = tierData.usage_reset_date ? new Date(tierData.usage_reset_date) : null;
        const now = new Date();
        const isCurrentMonth = resetDate &&
          resetDate.getFullYear() === now.getFullYear() &&
          resetDate.getMonth() === now.getMonth();
        current = isCurrentMonth ? (usage[featureKey] || 0) : 0;
      } catch (dbErr) {
        // Conservative: allow if we can't read (don't block users due to infra errors)
        current = 0;
      }
    }

    const remaining = Math.max(0, limit - current);
    const resets_at = isAnonymous ? null : nextMonthStart();
    return { allowed: remaining > 0, remaining, limit, resets_at };
  },

  /**
   * Increment counter by 1. Call AFTER confirming the request is allowed.
   */
  async increment(userId, featureKey, isAnonymous) {
    return this.incrementBy(userId, featureKey, 1, isAnonymous);
  },

  /**
   * Increment counter by `amount`. Used for voice_minutes.
   * Amount is Math.ceil'd to ensure it's an integer for Redis INCRBY.
   */
  async incrementBy(userId, featureKey, amount, isAnonymous) {
    const intAmount = Math.ceil(amount);
    const key = redisKey(userId, featureKey, isAnonymous);
    try {
      const rc = getRedis();
      if (redisReady && rc) {
        await rc.incrBy(key, intAmount);
        if (!isAnonymous) {
          // Set TTL to end of current month (idempotent — only matters on first set)
          await rc.expire(key, ttlToEndOfMonth());
        }
        // No TTL for guest keys (lifetime counters)
      } else {
        throw new Error('redis not ready');
      }
    } catch (_) {
      // DB fallback
      try {
        if (intAmount === 1) {
          await db.incrementUsage(userId, featureKey);
        } else {
          await db.incrementUsageBy(userId, featureKey, intAmount);
        }
      } catch (dbErr) {
        console.error('[usage-tracker] incrementBy DB fallback failed:', dbErr.message);
      }
    }
  },
};

module.exports = { usageTracker, TIER_LIMITS };
