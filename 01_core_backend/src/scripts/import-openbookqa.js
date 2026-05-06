/**
 * Import OpenBookQA — Allen AI, Apache 2.0 license
 * ~5,957 elementary science questions (grade 4-8) with core science fact explanations
 *
 * Usage:
 *   railway run node src/scripts/import-openbookqa.js
 *   railway run node src/scripts/import-openbookqa.js --dry-run --limit=5
 */
'use strict';

require('dotenv').config();
const https  = require('https');
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { buildTaxonomyPrompt } = require('./taxonomy');

const DRY_RUN = process.argv.includes('--dry-run');
const LIMIT   = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();

const TAGGING_BATCH = 10;
const EMBED_BATCH   = 20;
const HF_PAGE_SIZE  = 50;  // smaller pages → fewer items per request
const VALID_SUBJECTS = new Set(['Biology', 'Chemistry', 'Physics']);

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

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
            reject(new Error('Rate limited — set HF_TOKEN in .env to avoid this')); return;
          }
          try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
        });
        res.on('error', reject);
      }).on('error', reject);
    };
    attempt(retries);
  });
}

async function fetchSplit(split) {
  const rows = [];
  let offset = 0;
  while (true) {
    const url = `https://datasets-server.huggingface.co/rows?dataset=allenai%2Fopenbookqa&config=additional&split=${split}&offset=${offset}&length=${HF_PAGE_SIZE}`;
    const data = await fetchJson(url);
    if (!data.rows?.length) break;
    rows.push(...data.rows.map(r => r.row));
    if (rows.length >= data.num_rows_total) break;
    offset += HF_PAGE_SIZE;
    await sleep(2500); // longer delay to stay under rate limit
  }
  return rows;
}

// ---------------------------------------------------------------------------
// GPT tagging — classify into Biology/Chemistry/Physics
// ---------------------------------------------------------------------------
const SCIENCE_TAXONOMY = `Biology:\n${buildTaxonomyPrompt('Biology')}\nChemistry:\n${buildTaxonomyPrompt('Chemistry')}\nPhysics:\n${buildTaxonomyPrompt('Physics')}`;

const TAG_SYSTEM = `Classify elementary science questions into EXACTLY one of: Biology, Chemistry, or Physics.
No other subject values allowed — map earth science/ecology/space to closest of the three.
Return: {"subject":"Biology|Chemistry|Physics","base_branch":"...","detailed_branch":"..."}

Taxonomy:
${SCIENCE_TAXONOMY}

Return ONLY a JSON array: [{"subject":"...","base_branch":"...","detailed_branch":"..."},...]`;

async function tagBatch(questions) {
  const numbered = questions.map((q, i) => `${i + 1}. ${q.slice(0, 300)}`).join('\n\n');
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0,
    max_tokens: questions.length * 50,
    messages: [{ role: 'system', content: TAG_SYSTEM }, { role: 'user', content: numbered }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) throw new Error('No JSON');
  const parsed = JSON.parse(m[0]);
  if (parsed.length !== questions.length) throw new Error('Count mismatch');
  return parsed;
}

async function tagOne(question) {
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0, max_tokens: 60,
    messages: [{ role: 'system', content: TAG_SYSTEM }, { role: 'user', content: `1. ${question.slice(0, 300)}` }],
  });
  const m = res.choices[0].message.content.trim().match(/\[[\s\S]*\]/);
  if (!m) return null;
  return JSON.parse(m[0])[0] || null;
}

async function embedBatch(rows) {
  const texts = rows.map(r => [r.question, `Subject: ${r.subject}`, r.base_branch, r.detailed_branch, `Answer: ${r.correct_answer}`].filter(Boolean).join(' | ').slice(0, 2000));
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

(async () => {
  const client = await pool.connect();
  try {
    console.log('\nOpenBookQA import\nDry run:', DRY_RUN);
    console.log('HF_TOKEN:', process.env.HF_TOKEN ? '✅ loaded' : '❌ missing — add HF_TOKEN to .env');
    let allRows = [];

    for (const split of ['test', 'validation']) {  // train split triggers rate limits; 1000 questions is sufficient
      console.log(`\nFetching ${split}…`);
      const raw = await fetchSplit(split);
      console.log(`  ${raw.length} questions`);
      const normalized = raw.slice(0, LIMIT).map(r => {
        const labels = r.choices?.label || [];
        const texts  = r.choices?.text  || [];
        const options = labels.map((label, i) => ({ label, text: String(texts[i] || ''), is_correct: label === r.answerKey }));
        return {
          source: 'openbookqa', source_id: `obqa_${r.id}`,
          subject: null, difficulty: 1, question_type: 'multiple_choice',
          question: r.question_stem,
          options,
          correct_answer: r.answerKey,
          explanation: r.fact1 || null,
          topic: null, base_branch: null, detailed_branch: null, embedding: null,
        };
      });
      allRows.push(...normalized);
      await sleep(5000); // 5s between splits
    }

    if (DRY_RUN) {
      allRows.slice(0, 3).forEach(r => {
        console.log(`\n  Q: ${r.question.slice(0, 80)}…`);
        console.log(`  Choices: ${r.options.map(o => `${o.label}) ${o.text.slice(0,25)}`).join(' | ')}`);
        console.log(`  A: ${r.correct_answer}  Fact: ${r.explanation?.slice(0,60) || '—'}`);
      });
      return;
    }

    // Tag
    console.log(`\nTagging ${allRows.length} questions…`);
    for (let i = 0; i < allRows.length; i += TAGGING_BATCH) {
      const batch = allRows.slice(i, i + TAGGING_BATCH);
      let tags;
      try { tags = await tagBatch(batch.map(r => r.question)); }
      catch { tags = await Promise.all(batch.map(r => tagOne(r.question).catch(() => null))); }
      tags.forEach((t, j) => {
        if (t?.subject && VALID_SUBJECTS.has(t.subject) && t?.base_branch) {
          batch[j].subject = t.subject; batch[j].base_branch = t.base_branch;
          batch[j].detailed_branch = t.detailed_branch || null;
          batch[j].topic = t.detailed_branch ? `${t.base_branch} / ${t.detailed_branch}` : t.base_branch;
        } else {
          batch[j].subject = 'Biology'; batch[j].base_branch = 'Scientific Method & Lab Skills';
          batch[j].topic = 'Scientific Method & Lab Skills';
        }
      });
      process.stdout.write(`\r  tagged ${Math.min(i+TAGGING_BATCH, allRows.length)}/${allRows.length}`);
    }
    console.log();

    // Embed
    for (let i = 0; i < allRows.length; i += EMBED_BATCH) {
      const batch = allRows.slice(i, i + EMBED_BATCH);
      try { const v = await embedBatch(batch); v.forEach((vec, j) => { batch[j].embedding = vec; }); }
      catch (e) { console.warn(`  embed batch ${i} failed: ${e.message}`); }
      process.stdout.write(`\r  embedded ${Math.min(i+EMBED_BATCH, allRows.length)}/${allRows.length}`);
    }
    console.log();

    await insertRows(client, allRows);
    const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
    console.log(`\n✅ OpenBookQA done. question_bank total: ${count}`);
  } finally { client.release(); await pool.end(); }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
