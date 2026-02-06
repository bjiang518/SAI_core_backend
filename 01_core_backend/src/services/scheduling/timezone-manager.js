/**
 * Timezone Manager Service
 * Handles user timezone preferences and scheduling logic
 */

const { db } = require('../../utils/railway-database');

class TimezoneManager {
    /**
     * Get user's local timezone
     * @param {string} userId - User UUID
     * @returns {Promise<string>} Timezone string (e.g., 'America/New_York')
     */
    async getUserTimezone(userId) {
        try {
            const query = `
                SELECT timezone
                FROM profiles
                WHERE user_id = $1
            `;
            const result = await db.query(query, [userId]);

            // Default to UTC if not set
            return result.rows[0]?.timezone || 'UTC';
        } catch (error) {
            console.warn(`⚠️ Could not fetch timezone for user ${userId}, using UTC`);
            return 'UTC';
        }
    }

    /**
     * Get all users who should receive report at current time
     * Returns users where it's their scheduled report day/time in their local timezone
     * @returns {Promise<Array>} Array of user objects
     */
    async getUsersForReportGeneration() {
        try {
            const query = `
                SELECT
                    u.id as user_id,
                    u.email,
                    u.name,
                    p.timezone,
                    p.report_day_of_week,
                    p.report_time_hour
                FROM users u
                JOIN profiles p ON u.id = p.user_id
                WHERE p.parent_reports_enabled = true
                  AND EXTRACT(DOW FROM NOW() AT TIME ZONE COALESCE(p.timezone, 'UTC')) = COALESCE(p.report_day_of_week, 0)
                  AND EXTRACT(HOUR FROM NOW() AT TIME ZONE COALESCE(p.timezone, 'UTC')) = COALESCE(p.report_time_hour, 21)
            `;

            const result = await db.query(query);
            return result.rows || [];
        } catch (error) {
            console.error('❌ Failed to fetch users for report generation:', error);
            return [];
        }
    }

    /**
     * Calculate next Sunday 9 PM for a user
     * @param {string} timezone - Timezone string
     * @returns {Date} Next scheduled report time
     */
    getNextReportTime(timezone) {
        const now = new Date();

        try {
            const userTime = new Date(now.toLocaleString('en-US', { timeZone: timezone }));

            // Find next Sunday
            const daysUntilSunday = (7 - userTime.getDay()) % 7 || 7;
            const nextSunday = new Date(userTime);
            nextSunday.setDate(userTime.getDate() + daysUntilSunday);
            nextSunday.setHours(21, 0, 0, 0); // 9 PM

            return nextSunday;
        } catch (error) {
            console.warn(`⚠️ Invalid timezone ${timezone}, using UTC`);
            const nextSunday = new Date(now);
            nextSunday.setDate(now.getDate() + (7 - now.getDay()));
            nextSunday.setHours(21, 0, 0, 0);
            return nextSunday;
        }
    }

    /**
     * Update user's report preferences
     * @param {string} userId - User UUID
     * @param {Object} preferences - Report preferences
     * @returns {Promise<boolean>} Success status
     */
    async updateReportPreferences(userId, preferences) {
        try {
            const {
                enabled = true,
                dayOfWeek = 0, // Sunday
                timeHour = 21, // 9 PM
                timezone = 'UTC'
            } = preferences;

            const query = `
                UPDATE profiles
                SET
                    parent_reports_enabled = $1,
                    report_day_of_week = $2,
                    report_time_hour = $3,
                    timezone = $4
                WHERE user_id = $5
            `;

            await db.query(query, [enabled, dayOfWeek, timeHour, timezone, userId]);
            return true;
        } catch (error) {
            console.error('❌ Failed to update report preferences:', error);
            return false;
        }
    }
}

module.exports = new TimezoneManager();
