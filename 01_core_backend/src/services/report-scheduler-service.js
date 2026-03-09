/**
 * Report Scheduler Service
 * Automatically generates weekly and monthly parent reports for all opted-in users
 * based on their individual timezone and preferred delivery time.
 *
 * Cron: runs every hour on the hour (UTC).
 * Per-user check: converts current UTC time to the user's local timezone,
 *   then compares against report_day_of_week + report_time_hour (weekly)
 *   or day-of-month = 1 + report_time_hour (monthly).
 * Deduplication: skips if a report already exists within the cooldown window
 *   (6 days for weekly, 25 days for monthly).
 */

'use strict';

const cron = require('node-cron');
const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');
const PassiveReportGenerator = require('./passive-report-generator');

// ─── Helpers ─────────────────────────────────────────────────────────────────

/**
 * Parse the user's current local time from an IANA timezone string.
 * Returns { hour, dayOfWeek (0=Sun), dayOfMonth } or null on invalid timezone.
 */
function getUserLocalTime(timezone) {
    try {
        const now = new Date();
        const parts = new Intl.DateTimeFormat('en-US', {
            timeZone: timezone,
            hour:    'numeric',
            weekday: 'short',
            day:     'numeric',
            hour12:  false,
        }).formatToParts(now);

        const rawHour    = parseInt(parts.find(p => p.type === 'hour').value, 10);
        const dayOfMonth = parseInt(parts.find(p => p.type === 'day').value, 10);
        const weekday    = parts.find(p => p.type === 'weekday').value;
        const weekdayMap = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };

        // Intl may return 24 for midnight in some locales; normalise to 0
        return { hour: rawHour === 24 ? 0 : rawHour, dayOfWeek: weekdayMap[weekday], dayOfMonth };
    } catch {
        return null;
    }
}

/**
 * Build a { startDate, endDate } date range relative to now.
 * Mirrors the helper in passive-reports.js so report content is consistent.
 */
function buildDateRange(period) {
    const endDate   = new Date();
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - (period === 'monthly' ? 30 : 7));
    startDate.setHours(0, 0, 0, 0);
    endDate.setHours(23, 59, 59, 999);
    return { startDate, endDate };
}

// ─── Service ─────────────────────────────────────────────────────────────────

class ReportSchedulerService {
    constructor() {
        this.cronJob      = null;
        this.isInitialized = false;
        this.isRunning    = false;   // prevent overlapping runs
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    async initialize() {
        if (this.isInitialized) {
            logger.debug('⚠️ Report Scheduler already initialized');
            return;
        }

        // Run at the top of every hour
        this.cronJob = cron.schedule('0 * * * *', async () => {
            await this._runScheduledReports();
        }, { scheduled: true, timezone: 'UTC' });

        this.isInitialized = true;
        logger.debug('📅 Report Scheduler initialized — runs hourly');
    }

    stop() {
        if (this.cronJob) {
            this.cronJob.stop();
            this.cronJob.destroy();
            this.cronJob = null;
        }
        this.isInitialized = false;
        logger.debug('⏹️ Report Scheduler stopped');
    }

    // ── Main dispatch ────────────────────────────────────────────────────────

    async _runScheduledReports() {
        if (this.isRunning) {
            logger.debug('[ReportScheduler] Previous run still in progress — skipping this tick');
            return;
        }
        this.isRunning = true;
        try {
            const [weeklyCount, monthlyCount] = await Promise.all([
                this._processReports('weekly'),
                this._processReports('monthly'),
            ]);
            if (weeklyCount + monthlyCount > 0) {
                logger.info(`[ReportScheduler] Tick complete — weekly: ${weeklyCount}, monthly: ${monthlyCount}`);
            }
        } catch (err) {
            logger.error('[ReportScheduler] Unexpected error during tick:', err);
        } finally {
            this.isRunning = false;
        }
    }

    // ── Per-period processor ─────────────────────────────────────────────────

    /**
     * Fetches all opted-in users, checks each one's local time, and generates
     * a report for those whose scheduled window has arrived.
     * Returns the number of reports successfully generated.
     */
    async _processReports(period) {
        const users = await this._getEligibleUsers();
        if (users.length === 0) return 0;

        let generated = 0;

        for (const user of users) {
            try {
                const local = getUserLocalTime(user.timezone || 'UTC');
                if (!local) continue;

                const scheduledHour = user.report_time_hour ?? 21;

                // Hour must match in the user's local timezone
                if (local.hour !== scheduledHour) continue;

                if (period === 'weekly') {
                    const scheduledDay = user.report_day_of_week ?? 0;
                    if (local.dayOfWeek !== scheduledDay) continue;
                } else {
                    // Monthly: generate on the 1st of each month
                    if (local.dayOfMonth !== 1) continue;
                }

                // Skip if a report was already generated within the cooldown window
                const alreadyGenerated = await this._recentReportExists(user.user_id, period);
                if (alreadyGenerated) continue;

                const result = await this._generateReport(user, period);
                if (result) generated++;
            } catch (err) {
                logger.error(`[ReportScheduler] Failed for user ${user.user_id} (${period}):`, err);
            }
        }

        return generated;
    }

    // ── DB helpers ───────────────────────────────────────────────────────────

    async _getEligibleUsers() {
        const { rows } = await db.query(
            `SELECT user_id, timezone, report_day_of_week, report_time_hour, language_preference
             FROM profiles
             WHERE parent_reports_enabled = true`
        );
        return rows;
    }

    async _recentReportExists(userId, period) {
        const cooldown = period === 'monthly' ? '25 days' : '6 days';
        const { rows } = await db.query(
            `SELECT 1 FROM parent_report_batches
             WHERE user_id = $1
               AND period   = $2
               AND created_at > NOW() - INTERVAL '${cooldown}'
             LIMIT 1`,
            [userId, period]
        );
        return rows.length > 0;
    }

    // ── Generation ───────────────────────────────────────────────────────────

    async _generateReport(user, period) {
        const language  = user.language_preference || 'en';
        const dateRange = buildDateRange(period);
        const generator = new PassiveReportGenerator();

        const result = await generator.generateAllReports(user.user_id, period, dateRange, language);
        if (result) {
            logger.info(`[ReportScheduler] ${period} report generated — user: ${user.user_id}`);
        }
        return result;
    }
}

// ── Singleton ─────────────────────────────────────────────────────────────────

const reportSchedulerService = new ReportSchedulerService();

module.exports = {
    ReportSchedulerService,
    reportSchedulerService,
};
