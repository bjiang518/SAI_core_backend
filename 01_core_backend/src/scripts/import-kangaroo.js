/**
 * Import Math Kangaroo (qualcomm/M3Kang) into question_bank.
 *
 * Source : qualcomm/M3Kang on HuggingFace (Research Use Only)
 *          ~1,747 unique problems, 2007–2024, grades 5–12, MCQ (A–E)
 *          ~50 % have diagrams; available in 108 languages.
 *
 * This script fetches English-only rows via the HF filter API,
 * parses question text + choices, tags with the Math taxonomy, embeds, inserts.
 *
 * Requires HF_TOKEN in .env (must accept dataset terms on HuggingFace first):
 *   https://huggingface.co/datasets/qualcomm/M3Kang
 *
 * Usage:
 *   node src/scripts/import-kangaroo.js --probe          # inspect raw schema
 *   node src/scripts/import-kangaroo.js --dry-run --limit=5
 *   node src/scripts/import-kangaroo.js                  # full import
 *   node src/scripts/import-kangaroo.js --limit=200      # partial
 *   railway run node src/scripts/import-kangaroo.js
 */

'use strict';

require('dotenv').config();
const https = require('https');
const http  = require('http');
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { buildTaxonomyPrompt } = require('./taxonomy');

const DRY_RUN = process.argv.includes('--dry-run');
const PROBE   = process.argv.includes('--probe');
const LIMIT   = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();

const TAGGING_BATCH = 8;
const EMBED_BATCH   = 20;
const HF_PAGE_SIZE  = 100;
const HF_DELAY_MS   = 1800;

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const MATH_TAXONOMY = buildTaxonomyPrompt('Math');
const LETTERS = ['A', 'B', 'C', 'D', 'E'];

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------------------------------------------------------------------------
// HuggingFace helpers
// ---------------------------------------------------------------------------
function hfHeaders() {
  const h = { 'User-Agent': 'Mozilla/5.0 (compatible; StudyAI/1.0)', 'Accept': 'application/json' };
  if (process.env.HF_TOKEN) h['Authorization'] = `Bearer ${process.env.HF_TOKEN}`;
  return h;
}

function fetchJson(url, retries = 4) {
  return new Promise((resolve, reject) => {
    const attempt = (n) => {
      https.get(url, { headers: hfHeaders() }, res => {
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', async () => {
          const body = Buffer.concat(chunks).toString();
          if (res.statusCode === 401 || res.statusCode === 403) {
            reject(new Error(`HF auth error ${res.statusCode} — check HF_TOKEN and dataset terms acceptance`));
            return;
          }
          if (body.trim().startsWith('<') || res.statusCode === 429) {
            if (n > 0) {
              const d = (5 - n) * 4000;
              process.stdout.write(`\r  rate limited — retrying in ${d / 1000}s…`);
              await sleep(d);
              attempt(n - 1);
              return;
            }
            reject(new Error('HuggingFace rate limited after all retries'));
            return;
          }
          try { resolve(JSON.parse(body)); }
          catch (e) { reject(new Error(`JSON parse: ${e.message} — body: ${body.slice(0, 200)}`)); }
        });
        res.on('error', reject);
      }).on('error', reject);
    };
    attempt(retries);
  });
}

function fetchBinary(url) {
  return new Promise((resolve, reject) => {
    const fullUrl = url.startsWith('//') ? 'https:' + url : url;
    const lib = fullUrl.startsWith('https') ? https : http;
    const headers = { 'User-Agent': 'Mozilla/5.0' };
    if (process.env.HF_TOKEN && fullUrl.includes('huggingface')) {
      headers['Authorization'] = `Bearer ${process.env.HF_TOKEN}`;
    }
    lib.get(fullUrl, { headers, timeout: 15000 }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({
        status: res.statusCode,
        mime:   (res.headers['content-type'] || 'image/png').split(';')[0].trim(),
        body:   Buffer.concat(chunks),
      }));
      res.on('error', reject);
    }).on('error', reject).on('timeout', () => reject(new Error('image download timeout')));
  });
}

// ---------------------------------------------------------------------------
// Fetch English-only rows
// Tries HF filter API first (fast); falls back to full-scan with client filter.
// ---------------------------------------------------------------------------
async function fetchKangarooEnglish(limitRows) {
  const rows    = [];
  let offset    = 0;
  let useFilter = true;
  let totalKnown = null;
  const DATASET = 'qualcomm%2FM3Kang';
  const BASE    = 'https://datasets-server.huggingface.co';

  while (rows.length < limitRows) {
    const url = useFilter
      ? `${BASE}/filter?dataset=${DATASET}&config=default&split=train&where=language%3D'en'&offset=${offset}&length=${HF_PAGE_SIZE}`
      : `${BASE}/rows?dataset=${DATASET}&config=default&split=train&offset=${offset}&length=${HF_PAGE_SIZE}`;

    let data;
    try {
      data = await fetchJson(url);
    } catch (e) {
      if (useFilter && (e.message.includes('filter') || e.message.includes('400'))) {
        console.log('\n  Filter API unsupported — falling back to full scan (slower)');
        useFilter = false;
        offset    = 0;
        rows.length = 0;
        continue;
      }
      throw e;
    }

    const pageRows = (data.rows || []).map(r => r.row ?? r);
    const incoming = useFilter
      ? pageRows
      : pageRows.filter(r => {
          const lang = (r.language || r.lang || '').toLowerCase();
          return lang === 'en' || lang === 'english';
        });

    rows.push(...incoming);
    if (totalKnown === null) totalKnown = data.num_rows_total || data.total || 0;

    const pageEmpty = pageRows.length === 0;
    const reachedEnd = totalKnown > 0 && (offset + HF_PAGE_SIZE) >= totalKnown;
    if (pageEmpty || reachedEnd) break;

    offset += HF_PAGE_SIZE;
    process.stdout.write(`\r  fetched ${rows.length} English rows…`);
    await sleep(HF_DELAY_MS);
  }

  console.log(`\n  ${rows.length} English rows fetched (limit: ${limitRows === Infinity ? 'all' : limitRows})`);
  return rows.slice(0, limitRows);
}

// ---------------------------------------------------------------------------
// Parse question text → question body + options [{label, text, is_correct}]
//
// Math Kangaroo format (typical):
//   "Some question text.\n(A) 12  (B) 24  (C) 36  (D) 48  (E) 60"
// ---------------------------------------------------------------------------
function parseKangarooText(text, correctLabel) {
  if (!text) return { question: '', options: null };

  // Find where the first option marker appears
  const optStart = text.search(/\([A-E]\)/);
  if (optStart === -1) return { question: text.trim(), options: null };

  const questionBody = text.slice(0, optStart).trim();
  const optionBlock  = text.slice(optStart);

  // Split on "(A)" / "(B)" etc — works for both inline and newline-separated
  const parts    = optionBlock.split(/\s*\([A-E]\)\s*/);
  const optTexts = parts.slice(1).map(t => t.trim()).filter(Boolean);

  if (optTexts.length < 4) return { question: text.trim(), options: null };

  const correct = (correctLabel || 'A').trim().toUpperCase();
  const options = optTexts.slice(0, 5).map((txt, i) => ({
    label:      LETTERS[i],
    text:       txt,
    is_correct: LETTERS[i] === correct,
  }));

  return { question: questionBody || text.trim(), options };
}

// ---------------------------------------------------------------------------
// Map Kangaroo competition level → { diff (1–5), grade label }
// M3Kang uses named levels: "Benjamin", "Cadet", "Junior", "Student"
// (Some national editions use numeric levels 1–6 or grade-pair strings)
// ---------------------------------------------------------------------------
function levelToDifficulty(level) {
  if (level == null) return { diff: 3, grade: '8th Grade' };
  const l = String(level).toLowerCase().trim();

  if (/pre.?ecolier|pré.?ecolier/.test(l)) return { diff: 1, grade: '2nd Grade'  };
  if (/^ecolier$/.test(l))                 return { diff: 1, grade: '4th Grade'  };
  if (/benjamin/.test(l))                  return { diff: 2, grade: '6th Grade'  };
  if (/cadet/.test(l))                     return { diff: 3, grade: '8th Grade'  };
  if (/junior/.test(l))                    return { diff: 4, grade: '10th Grade' };
  if (/student|senior/.test(l))            return { diff: 5, grade: '12th Grade' };

  // Grade-pair strings e.g. "5-6", "7–8"
  const pairM = l.match(/(\d+)\s*[-–]\s*(\d+)/);
  if (pairM) {
    const g = (parseInt(pairM[1]) + parseInt(pairM[2])) / 2;
    if (g <= 3)  return { diff: 1, grade: '3rd Grade'  };
    if (g <= 6)  return { diff: 2, grade: '6th Grade'  };
    if (g <= 8)  return { diff: 3, grade: '8th Grade'  };
    if (g <= 10) return { diff: 4, grade: '10th Grade' };
    return       { diff: 5, grade: '12th Grade' };
  }

  // Numeric level (1–6 corresponding to kangaroo grade tiers)
  const n = parseInt(l);
  if (!isNaN(n)) {
    const table = [, { diff: 1, grade: '2nd Grade' }, { diff: 1, grade: '4th Grade' },
                      { diff: 2, grade: '6th Grade' }, { diff: 3, grade: '8th Grade' },
                      { diff: 4, grade: '10th Grade'}, { diff: 5, grade: '12th Grade'}];
    if (table[n]) return table[n];
  }

  return { diff: 3, grade: '8th Grade' };
}

// ---------------------------------------------------------------------------
// GPT Math taxonomy tagging
// ---------------------------------------------------------------------------
const TAG_SYSTEM = `Classify Math Kangaroo competition problems into the taxonomy below.
Return ONLY a JSON array: [{"base_branch":"...","detailed_branch":"..."},...]
Both values must EXACTLY match taxonomy entries.

Math taxonomy:
${MATH_TAXONOMY}`;

async function tagBatch(questions) {
  const numbered = questions.map((q, i) => `${i + 1}. ${q.slice(0, 350)}`).join('\n\n');
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0,
    max_tokens: questions.length * 45,
    messages: [{ role: 'system', content: TAG_SYSTEM }, { role: 'user', content: numbered }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) throw new Error('No JSON array from GPT');
  const parsed = JSON.parse(m[0]);
  if (parsed.length !== questions.length) throw new Error(`Count mismatch: ${parsed.length} vs ${questions.length}`);
  return parsed;
}

async function tagOne(question) {
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0, max_tokens: 50,
    messages: [{ role: 'system', content: TAG_SYSTEM }, { role: 'user', content: `1. ${question.slice(0, 350)}` }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) return null;
  return JSON.parse(m[0])[0] || null;
}

// ---------------------------------------------------------------------------
// Embedding
// ---------------------------------------------------------------------------
async function embedBatch(rows) {
  const texts = rows.map(r =>
    ['Math Kangaroo competition problem', r.question, r.base_branch, r.detailed_branch,
     r.correct_answer ? `Answer: ${r.correct_answer}` : '']
    .filter(Boolean).join(' | ').slice(0, 2000)
  );
  const res = await openai.embeddings.create({ model: 'text-embedding-3-small', input: texts });
  return res.data.map(d => d.embedding);
}

// ---------------------------------------------------------------------------
// DB insert
// ---------------------------------------------------------------------------
async function insertRows(client, rows) {
  for (let i = 0; i < rows.length; i += 50) {
    const batch = rows.slice(i, i + 50);
    const ph = batch.map((_, idx) => {
      const b = idx * 14;
      return `($${b+1},$${b+2},$${b+3},$${b+4},$${b+5},$${b+6},$${b+7},$${b+8},$${b+9},$${b+10},$${b+11},$${b+12},$${b+13},$${b+14})`;
    }).join(',');
    const vals = batch.flatMap(r => [
      r.source, r.source_id, r.subject, r.topic, r.base_branch, r.detailed_branch,
      r.difficulty, r.question_type, r.question,
      r.options ? JSON.stringify(r.options) : null,
      r.correct_answer, r.explanation || null,
      r.embedding, r.figure_base64 || null,
    ]);
    await client.query(`
      INSERT INTO question_bank
        (source, source_id, subject, topic, base_branch, detailed_branch,
         difficulty, question_type, question, options, correct_answer, explanation,
         embedding, figure_data)
      VALUES ${ph}
      ON CONFLICT ON CONSTRAINT uq_question_bank_source_id DO NOTHING
    `, vals);
  }
}

// ---------------------------------------------------------------------------
// Normalize a raw M3Kang row
// ---------------------------------------------------------------------------
function normalizeRow(r, idx) {
  const rawText      = r.text || r.question || '';
  const correctLabel = (r.label || r.answer || r.correct_answer || 'A').trim().toUpperCase();
  const { question, options } = parseKangarooText(rawText, correctLabel);
  const { diff }              = levelToDifficulty(r.level);
  // Prefer the dataset's own problem ID; fall back to row index
  const problemId  = r.id || r.problem_id || `row${idx}`;
  const sourceId   = `kangaroo_${problemId}`;
  const imageUrl   = r.image?.src || r.image_url || (typeof r.image === 'string' ? r.image : null);

  return {
    source:          'kangaroo',
    source_id:       sourceId,
    subject:         'Math',
    topic:           null,      // filled by GPT
    base_branch:     null,
    detailed_branch: null,
    difficulty:      diff,
    question_type:   'multiple_choice',
    question,
    options,
    correct_answer:  correctLabel,
    explanation:     null,
    embedding:       null,
    figure_base64:   null,
    image_url:       imageUrl,
    has_image:       !!imageUrl,
  };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    console.log('\nMath Kangaroo (M3Kang) import');
    console.log(`HF_TOKEN : ${process.env.HF_TOKEN ? '✅ set' : '❌ missing — gated dataset needs token'}`);
    console.log(`Dry run  : ${DRY_RUN}`);
    console.log(`Probe    : ${PROBE}`);
    console.log(`Limit    : ${LIMIT === Infinity ? 'all' : LIMIT}\n`);

    if (!process.env.HF_TOKEN) {
      console.error('Set HF_TOKEN in .env. Accept the dataset terms first at:');
      console.error('  https://huggingface.co/datasets/qualcomm/M3Kang');
      process.exit(1);
    }

    // ── PROBE: inspect raw schema ──────────────────────────────────────────
    if (PROBE) {
      console.log('Fetching 3 rows to inspect M3Kang schema…\n');
      const data = await fetchJson(
        `https://datasets-server.huggingface.co/rows?dataset=qualcomm%2FM3Kang&config=default&split=train&offset=0&length=3`
      );
      if (!data.rows?.length) {
        console.log('No rows returned. Raw response:', JSON.stringify(data).slice(0, 500));
        return;
      }
      data.rows.forEach((wrapper, i) => {
        const r = wrapper.row ?? wrapper;
        console.log(`── Row ${i + 1} (${r.language || '?'}, level=${r.level}) ──`);
        for (const [k, v] of Object.entries(r)) {
          const display = typeof v === 'object' ? JSON.stringify(v).slice(0, 120) : String(v).slice(0, 120);
          console.log(`  ${k.padEnd(18)}: ${display}`);
        }
        console.log();
      });
      console.log('Level values seen:', [...new Set(data.rows.map(w => String((w.row ?? w).level)))].join(', '));
      return;
    }

    // ── Fetch ──────────────────────────────────────────────────────────────
    console.log('Fetching English rows…');
    const rawRows = await fetchKangarooEnglish(LIMIT);

    // ── Normalize ──────────────────────────────────────────────────────────
    const normalized = rawRows.map((r, idx) => {
      try { return normalizeRow(r, idx); } catch { return null; }
    }).filter(Boolean);

    const withImg   = normalized.filter(r => r.has_image).length;
    const noOpts    = normalized.filter(r => !r.options).length;
    const levelDist = {};
    rawRows.forEach(r => { const k = String(r.level); levelDist[k] = (levelDist[k] || 0) + 1; });

    console.log(`\nNormalized : ${normalized.length}`);
    console.log(`With images: ${withImg}`);
    console.log(`No options : ${noOpts} (skipped — can't parse choices from text)`);
    console.log('Level dist :', JSON.stringify(levelDist));

    if (DRY_RUN) {
      normalized.slice(0, 4).forEach(r => {
        const imgMark = r.has_image ? '🖼 ' : '   ';
        console.log(`\n${imgMark}[diff:${r.difficulty}] ${r.source_id}`);
        console.log(`  Q: ${r.question.slice(0, 120)}…`);
        if (r.options) {
          console.log(`  Opts: ${r.options.map(o => `${o.label}) ${o.text.slice(0, 20)}`).join(' | ')}`);
        } else {
          console.log('  ⚠️  No options parsed');
        }
        console.log(`  Correct: ${r.correct_answer}`);
      });
      return;
    }

    // Only insert rows where choices were parsed (quality gate)
    const valid = normalized.filter(r => r.options && r.options.length >= 4);
    console.log(`\nValid rows (options OK): ${valid.length}/${normalized.length}`);

    // ── Tag ────────────────────────────────────────────────────────────────
    console.log(`\nTagging…`);
    for (let i = 0; i < valid.length; i += TAGGING_BATCH) {
      const batch = valid.slice(i, i + TAGGING_BATCH);
      let tags;
      try {
        tags = await tagBatch(batch.map(r => r.question));
      } catch {
        tags = await Promise.all(batch.map(r => tagOne(r.question).catch(() => null)));
      }
      tags.forEach((t, j) => {
        if (t?.base_branch) {
          batch[j].base_branch     = t.base_branch;
          batch[j].detailed_branch = t.detailed_branch || null;
          batch[j].topic = t.detailed_branch
            ? `${t.base_branch} / ${t.detailed_branch}`
            : t.base_branch;
        } else {
          batch[j].topic      = 'Number & Operations';
          batch[j].base_branch = 'Number & Operations';
        }
      });
      process.stdout.write(`\r  tagged ${Math.min(i + TAGGING_BATCH, valid.length)}/${valid.length}`);
    }
    console.log();

    // ── Download images ────────────────────────────────────────────────────
    console.log('\nDownloading images…');
    let imgCount = 0;
    for (const row of valid) {
      if (!row.image_url) continue;
      try {
        const src = row.image_url;
        if (src.startsWith('data:')) {
          const comma = src.indexOf(',');
          if (comma !== -1 && src.length - comma > 10) {
            row.figure_base64 = src.slice(comma + 1).trim();
            imgCount++;
          }
          continue;
        }
        const fullUrl = src.startsWith('//') ? 'https:' + src : src;
        if (fullUrl.startsWith('http')) {
          const res = await fetchBinary(fullUrl);
          if (res.status === 200 && res.body.length > 0) {
            row.figure_base64 = res.body.toString('base64');
            imgCount++;
          }
        }
      } catch { /* non-critical — question still inserted without image */ }
    }
    console.log(`  ${imgCount} / ${valid.filter(r => r.image_url).length} downloaded`);

    // ── Embed ──────────────────────────────────────────────────────────────
    console.log('\nEmbedding…');
    for (let i = 0; i < valid.length; i += EMBED_BATCH) {
      const batch = valid.slice(i, i + EMBED_BATCH);
      try {
        const vecs = await embedBatch(batch);
        vecs.forEach((v, j) => { batch[j].embedding = v; });
      } catch (e) {
        console.warn(`\n  embed batch ${i} failed: ${e.message}`);
      }
      process.stdout.write(`\r  embedded ${Math.min(i + EMBED_BATCH, valid.length)}/${valid.length}`);
    }
    console.log();

    // ── Insert ─────────────────────────────────────────────────────────────
    await insertRows(client, valid);

    const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
    const { rows: dist } = await client.query(
      `SELECT difficulty, COUNT(*) n FROM question_bank WHERE source='kangaroo' GROUP BY difficulty ORDER BY difficulty`
    );
    const { rows: imgDist } = await client.query(
      `SELECT COUNT(*) n FROM question_bank WHERE source='kangaroo' AND figure_data IS NOT NULL`
    );

    console.log(`\n✅ Kangaroo import complete`);
    console.log(`   Inserted      : ${valid.length}`);
    console.log(`   With figures  : ${imgDist[0]?.n || 0}`);
    console.log(`   question_bank total: ${count}`);
    console.log('\nKangaroo by difficulty:');
    dist.forEach(r => console.log(`  diff ${r.difficulty}: ${r.n} questions`));

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('\nFatal:', err.message); process.exit(1); });
