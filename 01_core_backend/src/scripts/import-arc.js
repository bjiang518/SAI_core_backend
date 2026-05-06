/**
 * Import ARC (AI2 Reasoning Challenge) science questions into question_bank.
 *
 * Source: allenai/ai2_arc on HuggingFace (Apache 2.0 license)
 * Two configs:
 *   ARC-Easy      → difficulty 1-2, grade 3-5 science
 *   ARC-Challenge → difficulty 2-3, grade 6-9 science
 *
 * GPT-4o-mini classifies each question into Biology / Chemistry / Physics
 * and assigns base_branch + detailed_branch from the existing taxonomy.
 *
 * Usage:
 *   railway run node src/scripts/import-arc.js
 *   railway run node src/scripts/import-arc.js --config=ARC-Easy
 *   railway run node src/scripts/import-arc.js --dry-run --limit=5
 */

'use strict';

require('dotenv').config();
const https  = require('https');
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { buildTaxonomyPrompt } = require('./taxonomy');

const DRY_RUN     = process.argv.includes('--dry-run');
const LIMIT       = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();
const CONF_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--config=')); return f ? f.split('=')[1] : null; })();

const TAGGING_BATCH = 10;
const EMBED_BATCH   = 20;
const HF_PAGE_SIZE  = 100;

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ARC configs with difficulty mapping
const ARC_CONFIGS = [
  { config: 'ARC-Easy',      difficulty: 1, splits: ['test', 'validation'] },
  { config: 'ARC-Challenge', difficulty: 2, splits: ['test', 'validation'] },
];

// ---------------------------------------------------------------------------
// HuggingFace API with retry
// ---------------------------------------------------------------------------
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function fetchJson(url, retries = 4) {
  return new Promise((resolve, reject) => {
    const attempt = (n) => {
      https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (compatible; StudyAI/1.0)', 'Accept': 'application/json' } }, res => {
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', async () => {
          const body = Buffer.concat(chunks).toString();
          if (body.trim().startsWith('<')) {
            if (n > 0) {
              const delay = (5 - n) * 3000;
              process.stdout.write(`\r     rate limited — retrying in ${delay/1000}s…`);
              await sleep(delay);
              attempt(n - 1);
            } else {
              reject(new Error('HuggingFace rate limited after all retries'));
            }
            return;
          }
          try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
        });
        res.on('error', reject);
      }).on('error', reject);
    };
    attempt(retries);
  });
}

async function fetchARC(config, split) {
  const rows = [];
  let offset = 0;
  while (true) {
    const url = `https://datasets-server.huggingface.co/rows?dataset=allenai%2Fai2_arc&config=${config}&split=${split}&offset=${offset}&length=${HF_PAGE_SIZE}`;
    const data = await fetchJson(url);
    if (!data.rows || data.rows.length === 0) break;
    rows.push(...data.rows.map(r => r.row));
    if (rows.length >= data.num_rows_total) break;
    offset += HF_PAGE_SIZE;
    await sleep(1500);
  }
  return rows;
}

// ---------------------------------------------------------------------------
// GPT tagging — classify into Biology/Chemistry/Physics + base+detailed branch
// ---------------------------------------------------------------------------
const SCIENCE_TAXONOMY = `
Biology:
${buildTaxonomyPrompt('Biology')}

Chemistry:
${buildTaxonomyPrompt('Chemistry')}

Physics:
${buildTaxonomyPrompt('Physics')}
`;

const TAG_SYSTEM = `You classify K-12 science questions into EXACTLY one of three subjects: Biology, Chemistry, or Physics.
No other subject values are allowed — not Geology, Astronomy, Earth Science, etc.
Map everything to the closest of the three: earth science → Physics, ecology → Biology, biochemistry → Biology.

For each numbered question return a JSON object:
{"subject":"Biology|Chemistry|Physics","base_branch":"...","detailed_branch":"..."}

Both base_branch and detailed_branch must EXACTLY match entries in the taxonomy below.

Taxonomy:
${SCIENCE_TAXONOMY}

Return ONLY a JSON array: [{"subject":"...","base_branch":"...","detailed_branch":"..."},...]`;

async function tagBatch(questions) {
  const numbered = questions.map((q, i) => `${i + 1}. ${q.slice(0, 400)}`).join('\n\n');
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0,
    max_tokens: questions.length * 50,
    messages: [
      { role: 'system', content: TAG_SYSTEM },
      { role: 'user',   content: numbered },
    ],
  });
  const text = res.choices[0].message.content.trim();
  const m = text.match(/\[[\s\S]*\]/);
  if (!m) throw new Error('No JSON array');
  const parsed = JSON.parse(m[0]);
  if (parsed.length !== questions.length) throw new Error(`Count mismatch: ${parsed.length} vs ${questions.length}`);
  return parsed;
}

async function tagOne(question) {
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0, max_tokens: 60,
    messages: [
      { role: 'system', content: TAG_SYSTEM },
      { role: 'user',   content: `1. ${question.slice(0, 400)}` },
    ],
  });
  const text = res.choices[0].message.content.trim();
  const m = text.match(/\[[\s\S]*\]/);
  if (!m) return null;
  const parsed = JSON.parse(m[0]);
  return Array.isArray(parsed) && parsed[0] ? parsed[0] : null;
}

// ---------------------------------------------------------------------------
// Normalize raw ARC row → our schema (no tags/embedding yet)
// ---------------------------------------------------------------------------
function normalizeRow(row, arcConfig, difficulty) {
  const labels   = row.choices?.label || [];
  const texts    = row.choices?.text  || [];
  const answerKey = row.answerKey || 'A';

  const options = labels.map((label, i) => ({
    label,
    text:       String(texts[i] || ''),
    is_correct: label === answerKey,
  }));

  return {
    source:        'arc',
    source_id:     `${arcConfig.toLowerCase().replace('-','_')}_${row.id}`,
    subject:       null,   // filled by GPT
    topic:         null,
    base_branch:   null,
    detailed_branch: null,
    difficulty,
    question_type: 'multiple_choice',
    question:      row.question,
    options,
    correct_answer: answerKey,
    explanation:   null,
    embedding:     null,
  };
}

// ---------------------------------------------------------------------------
// Embedding
// ---------------------------------------------------------------------------
async function embedBatch(rows) {
  const texts = rows.map(r => {
    const parts = [r.question];
    if (r.subject)         parts.push(`Subject: ${r.subject}`);
    if (r.base_branch)     parts.push(r.base_branch);
    if (r.detailed_branch) parts.push(r.detailed_branch);
    if (r.correct_answer)  parts.push(`Answer: ${r.correct_answer}`);
    return parts.join(' | ').slice(0, 2000);
  });
  const res = await openai.embeddings.create({ model: 'text-embedding-3-small', input: texts });
  return res.data.map(d => d.embedding);
}

// ---------------------------------------------------------------------------
// DB insert
// ---------------------------------------------------------------------------
async function insertRows(client, rows) {
  for (let i = 0; i < rows.length; i += 50) {
    const batch = rows.slice(i, i + 50);
    const placeholders = batch.map((_, idx) => {
      const b = idx * 13;
      return `($${b+1},$${b+2},$${b+3},$${b+4},$${b+5},$${b+6},$${b+7},$${b+8},$${b+9},$${b+10},$${b+11},$${b+12},$${b+13})`;
    }).join(',');
    const values = batch.flatMap(r => [
      r.source, r.source_id, r.subject, r.topic,
      r.base_branch, r.detailed_branch, r.difficulty, r.question_type,
      r.question, JSON.stringify(r.options),
      r.correct_answer, r.explanation, r.embedding,
    ]);
    await client.query(`
      INSERT INTO question_bank
        (source, source_id, subject, topic, base_branch, detailed_branch,
         difficulty, question_type, question, options, correct_answer,
         explanation, embedding)
      VALUES ${placeholders}
      ON CONFLICT ON CONSTRAINT uq_question_bank_source_id DO NOTHING
    `, values);
  }
}

// ---------------------------------------------------------------------------
// Process one ARC config + split
// ---------------------------------------------------------------------------
async function processConfig(client, arcConfig, difficulty, split, limit) {
  console.log(`\n  📥 ${arcConfig} / ${split} (diff:${difficulty})`);

  const rawRows = await fetchARC(arcConfig, split);
  console.log(`     ${rawRows.length} questions`);

  const normalized = rawRows.slice(0, limit).map(r => normalizeRow(r, arcConfig, difficulty));

  if (DRY_RUN) {
    const s = normalized[0];
    console.log(`     Sample: ${s.question.slice(0, 80)}…`);
    console.log(`     Choices: ${s.options.map(o => `${o.label}) ${o.text.slice(0,20)}`).join(' | ')}`);
    console.log(`     Answer: ${s.correct_answer}`);
    return normalized.length;
  }

  // Tag
  let tagged = 0;
  for (let i = 0; i < normalized.length; i += TAGGING_BATCH) {
    const batch = normalized.slice(i, i + TAGGING_BATCH);
    let results;
    try {
      results = await tagBatch(batch.map(r => r.question));
    } catch {
      results = await Promise.all(batch.map(r => tagOne(r.question).catch(() => null)));
    }
    const VALID_SUBJECTS = new Set(['Biology', 'Chemistry', 'Physics']);
    results.forEach((tag, j) => {
      if (tag?.subject && VALID_SUBJECTS.has(tag.subject) && tag?.base_branch) {
        batch[j].subject         = tag.subject;
        batch[j].base_branch     = tag.base_branch;
        batch[j].detailed_branch = tag.detailed_branch || null;
        batch[j].topic           = tag.detailed_branch
          ? `${tag.base_branch} / ${tag.detailed_branch}`
          : tag.base_branch;
      } else {
        batch[j].subject = 'Biology';
        batch[j].topic   = 'Scientific Method & Lab Skills';
      }
    });
    tagged += batch.length;
    process.stdout.write(`\r     tagged ${tagged}/${normalized.length}`);
  }
  console.log();

  // Embed
  for (let i = 0; i < normalized.length; i += EMBED_BATCH) {
    const batch = normalized.slice(i, i + EMBED_BATCH);
    try {
      const vectors = await embedBatch(batch);
      vectors.forEach((v, j) => { batch[j].embedding = v; });
    } catch (err) {
      console.warn(`     embed batch ${i} failed: ${err.message}`);
    }
    process.stdout.write(`\r     embedded ${Math.min(i+EMBED_BATCH, normalized.length)}/${normalized.length}`);
  }
  console.log();

  await insertRows(client, normalized);
  console.log(`     ✅ inserted`);
  return normalized.length;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    const configs = ARC_CONFIGS.filter(c => !CONF_FILTER || c.config === CONF_FILTER);

    console.log(`\nARC import`);
    console.log(`Configs    : ${configs.map(c => c.config).join(', ')}`);
    console.log(`Dry run    : ${DRY_RUN}\n`);

    let total = 0;
    for (const arcConfig of configs) {
      for (const split of arcConfig.splits) {
        try {
          const count = await processConfig(client, arcConfig.config, arcConfig.difficulty, split, LIMIT);
          total += count;
          await sleep(2000);
        } catch (err) {
          console.error(`  ❌ ${arcConfig.config}/${split}: ${err.message}`);
          await sleep(5000);
        }
      }
    }

    console.log(`\n${'─'.repeat(60)}`);
    console.log(`Questions processed: ${total}`);

    if (!DRY_RUN) {
      const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
      const { rows: dist }        = await client.query(`SELECT subject, COUNT(*) n FROM question_bank WHERE source='arc' GROUP BY subject ORDER BY n DESC`);
      console.log(`question_bank total: ${count}`);
      console.log('\nARC by subject:');
      dist.forEach(r => console.log(`  ${String(r.n).padStart(5)} × ${r.subject}`));
    }

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
