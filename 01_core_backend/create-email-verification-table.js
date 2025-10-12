/**
 * Quick migration script to create email_verifications table
 * Run this to add the table without redeploying
 */

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

async function createEmailVerificationTable() {
  console.log('🔧 Creating email_verifications table...');

  const query = `
    -- Email verifications table for email verification codes
    CREATE TABLE IF NOT EXISTS email_verifications (
      id SERIAL PRIMARY KEY,
      email VARCHAR(255) NOT NULL UNIQUE,
      code VARCHAR(6) NOT NULL,
      name VARCHAR(255) NOT NULL,
      attempts INTEGER DEFAULT 0,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      expires_at TIMESTAMP WITH TIME ZONE NOT NULL
    );

    -- Email verifications indexes
    CREATE INDEX IF NOT EXISTS idx_email_verifications_email ON email_verifications(email);
    CREATE INDEX IF NOT EXISTS idx_email_verifications_expires ON email_verifications(expires_at);
  `;

  try {
    await pool.query(query);
    console.log('✅ email_verifications table created successfully!');
    console.log('✅ Indexes created successfully!');
    console.log('');
    console.log('🎉 You can now use email verification in your app!');
  } catch (error) {
    console.error('❌ Error creating table:', error.message);
    process.exit(1);
  } finally {
    await pool.end();
    process.exit(0);
  }
}

createEmailVerificationTable();
