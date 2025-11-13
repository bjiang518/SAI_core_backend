#!/usr/bin/env node

/**
 * Quick Fix: Add missing columns to questions table
 */

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { db } = require('../src/utils/railway-database');

async function fixQuestionsTable() {
  try {
    console.log('🔧 Fixing questions table schema...');

    const migrationSQL = fs.readFileSync(
      path.join(__dirname, '../src/migrations/fix_questions_table.sql'),
      'utf8'
    );

    await db.query(migrationSQL);

    console.log('✅ Migration applied successfully!');

    // Verify columns
    const result = await db.query(`
      SELECT column_name, data_type
      FROM information_schema.columns
      WHERE table_name = 'questions'
      ORDER BY ordinal_position
    `);

    console.log('\n📋 Questions table columns:');
    result.rows.forEach(row => {
      console.log(`  - ${row.column_name}: ${row.data_type}`);
    });

    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  }
}

fixQuestionsTable();
