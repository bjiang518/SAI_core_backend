/**
 * Import AGIEval non-math English datasets — MIT license
 *
 * Files imported:
 *   sat-en.jsonl    — SAT English reading (206 questions, diff:3, with passage)
 *   lsat-lr.jsonl   — LSAT Logical Reasoning (510 questions, diff:4)
 *   lsat-rc.jsonl   — LSAT Reading Comprehension (270 questions, diff:4, with passage)
 *   lsat-ar.jsonl   — LSAT Analytical Reasoning (230 questions, diff:5)
 *
 * For passage-based questions, passage is prepended to the question text.
 * Options format: "(A) text" — letter extracted as label.
 *
 * Usage:
 *   railway run node src/scripts/import-agieval.js
 *   railway run node src/scripts/import-agieval.js --file=lsat-lr
 *   railway run node src/scripts/import-agieval.js --dry-run --limit=3
 */
'use strict';

require('dotenv').config();
const https  = require('https');
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { buildTaxonomyPrompt } = require('./taxonomy');

const DRY_RUN     = process.argv.includes('--dry-run');
const LIMIT       = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();
const FILE_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--file=')); return f ? f.split('=')[1] : null; })();

const TAGGING_BATCH = 10;
const EMBED_BATCH   = 20;

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// AGIEval files and their metadata
const AGIEVAL_FILES = [
  { file: 'sat-en',  subject: 'English', difficulty: 3, hasPassage: true  },
  { file: 'lsat-lr', subject: 'English', difficulty: 4, hasPassage: true  },
  { file: 'lsat-rc', subject: 'English', difficulty: 4, hasPassage: true  },
  { file: 'lsat-ar', subject: 'English', difficulty: 5, hasPassage: true  },
];

const BASE_URL = 'https://raw.githubusercontent.com/ruixiangcui/AGIEval/main/data/v1';

// ---------------------------------------------------------------------------
// Download + parse JSONL from GitHub
// ---------------------------------------------------------------------------
function fetchText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'StudyAI-import/1.0' } }, res => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
      res.on('error', reject);
    }).on('error', reject);
  });
}

function parseJsonl(text) {
  return text.split('\n').map(l => l.trim()).filter(Boolean).map(l => JSON.parse(l));
}

// ---------------------------------------------------------------------------
// Normalize a raw AGIEval row
// Options format: "(A) some text" or ["(A) text", "(B) text", ...]
// ---------------------------------------------------------------------------
function normalizeRow(row, fileConfig, idx) {
  const rawOptions = row.options || [];

  // Parse each option: "(A) text" → {label: "A", text: "text"}
  const options = rawOptions.map(opt => {
    const m = String(opt).match(/^\(([A-E])\)\s*(.*)/s);
    return m ? { label: m[1], text: m[2].trim(), is_correct: m[1] === row.label }
              : { label: opt, text: opt, is_correct: opt === row.label };
  });

  // Build question text — include passage if present (truncated to keep embedding meaningful)
  let questionText = row.question || '';
  if (row.passage && row.passage.trim()) {
    const truncatedPassage = row.passage.length > 1500
      ? row.passage.slice(0, 1500) + '…'
      : row.passage;
    questionText = `[Passage]\n${truncatedPassage}\n\n[Question]\n${questionText}`;
  }

  return {
    source:        'agieval',
    source_id:     `agieval_${fileConfig.file.replace('-', '_')}_${idx}`,
    subject:       fileConfig.subject,
    difficulty:    fileConfig.difficulty,
    question_type: 'multiple_choice',
    question:      questionText,
    options,
    correct_answer: row.label || 'A',
    explanation:   row.other?.solution || null,
    topic:         null, base_branch: null, detailed_branch: null, embedding: null,
  };
}

// ---------------------------------------------------------------------------
// GPT tagging for English taxonomy
// ---------------------------------------------------------------------------
const ENGLISH_TAXONOMY = buildTaxonomyPrompt('English');
const TAG_SYSTEM = `You classify English language arts questions into the taxonomy below.
Return: {"base_branch":"...","detailed_branch":"..."} for each question.
Both values must EXACTLY match taxonomy entries.

Taxonomy:
${ENGLISH_TAXONOMY}

Return ONLY a JSON array: [{"base_branch":"...","detailed_branch":"..."},...]`;

async function tagBatch(questions) {
  const numbered = questions.map((q, i) => {
    // Use only the [Question] part for tagging if passage present
    const qOnly = q.includes('[Question]\n') ? q.split('[Question]\n')[1] : q;
    return `${i + 1}. ${qOnly.slice(0, 300)}`;
  }).join('\n\n');
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0,
    max_tokens: questions.length * 40,
    messages: [{ role: 'system', content: TAG_SYSTEM }, { role: 'user', content: numbered }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) throw new Error('No JSON');
  const parsed = JSON.parse(m[0]);
  if (parsed.length !== questions.length) throw new Error('Count mismatch');
  return parsed;
}

async function tagOne(question) {
  const qOnly = question.includes('[Question]\n') ? question.split('[Question]\n')[1] : question;
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0, max_tokens: 60,
    messages: [{ role: 'system', content: TAG_SYSTEM }, { role: 'user', content: `1. ${qOnly.slice(0, 300)}` }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) return null;
  return JSON.parse(m[0])[0] || null;
}

async function embedBatch(rows) {
  const texts = rows.map(r => {
    // For embedding, use question (without passage) + taxonomy
    const qOnly = r.question.includes('[Question]\n') ? r.question.split('[Question]\n')[1] : r.question;
    return [qOnly, `Subject: ${r.subject}`, r.base_branch, r.detailed_branch].filter(Boolean).join(' | ').slice(0, 2000);
  });
  const res = await openai.embeddings.create({ model: 'text-embedding-3-small', input: texts });
  return res.data.map(d => d.embedding);
}

async function insertRows(client, rows) {
  for (let i = 0; i < rows.length; i += 50) {
    const batch = rows.slice(i, i + 50);
    const ph = batch.map((_, idx) => { const b = idx * 13; return `($${b+1},$${b+2},$${b+3},$${b+4},$${b+5},$${b+6},$${b+7},$${b+8},$${b+9},$${b+10},$${b+11},$${b+12},$${b+13})`; }).join(',');
    const vals = batch.flatMap(r => [r.source, r.source_id, r.subject, r.topic, r.base_branch, r.detailed_branch, r.difficulty, r.question_type, r.question, JSON.stringify(r.options), r.correct_answer, r.explanation, r.embedding]);
    await client.query(`INSERT INTO question_bank (source,source_id,subject,topic,base_branch,detailed_branch,difficulty,question_type,question,options,correct_answer,explanation,embedding) VALUES ${ph} ON CONFLICT ON CONSTRAINT uq_question_bank_source_id DO NOTHING`, vals);
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    const files = AGIEVAL_FILES.filter(f => !FILE_FILTER || f.file === FILE_FILTER);
    console.log(`\nAGIEval import — files: ${files.map(f => f.file).join(', ')}`);
    console.log(`Dry run: ${DRY_RUN}\n`);

    let grandTotal = 0;
    for (const fileConfig of files) {
      console.log(`\n📥 ${fileConfig.file} (${fileConfig.subject}, diff:${fileConfig.difficulty})`);
      const text = await fetchText(`${BASE_URL}/${fileConfig.file}.jsonl`);
      const raw  = parseJsonl(text);
      console.log(`   ${raw.length} questions`);

      const allRows = raw.slice(0, LIMIT).map((r, idx) => normalizeRow(r, fileConfig, idx));

      if (DRY_RUN) {
        allRows.slice(0, 2).forEach(r => {
          const preview = r.question.includes('[Question]\n')
            ? r.question.split('[Question]\n')[1].slice(0, 80)
            : r.question.slice(0, 80);
          console.log(`   Q: ${preview}…`);
          console.log(`   Options: ${r.options.map(o => `${o.label}) ${o.text.slice(0,20)}`).join(' | ')}`);
          console.log(`   A: ${r.correct_answer}\n`);
        });
        grandTotal += allRows.length;
        continue;
      }

      // Tag
      for (let i = 0; i < allRows.length; i += TAGGING_BATCH) {
        const batch = allRows.slice(i, i + TAGGING_BATCH);
        let tags;
        try { tags = await tagBatch(batch.map(r => r.question)); }
        catch { tags = await Promise.all(batch.map(r => tagOne(r.question).catch(() => null))); }
        tags.forEach((t, j) => {
          if (t?.base_branch) {
            batch[j].base_branch = t.base_branch; batch[j].detailed_branch = t.detailed_branch || null;
            batch[j].topic = t.detailed_branch ? `${t.base_branch} / ${t.detailed_branch}` : t.base_branch;
          } else {
            batch[j].base_branch = 'Reading Comprehension'; batch[j].topic = 'Reading Comprehension';
          }
        });
        process.stdout.write(`\r   tagged ${Math.min(i+TAGGING_BATCH, allRows.length)}/${allRows.length}`);
      }
      console.log();

      // Embed
      for (let i = 0; i < allRows.length; i += EMBED_BATCH) {
        const batch = allRows.slice(i, i + EMBED_BATCH);
        try { const v = await embedBatch(batch); v.forEach((vec, j) => { batch[j].embedding = vec; }); }
        catch (e) { console.warn(`   embed batch ${i} failed: ${e.message}`); }
        process.stdout.write(`\r   embedded ${Math.min(i+EMBED_BATCH, allRows.length)}/${allRows.length}`);
      }
      console.log();

      await insertRows(client, allRows);
      console.log(`   ✅ inserted`);
      grandTotal += allRows.length;
    }

    console.log(`\n${'─'.repeat(50)}`);
    console.log(`Total processed: ${grandTotal}`);
    if (!DRY_RUN) {
      const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
      console.log(`question_bank total: ${count}`);
    }
  } finally { client.release(); await pool.end(); }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
