/**
 * Version Gate Middleware — Soft Warning Mode
 *
 * Checks the iOS client version from User-Agent and adds a response header
 * when the client is outdated, so the app can show a dismissable update prompt.
 * Never blocks the request — users can always continue using the app.
 *
 * Controlled by one environment variable:
 *
 *   IOS_RECOMMENDED_VERSION  – semver string, e.g. "1.0.6" (default: "0.0.0" = no warning)
 *
 * The iOS app sends `User-Agent: StudyAI-iOS/<version>`.
 * Old builds may send "StudyAI-iOS/1.0"; new builds send the real CFBundleShortVersionString.
 *
 * When the client version < recommendedVersion, the middleware tags the request
 * and an onSend hook adds the `X-Version-Warning` response header with JSON metadata.
 * Old clients that don't understand the header simply ignore it.
 */

const logger = require('../../utils/logger');

// Read once at startup — change requires restart or redeploy
const RECOMMENDED_VERSION = process.env.IOS_RECOMMENDED_VERSION || '0.0.0';
const STORE_URL = 'https://apps.apple.com/app/id6754365864';

/**
 * Compare two semver-ish strings ("1.0.5" vs "1.0").
 * Returns -1 if a < b, 0 if equal, 1 if a > b.
 */
function compareSemver(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const na = pa[i] || 0;
    const nb = pb[i] || 0;
    if (na < nb) return -1;
    if (na > nb) return 1;
  }
  return 0;
}

/**
 * Extract version from User-Agent header.
 * Expected format: "StudyAI-iOS/1.0.5"
 * Returns the version string, or null if not an iOS client.
 */
function parseIOSVersion(userAgent) {
  if (!userAgent) return null;
  const match = userAgent.match(/^StudyAI-iOS\/(.+)$/);
  return match ? match[1] : null;
}

/**
 * Fastify preHandler — tags the request with version warning metadata
 * when the iOS client is below the recommended version. Never blocks.
 */
async function versionGate(request, reply) {
  const ua = request.headers['user-agent'];
  const clientVersion = parseIOSVersion(ua);

  // Non-iOS clients (web, curl, etc.) or missing UA — skip
  if (!clientVersion) return;

  if (compareSemver(clientVersion, RECOMMENDED_VERSION) < 0) {
    // Tag the request so the onSend hook can add the response header
    request.versionWarning = {
      recommendedVersion: RECOMMENDED_VERSION,
      clientVersion,
      storeUrl: STORE_URL
    };
  }
}

/**
 * Fastify onSend hook — adds `X-Version-Warning` response header
 * when the preHandler tagged the request.
 */
async function versionWarningHook(request, reply, payload) {
  if (request.versionWarning) {
    reply.header('X-Version-Warning', JSON.stringify(request.versionWarning));
  }
  return payload;
}

module.exports = { versionGate, versionWarningHook, compareSemver, parseIOSVersion };
