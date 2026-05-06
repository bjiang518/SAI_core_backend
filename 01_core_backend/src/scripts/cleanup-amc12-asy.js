/**
 * Two-step cleanup for AMC12 question bank:
 *
 * 1. Strip ```asy ... ``` blocks from question text (they're raw Asymptote code,
 *    not readable by students) and mark those rows as needing a figure scraped.
 * 2. Report counts so we know what to scrape next.
 *
 * Usage:
 *   railway run --environment staging node src/scripts/cleanup-amc12-asy.js
 *   railway run --environment staging node src/scripts/cleanup-amc12-asy.js --dry-run
 */

'use strict';

require('dotenv').config();
const { Pool } = require('pg');

const DRY_RUN = process.argv.includes('--dry-run');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// Strip ```asy ... ``` blocks (and ```asymptote ... ```) from question text.
// Returns { cleaned, hadAsy }
function stripAsyBlock(text) {
  const asyRegex = /```(?:asy|asymptote)[\s\S]*?```/gi;
  const hadAsy = asyRegex.test(text);
  const cleaned = text.replace(/```(?:asy|asymptote)[\s\S]*?```/gi, '').trim();
  return { cleaned, hadAsy };
}

(async () => {
  const client = await pool.connect();
  try {
    const { rows } = await client.query(
      `SELECT id, question FROM question_bank WHERE source = 'amc12'`
    );

    const toUpdate = rows
      .map(r => ({ ...r, ...stripAsyBlock(r.question) }))
      .filter(r => r.hadAsy);

    console.log(`AMC12 rows total      : ${rows.length}`);
    console.log(`Rows with asy blocks  : ${toUpdate.length}`);
    if (DRY_RUN) {
      console.log('DRY RUN — showing first 5 stripped questions:\n');
      toUpdate.slice(0, 5).forEach(r => {
        console.log(`  ID: ${r.id}`);
        console.log(`  Before: ${r.question.slice(0, 100).replace(/\n/g, ' ')}…`);
        console.log(`  After : ${r.cleaned.slice(0, 100).replace(/\n/g, ' ')}…\n`);
      });
      return;
    }

    // Update in batches of 50
    let updated = 0;
    for (let i = 0; i < toUpdate.length; i += 50) {
      const batch = toUpdate.slice(i, i + 50);
      for (const row of batch) {
        await client.query(
          // Store cleaned text; use figure_mime='needs_scrape' as marker for scraper
          `UPDATE question_bank
           SET question = $1, figure_mime = 'needs_scrape'
           WHERE id = $2`,
          [row.cleaned, row.id]
        );
      }
      updated += batch.length;
      process.stdout.write(`\r  updated ${updated}/${toUpdate.length}`);
    }
    console.log(`\n✅ Stripped asy blocks and marked ${toUpdate.length} rows for figure scraping.`);

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
