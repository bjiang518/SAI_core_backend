'use strict';

const { sendNotification } = require('./apns-service');
const logger = require('../utils/logger');

/**
 * Send a push notification to a single user by userId.
 * Looks up the APNs token from the profiles table.
 *
 * @param {object} db        Postgres client / pool with a `.query()` method
 * @param {string} userId    UUID of the target user
 * @param {string} title     Notification title
 * @param {string} body      Notification body
 * @param {object} data      Custom payload merged under the `data` key
 * @returns {Promise<{sent: boolean, reason?: string}>}
 */
async function sendToUser(db, userId, title, body, data = {}) {
    const result = await db.query(
        'SELECT apns_token, apns_env FROM profiles WHERE user_id = $1',
        [userId]
    );
    const row = result.rows[0];
    if (!row?.apns_token) {
        logger.info(`[Push] No APNs token for user ${userId} — skipping`);
        return { sent: false, reason: 'no_token' };
    }
    try {
        await sendNotification(row.apns_token, title, body, data, row.apns_env);
        logger.info(`[Push] Delivered to user ${userId}`);
        return { sent: true };
    } catch (err) {
        logger.warn(`[Push] Failed for user ${userId}: ${err.message}`);
        return { sent: false, reason: err.message };
    }
}

/**
 * Send the same push notification to multiple users.
 *
 * @param {object} db
 * @param {string[]} userIds
 * @param {string} title
 * @param {string} body
 * @param {object} data
 * @returns {Promise<{sent: number, total: number}>}
 */
async function sendToUsers(db, userIds, title, body, data = {}) {
    const results = await Promise.allSettled(
        userIds.map(id => sendToUser(db, id, title, body, data))
    );
    const sent = results.filter(r => r.status === 'fulfilled' && r.value.sent).length;
    logger.info(`[Push] Batch: ${sent}/${userIds.length} delivered`);
    return { sent, total: userIds.length };
}

module.exports = { sendToUser, sendToUsers };
