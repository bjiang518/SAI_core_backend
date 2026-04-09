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

function buildProviderToken() {
    const now = Math.floor(Date.now() / 1000);
    if (_cachedToken && _tokenExpiresAt > now + 60) return _cachedToken;

    const { APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY, APNS_KEY_FILE } = process.env;

    if (!APNS_KEY_ID || !APNS_TEAM_ID) {
        throw new Error('APNs not configured: set APNS_KEY_ID and APNS_TEAM_ID env vars');
    }

    // Load key — either inline (with \\n) or from file
    let keyPem;
    if (APNS_KEY) {
        keyPem = APNS_KEY.replace(/\\n/g, '\n');
    } else if (APNS_KEY_FILE) {
        keyPem = require('fs').readFileSync(APNS_KEY_FILE, 'utf8');
    } else {
        throw new Error('APNs not configured: set APNS_KEY or APNS_KEY_FILE env var');
    }

    const header  = Buffer.from(JSON.stringify({ alg: 'ES256', kid: APNS_KEY_ID })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })).toString('base64url');
    const unsigned = `${header}.${payload}`;
    const sign = crypto.createSign('SHA256');
    sign.update(unsigned);
    const signature = sign.sign({ key: keyPem, dsaEncoding: 'ieee-p1363' }).toString('base64url');

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
