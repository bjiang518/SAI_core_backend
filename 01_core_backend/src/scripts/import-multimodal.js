/**
 * Import multimodal question datasets with images into question_bank.
 *
 * Datasets:
 *   scienceqa  — derek-thomas/ScienceQA  (CC-BY-SA 4.0) — K-12 science MCQ with diagrams
 *   ai2d       — lmms-lab/ai2d           (unspecified)   — Science diagram MCQ
 *   mathvista  — AI4Math/MathVista       (CC-BY-SA 4.0)  — Math MCQ with visual context
 *
 * Images come as CDN URLs from the HuggingFace datasets-server API.
 * Downloaded and stored as base64 in figure_data (same as AoPS figures).
 *
 * Usage:
 *   railway run node src/scripts/import-multimodal.js
 *   railway run node src/scripts/import-multimodal.js --dataset=scienceqa
 *   railway run node src/scripts/import-multimodal.js --dataset=ai2d
 *   railway run node src/scripts/import-multimodal.js --dataset=mathvista
 *   railway run node src/scripts/import-multimodal.js --dry-run --limit=5
 */

'use strict';

require('dotenv').config();
const https  = require('https');
const http   = require('http');
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { buildTaxonomyPrompt, TAXONOMY } = require('./taxonomy');

const DRY_RUN = process.argv.includes('--dry-run');
const LIMIT   = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();
const DS_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--dataset=')); return f ? f.split('=')[1] : null; })();

const TAGGING_BATCH = 8;
const EMBED_BATCH   = 20;
const HF_PAGE_SIZE  = 100;

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const LETTERS = ['A', 'B', 'C', 'D', 'E'];

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function fetchJson(url, retries = 4) {
  return new Promise((resolve, reject) => {
    const headers = { 'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json' };
    if (process.env.HF_TOKEN) headers['Authorization'] = `Bearer ${process.env.HF_TOKEN}`;
    const attempt = (n) => {
      https.get(url, { headers }, res => {
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', async () => {
          const body = Buffer.concat(chunks).toString();
          if (body.trim().startsWith('<')) {
            if (n > 0) { await sleep((5 - n) * 3000); attempt(n - 1); return; }
            reject(new Error('Rate limited')); return;
          }
          try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
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
    if (process.env.HF_TOKEN && fullUrl.includes('huggingface')) headers['Authorization'] = `Bearer ${process.env.HF_TOKEN}`;
    lib.get(fullUrl, { headers, timeout: 15000 }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, mime: (res.headers['content-type'] || 'image/png').split(';')[0].trim(), body: Buffer.concat(chunks) }));
      res.on('error', reject);
    }).on('error', reject).on('timeout', () => reject(new Error('Image download timeout')));
  });
}

async function fetchHFPages(dataset, config, split, limitRows) {
  const rows = [];
  let offset = 0;
  while (rows.length < limitRows) {
    const url = `https://datasets-server.huggingface.co/rows?dataset=${encodeURIComponent(dataset)}&config=${config}&split=${split}&offset=${offset}&length=${HF_PAGE_SIZE}`;
    const data = await fetchJson(url);
    if (!data.rows?.length) break;
    rows.push(...data.rows.map(r => r.row));
    if (rows.length >= Math.min(limitRows, data.num_rows_total)) break;
    offset += HF_PAGE_SIZE;
    await sleep(1800);
  }
  return rows.slice(0, limitRows);
}

// ---------------------------------------------------------------------------
// GPT taxonomy tagging
// ---------------------------------------------------------------------------
function buildTagPrompt(subjectKey) {
  const tax = buildTaxonomyPrompt(subjectKey);
  return `Classify questions into the taxonomy below. Return JSON array:
[{"base_branch":"...","detailed_branch":"..."},...]
Both values must EXACTLY match taxonomy entries.

${subjectKey}:
${tax}`;
}

async function tagBatch(questions, subjectKey) {
  if (!TAXONOMY[subjectKey]) return questions.map(() => null);
  const numbered = questions.map((q, i) => `${i + 1}. ${q.slice(0, 350)}`).join('\n\n');
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0, max_tokens: questions.length * 45,
    messages: [{ role: 'system', content: buildTagPrompt(subjectKey) }, { role: 'user', content: numbered }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) throw new Error('No JSON');
  const parsed = JSON.parse(m[0]);
  if (parsed.length !== questions.length) throw new Error('Count mismatch');
  return parsed;
}

async function tagOne(question, subjectKey) {
  if (!TAXONOMY[subjectKey]) return null;
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0, max_tokens: 50,
    messages: [{ role: 'system', content: buildTagPrompt(subjectKey) }, { role: 'user', content: `1. ${question.slice(0, 350)}` }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) return null;
  return JSON.parse(m[0])[0] || null;
}

// ---------------------------------------------------------------------------
// Embedding
// ---------------------------------------------------------------------------
async function embedBatch(rows) {
  const texts = rows.map(r => [r.question, `Subject: ${r.subject}`, r.base_branch, r.detailed_branch, r.correct_answer ? `Answer: ${r.correct_answer}` : ''].filter(Boolean).join(' | ').slice(0, 2000));
  const res = await openai.embeddings.create({ model: 'text-embedding-3-small', input: texts });
  return res.data.map(d => d.embedding);
}

// ---------------------------------------------------------------------------
// DB insert
// ---------------------------------------------------------------------------
async function insertRows(client, rows) {
  for (let i = 0; i < rows.length; i += 50) {
    const batch = rows.slice(i, i + 50);
    const ph = batch.map((_, idx) => { const b = idx * 14; return `($${b+1},$${b+2},$${b+3},$${b+4},$${b+5},$${b+6},$${b+7},$${b+8},$${b+9},$${b+10},$${b+11},$${b+12},$${b+13},$${b+14})`; }).join(',');
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
// ScienceQA normalizer
// ---------------------------------------------------------------------------
function scienceqaSubject(subject, topic) {
  const s = (subject || '').toLowerCase();
  const t = (topic || '').toLowerCase();
  if (s === 'social science') return 'History';
  if (s === 'language science') return 'English';
  // natural science — infer from topic
  if (/bio|life|plant|animal|cell|organ|ecolog|microb|genet|evolution|human body/.test(t)) return 'Biology';
  if (/chem|element|compound|reaction|molecule|acid|base|bond/.test(t)) return 'Chemistry';
  if (/physic|force|motion|energy|electric|wave|light|heat|magnet|mech/.test(t)) return 'Physics';
  if (/earth|geology|weather|climate|rock|mineral|tectonic|ocean|atmos/.test(t)) return 'Biology';  // Earth sci → Biology
  if (/astro|space|planet|star|solar|cosmos/.test(t)) return 'Physics';
  return 'Biology'; // default natural science
}

function scienceqaDifficulty(grade) {
  const num = parseInt((grade || '').replace(/\D/g, '') || '5', 10);
  if (num <= 3) return 1;
  if (num <= 6) return 2;
  if (num <= 9) return 3;
  return 4;
}

async function importScienceQA(client, limitRows) {
  console.log('\n📥 ScienceQA');
  const splits = ['train', 'validation', 'test'];
  const perSplit = Math.ceil(limitRows / splits.length);
  const allRows = [];
  for (const split of splits) {
    console.log(`  Fetching ${split}…`);
    const rows = await fetchHFPages('derek-thomas/ScienceQA', 'default', split, perSplit);
    console.log(`  ${rows.length} rows`);
    allRows.push(...rows.map((r, idx) => ({ ...r, _split: split, _idx: idx })));
    await sleep(2000);
  }
  return processDataset(client, allRows, 'scienceqa', limitRows, (r) => {
    const choices = r.choices || [];
    const answerIdx = typeof r.answer === 'number' ? r.answer : parseInt(r.answer || '0', 10);
    const correctLetter = LETTERS[answerIdx] || 'A';
    const options = choices.map((text, i) => ({ label: LETTERS[i], text: String(text), is_correct: i === answerIdx }));
    const hasImage = !!(r.image?.src);
    return {
      source: 'scienceqa',
      source_id: `scienceqa_${r._split}_${r._idx}`,
      subject: scienceqaSubject(r.subject, r.topic),
      difficulty: scienceqaDifficulty(r.grade),
      question_type: options.length > 0 ? 'multiple_choice' : 'short_answer',
      question: r.question,
      options: options.length > 0 ? options : null,
      correct_answer: correctLetter,
      explanation: r.solution || r.lecture || null,
      image_url: r.image?.src || null,
      has_image: hasImage,
    };
  });
}

// ---------------------------------------------------------------------------
// AI2D normalizer
// ---------------------------------------------------------------------------
async function importAI2D(client, limitRows) {
  console.log('\n📥 AI2D');
  const rows = await fetchHFPages('lmms-lab/ai2d', 'default', 'test', limitRows);
  console.log(`  ${rows.length} rows`);
  return processDataset(client, rows, 'ai2d', limitRows, (r, idx) => {
    const options = (r.options || []);
    const answerIdx = parseInt(r.answer || '0', 10);
    // options are diagram labels ('a','b','c','d') — display as-is
    const formattedOptions = options.map((text, i) => ({
      label: LETTERS[i],
      text: String(text).trim(),
      is_correct: i === answerIdx,
    }));
    return {
      source: 'ai2d',
      source_id: `ai2d_${idx}`,
      subject: 'Biology',         // Earth/life science diagrams — default Biology
      difficulty: 2,
      question_type: 'multiple_choice',
      question: r.question,
      options: formattedOptions,
      correct_answer: LETTERS[answerIdx] || 'A',
      explanation: null,
      image_url: r.image?.src || null,
      has_image: !!(r.image?.src),
    };
  });
}

// ---------------------------------------------------------------------------
// MathVista normalizer
// ---------------------------------------------------------------------------
function mathvistaDifficulty(meta) {
  const g = ((meta || {}).grade || '').toLowerCase();
  if (g.includes('elementary')) return 2;
  if (g.includes('middle'))     return 3;
  if (g.includes('high'))       return 4;
  if (g.includes('college'))    return 5;
  return 3;
}

async function importMathVista(client, limitRows) {
  console.log('\n📥 MathVista');
  // testmini has 1000 rows; test has 5140 — start with testmini
  const splits = limitRows <= 1000 ? ['testmini'] : ['testmini', 'test'];
  const allRows = [];
  for (const split of splits) {
    const lim = Math.min(limitRows - allRows.length, split === 'testmini' ? 1000 : limitRows);
    const rows = await fetchHFPages('AI4Math/MathVista', 'default', split, lim);
    allRows.push(...rows.map(r => ({ ...r, _split: split })));
    await sleep(2000);
  }
  // Only English MCQ (skip free_form and Chinese)
  const mcq = allRows.filter(r =>
    r.question_type === 'multi_choice' &&
    r.choices?.length > 0 &&
    (r.metadata?.language || 'english').toLowerCase() === 'english'
  );
  console.log(`  ${allRows.length} total, ${mcq.length} English MCQ`);
  return processDataset(client, mcq, 'mathvista', limitRows, (r, idx) => {
    const choices = r.choices || [];
    const correctLetter = choices.length > 0
      ? (LETTERS.includes(r.answer?.toUpperCase()) ? r.answer.toUpperCase() : 'A')
      : 'A';
    const options = choices.map((text, i) => ({
      label: LETTERS[i],
      text: String(text).trim(),
      is_correct: LETTERS[i] === correctLetter,
    }));
    // decoded_image has the CDN src URL; image is just a relative path string
    const imgSrc = r.decoded_image?.src || null;
    return {
      source: 'mathvista',
      source_id: `mathvista_${r.pid || idx}`,
      subject: 'Math',
      difficulty: mathvistaDifficulty(r.metadata),
      question_type: 'multiple_choice',
      question: r.question,
      options,
      correct_answer: correctLetter,
      explanation: null,
      image_url: imgSrc,
      has_image: !!imgSrc,
    };
  });
}

// ---------------------------------------------------------------------------
// Shared processing: tag + embed + insert
// ---------------------------------------------------------------------------
async function processDataset(client, rawRows, label, limitRows, normalizer) {
  const normalized = rawRows.slice(0, limitRows).map((r, idx) => {
    try { return normalizer(r, idx); }
    catch (e) { return null; }
  }).filter(Boolean);

  if (DRY_RUN) {
    normalized.slice(0, 3).forEach(r => {
      const imgStr = r.has_image ? '🖼 ' : '  ';
      console.log(`  ${imgStr}[${r.source}] [${r.subject}] [diff:${r.difficulty}]`);
      console.log(`     Q: ${r.question.slice(0, 90)}…`);
      console.log(`     Choices: ${r.options?.map(o => `${o.label}) ${o.text.slice(0,20)}`).join(' | ') || 'none'}`);
      console.log(`     A: ${r.correct_answer}  img: ${r.image_url ? 'yes' : 'no'}\n`);
    });
    const withImg = normalized.filter(r => r.has_image).length;
    console.log(`  ${normalized.length} questions (${withImg} with images)`);
    return normalized.length;
  }

  // Group by subject for taxonomy tagging
  const bySubject = {};
  normalized.forEach(r => { if (!bySubject[r.subject]) bySubject[r.subject] = []; bySubject[r.subject].push(r); });

  // Tag base_branch + detailed_branch
  console.log(`  Tagging ${normalized.length} questions…`);
  for (const [subj, rows] of Object.entries(bySubject)) {
    const taxKey = subj === 'Math' ? 'Math' : subj;
    for (let i = 0; i < rows.length; i += TAGGING_BATCH) {
      const batch = rows.slice(i, i + TAGGING_BATCH);
      let tags;
      try { tags = await tagBatch(batch.map(r => r.question), taxKey); }
      catch { tags = await Promise.all(batch.map(r => tagOne(r.question, taxKey).catch(() => null))); }
      tags.forEach((t, j) => {
        if (t?.base_branch) {
          batch[j].base_branch    = t.base_branch;
          batch[j].detailed_branch = t.detailed_branch || null;
          batch[j].topic = t.detailed_branch ? `${t.base_branch} / ${t.detailed_branch}` : t.base_branch;
        } else {
          batch[j].topic = subj;
        }
      });
      process.stdout.write(`\r    ${label} tagged ${Math.min(i + TAGGING_BATCH, rows.length)}/${rows.length} (${subj})`);
    }
  }
  console.log();

  // Download images
  console.log(`  Downloading images…`);
  let imgCount = 0;
  for (const row of normalized) {
    if (!row.image_url) continue;
    try {
      const res = await fetchBinary(row.image_url);
      if (res.status === 200 && res.body.length > 0) {
        row.figure_base64 = res.body.toString('base64');
        imgCount++;
      }
    } catch { /* non-critical */ }
  }
  console.log(`    ${imgCount}/${normalized.filter(r => r.image_url).length} images downloaded`);

  // Embed
  console.log(`  Embedding…`);
  for (let i = 0; i < normalized.length; i += EMBED_BATCH) {
    const batch = normalized.slice(i, i + EMBED_BATCH);
    try {
      const vecs = await embedBatch(batch);
      vecs.forEach((v, j) => { batch[j].embedding = v; });
    } catch (e) { console.warn(`    embed batch ${i} failed: ${e.message}`); }
    process.stdout.write(`\r    embedded ${Math.min(i + EMBED_BATCH, normalized.length)}/${normalized.length}`);
  }
  console.log();

  // Insert
  await insertRows(client, normalized);
  console.log(`  ✅ ${normalized.length} inserted (${imgCount} with images)`);
  return normalized.length;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    const datasets = {
      scienceqa: importScienceQA,
      ai2d:      importAI2D,
      mathvista: importMathVista,
    };

    const toRun = DS_FILTER
      ? { [DS_FILTER]: datasets[DS_FILTER] }
      : datasets;

    console.log(`\nMultimodal import`);
    console.log(`Datasets: ${Object.keys(toRun).join(', ')}`);
    console.log(`Dry run: ${DRY_RUN}\n`);

    let total = 0;
    for (const [name, fn] of Object.entries(toRun)) {
      if (!fn) { console.error(`Unknown dataset: ${name}`); continue; }
      const count = await fn(client, LIMIT);
      total += count;
    }

    console.log(`\n${'─'.repeat(60)}`);
    console.log(`Total processed: ${total}`);

    if (!DRY_RUN) {
      const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
      const { rows: [{ fig }] }   = await client.query('SELECT COUNT(*) fig FROM question_bank WHERE figure_data IS NOT NULL');
      console.log(`question_bank total: ${count} (${fig} with figures)`);
    }
  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
