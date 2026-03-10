/**
 * UserApiTracker — lightweight in-memory per-user API call counter.
 *
 * Stores: Map<userId, Map<"METHOD /route/pattern", count>>
 * Data lives for the lifetime of the process (resets on deploy).
 * Designed for admin monitoring — not a billing or audit log.
 */

class UserApiTracker {
  constructor() {
    // Map<userId, Map<routeKey, count>>
    this._data = new Map();
    // Cap how many distinct route keys we store per user (prevent unbounded growth)
    this._maxRoutesPerUser = 100;
  }

  /**
   * Record one API call for a user.
   * @param {string} userId
   * @param {string} method  - HTTP method e.g. "GET"
   * @param {string} route   - Fastify route pattern e.g. "/api/ai/sessions/:id/message"
   */
  record(userId, method, route) {
    if (!userId || !route) return;

    // Normalize: strip query string, collapse UUIDs to :id for grouping
    const normalized = normalizeRoute(method, route);

    let userMap = this._data.get(userId);
    if (!userMap) {
      userMap = new Map();
      this._data.set(userId, userMap);
    }

    if (!userMap.has(normalized) && userMap.size >= this._maxRoutesPerUser) return;
    userMap.set(normalized, (userMap.get(normalized) || 0) + 1);
  }

  /**
   * Get top N routes for a user, sorted by call count descending.
   * @param {string} userId
   * @param {number} limit
   * @returns {Array<{ route: string, count: number }>}
   */
  getTopRoutes(userId, limit = 10) {
    const userMap = this._data.get(userId);
    if (!userMap) return [];

    return Array.from(userMap.entries())
      .map(([route, count]) => ({ route, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, limit);
  }

  /** Total distinct users being tracked */
  get userCount() {
    return this._data.size;
  }
}

/** Strip query string; collapse UUIDs to :id; uppercase method */
function normalizeRoute(method, route) {
  const path = route.split('?')[0]
    .replace(/\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi, '/:id')
    .replace(/\/\d{6,}/g, '/:id');  // long numeric IDs
  return `${method.toUpperCase()} ${path}`;
}

// Singleton
const userApiTracker = new UserApiTracker();
module.exports = { userApiTracker };
