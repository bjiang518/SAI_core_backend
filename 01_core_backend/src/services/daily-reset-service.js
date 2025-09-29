/**
 * Daily Reset Service for StudyAI
 * Handles automated daily reset of progress tracking data at midnight UTC
 */

const cron = require('node-cron');
const { db } = require('../utils/railway-database');

class DailyResetService {
    constructor() {
        this.cronJobs = new Map();
        this.isInitialized = false;
        this.lastResetDate = null;
        this.resetInProgress = false;
    }

    /**
     * Initialize the daily reset service
     */
    async initialize() {
        if (this.isInitialized) {
            console.log('⚠️ Daily Reset Service already initialized');
            return;
        }

        try {
            console.log('🕒 Initializing Daily Reset Service...');

            // Setup midnight reset cron job (runs at 12:00 AM UTC every day)
            this.setupMidnightResetJob();

            // Setup periodic health check
            this.setupHealthCheckJob();

            // Check if we need to perform an immediate reset on startup
            await this.checkStartupReset();

            this.isInitialized = true;
            console.log('✅ Daily Reset Service initialized successfully');

        } catch (error) {
            console.error('❌ Failed to initialize Daily Reset Service:', error);
            throw error;
        }
    }

    /**
     * Setup the midnight reset cron job
     */
    setupMidnightResetJob() {
        // Run at 12:00 AM UTC every day
        const midnightJob = cron.schedule('0 0 * * *', async () => {
            await this.performDailyReset();
        }, {
            scheduled: true,
            timezone: 'UTC'
        });

        this.cronJobs.set('midnight-reset', midnightJob);
        console.log('🕛 Scheduled daily reset for 12:00 AM UTC');
    }

    /**
     * Setup health check job (runs every 6 hours)
     */
    setupHealthCheckJob() {
        const healthCheckJob = cron.schedule('0 */6 * * *', async () => {
            await this.performHealthCheck();
        }, {
            scheduled: true,
            timezone: 'UTC'
        });

        this.cronJobs.set('health-check', healthCheckJob);
        console.log('🏥 Scheduled health check every 6 hours');
    }

    /**
     * Check if we need to perform a reset on startup
     */
    async checkStartupReset() {
        try {
            const today = new Date().toISOString().split('T')[0];

            // Check if we have any activity recorded for today
            const todayActivityCheck = await db.query(`
                SELECT COUNT(*) as activity_count
                FROM daily_subject_activities
                WHERE activity_date = $1
            `, [today]);

            const activityCount = parseInt(todayActivityCheck.rows[0]?.activity_count || 0);

            if (activityCount > 0) {
                console.log(`📊 Found ${activityCount} daily activities for today - no startup reset needed`);
                this.lastResetDate = today;
            } else {
                console.log('🔄 No daily activities found for today - checking if reset is needed');

                // Check the last recorded activity date
                const lastActivityCheck = await db.query(`
                    SELECT MAX(activity_date) as last_date
                    FROM daily_subject_activities
                `);

                const lastDate = lastActivityCheck.rows[0]?.last_date;

                if (lastDate) {
                    const lastDateString = lastDate.toISOString().split('T')[0];
                    if (lastDateString < today) {
                        console.log(`🕒 Last activity was on ${lastDateString}, performing startup reset for ${today}`);
                        await this.performDailyReset();
                    }
                } else {
                    console.log('📝 No previous activity found - fresh database state');
                }
            }
        } catch (error) {
            console.error('❌ Error checking startup reset:', error);
        }
    }

    /**
     * Perform the daily reset operation
     */
    async performDailyReset(force = false) {
        if (this.resetInProgress) {
            console.log('⚠️ Daily reset already in progress, skipping...');
            return;
        }

        this.resetInProgress = true;
        const startTime = Date.now();
        const today = new Date().toISOString().split('T')[0];

        try {
            console.log('🔄 ==> DAILY RESET STARTING <==');
            console.log(`📅 Reset date: ${today}`);
            console.log(`🕒 Reset time: ${new Date().toISOString()}`);
            console.log(`🔧 Force reset: ${force}`);

            // Check if we've already reset today (unless forced)
            if (!force && this.lastResetDate === today) {
                console.log('✅ Daily reset already performed today, skipping');
                return;
            }

            if (force && this.lastResetDate === today) {
                console.log('🔧 Forcing reset even though already performed today');
            }

            const resetStats = {
                usersAffected: 0,
                dailyActivitiesReset: 0,
                subjectProgressUpdated: 0,
                errorsEncountered: 0
            };

            await db.transaction(async (client) => {
                console.log('📊 Starting daily reset transaction...');

                // Step 1: Get all users who had activity yesterday
                const usersWithActivityQuery = `
                    SELECT DISTINCT user_id, COUNT(*) as activity_count
                    FROM daily_subject_activities
                    WHERE activity_date < $1
                    GROUP BY user_id
                `;

                const usersResult = await client.query(usersWithActivityQuery, [today]);
                resetStats.usersAffected = usersResult.rows.length;

                console.log(`👥 Found ${resetStats.usersAffected} users with previous activity`);

                // Step 2: Archive/backup previous day's data (optional - for analytics)
                const yesterday = new Date();
                yesterday.setDate(yesterday.getDate() - 1);
                const yesterdayString = yesterday.toISOString().split('T')[0];

                // Step 3: Reset daily subject activities for all users
                // We need to reset today's activities to zero for all users
                // This ensures each user has a fresh start for daily tracking

                console.log('🔄 Resetting daily subject activities...');

                // First, reset TODAY's activities to zero for all users
                const resetTodayQuery = `
                    UPDATE daily_subject_activities
                    SET questions_attempted = 0,
                        questions_correct = 0,
                        time_spent = 0,
                        points_earned = 0
                    WHERE activity_date = $1
                `;
                const resetTodayResult = await client.query(resetTodayQuery, [today]);
                console.log(`🔄 Reset today's activities for ${resetTodayResult.rowCount} user-subject combinations`);

                // Alternatively, delete today's records entirely (cleaner approach)
                const deleteTodayQuery = `
                    DELETE FROM daily_subject_activities
                    WHERE activity_date = $1
                `;
                const deleteTodayResult = await client.query(deleteTodayQuery, [today]);
                console.log(`🗑️ Deleted ${deleteTodayResult.rowCount} today's activity records for fresh start`);

                // Clear out old daily activities (keep last 30 days for analytics)
                const cleanupQuery = `
                    DELETE FROM daily_subject_activities
                    WHERE activity_date < $1
                `;
                const thirtyDaysAgo = new Date();
                thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
                const cleanupResult = await client.query(cleanupQuery, [thirtyDaysAgo.toISOString().split('T')[0]]);

                console.log(`🗑️ Cleaned up ${cleanupResult.rowCount} old daily activity records`);

                // Step 4: Update subject progress for streak calculations
                console.log('📈 Updating subject progress streaks...');

                // For each user, update their streak based on yesterday's activity
                for (const userRow of usersResult.rows) {
                    const userId = userRow.user_id;

                    try {
                        // Check if user had activity yesterday
                        const yesterdayActivityQuery = `
                            SELECT SUM(questions_attempted) as total_questions
                            FROM daily_subject_activities
                            WHERE user_id = $1 AND activity_date = $2
                        `;

                        const yesterdayResult = await client.query(yesterdayActivityQuery, [userId, yesterdayString]);
                        const hadActivityYesterday = (yesterdayResult.rows[0]?.total_questions || 0) > 0;

                        // Update streak count in subject_progress table
                        if (hadActivityYesterday) {
                            // Continue/increment streak for all subjects the user studied
                            const updateStreakQuery = `
                                UPDATE subject_progress
                                SET streak_count = streak_count + 1,
                                    updated_at = NOW()
                                WHERE user_id = $1
                            `;
                            await client.query(updateStreakQuery, [userId]);
                        } else {
                            // Reset streak to 0 for users who didn't study yesterday
                            const resetStreakQuery = `
                                UPDATE subject_progress
                                SET streak_count = 0,
                                    updated_at = NOW()
                                WHERE user_id = $1
                            `;
                            await client.query(resetStreakQuery, [userId]);
                        }

                        resetStats.subjectProgressUpdated++;

                    } catch (userError) {
                        console.error(`❌ Error updating streaks for user ${userId}:`, userError);
                        resetStats.errorsEncountered++;
                    }
                }

                // Step 5: Reset any other daily counters if needed
                // This could include daily goals, achievements, etc.
                console.log('🎯 Resetting daily goals and achievements...');

                // If we have additional daily reset tables, we would handle them here
                // For now, we focus on the core progress tracking

                console.log('✅ Daily reset transaction completed successfully');
            });

            // Update reset tracking
            this.lastResetDate = today;
            const duration = Date.now() - startTime;

            // Log reset summary
            console.log('📊 ==> DAILY RESET SUMMARY <==');
            console.log(`✅ Reset completed successfully in ${duration}ms`);
            console.log(`👥 Users affected: ${resetStats.usersAffected}`);
            console.log(`📈 Subject progress updated: ${resetStats.subjectProgressUpdated}`);
            console.log(`❌ Errors encountered: ${resetStats.errorsEncountered}`);
            console.log(`📅 Next reset: Tomorrow at 12:00 AM UTC`);
            console.log('🔄 ==> DAILY RESET COMPLETED <==');

        } catch (error) {
            const duration = Date.now() - startTime;
            console.error('❌ ==> DAILY RESET FAILED <==');
            console.error(`❌ Reset failed after ${duration}ms:`, error);
            console.error(`📅 Will retry tomorrow at 12:00 AM UTC`);

            // Don't throw - let the service continue running
        } finally {
            this.resetInProgress = false;
        }
    }

    /**
     * Perform health check
     */
    async performHealthCheck() {
        try {
            console.log('🏥 Daily Reset Service health check starting...');

            const healthStatus = {
                isRunning: this.isInitialized,
                lastResetDate: this.lastResetDate,
                resetInProgress: this.resetInProgress,
                activeJobs: this.cronJobs.size,
                timestamp: new Date().toISOString()
            };

            // Check database connectivity
            const dbCheck = await db.query('SELECT NOW() as current_time');
            healthStatus.databaseConnected = !!dbCheck.rows[0];

            // Check if we're missing a reset (should reset daily)
            const today = new Date().toISOString().split('T')[0];
            if (this.lastResetDate && this.lastResetDate < today) {
                console.log('⚠️ Daily reset appears to be behind schedule');
                healthStatus.resetBehind = true;

                // Trigger a manual reset
                await this.performDailyReset();
            } else {
                healthStatus.resetBehind = false;
            }

            console.log('✅ Daily Reset Service health check completed:', healthStatus);

        } catch (error) {
            console.error('❌ Daily Reset Service health check failed:', error);
        }
    }

    /**
     * Manual trigger for daily reset (for testing/admin purposes)
     */
    async triggerManualReset() {
        console.log('🔧 Manual daily reset triggered');
        await this.performDailyReset(true); // Force reset even if already done today
    }

    /**
     * Get service status
     */
    getStatus() {
        return {
            isInitialized: this.isInitialized,
            lastResetDate: this.lastResetDate,
            resetInProgress: this.resetInProgress,
            activeJobs: Array.from(this.cronJobs.keys()),
            nextResetTime: '12:00 AM UTC'
        };
    }

    /**
     * Stop the daily reset service
     */
    stop() {
        console.log('🛑 Stopping Daily Reset Service...');

        for (const [name, job] of this.cronJobs) {
            job.stop();
            job.destroy();
            console.log(`⏹️ Stopped cron job: ${name}`);
        }

        this.cronJobs.clear();
        this.isInitialized = false;

        console.log('✅ Daily Reset Service stopped');
    }
}

// Create singleton instance
const dailyResetService = new DailyResetService();

module.exports = {
    DailyResetService,
    dailyResetService
};