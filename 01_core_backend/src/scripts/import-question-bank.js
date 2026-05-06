/**
 * Import AMC12, AIME, and SAT math questions into the question_bank table.
 *
 * Sources:
 *   AMC12  — edev2000/amc12-full           (~1,200 problems, difficulty 2/3/4)
 *   AIME   — gneubig/aime-1983-2024        (~933 problems, CC0)
 *   SAT    — AGIEval sat-math.jsonl        (220 problems, MIT)
 *
 * Usage:
 *   railway run node src/scripts/import-question-bank.js
 *
 * Flags:
 *   --source=amc12|aime|sat   only import one source (default: all)
 *   --dry-run                 print counts without writing to DB
 *   --skip-embed              insert rows without embeddings (useful for testing)
 */

'use strict';

require('dotenv').config();
const https = require('https');
const { Pool } = require('pg');
const OpenAI = require('openai');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const DRY_RUN    = process.argv.includes('--dry-run');
const SKIP_EMBED = process.argv.includes('--skip-embed');
const SOURCE_FILTER = (() => {
  const flag = process.argv.find(a => a.startsWith('--source='));
  return flag ? flag.split('=')[1] : null;
})();

const EMBED_MODEL   = 'text-embedding-3-small';
const EMBED_BATCH   = 20;   // questions per OpenAI batch call
const INSERT_BATCH  = 50;   // rows per DB insert

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ---------------------------------------------------------------------------
// Fetch helpers
// ---------------------------------------------------------------------------
function httpsGet(url, redirects = 0) {
  if (redirects > 10) return Promise.reject(new Error('Too many redirects'));
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'StudyAI-import/1.0' } }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const next = res.headers.location.startsWith('http')
          ? res.headers.location
          : new URL(res.headers.location, url).href;
        res.resume(); // drain so socket can be reused
        return resolve(httpsGet(next, redirects + 1));
      }
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      res.on('error', reject);
    }).on('error', reject);
  });
}

function parseJsonLines(text) {
  const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
  // Sanity check: first line must start with '{' (JSONL), not HTML/redirect pages
  if (lines.length === 0 || !lines[0].startsWith('{')) {
    throw new Error(`Response does not look like JSONL. First 120 chars: ${text.slice(0, 120)}`);
  }
  return lines.map(l => JSON.parse(l));
}

// Parses a single CSV line respecting double-quoted fields (handles embedded commas/newlines).
function parseCsvLine(line) {
  const fields = [];
  let i = 0;
  while (i < line.length) {
    if (line[i] === '"') {
      // Quoted field — scan for closing quote (doubled quotes = escaped quote)
      let field = '';
      i++; // skip opening quote
      while (i < line.length) {
        if (line[i] === '"' && line[i + 1] === '"') { field += '"'; i += 2; }
        else if (line[i] === '"') { i++; break; }
        else { field += line[i++]; }
      }
      fields.push(field);
      if (line[i] === ',') i++; // skip comma separator
    } else {
      // Unquoted field
      const end = line.indexOf(',', i);
      if (end === -1) { fields.push(line.slice(i)); break; }
      fields.push(line.slice(i, end));
      i = end + 1;
    }
  }
  return fields;
}

// ---------------------------------------------------------------------------
// Normalizers — convert each source's schema → our internal row shape
// ---------------------------------------------------------------------------

/**
 * AMC12 from edev2000/amc12-full
 * Fields: question (string with embedded choices), answer (A-E letter),
 *         difficulty (2/3/4), problem_id ('2019A-15')
 */
function normalizeAMC12(raw) {
  if (!raw.question || !raw.answer) return null;

  // Difficulty mapping: position 2 = easy, 3 = medium, 4 = hard
  const diffMap = { 2: 2, 3: 3, 4: 4 };
  const difficulty = diffMap[raw.difficulty] || 3;

  // Extract answer choices from the question text if present
  // AMC12 embeds choices inline: "(A) 2  (B) 4  (C) 6  (D) 8  (E) 10"
  const choiceRegex = /\(([A-E])\)\s*([^(]+?)(?=\([A-E]\)|$)/g;
  const options = [];
  let match;
  const choiceSection = raw.question.match(/\(A\).*$/s)?.[0] || '';
  while ((match = choiceRegex.exec(choiceSection)) !== null) {
    options.push({
      label: match[1],
      text: match[2].trim(),
      is_correct: match[1] === raw.answer,
    });
  }

  // Strip choices from question text for cleaner display
  const questionText = raw.question.replace(/\(A\).*$/s, '').trim();

  return {
    source:        'amc12',
    source_id:     raw.problem_id || null,
    topic:         inferAMCTopic(raw.problem_id),
    difficulty,
    question_type: 'multiple_choice',
    question:      questionText || raw.question,
    options:       options.length >= 4 ? options : null,
    correct_answer: raw.answer,
    explanation:   null,
  };
}

/**
 * AIME from gneubig/aime-1983-2024
 * Fields: Year, Problem Number, Question, Answer, Part (I/II)
 */
function normalizeAIME(raw) {
  const q = raw.Question || raw.question;
  const a = raw.Answer   || raw.answer;
  if (!q || a == null) return null;

  // AIME problems increase in difficulty: 1-5 easy, 6-10 medium, 11-15 hard
  const num = parseInt(raw['Problem Number'] || raw.problem_number || 8, 10);
  let difficulty;
  if (num <= 5)       difficulty = 3;
  else if (num <= 10) difficulty = 4;
  else                difficulty = 5;

  return {
    source:        'aime',
    source_id:     `${raw.Year}-${raw.Part || 'I'}-${num}`,
    topic:         null,
    difficulty,
    question_type: 'short_answer',
    question:      q.trim(),
    options:       null,
    correct_answer: String(a).trim(),
    explanation:   null,
  };
}

/**
 * SAT from AGIEval sat-math.jsonl
 * Fields: passage, question, options (array), label (letter), other.solution
 */
function normalizeSAT(raw) {
  if (!raw.question || !raw.label) return null;

  const optionLetters = ['A', 'B', 'C', 'D', 'E'];
  const rawOptions = raw.options || [];
  const options = rawOptions.map((text, i) => ({
    label: optionLetters[i] || String(i),
    text:  String(text).replace(/^\([A-E]\)\s*/, '').trim(),
    is_correct: optionLetters[i] === raw.label,
  }));

  const solution = raw.other?.solution || null;

  return {
    source:        'sat',
    source_id:     null,
    topic:         null,
    difficulty:    3,   // SAT problems don't carry difficulty; default medium
    question_type: options.length > 0 ? 'multiple_choice' : 'short_answer',
    question:      raw.question.trim(),
    options:       options.length > 0 ? options : null,
    correct_answer: raw.label,
    explanation:   solution,
  };
}

// Simple AMC topic inference from problem position (AMC12 topic distribution by position)
function inferAMCTopic(problemId) {
  if (!problemId) return null;
  const num = parseInt((problemId.match(/-(\d+)$/) || [])[1] || '0', 10);
  if (num <= 5)        return 'Algebra - Basics';
  if (num <= 10)       return 'Geometry - Plane';
  if (num <= 15)       return 'Algebra - Intermediate';
  if (num <= 20)       return 'Number Theory';
  return 'Combinatorics - Counting';
}

// ---------------------------------------------------------------------------
// Embedding
// ---------------------------------------------------------------------------
function buildEmbedInput(row) {
  const parts = [row.question];
  if (row.topic)          parts.push(`Topic: ${row.topic}`);
  if (row.correct_answer) parts.push(`Answer: ${row.correct_answer}`);
  return parts.join(' | ').slice(0, 2000); // token safety cap
}

async function embedBatch(texts) {
  const res = await openai.embeddings.create({ model: EMBED_MODEL, input: texts });
  return res.data.map(d => d.embedding);
}

// ---------------------------------------------------------------------------
// DB insert
// ---------------------------------------------------------------------------
async function insertRows(client, rows) {
  // Build a multi-row INSERT with $N placeholders
  const values = [];
  const placeholders = rows.map((row, i) => {
    const base = i * 11;
    values.push(
      row.source, row.source_id, row.subject, row.topic,
      row.difficulty, row.question_type, row.question,
      row.options ? JSON.stringify(row.options) : null,
      row.correct_answer, row.explanation,
      row.embedding || null,
    );
    return `($${base+1},$${base+2},$${base+3},$${base+4},$${base+5},$${base+6},$${base+7},$${base+8},$${base+9},$${base+10},$${base+11})`;
  });

  await client.query(`
    INSERT INTO question_bank
      (source, source_id, subject, topic, difficulty, question_type,
       question, options, correct_answer, explanation, embedding)
    VALUES ${placeholders.join(',')}
    ON CONFLICT DO NOTHING
  `, values);
}

// ---------------------------------------------------------------------------
// Pipeline for one source
// ---------------------------------------------------------------------------
async function runSource(name, rows, client) {
  rows = rows.filter(Boolean);
  console.log(`[${name}] ${rows.length} valid rows`);
  if (DRY_RUN) return;

  // Add subject field (all are math)
  rows.forEach(r => { r.subject = 'Mathematics'; });

  // Embed in batches
  if (!SKIP_EMBED) {
    for (let i = 0; i < rows.length; i += EMBED_BATCH) {
      const batch = rows.slice(i, i + EMBED_BATCH);
      const texts  = batch.map(buildEmbedInput);
      try {
        const vectors = await embedBatch(texts);
        vectors.forEach((v, j) => { batch[j].embedding = v; });
      } catch (err) {
        console.warn(`  embed batch ${i}-${i+EMBED_BATCH} failed: ${err.message} — skipping embeddings for batch`);
      }
      process.stdout.write(`\r  embedded ${Math.min(i + EMBED_BATCH, rows.length)}/${rows.length}`);
    }
    console.log();
  }

  // Insert in batches
  for (let i = 0; i < rows.length; i += INSERT_BATCH) {
    await insertRows(client, rows.slice(i, i + INSERT_BATCH));
    process.stdout.write(`\r  inserted ${Math.min(i + INSERT_BATCH, rows.length)}/${rows.length}`);
  }
  console.log();
  console.log(`[${name}] ✅ done`);
}

// ---------------------------------------------------------------------------
// Source downloaders
// ---------------------------------------------------------------------------
async function importAMC12(client) {
  console.log('[amc12] downloading…');
  const url = 'https://huggingface.co/datasets/edev2000/amc12-full/resolve/main/amc12_dataset_full_annotated.jsonl';
  const text = await httpsGet(url);
  const raw  = parseJsonLines(text);
  const rows = raw.map(normalizeAMC12);
  await runSource('amc12', rows, client);
}

async function importAIME(client) {
  console.log('[aime] downloading…');
  const url = 'https://huggingface.co/datasets/gneubig/aime-1983-2024/resolve/main/AIME_Dataset_1983_2024.csv';
  const text = await httpsGet(url);

  const lines  = text.split('\n').filter(l => l.trim());
  const header = parseCsvLine(lines[0]).map(h => h.trim());
  const raw    = lines.slice(1).map(line => {
    const cols = parseCsvLine(line);
    return Object.fromEntries(header.map((h, i) => [h, (cols[i] || '').trim()]));
  });
  const rows = raw.map(normalizeAIME);
  await runSource('aime', rows, client);
}

async function importSAT(client) {
  console.log('[sat] downloading…');
  const url = 'https://raw.githubusercontent.com/ruixiangcui/AGIEval/main/data/v1/sat-math.jsonl';
  const text = await httpsGet(url);
  const raw  = parseJsonLines(text);
  const rows = raw.map(normalizeSAT);
  await runSource('sat', rows, client);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    const sources = {
      amc12: importAMC12,
      aime:  importAIME,
      sat:   importSAT,
    };

    const toRun = SOURCE_FILTER
      ? { [SOURCE_FILTER]: sources[SOURCE_FILTER] }
      : sources;

    for (const [name, fn] of Object.entries(toRun)) {
      if (!fn) { console.error(`Unknown source: ${name}`); continue; }
      await fn(client);
    }

    if (!DRY_RUN) {
      const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
      console.log(`\n📚 question_bank total rows: ${count}`);
    }
  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
