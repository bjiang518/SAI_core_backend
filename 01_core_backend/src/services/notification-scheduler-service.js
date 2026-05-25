'use strict';

/**
 * Notification Scheduler Service
 * Sends one AI-personalized push notification per user per day at 18:00 local time.
 *
 * Cron: runs every hour (UTC). Per-user check converts to local timezone.
 * Dedup:  Redis key  notif_daily:{userId}:{YYYY-MM-DD}  prevents double-sends.
 * Fallback: if Redis is unavailable, dedup falls back to a DB check.
 */

const cron                      = require('node-cron');
const { db }                    = require('../utils/railway-database');
const logger                    = require('../utils/logger');
const { sendNotification }      = require('./apns-service');
const { collectSignals }        = require('./notification-signal-collector');
const { generateNotification }  = require('./notification-ai-generator');

// Target local hour to send (18 = 6 PM)
const SEND_HOUR = 18;

// Deep-link scheme map
const ACTION_TO_DEEP_LINK = {
    weakness: 'studyai://practice/weakness',
    practice: 'studyai://practice/daily',
    goal:     'studyai://practice/daily',
    daily:    'studyai://practice/daily',
};

// ─── Timezone helper (mirrors report-scheduler) ───────────────────────────────

function getUserLocalHour(timezone) {
    try {
        const parts = new Intl.DateTimeFormat('en-US', {
            timeZone: timezone,
            hour:     'numeric',
            hour12:   false,
        }).formatToParts(new Date());
        const raw = parseInt(parts.find(p => p.type === 'hour').value, 10);
        return raw === 24 ? 0 : raw;
    } catch {
        return null;
    }
}

function todayKeyForTimezone(timezone) {
    try {
        return new Intl.DateTimeFormat('en-CA', { timeZone: timezone })
            .format(new Date()); // returns "YYYY-MM-DD"
    } catch {
        return new Date().toISOString().slice(0, 10);
    }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class NotificationSchedulerService {
    constructor() {
        this.cronJob       = null;
        this.isInitialized = false;
        this.isRunning     = false;
        this._redis        = null;  // set in initialize()
    }

    async initialize(redisClient = null) {
        if (this.isInitialized) return;

        this._redis = redisClient;

        this.cronJob = cron.schedule('0 * * * *', async () => {
            await this._tick();
        }, { scheduled: true, timezone: 'UTC' });

        this.isInitialized = true;
        logger.info('🔔 Notification Scheduler initialized — fires daily at 18:00 user local time');
    }

    stop() {
        if (this.cronJob) {
            this.cronJob.stop();
            this.cronJob.destroy();
            this.cronJob = null;
        }
        this.isInitialized = false;
        logger.debug('⏹️ Notification Scheduler stopped');
    }

    // ── Main tick ────────────────────────────────────────────────────────────

    async _tick() {
        if (this.isRunning) {
            logger.debug('[NotifScheduler] Previous tick still running — skipping');
            return;
        }
        this.isRunning = true;

        try {
            const users = await this._getEligibleUsers();
            if (users.length === 0) return;

            let sent = 0;
            for (const user of users) {
                try {
                    const localHour = getUserLocalHour(user.timezone || 'UTC');
                    if (localHour !== SEND_HOUR) continue;

                    const dateKey = todayKeyForTimezone(user.timezone || 'UTC');
                    const dedupKey = `notif_daily:${user.user_id}:${dateKey}`;

                    if (await this._alreadySent(user.user_id, dedupKey)) continue;

                    await this._sendToUser(user, dedupKey);
                    sent++;
                } catch (err) {
                    logger.error(`[NotifScheduler] Failed for user ${user.user_id}: ${err.message}`);
                }
            }

            if (sent > 0) logger.info(`[NotifScheduler] Tick — sent ${sent} notification(s)`);

        } catch (err) {
            logger.error('[NotifScheduler] Unexpected tick error:', err);
        } finally {
            this.isRunning = false;
        }
    }

    // ── Per-user send ────────────────────────────────────────────────────────

    async _sendToUser(user, dedupKey) {
        const signals = await collectSignals(user.user_id);

        // No APNs token — can't deliver
        if (!signals.profile?.apns_token) return;

        const notif = await generateNotification(signals);

        const deepLink = buildDeepLink(notif);
        const data = {
            deepLink,
            ...(notif.weakness_key ? { weaknessKey: notif.weakness_key } : {}),
        };

        await sendNotification(
            signals.profile.apns_token,
            notif.title,
            notif.body,
            data,
            signals.profile.apns_env || null
        );

        // Mark sent — TTL 25 h so it survives across the next tick
        await this._markSent(user.user_id, dedupKey);

        logger.info(`[NotifScheduler] ✉️ user=${user.user_id} title="${notif.title}"`);
    }

    // ── DB / Redis helpers ───────────────────────────────────────────────────

    async _getEligibleUsers() {
        // All users with a registered APNs token and a known timezone
        const { rows } = await db.query(
            `SELECT user_id, timezone
             FROM profiles
             WHERE apns_token IS NOT NULL
               AND timezone   IS NOT NULL
               AND timezone   != ''`
        );
        return rows;
    }

    async _alreadySent(userId, redisKey) {
        if (this._redis) {
            try {
                const val = await this._redis.get(redisKey);
                return val !== null;
            } catch (e) {
                logger.warn(`[NotifScheduler] Redis get failed: ${e.message}`);
            }
        }
        // DB fallback — check notification_log table if it exists, else skip dedup
        try {
            const { rows } = await db.query(
                `SELECT 1 FROM notification_log
                 WHERE user_id = $1 AND sent_at >= CURRENT_DATE
                 LIMIT 1`,
                [userId]
            );
            return rows.length > 0;
        } catch {
            return false; // table may not exist yet — allow the send
        }
    }

    async _markSent(userId, redisKey) {
        if (this._redis) {
            try {
                await this._redis.setex(redisKey, 90000, '1'); // 25 h
                return;
            } catch (e) {
                logger.warn(`[NotifScheduler] Redis setex failed: ${e.message}`);
            }
        }
        // DB fallback — best-effort insert, ignore if table missing
        db.query(
            `INSERT INTO notification_log (user_id, sent_at)
             VALUES ($1, NOW()) ON CONFLICT DO NOTHING`,
            [userId]
        ).catch(() => {});
    }
}

// ─── Deep-link builder ────────────────────────────────────────────────────────

function buildDeepLink(notif) {
    const base = ACTION_TO_DEEP_LINK[notif.action] || ACTION_TO_DEEP_LINK.daily;
    if (notif.action === 'weakness' && notif.weakness_key) {
        const encoded = encodeURIComponent(notif.weakness_key);
        return `${base}?key=${encoded}`;
    }
    return base;
}

// ── Singleton ─────────────────────────────────────────────────────────────────

const notificationSchedulerService = new NotificationSchedulerService();

module.exports = {
    NotificationSchedulerService,
    notificationSchedulerService,
};
