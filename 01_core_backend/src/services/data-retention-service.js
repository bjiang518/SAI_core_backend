/**
 * Data Retention Policy Service
 * COPPA and GDPR Compliance - Automatic data deletion
 *
 * - Soft deletes data older than 90 days (retention policy)
 * - Hard deletes soft-deleted data after 30 days
 * - Runs daily at midnight
 */

const { db } = require('../utils/railway-database');
const cron = require('node-cron');

class DataRetentionService {
  constructor() {
    this.isRunning = false;
    this.cronJob = null;
    this.lastRun = null;
    this.stats = {
      totalSoftDeleted: 0,
      totalHardDeleted: 0,
      lastSoftDelete: null,
      lastHardDelete: null
    };
  }

  /**
   * Initialize the retention policy service
   * Schedules daily cleanup at midnight
   */
  async initialize() {
    console.log('📅 Initializing Data Retention Policy Service...');

    // Schedule daily cleanup at midnight (00:00)
    this.cronJob = cron.schedule('0 0 * * *', async () => {
      await this.runRetentionPolicy();
    });

    console.log('✅ Data Retention Policy Service initialized');
    console.log('📅 Scheduled to run daily at midnight (00:00)');

    // Run once immediately on startup (optional - comment out if not needed)
    // await this.runRetentionPolicy();

    return this;
  }

  /**
   * Run the complete retention policy
   * 1. Soft delete expired data (> 90 days)
   * 2. Hard delete soft-deleted data (> 30 days after soft delete)
   */
  async runRetentionPolicy() {
    if (this.isRunning) {
      console.log('⚠️ Retention policy already running, skipping...');
      return;
    }

    this.isRunning = true;
    const startTime = Date.now();

    console.log('🗑️  === DATA RETENTION POLICY EXECUTION ===');
    console.log(`📅 Started at: ${new Date().toISOString()}`);

    try {
      // Step 1: Soft delete expired data (> 90 days)
      const softDeleteResults = await this.softDeleteExpiredData();

      // Step 2: Hard delete soft-deleted data (> 30 days)
      const hardDeleteResults = await this.hardDeleteOldData();

      // Update stats
      this.lastRun = new Date();
      this.stats.lastSoftDelete = softDeleteResults;
      this.stats.lastHardDelete = hardDeleteResults;

      const duration = Date.now() - startTime;
      console.log(`✅ Retention policy completed in ${duration}ms`);
      console.log(`📊 Soft deleted: ${JSON.stringify(softDeleteResults)}`);
      console.log(`📊 Hard deleted: ${JSON.stringify(hardDeleteResults)}`);
      console.log('====================================');

      return {
        success: true,
        duration,
        softDelete: softDeleteResults,
        hardDelete: hardDeleteResults
      };

    } catch (error) {
      console.error('❌ Error running retention policy:', error);
      return {
        success: false,
        error: error.message
      };
    } finally {
      this.isRunning = false;
    }
  }

  /**
   * Soft delete data older than 90 days
   * Sets deleted_at timestamp but keeps data for 30-day recovery period
   */
  async softDeleteExpiredData() {
    console.log('🔄 Step 1: Soft deleting expired data (> 90 days)...');

    try {
      const result = await db.query('SELECT * FROM soft_delete_expired_data()');

      const stats = {};
      result.rows.forEach(row => {
        stats[row.table_name] = parseInt(row.deleted_count);
        this.stats.totalSoftDeleted += parseInt(row.deleted_count);
      });

      console.log(`✅ Soft delete completed: ${JSON.stringify(stats)}`);
      return stats;

    } catch (error) {
      console.error('❌ Error in soft delete:', error);
      throw error;
    }
  }

  /**
   * Hard delete data that was soft-deleted > 30 days ago
   * Permanent deletion for GDPR "right to be forgotten"
   */
  async hardDeleteOldData() {
    console.log('🔄 Step 2: Hard deleting old soft-deleted data (> 30 days)...');

    try {
      const result = await db.query('SELECT * FROM hard_delete_old_soft_deleted()');

      const stats = {};
      result.rows.forEach(row => {
        stats[row.table_name] = parseInt(row.purged_count);
        this.stats.totalHardDeleted += parseInt(row.purged_count);
      });

      console.log(`✅ Hard delete completed: ${JSON.stringify(stats)}`);
      return stats;

    } catch (error) {
      console.error('❌ Error in hard delete:', error);
      throw error;
    }
  }

  /**
   * Manual user data deletion (GDPR Article 17 - Right to be forgotten)
   * @param {string} userId - User ID to delete all data for
   */
  async deleteUserData(userId) {
    console.log(`🗑️  Deleting all data for user: ${userId}`);

    try {
      // Soft delete all user data immediately
      await db.query(`
        UPDATE archived_conversations_new
        SET deleted_at = CURRENT_TIMESTAMP
        WHERE user_id = $1 AND deleted_at IS NULL
      `, [userId]);

      await db.query(`
        UPDATE question_sessions
        SET deleted_at = CURRENT_TIMESTAMP
        WHERE user_id = $1 AND deleted_at IS NULL
      `, [userId]);

      await db.query(`
        UPDATE sessions
        SET deleted_at = CURRENT_TIMESTAMP
        WHERE user_id = $1 AND deleted_at IS NULL
      `, [userId]);

      console.log(`✅ User data marked for deletion: ${userId}`);
      console.log(`ℹ️  Data will be permanently deleted in 30 days`);

      return {
        success: true,
        userId,
        message: 'All user data marked for deletion. Permanent deletion in 30 days.'
      };

    } catch (error) {
      console.error('❌ Error deleting user data:', error);
      throw error;
    }
  }

  /**
   * Get retention policy statistics
   */
  getStats() {
    return {
      isRunning: this.isRunning,
      lastRun: this.lastRun,
      stats: this.stats,
      nextRun: this.cronJob?.nextDate()?.toISOString() || 'Not scheduled'
    };
  }

  /**
   * Stop the retention policy service
   */
  stop() {
    if (this.cronJob) {
      this.cronJob.stop();
      console.log('🛑 Data Retention Policy Service stopped');
    }
  }

  /**
   * Trigger manual retention policy run (for testing or admin)
   */
  async triggerManual() {
    console.log('🔧 Manual retention policy trigger requested');
    return await this.runRetentionPolicy();
  }
}

// Export singleton instance
module.exports = new DataRetentionService();
