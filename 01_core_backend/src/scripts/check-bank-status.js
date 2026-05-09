'use strict';
require('dotenv').config();
const { Pool } = require('pg');
const p = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });

Promise.all([
  p.query(`SELECT
      COUNT(*)                                                    AS total,
      COUNT(*) FILTER (WHERE embedding   IS NOT NULL)            AS embedded,
      COUNT(*) FILTER (WHERE figure_data IS NOT NULL)            AS with_fig,
      COUNT(*) FILTER (WHERE base_branch IS NULL OR base_branch = '') AS untagged,
      COUNT(*) FILTER (WHERE subject     IS NULL OR subject     = '') AS no_subject
    FROM question_bank`),

  p.query(`SELECT subject,
      COUNT(*)                                                     AS n,
      COUNT(*) FILTER (WHERE base_branch IS NOT NULL AND base_branch != '') AS tagged,
      COUNT(*) FILTER (WHERE figure_data IS NOT NULL)              AS figs,
      COUNT(*) FILTER (WHERE embedding   IS NOT NULL)              AS emb
    FROM question_bank
    GROUP BY subject ORDER BY n DESC`),

  p.query(`SELECT source,
      COUNT(*)                                                     AS n,
      COUNT(*) FILTER (WHERE base_branch IS NOT NULL AND base_branch != '') AS tagged,
      COUNT(*) FILTER (WHERE figure_data IS NOT NULL)              AS figs,
      COUNT(*) FILTER (WHERE embedding   IS NOT NULL)              AS emb,
      ROUND(AVG(difficulty), 1)                                    AS avg_diff
    FROM question_bank
    GROUP BY source ORDER BY n DESC`),

  p.query(`SELECT source, COUNT(*) AS untagged
    FROM question_bank
    WHERE base_branch IS NULL OR base_branch = ''
    GROUP BY source ORDER BY untagged DESC`),

  p.query(`SELECT base_branch, COUNT(*) AS n
    FROM question_bank
    WHERE base_branch IS NOT NULL AND base_branch != ''
    GROUP BY base_branch ORDER BY n DESC LIMIT 20`),

  p.query(`SELECT difficulty, COUNT(*) AS n
    FROM question_bank GROUP BY difficulty ORDER BY difficulty`),

  p.query(`SELECT question_type, COUNT(*) AS n
    FROM question_bank GROUP BY question_type`),

]).then(([tot, bySub, bySrc, untagged, topBranch, byDiff, byType]) => {
  const t = tot.rows[0];
  const pct = (a, b) => Math.round(Number(a) / Number(b) * 100) + '%';

  console.log('╔══════════════════════════════════════════════════╗');
  console.log('║          QUESTION BANK STATUS                    ║');
  console.log('╚══════════════════════════════════════════════════╝');
  console.log(`  Total rows :  ${t.total}`);
  console.log(`  Embedded   :  ${t.embedded}  (${pct(t.embedded, t.total)})`);
  console.log(`  With figure:  ${t.with_fig}  (${pct(t.with_fig, t.total)})`);
  console.log(`  Untagged   :  ${t.untagged}  (${pct(t.untagged, t.total)})  ← base_branch missing`);
  console.log(`  No subject :  ${t.no_subject}`);

  console.log('\n── BY SUBJECT ── (n | tagged | figs | emb)');
  bySub.rows.forEach(r =>
    console.log(
      String(r.n).padStart(7),
      (r.subject || '(null)').padEnd(20),
      'tagged:' + String(r.tagged).padStart(6),
      ' figs:' + String(r.figs).padStart(6),
      ' emb:' + String(r.emb).padStart(6),
    )
  );

  console.log('\n── BY SOURCE ── (n | tagged | figs | avg_diff)');
  bySrc.rows.forEach(r =>
    console.log(
      String(r.n).padStart(7),
      String(r.source || 'null').padEnd(14),
      'tagged:' + String(r.tagged).padStart(6),
      ' figs:' + String(r.figs).padStart(6),
      ' diff:' + r.avg_diff,
    )
  );

  console.log('\n── UNTAGGED BY SOURCE ──');
  if (!untagged.rows.length) {
    console.log('  ✅ All rows have base_branch!');
  } else {
    untagged.rows.forEach(r =>
      console.log(' ', String(r.untagged).padStart(7), r.source)
    );
  }

  console.log('\n── TOP 20 base_branch ──');
  topBranch.rows.forEach(r =>
    console.log(String(r.n).padStart(7), r.base_branch)
  );

  console.log('\n── DIFFICULTY DISTRIBUTION (1=easy … 5=hard) ──');
  const bar = (n, max) => '█'.repeat(Math.round(Number(n) / max * 30));
  const maxN = Math.max(...byDiff.rows.map(r => Number(r.n)));
  byDiff.rows.forEach(r =>
    console.log(`  ${r.difficulty}  ${String(r.n).padStart(6)}  ${bar(r.n, maxN)}`)
  );

  console.log('\n── QUESTION TYPE ──');
  byType.rows.forEach(r =>
    console.log(' ', String(r.n).padStart(7), r.question_type || '(null)')
  );

  p.end();
}).catch(e => { console.error('Error:', e.message); p.end(); process.exit(1); });
