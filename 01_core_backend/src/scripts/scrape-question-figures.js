/**
 * Scrape geometric figures from Art of Problem Solving wiki pages
 * for AMC12 problems that contain figure references.
 *
 * Stores image bytes as base64 in question_bank.figure_data.
 *
 * Usage:
 *   railway run --environment staging node src/scripts/scrape-question-figures.js
 *   railway run --environment staging node src/scripts/scrape-question-figures.js --dry-run
 *   railway run --environment staging node src/scripts/scrape-question-figures.js --limit=20
 */

'use strict';

require('dotenv').config();
const https  = require('https');
const http   = require('http');
const { Pool } = require('pg');

const DRY_RUN = process.argv.includes('--dry-run');
const LIMIT   = (() => {
  const f = process.argv.find(a => a.startsWith('--limit='));
  return f ? parseInt(f.split('=')[1], 10) : Infinity;
})();

// Delay between AoPS requests — be polite to their servers
const REQUEST_DELAY_MS = 1500;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// ---------------------------------------------------------------------------
// HTTP fetch with redirect support
// ---------------------------------------------------------------------------
function fetch(url, redirects = 0) {
  if (redirects > 10) return Promise.reject(new Error('Too many redirects'));
  const lib = url.startsWith('https') ? https : http;
  return new Promise((resolve, reject) => {
    lib.get(url, { headers: { 'User-Agent': 'StudyAI-figure-scraper/1.0' } }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const next = res.headers.location.startsWith('http')
          ? res.headers.location
          : new URL(res.headers.location, url).href;
        res.resume();
        return resolve(fetch(next, redirects + 1));
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
      res.on('error', reject);
    }).on('error', reject);
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------------------------------------------------------------------------
// Figure detection — text patterns + asy marker from cleanup script
// ---------------------------------------------------------------------------
const FIGURE_PATTERNS = [
  /\bfigure\b/i, /\bdiagram\b/i, /\bshown (above|below|at right|at left)\b/i,
  /\bas shown\b/i, /\bin the (graph|chart|image|picture)\b/i, /\bsee (figure|diagram)\b/i,
  /\bthe (graph|chart) (above|below)\b/i,
];
const hasFigureReference = q => FIGURE_PATTERNS.some(p => p.test(q));

// ---------------------------------------------------------------------------
// Build AoPS wiki URL from source_id (AMC12 and AIME)
//
// AMC12 source_id: "2003A-P15"  → 2003_AMC_12A_Problems/Problem_15
//                  "2001A-P5"   → 2001_AMC_12_Problems/Problem_5  (no A/B before 2002)
//
// AIME  source_id: "1990-I-5"   → 1990_AIME_Problems/Problem_5   (no I/II before 2000)
//                  "2002-I-5"   → 2002_AIME_I_Problems/Problem_5
//                  "2005-II-12" → 2005_AIME_II_Problems/Problem_12
// ---------------------------------------------------------------------------
function sourceIdToAoPSUrl(source, sourceId) {
  if (!sourceId) return null;

  if (source === 'amc12') {
    const m = sourceId.match(/^(\d{4})([AB])-P(\d+)$/);
    if (!m) return null;
    const [, year, part, num] = m;
    const suffix = parseInt(year, 10) < 2002 ? '' : part;
    return `https://artofproblemsolving.com/wiki/index.php/${year}_AMC_12${suffix}_Problems/Problem_${num}`;
  }

  if (source === 'aime') {
    const m = sourceId.match(/^(\d{4})-(I{1,2})-(\d+)$/);
    if (!m) return null;
    const [, year, part, num] = m;
    const yearNum = parseInt(year, 10);
    // AIME II was introduced in 2000
    const suffix = yearNum < 2000 ? '' : `_${part}`;
    return `https://artofproblemsolving.com/wiki/index.php/${year}_AIME${suffix}_Problems/Problem_${num}`;
  }

  return null;
}

// ---------------------------------------------------------------------------
// Extract figure image URL from AoPS wiki HTML.
// Asymptote figures use class="latexcenter" (rendered by AoPS latex service).
// Inline math uses class="latex" — we skip those.
// ---------------------------------------------------------------------------
function extractFigureUrl(html, pageUrl) {
  const base = 'https:';

  // Target only latexcenter images (Asymptote figures)
  const figureRegex = /<img[^>]+class="latexcenter"[^>]+>/gi;
  const imgSrcRegex = /src="([^"]+)"/i;

  let m;
  while ((m = figureRegex.exec(html)) !== null) {
    const srcMatch = imgSrcRegex.exec(m[0]);
    if (!srcMatch) continue;
    const src = srcMatch[1];
    // Resolve protocol-relative URLs (//latex.artofproblemsolving.com/...)
    return src.startsWith('//') ? base + src : src;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Fetch image bytes and return {base64, mime}
// ---------------------------------------------------------------------------
async function downloadImage(imgUrl) {
  const res = await fetch(imgUrl);
  if (res.status !== 200) throw new Error(`HTTP ${res.status} for ${imgUrl}`);

  const contentType = res.headers['content-type'] || 'image/png';
  const mime = contentType.split(';')[0].trim();
  const base64 = res.body.toString('base64');
  return { base64, mime };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    // Fetch AMC12 + AIME rows that need figures
    const { rows } = await client.query(`
      SELECT id, source, source_id, question
      FROM question_bank
      WHERE source IN ('amc12', 'aime')
        AND figure_data IS NULL
        AND (figure_mime = 'needs_scrape' OR question ~* '\\mfigure\\M|\\mdiagram\\M|as shown|in the graph')
      ORDER BY source, source_id
    `);

    const targets = rows
      .filter(r => sourceIdToAoPSUrl(r.source, r.source_id))
      .slice(0, LIMIT);

    console.log(`\n📐 Figure scrape plan:`);
    console.log(`   AMC12 rows without figure_data : ${rows.length}`);
    console.log(`   Figure-referenced + valid URL  : ${targets.length}`);
    if (DRY_RUN) { console.log('   DRY RUN — no writes'); }
    console.log();

    let success = 0, notFound = 0, errors = 0;

    for (let i = 0; i < targets.length; i++) {
      const row = targets[i];
      const pageUrl = sourceIdToAoPSUrl(row.source, row.source_id);

      process.stdout.write(`[${i + 1}/${targets.length}] ${row.source_id} … `);

      try {
        // 1. Fetch the AoPS wiki page
        const pageRes = await fetch(pageUrl);
        if (pageRes.status !== 200) {
          console.log(`SKIP (HTTP ${pageRes.status})`);
          notFound++;
          await sleep(REQUEST_DELAY_MS);
          continue;
        }

        const html = pageRes.body.toString('utf8');

        // 2. Extract figure image URL
        const imgUrl = extractFigureUrl(html, pageUrl);
        if (!imgUrl) {
          console.log('no figure found');
          notFound++;
          await sleep(REQUEST_DELAY_MS);
          continue;
        }

        // 3. Download image
        const { base64, mime } = await downloadImage(imgUrl);

        if (DRY_RUN) {
          console.log(`found: ${imgUrl.slice(0, 80)} (${Math.round(base64.length * 0.75 / 1024)}KB)`);
        } else {
          // 4. Store in DB
          await client.query(
            `UPDATE question_bank SET figure_data = $1, figure_mime = $2 WHERE id = $3`,
            [base64, mime, row.id]
          );
          console.log(`✅ ${mime} ${Math.round(base64.length * 0.75 / 1024)}KB`);
          success++;
        }

      } catch (err) {
        console.log(`❌ ${err.message}`);
        errors++;
      }

      await sleep(REQUEST_DELAY_MS);
    }

    console.log(`\n📊 Results: ${success} saved, ${notFound} no figure, ${errors} errors`);

    if (!DRY_RUN) {
      const { rows: [{ count }] } = await client.query(
        `SELECT COUNT(*) FROM question_bank WHERE figure_data IS NOT NULL`
      );
      console.log(`   question_bank rows with figures: ${count}`);
    }

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
