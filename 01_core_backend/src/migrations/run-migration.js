/**
 * One-shot migration runner — runs a specific .sql file against the DATABASE_URL.
 * Usage:  node src/migrations/run-migration.js 20260324_promo_codes.sql
 *   or:   railway run node src/migrations/run-migration.js 20260324_promo_codes.sql
 */

const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

const file = process.argv[2];
if (!file) {
  console.error('Usage: node run-migration.js <filename.sql>');
  process.exit(1);
}

const sqlPath = path.join(__dirname, file);
if (!fs.existsSync(sqlPath)) {
  console.error(`File not found: ${sqlPath}`);
  process.exit(1);
}

const sql = fs.readFileSync(sqlPath, 'utf8');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

(async () => {
  const client = await pool.connect();
  try {
    console.log(`Running migration: ${file}`);
    await client.query(sql);
    console.log('✅ Migration complete.');
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
})();
