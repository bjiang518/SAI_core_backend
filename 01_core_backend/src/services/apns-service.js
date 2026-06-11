/**
 * APNs Push Notification Service
 * Sends remote push notifications via Apple Push Notification service (APNs) HTTP/2 API.
 *
 * Configuration (environment variables):
 *   APNS_KEY_ID      — 10-character key ID from Apple Developer portal (e.g. ABC1234567)
 *   APNS_TEAM_ID     — 10-character Team ID from Apple Developer account
 *   APNS_KEY         — Private key (.p8) contents as a single-line string with \n escapes
 *                      OR set APNS_KEY_FILE to a file path
 *   APNS_BUNDLE_ID   — App bundle identifier (e.g. com.OliOli.StudyMatesAI)
 *   APNS_ENV         — 'production' | 'sandbox' (default: 'sandbox' unless NODE_ENV=production)
 */

'use strict';

const https  = require('https');
const http2  = require('http2');
const crypto = require('crypto');
const logger = require('../utils/logger');

// ── JWT token generation ─────────────────────────────────────────────────────

let _cachedToken = null;
let _tokenExpiresAt = 0;
let _cachedKeyObject = null;   // KeyObject parsed from APNS_KEY — reused across token rotations
let _cachedKeyDigest = null;   // First 6 chars of sha256 of the key PEM — for log diagnostics

/// Normalize a PEM string from an env var. Production env-var pipelines
/// (Railway, Heroku, etc.) frequently mangle multi-line secrets:
///   • literal "\n" instead of actual newlines  → unescape
///   • surrounding single or double quotes      → strip
///   • Windows "\r\n" line endings              → normalize
///   • leading/trailing whitespace              → trim
///   • Body run-on with spaces (no line breaks) → re-wrap to 64-char lines
/// Without normalization, OpenSSL 3's stricter decoder rejects the key
/// with `error:1E08010C:DECODER routines::unsupported` and every push fails.
function normalizePem(raw) {
    if (!raw) return raw;
    let s = String(raw).trim();

    // Strip wrapping quotes (env vars are sometimes pasted as `"-----BEGIN ..."`).
    if ((s.startsWith('"') && s.endsWith('"')) ||
        (s.startsWith("'") && s.endsWith("'"))) {
        s = s.slice(1, -1).trim();
    }

    // Unescape literal "\n" sequences and normalize CRLF → LF.
    s = s.replace(/\\r\\n/g, '\n')
         .replace(/\\n/g, '\n')
         .replace(/\r\n/g, '\n')
         .replace(/\r/g, '\n');

    // If the BEGIN/END markers are present but the body is one long blob
    // without line breaks (common when env-var pipelines collapse whitespace),
    // re-wrap the base64 body to 64-char lines so OpenSSL accepts it.
    const beginMatch = s.match(/-----BEGIN ([A-Z ]+)-----/);
    const endMatch   = s.match(/-----END ([A-Z ]+)-----/);
    if (beginMatch && endMatch) {
        const label = beginMatch[1];
        const begin = `-----BEGIN ${label}-----`;
        const end   = `-----END ${label}-----`;
        const beginIdx = s.indexOf(begin);
        const endIdx   = s.indexOf(end);
        if (beginIdx >= 0 && endIdx > beginIdx) {
            const body = s.slice(beginIdx + begin.length, endIdx)
                          .replace(/\s+/g, ''); // drop all whitespace
            const wrapped = body.match(/.{1,64}/g)?.join('\n') ?? body;
            s = `${begin}\n${wrapped}\n${end}\n`;
        }
    }

    return s;
}

function loadKeyObject() {
    if (_cachedKeyObject) return _cachedKeyObject;

    const { APNS_KEY, APNS_KEY_FILE } = process.env;

    let keyPem;
    if (APNS_KEY) {
        keyPem = normalizePem(APNS_KEY);
    } else if (APNS_KEY_FILE) {
        keyPem = require('fs').readFileSync(APNS_KEY_FILE, 'utf8');
    } else {
        throw new Error('APNs not configured: set APNS_KEY or APNS_KEY_FILE env var');
    }

    // Parse explicitly via createPrivateKey — gives a much clearer error than
    // the opaque DECODER failure that surfaces from `.sign({ key })` later.
    let keyObj;
    try {
        keyObj = crypto.createPrivateKey({ key: keyPem, format: 'pem' });
    } catch (err) {
        const digest = crypto.createHash('sha256').update(keyPem).digest('hex').slice(0, 6);
        const lineCount = (keyPem.match(/\n/g) || []).length;
        const hasBegin  = /-----BEGIN [A-Z ]+-----/.test(keyPem);
        const hasEnd    = /-----END [A-Z ]+-----/.test(keyPem);
        throw new Error(
            `APNs key parse failed (${err.code || err.message}). ` +
            `Diagnostics: digest=${digest} length=${keyPem.length} lines=${lineCount} ` +
            `hasBegin=${hasBegin} hasEnd=${hasEnd}. ` +
            `Verify APNS_KEY env var contains the .p8 contents with proper newlines.`
        );
    }

    if (keyObj.asymmetricKeyType !== 'ec') {
        throw new Error(
            `APNs key has wrong type: expected 'ec' (P-256), got '${keyObj.asymmetricKeyType}'. ` +
            `The .p8 from Apple Developer is always EC; check you didn't paste a different key.`
        );
    }

    _cachedKeyObject = keyObj;
    _cachedKeyDigest = crypto.createHash('sha256').update(keyPem).digest('hex').slice(0, 6);
    return keyObj;
}

function buildProviderToken() {
    const now = Math.floor(Date.now() / 1000);
    if (_cachedToken && _tokenExpiresAt > now + 60) return _cachedToken;

    const { APNS_KEY_ID, APNS_TEAM_ID } = process.env;

    if (!APNS_KEY_ID || !APNS_TEAM_ID) {
        throw new Error('APNs not configured: set APNS_KEY_ID and APNS_TEAM_ID env vars');
    }

    // Parse-and-cache the key once (loadKeyObject normalizes mangled PEMs
    // and surfaces clear errors for malformed keys). Re-using the parsed
    // KeyObject across token rotations also avoids re-parsing every hour.
    const keyObj = loadKeyObject();

    const header  = Buffer.from(JSON.stringify({ alg: 'ES256', kid: APNS_KEY_ID })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })).toString('base64url');
    const unsigned = `${header}.${payload}`;
    const sign = crypto.createSign('SHA256');
    sign.update(unsigned);
    // dsaEncoding 'ieee-p1363' produces the raw r||s output that JWT/ES256
    // requires (vs. DER, which is the default and would be rejected by APNs).
    const signature = sign.sign({ key: keyObj, dsaEncoding: 'ieee-p1363' }).toString('base64url');

    _cachedToken    = `${unsigned}.${signature}`;
    _tokenExpiresAt = now + 3600; // tokens valid for 1 hour
    return _cachedToken;
}

// ── APNs HTTP/2 sender ───────────────────────────────────────────────────────

/**
 * Send a push notification to a single device.
 *
 * @param {string} deviceToken   Hex APNs device token
 * @param {string} title         Notification title
 * @param {string} body          Notification body
 * @param {object} data          Custom payload (delivered under the 'data' key)
 * @returns {Promise<void>}
 */
async function sendNotification(deviceToken, title, body, data = {}, env = null) {
    // Caller can pass env explicitly ('sandbox'|'production'); fall back to env var / NODE_ENV.
    const resolvedEnv = env || process.env.APNS_ENV || (process.env.NODE_ENV === 'production' ? 'production' : 'sandbox');
    const host       = resolvedEnv === 'production' ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
    logger.info(`[APNs] Sending to ${resolvedEnv} (${host}) token=${deviceToken.slice(0, 8)}...`);
    const bundleId   = process.env.APNS_BUNDLE_ID || 'com.OliOli.StudyMatesAI';
    const providerToken = buildProviderToken();

    const payload = JSON.stringify({
        aps: {
            alert: { title, body },
            sound: 'default',
            badge: 1,
        },
        data,
    });

    return new Promise((resolve, reject) => {
        const client = http2.connect(`https://${host}`);
        client.on('error', reject);

        const path = `/3/device/${deviceToken}`;
        const headers = {
            ':method': 'POST',
            ':path': path,
            ':scheme': 'https',
            ':authority': host,
            'authorization': `bearer ${providerToken}`,
            'content-type': 'application/json',
            'content-length': Buffer.byteLength(payload),
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'apns-topic': bundleId,
        };

        const req = client.request(headers);
        let statusCode = 0;
        let responseBody = '';

        req.on('response', (resHeaders) => {
            statusCode = parseInt(resHeaders[':status'], 10);
        });

        req.on('data', chunk => { responseBody += chunk; });

        req.on('end', () => {
            client.close();
            if (statusCode === 200) {
                resolve();
            } else {
                const err = new Error(`APNs responded ${statusCode}: ${responseBody}`);
                err.statusCode = statusCode;
                reject(err);
            }
        });

        req.on('error', reject);
        req.write(payload);
        req.end();
    });
}

module.exports = { sendNotification };
