/**
 * Report Scheduler Service
 * Manages automated report generation on schedule
 */

const cron = require('node-cron');
const timezoneManager = require('./timezone-manager');
const activityGenerator = require('../report-generators/activity-report-generator');
const improvementGenerator = require('../report-generators/improvement-report-generator');
const logger = require('../../utils/logger');

class ReportScheduler {
    constructor() {
        this.cronJob = null;
        this.isRunning = false;
    }

    /**
     * Start automated report generation
     * Runs every hour to check if any users need reports
     */
    start() {
        if (this.isRunning) {
            logger.warn('⚠️ Report scheduler already running');
            return;
        }

        logger.info('🕐 Starting automated report scheduler...');

        // Run every hour at minute 0
        this.cronJob = cron.schedule('0 * * * *', async () => {
            await this.generateScheduledReports();
        }, {
            timezone: 'UTC'
        });

        this.isRunning = true;
        logger.info('✅ Report scheduler started (runs hourly)');
    }

    /**
     * Stop scheduler
     */
    stop() {
        if (this.cronJob) {
            this.cronJob.stop();
            this.isRunning = false;
            logger.info('🛑 Report scheduler stopped');
        }
    }

    /**
     * Generate reports for users whose local time is at their scheduled time
     */
    async generateScheduledReports() {
        try {
            logger.info('📊 Checking for scheduled reports...');

            // Get users who should receive reports now
            const users = await timezoneManager.getUsersForReportGeneration();

            if (users.length === 0) {
                logger.info('  No users scheduled for reports at this time');
                return;
            }

            logger.info(`  📤 Generating reports for ${users.length} users`);

            // Generate reports for each user
            const results = await Promise.allSettled(
                users.map(user => this.generateReportForUser(user))
            );

            // Log results
            const successful = results.filter(r => r.status === 'fulfilled').length;
            const failed = results.filter(r => r.status === 'rejected').length;

            logger.info(`  ✅ Generated ${successful} reports successfully`);
            if (failed > 0) {
                logger.warn(`  ⚠️ Failed to generate ${failed} reports`);
            }

        } catch (error) {
            logger.error('❌ Scheduled report generation failed:', error);
        }
    }

    /**
     * Generate report for a single user
     * @param {Object} user - User object with id, email, timezone
     * @returns {Promise<Object>} Generation result
     */
    async generateReportForUser(user) {
        const { user_id, email, name, timezone } = user;

        try {
            logger.info(`  📝 Generating report for user ${user_id} (${email})`);

            // Calculate date range (past 7 days)
            const endDate = new Date();
            const startDate = new Date();
            startDate.setDate(endDate.getDate() - 7);

            // Generate all reports
            const activityHtml = await activityGenerator.generateReport(user_id, startDate, endDate);
            const improvementHtml = await improvementGenerator.generateReport(user_id, startDate, endDate);

            // TODO: Store reports in database or send via email

            logger.info(`  ✅ Report generated for user ${user_id}`);

            return {
                success: true,
                userId: user_id,
                reportDate: new Date()
            };

        } catch (error) {
            logger.error(`  ❌ Failed to generate report for user ${user_id}:`, error);
            throw error;
        }
    }

    /**
     * Manual trigger for testing
     * @param {string} userId - User UUID
     * @returns {Promise<Object>} Generation result
     */
    async generateReportNow(userId) {
        const timezone = await timezoneManager.getUserTimezone(userId);

        const user = {
            user_id: userId,
            email: 'test@example.com',
            name: 'Test User',
            timezone
        };

        return await this.generateReportForUser(user);
    }
}

module.exports = new ReportScheduler();
