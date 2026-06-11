/**
 * Version Gate Middleware — Soft Warning Mode
 *
 * Checks the iOS client version from User-Agent and adds a response header
 * when the client is outdated, so the app can show a dismissable update prompt.
 * Never blocks the request — users can always continue using the app.
 *
 * Controlled by one environment variable:
 *
 *   IOS_RECOMMENDED_VERSION  – semver string, e.g. "1.2.6" (default: "0.0.0" = no warning)
 *
 * The iOS app sends `User-Agent: StudyAI-iOS/<version>`.
 * Old builds may send "StudyAI-iOS/1.0"; new builds send the real CFBundleShortVersionString.
 *
 * When the client version < recommendedVersion, the middleware tags the request
 * and an onSend hook adds the `X-Version-Warning` response header with JSON metadata
 * including a bilingual release-notes payload.
 *
 * IMPORTANT: HTTP header values must be ASCII (Node rejects non-printable bytes
 * with ERR_INVALID_CHAR). The release-notes object contains Chinese / emoji /
 * em-dash, so it's serialized as base64-of-JSON under the `releaseNotesB64`
 * field. iOS 1.2.7+ decodes it; older clients that don't recognize the field
 * just ignore it — the rest of the header stays plain ASCII.
 */

const logger = require('../../utils/logger');

// Read once at startup — change requires restart or redeploy
const RECOMMENDED_VERSION = process.env.IOS_RECOMMENDED_VERSION || '0.0.0';
const STORE_URL = 'https://apps.apple.com/app/id6754365864';

/**
 * Bilingual release notes for the current `RECOMMENDED_VERSION`.
 * iOS 1.2.7+ reads `releaseNotes[lang]` and shows it in the soft-update prompt.
 * Clients < 1.2.7 ignore this field entirely (alert message is hardcoded locally).
 *
 * Keep each language's body short — at most ~5 bullet points, ~300 chars total —
 * so it fits cleanly inside an iOS alert / sheet.
 */
const RELEASE_NOTES = {
  version: '1.2.6',
  zh: {
    title: '新版本上线啦 🎉',
    body: [
      '• 真题库全面增强：更多真实考试题，按知识点精准筛选',
      '• 知识树升级：直观看见薄弱点，一键点亮未掌握的概念',
      '• AI 视频学习：和 AI 一起看视频，边看边讲解、边练习',
      '• 多项性能优化和体验提升',
    ].join('\n'),
  },
  en: {
    title: "What's New 🎉",
    body: [
      '• Question Bank upgraded — more real exam questions, filterable by topic',
      '• Knowledge Tree improved — see weak spots clearly, light up concepts you haven\'t mastered',
      '• Learn-with-AI Videos — watch with AI, get live explanations and practice',
      '• Performance and UX improvements',
    ].join('\n'),
  },
};

// Pre-compute the base64 form once at module load — RELEASE_NOTES is a constant.
// Storing it directly in an HTTP header would crash Node with ERR_INVALID_CHAR
// because of the Chinese / emoji / em-dash bytes.
const RELEASE_NOTES_B64 = Buffer.from(JSON.stringify(RELEASE_NOTES), 'utf8').toString('base64');

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
      storeUrl: STORE_URL,
      releaseNotesB64: RELEASE_NOTES_B64,
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

module.exports = { versionGate, versionWarningHook, compareSemver, parseIOSVersion, RELEASE_NOTES };
