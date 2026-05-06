/**
 * Strip ```asy / ```asymptote blocks from question text for ALL sources.
 * Marks stripped rows with figure_mime='needs_scrape'.
 *
 * Usage:
 *   railway run --environment staging node src/scripts/cleanup-asy-blocks.js
 *   railway run --environment staging node src/scripts/cleanup-asy-blocks.js --dry-run
 *   railway run --environment staging node src/scripts/cleanup-asy-blocks.js --source=aime
 */

'use strict';

require('dotenv').config();
const { Pool } = require('pg');

const DRY_RUN = process.argv.includes('--dry-run');
const SOURCE  = (() => {
  const f = process.argv.find(a => a.startsWith('--source='));
  return f ? f.split('=')[1] : null;
})();

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

function stripAsyBlock(text) {
  const hadAsy = /```(?:asy|asymptote)/i.test(text);
  const cleaned = text.replace(/```(?:asy|asymptote)[\s\S]*?```/gi, '').trim();
  return { cleaned, hadAsy };
}

(async () => {
  const client = await pool.connect();
  try {
    const sourceClause = SOURCE ? `AND source = '${SOURCE}'` : '';
    const { rows } = await client.query(
      `SELECT id, source, question FROM question_bank WHERE 1=1 ${sourceClause}`
    );

    const toUpdate = rows
      .map(r => ({ ...r, ...stripAsyBlock(r.question) }))
      .filter(r => r.hadAsy);

    console.log(`Rows scanned          : ${rows.length}`);
    console.log(`Rows with asy blocks  : ${toUpdate.length}`);

    const bySource = toUpdate.reduce((a, r) => { a[r.source] = (a[r.source] || 0) + 1; return a; }, {});
    console.log(`By source             :`, bySource);

    if (DRY_RUN) {
      console.log('\nDRY RUN — first 3 samples:\n');
      toUpdate.slice(0, 3).forEach(r => {
        console.log(`  [${r.source}] before: ${r.question.slice(0, 80).replace(/\n/g,' ')}…`);
        console.log(`           after : ${r.cleaned.slice(0, 80).replace(/\n/g,' ')}…\n`);
      });
      return;
    }

    let updated = 0;
    for (const row of toUpdate) {
      await client.query(
        `UPDATE question_bank SET question = $1, figure_mime = 'needs_scrape' WHERE id = $2`,
        [row.cleaned, row.id]
      );
      updated++;
      if (updated % 50 === 0) process.stdout.write(`\r  updated ${updated}/${toUpdate.length}`);
    }
    console.log(`\n✅ Stripped asy blocks and marked ${toUpdate.length} rows for figure scraping.`);

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
