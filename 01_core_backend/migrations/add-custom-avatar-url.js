/**
 * Migration: Add custom_avatar_url column to profiles table
 * Run with: node migrations/add-custom-avatar-url.js
 */

require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

async function runMigration() {
  const client = await pool.connect();

  try {
    console.log('🔄 Starting migration: Add custom_avatar_url column...');

    // Check if column exists
    const checkResult = await client.query(`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name = 'profiles'
      AND column_name = 'custom_avatar_url'
    `);

    if (checkResult.rows.length > 0) {
      console.log('✅ Column custom_avatar_url already exists');
      return;
    }

    // Add column
    await client.query(`
      ALTER TABLE profiles
      ADD COLUMN custom_avatar_url TEXT
    `);

    console.log('✅ Successfully added custom_avatar_url column to profiles table');

    // Add comment
    await client.query(`
      COMMENT ON COLUMN profiles.custom_avatar_url
      IS 'URL for custom uploaded avatar image (data URL or external URL)'
    `);

    console.log('✅ Migration completed successfully');

  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

runMigration()
  .then(() => {
    console.log('✅ Migration script finished');
    process.exit(0);
  })
  .catch(err => {
    console.error('❌ Migration script failed:', err);
    process.exit(1);
  });
