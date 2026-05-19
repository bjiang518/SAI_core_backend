/**
 * Import Math Kangaroo (qualcomm/M3Kang) into question_bank.
 *
 * Source : qualcomm/M3Kang on HuggingFace (Research Use Only)
 *          ~1,747 unique English problems, 2007–2024, grades 5–12, MCQ (A–E)
 *          ~50% have diagrams.
 *
 * The dataset is stored as large Parquet files (~400 MB each).
 * Step 1 — extract to JSONL using the Python helper:
 *   pip install datasets pillow
 *   HF_TOKEN=hf_xxx python src/scripts/extract-kangaroo-data.py
 *
 * Step 2 — import JSONL into the DB:
 *   node src/scripts/import-kangaroo.js --from-file=kangaroo_en.jsonl
 *   node src/scripts/import-kangaroo.js --from-file=kangaroo_en.jsonl --dry-run --limit=5
 *   railway run node src/scripts/import-kangaroo.js --from-file=kangaroo_en.jsonl
 *
 * Probe (check HF file tree):
 *   node src/scripts/import-kangaroo.js --probe
 */

'use strict';

require('dotenv').config();
const https = require('https');
const http  = require('http');
const fs    = require('fs');
const readline = require('readline');
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { buildTaxonomyPrompt } = require('./taxonomy');

const DRY_RUN   = process.argv.includes('--dry-run');
const PROBE     = process.argv.includes('--probe');
const LIMIT     = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();
const FROM_FILE = (() => { const f = process.argv.find(a => a.startsWith('--from-file=')); return f ? f.split('=').slice(1).join('=') : null; })();

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

// Fetch first `maxBytes` of a file from the dataset repo (for probing)
function fetchRawFile(filePath, maxBytes = 4096) {
  return new Promise((resolve, reject) => {
    const url = `https://huggingface.co/datasets/qualcomm/M3Kang/resolve/main/${filePath}`;
    const headers = { ...hfHeaders(), Accept: '*/*' };
    if (maxBytes) headers['Range'] = `bytes=0-${maxBytes - 1}`;
    https.get(url, { headers }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      res.on('error', reject);
    }).on('error', reject);
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
// Read rows from a JSONL file produced by extract-kangaroo-data.py
// ---------------------------------------------------------------------------
async function readJsonlFile(filePath, limitRows) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}\nRun: python src/scripts/extract-kangaroo-data.py`);
  }
  const rows = [];
  const rl = readline.createInterface({ input: fs.createReadStream(filePath, 'utf8'), crlfDelay: Infinity });
  for await (const line of rl) {
    const t = line.trim();
    if (!t) continue;
    try { rows.push(JSON.parse(t)); } catch { /* skip malformed lines */ }
    if (rows.length >= limitRows) break;
  }
  console.log(`  ${rows.length} rows read from ${filePath}`);
  return rows;
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

  // Numeric levels 0-5 (M3Kang high_quality format: lvl-N_YYYY_P)
  // 0 = Pre-Écolier (Gr 1-2), 1 = Écolier (Gr 3-4), 2 = Benjamin (Gr 5-6)
  // 3 = Cadet (Gr 7-8), 4 = Junior (Gr 9-10), 5 = Student (Gr 11-12)
  const n = parseInt(l);
  if (!isNaN(n)) {
    const table = {
      0: { diff: 1, grade: '2nd Grade'  },
      1: { diff: 1, grade: '4th Grade'  },
      2: { diff: 2, grade: '6th Grade'  },
      3: { diff: 3, grade: '8th Grade'  },
      4: { diff: 4, grade: '10th Grade' },
      5: { diff: 5, grade: '12th Grade' },
    };
    if (table[n]) return table[n];
  }

  // Named levels (fallback for standard split)
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

  return { diff: 3, grade: '8th Grade' };
}

// ---------------------------------------------------------------------------
// GPT-4o-mini vision — extract MCQ choices (A-E) from the question image.
// Used when the text field doesn't contain the choices (all M3Kang rows).
// ---------------------------------------------------------------------------
const CHOICE_EXTRACT_CONCURRENCY = 5;  // parallel vision calls
const CHOICE_EXTRACT_PROMPT =
  'This is a Math Kangaroo multiple-choice problem. ' +
  'Extract the 5 answer options (A through E) from the image. ' +
  'Return ONLY a JSON array (no markdown): ' +
  '[{"label":"A","text":"..."},{"label":"B","text":"..."},...]. ' +
  'Keep each text short and exact. If an option contains a diagram or expression, describe it briefly.';

async function extractChoicesFromImage(correctLabel, imageBase64) {
  try {
    const res = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      max_tokens: 300,
      temperature: 0,
      messages: [{
        role: 'user',
        content: [
          { type: 'image_url', image_url: { url: `data:image/jpeg;base64,${imageBase64}`, detail: 'low' } },
          { type: 'text', text: CHOICE_EXTRACT_PROMPT },
        ],
      }],
    });
    const m = res.choices[0].message.content.match(/\[[\s\S]*\]/);
    if (!m) return null;
    const choices = JSON.parse(m[0]);
    if (!Array.isArray(choices) || choices.length < 4) return null;
    return choices.slice(0, 5).map(c => ({
      label:      String(c.label || '').toUpperCase(),
      text:       String(c.text || '').trim(),
      is_correct: String(c.label || '').toUpperCase() === correctLabel,
    })).filter(c => c.label && c.text);
  } catch {
    return null;
  }
}

// Run extractChoicesFromImage with bounded concurrency
async function extractChoicesBatch(rows) {
  const results = new Array(rows.length).fill(null);
  const queue   = rows.map((r, i) => ({ r, i }));
  let done = 0;

  async function worker() {
    while (queue.length > 0) {
      const { r, i } = queue.shift();
      if (!r.figure_base64) { done++; continue; }
      results[i] = await extractChoicesFromImage(r.correct_answer, r.figure_base64);
      done++;
      process.stdout.write(`\r  vision extracted ${done}/${rows.length}`);
      await sleep(200); // gentle rate limit
    }
  }

  await Promise.all(Array.from({ length: CHOICE_EXTRACT_CONCURRENCY }, worker));
  console.log();
  return results;
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
// Normalize a raw M3Kang row (from HF API or from JSONL file)
// ---------------------------------------------------------------------------
function normalizeRow(r, idx) {
  const rawText      = r.text || r.question || '';
  const correctLabel = (r.label || r.answer || r.correct_answer || 'A').trim().toUpperCase();
  const { question, options } = parseKangarooText(rawText, correctLabel);
  const { diff }              = levelToDifficulty(r.level);
  const problemId  = r.id || r.problem_id || `row${idx}`;
  const sourceId   = `kangaroo_${problemId}`;
  // image_b64: from Python extractor (already base64 PNG)
  // image_url: from HF datasets-server (needs downloading)
  const imageB64   = r.image_b64 || null;
  const imageUrl   = (!imageB64) ? (r.image?.src || r.image_url || (typeof r.image === 'string' ? r.image : null)) : null;

  return {
    source:          'kangaroo',
    source_id:       sourceId,
    subject:         'Math',
    topic:           null,
    base_branch:     null,
    detailed_branch: null,
    difficulty:      diff,
    question_type:   'multiple_choice',
    question,
    options,
    correct_answer:  correctLabel,
    explanation:     null,
    embedding:       null,
    figure_base64:   imageB64,   // pre-filled from Python extractor
    image_url:       imageUrl,   // needs downloading (HF API path)
    has_image:       !!(imageB64 || imageUrl),
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
    console.log(`Limit    : ${LIMIT === Infinity ? 'all' : LIMIT}`);
    console.log(`From file: ${FROM_FILE || '(HF API)'}\n`);

    if (!FROM_FILE && !process.env.HF_TOKEN) {
      console.error('Set HF_TOKEN in .env. Accept the dataset terms first at:');
      console.error('  https://huggingface.co/datasets/qualcomm/M3Kang');
      process.exit(1);
    }

    // ── PROBE: inspect raw schema ──────────────────────────────────────────
    if (PROBE) {
      console.log('Querying HuggingFace Hub for M3Kang file tree…\n');

      // 1. List root
      const root = await fetchJson('https://huggingface.co/api/datasets/qualcomm/M3Kang/tree/main');
      const rootFiles = Array.isArray(root) ? root : [];
      console.log(`Root (${rootFiles.length} entries):`);
      rootFiles.forEach(f => console.log(`  ${(f.type||'?').padEnd(10)} ${f.path}`));

      // 2. List data/ subdirectory
      console.log('\nListing data/ …');
      const dataDir = await fetchJson('https://huggingface.co/api/datasets/qualcomm/M3Kang/tree/main/data')
        .catch(() => []);
      const dataFiles = Array.isArray(dataDir) ? dataDir : [];
      console.log(`data/ (${dataFiles.length} entries):`);
      dataFiles.slice(0, 20).forEach(f => console.log(`  ${(f.type||'?').padEnd(10)} ${f.path}  (${f.size||'?'} bytes)`));
      if (dataFiles.length > 20) console.log(`  … and ${dataFiles.length - 20} more`);

      // 3. Fetch first 3 lines of the first JSONL/parquet file
      const sampleFile = dataFiles.find(f => {
        const p = f.path || '';
        return p.endsWith('.jsonl') || p.endsWith('.jsonl.gz') || p.endsWith('.parquet') || p.endsWith('.json') || p.endsWith('.arrow');
      });
      if (sampleFile) {
        console.log(`\nFetching first ~3KB of: ${sampleFile.path}`);
        const raw = await fetchRawFile(sampleFile.path, 3000).catch(e => `ERROR: ${e.message}`);
        console.log(raw.slice(0, 800));
      } else {
        console.log('\nNo JSONL/Parquet/JSON files found in data/. Trying README for schema hints…');
        const readme = await fetchRawFile('README.md', 4000).catch(() => '');
        const schemaSection = readme.slice(readme.indexOf('feature') > 0 ? readme.indexOf('feature') - 100 : 0, readme.indexOf('feature') + 1000);
        console.log(schemaSection.slice(0, 1000));
      }
      return;
    }

    // ── Fetch or read file ─────────────────────────────────────────────────
    let rawRows;
    if (FROM_FILE) {
      console.log(`Reading from file: ${FROM_FILE}`);
      rawRows = await readJsonlFile(FROM_FILE, LIMIT);
    } else {
      console.log('Fetching English rows from HF API…');
      rawRows = await fetchKangarooEnglish(LIMIT);
    }

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
      // For dry-run: try vision on first row that has no options + has image
      const sample = normalized.slice(0, 5);
      const noOpts = sample.filter(r => !r.options && r.figure_base64);
      if (noOpts.length > 0) {
        console.log(`\nTesting vision extraction on first ${Math.min(2, noOpts.length)} images…`);
        for (const r of noOpts.slice(0, 2)) {
          const choices = await extractChoicesFromImage(r.correct_answer, r.figure_base64);
          console.log(`  ${r.source_id}: ${choices ? choices.map(o => `${o.label}) ${o.text.slice(0,20)}`).join(' | ') : '⚠️ vision failed'}`);
        }
      }
      sample.forEach(r => {
        const imgMark = r.has_image ? '🖼 ' : '   ';
        console.log(`\n${imgMark}[diff:${r.difficulty}] ${r.source_id}`);
        console.log(`  Q: ${r.question.slice(0, 120)}…`);
        if (r.options) {
          console.log(`  Opts: ${r.options.map(o => `${o.label}) ${o.text.slice(0, 20)}`).join(' | ')}`);
        } else {
          console.log('  (choices in image — vision will extract)');
        }
        console.log(`  Correct: ${r.correct_answer}`);
      });
      return;
    }

    // ── Vision extraction: get MCQ choices from images ─────────────────────
    // All M3Kang rows have choices in the image, not in text.
    const needsVision = normalized.filter(r => !r.options && r.figure_base64);
    const hasOptions  = normalized.filter(r => r.options && r.options.length >= 4);
    console.log(`\nChoice extraction:  ${hasOptions.length} from text,  ${needsVision.length} need vision`);

    if (needsVision.length > 0) {
      console.log(`Running GPT-4o-mini vision on ${needsVision.length} images…`);
      const visionResults = await extractChoicesBatch(needsVision);
      let visionOk = 0;
      visionResults.forEach((choices, i) => {
        if (choices && choices.length >= 4) {
          needsVision[i].options = choices;
          visionOk++;
        }
      });
      console.log(`  ${visionOk}/${needsVision.length} choices extracted successfully`);
    }

    // Only insert rows where choices are now available (text-parsed or vision-extracted)
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
