/**
 * Patch missing ScienceQA figure_data in question_bank.
 *
 * Root cause: the original import called http.get() on `data:image/...;base64,...`
 * URLs returned by the HuggingFace datasets-server API — those always fail because
 * they are not HTTP URLs. This script re-fetches each split page-by-page, extracts
 * the base64 image directly from the data: URL (or downloads it when it's a real
 * https:// CDN URL), and UPDATEs the matching row.
 *
 * Usage:
 *   railway run node src/scripts/patch-scienceqa-figures.js
 *   railway run node src/scripts/patch-scienceqa-figures.js --dry-run
 *   railway run node src/scripts/patch-scienceqa-figures.js --split=train
 *   railway run node src/scripts/patch-scienceqa-figures.js --concurrency=20
 */

'use strict';

require('dotenv').config();
const https = require('https');
const http  = require('http');
const { Pool } = require('pg');

const DRY_RUN     = process.argv.includes('--dry-run');
const SPLIT_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--split=')); return f ? f.split('=')[1] : null; })();
const CONCURRENCY  = (() => { const f = process.argv.find(a => a.startsWith('--concurrency=')); return f ? parseInt(f.split('=')[1]) : 10; })();
const HF_PAGE_SIZE = 100;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  max: 5,
  statement_timeout: 60000,
  query_timeout: 60000,
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function fetchJson(url, retries = 4) {
  return new Promise((resolve, reject) => {
    const headers = { 'User-Agent': 'Mozilla/5.0', Accept: 'application/json' };
    if (process.env.HF_TOKEN) headers['Authorization'] = `Bearer ${process.env.HF_TOKEN}`;
    const attempt = (n) => {
      https.get(url, { headers }, res => {
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', async () => {
          const body = Buffer.concat(chunks).toString();
          if (res.statusCode === 429 || body.trim().startsWith('<')) {
            if (n > 0) { await sleep((5 - n) * 4000); return attempt(n - 1); }
            return reject(new Error(`Rate limited (${url.slice(0, 80)})`));
          }
          try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
        });
        res.on('error', reject);
      }).on('error', reject);
    };
    attempt(retries);
  });
}

function fetchBinaryUrl(url, retries = 3) {
  return new Promise((resolve, reject) => {
    const fullUrl = url.startsWith('//') ? 'https:' + url : url;
    const lib = fullUrl.startsWith('https') ? https : http;
    const headers = { 'User-Agent': 'Mozilla/5.0' };
    if (process.env.HF_TOKEN && fullUrl.includes('huggingface')) {
      headers['Authorization'] = `Bearer ${process.env.HF_TOKEN}`;
    }
    const attempt = (n) => {
      lib.get(fullUrl, { headers, timeout: 20000 }, res => {
        if (res.statusCode === 429 && n > 0) {
          res.resume();
          return sleep((4 - n) * 3000).then(() => attempt(n - 1));
        }
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(chunks) }));
        res.on('error', reject);
      }).on('error', (e) => {
        if (n > 0) return sleep(2000).then(() => attempt(n - 1));
        reject(e);
      }).on('timeout', () => {
        if (n > 0) return sleep(2000).then(() => attempt(n - 1));
        reject(new Error('timeout'));
      });
    };
    attempt(retries);
  });
}

// Unified image extractor — handles both data: URLs and https:// URLs.
async function extractBase64(src) {
  if (!src) return null;

  // data:image/png;base64,<data> — just decode directly
  if (src.startsWith('data:')) {
    const comma = src.indexOf(',');
    if (comma === -1) return null;
    const b64 = src.slice(comma + 1).trim();
    // Validate it's non-empty valid base64
    if (b64.length < 10) return null;
    return b64;
  }

  // Real https/http URL — download it
  const fullUrl = src.startsWith('//') ? 'https:' + src : src;
  if (!fullUrl.startsWith('http')) return null;

  try {
    const { status, body } = await fetchBinaryUrl(fullUrl);
    if (status === 200 && body.length > 100) return body.toString('base64');
    return null;
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Fetch one page of HF rows
// ---------------------------------------------------------------------------
async function fetchHFPage(dataset, config, split, offset) {
  const url = `https://datasets-server.huggingface.co/rows?dataset=${encodeURIComponent(dataset)}&config=${config}&split=${split}&offset=${offset}&length=${HF_PAGE_SIZE}`;
  const data = await fetchJson(url);
  return { rows: (data.rows || []).map(r => r.row), total: data.num_rows_total || 0 };
}

// ---------------------------------------------------------------------------
// Concurrency limiter
// ---------------------------------------------------------------------------
async function runConcurrent(items, concurrency, fn) {
  let i = 0;
  const results = [];
  const workers = Array.from({ length: concurrency }, async () => {
    while (i < items.length) {
      const idx = i++;
      results[idx] = await fn(items[idx], idx);
    }
  });
  await Promise.all(workers);
  return results;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  console.log('\nScienceQA figure patcher');
  console.log(`Dry run: ${DRY_RUN} | Concurrency: ${CONCURRENCY}${SPLIT_FILTER ? ` | Split: ${SPLIT_FILTER}` : ''}\n`);

  // 1. Load which source_ids still need figures
  console.log('Loading missing rows from DB…');
  const { rows: missing } = await pool.query(
    `SELECT id, source_id FROM question_bank
     WHERE source = 'scienceqa' AND figure_data IS NULL
     ORDER BY source_id`
  );
  console.log(`  ${missing.length} rows need figures\n`);
  if (missing.length === 0) { console.log('Nothing to do.'); await pool.end(); return; }

  const needsMap = new Map(missing.map(r => [r.source_id, r.id]));

  const SPLITS = SPLIT_FILTER ? [SPLIT_FILTER] : ['train', 'validation', 'test'];
  let totalPatched = 0, totalFailed = 0, totalNoImage = 0;

  for (const split of SPLITS) {
    console.log(`── ${split} ──────────────────────────────────────────`);

    // 2. Paginate through HF rows for this split
    let offset = 0;
    let splitTotal = null;
    let pageNum = 0;
    const toUpdate = []; // { dbId, base64 }

    while (true) {
      pageNum++;
      process.stdout.write(`\r  Page ${pageNum} (offset ${offset})… `);
      let page;
      try {
        page = await fetchHFPage('derek-thomas/ScienceQA', 'default', split, offset);
      } catch (e) {
        console.log(`\n  ⚠ Fetch error at offset ${offset}: ${e.message} — retrying after 10s`);
        await sleep(10000);
        try { page = await fetchHFPage('derek-thomas/ScienceQA', 'default', split, offset); }
        catch (e2) { console.log(`  ✗ Giving up on offset ${offset}: ${e2.message}`); break; }
      }

      if (splitTotal === null) splitTotal = page.total;
      if (!page.rows.length) break;

      // 3. Find rows with images that we still need
      for (let i = 0; i < page.rows.length; i++) {
        const r = page.rows[i];
        const src_id = `scienceqa_${split}_${offset + i}`;
        if (!needsMap.has(src_id)) continue; // already has figure or not in DB
        const imgSrc = r.image?.src || null;
        if (!imgSrc) { totalNoImage++; continue; } // question genuinely has no image
        toUpdate.push({ srcId: src_id, dbId: needsMap.get(src_id), imgSrc });
      }

      offset += page.rows.length;
      if (offset >= splitTotal) break;
      await sleep(800); // polite pacing
    }

    console.log(`\n  Found ${toUpdate.length} rows with images to patch`);
    if (toUpdate.length === 0) continue;

    // 4. Download / decode images concurrently
    console.log(`  Extracting images (concurrency ${CONCURRENCY})…`);
    let done = 0;
    const patches = await runConcurrent(toUpdate, CONCURRENCY, async ({ srcId, dbId, imgSrc }) => {
      const b64 = await extractBase64(imgSrc);
      done++;
      if (done % 100 === 0 || done === toUpdate.length) {
        process.stdout.write(`\r  Extracted ${done}/${toUpdate.length} `);
      }
      return { dbId, b64, srcId };
    });
    console.log();

    const ok     = patches.filter(p => p.b64);
    const failed = patches.filter(p => !p.b64);
    totalFailed += failed.length;

    console.log(`  ✓ ${ok.length} images extracted, ✗ ${failed.length} failed`);
    if (failed.length > 0 && failed.length <= 5) {
      failed.forEach(p => console.log(`    - ${p.srcId}`));
    }

    if (DRY_RUN) {
      console.log(`  [dry-run] would UPDATE ${ok.length} rows`);
      totalPatched += ok.length;
      continue;
    }

    // 5. Batch UPDATE
    console.log(`  Updating DB…`);
    const BATCH_SIZE = 50;
    let updated = 0;
    for (let i = 0; i < ok.length; i += BATCH_SIZE) {
      const batch = ok.slice(i, i + BATCH_SIZE);
      // Build a single UPDATE ... SET figure_data = CASE WHEN id = ... THEN ...
      const cases = batch.map((p, j) => `WHEN $${j * 2 + 1}::uuid THEN $${j * 2 + 2}`).join(' ');
      const ids   = batch.map(p => p.dbId);
      const vals  = batch.flatMap(p => [p.dbId, p.b64]);
      await pool.query(
        `UPDATE question_bank SET figure_data = CASE id ${cases} END WHERE id = ANY($${vals.length + 1}::uuid[])`,
        [...vals, ids]
      );
      updated += batch.length;
      process.stdout.write(`\r  Updated ${updated}/${ok.length} `);
    }
    console.log(`\n  ✅ ${ok.length} rows patched\n`);
    totalPatched += ok.length;
  }

  // 6. Final summary
  const { rows: [{ fig, total }] } = await pool.query(
    `SELECT COUNT(*) FILTER (WHERE figure_data IS NOT NULL) fig, COUNT(*) total FROM question_bank WHERE source = 'scienceqa'`
  );
  console.log('────────────────────────────────────────────────────────────');
  console.log(`Patched this run: ${totalPatched}`);
  console.log(`Failed downloads: ${totalFailed}`);
  console.log(`No image (text-only): ${totalNoImage}`);
  console.log(`ScienceQA total: ${total} (${fig} with figures)`);

  await pool.end();
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
