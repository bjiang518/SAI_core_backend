/**
 * Import MMLU (Massive Multitask Language Understanding) questions into question_bank.
 *
 * Source: cais/mmlu on HuggingFace (MIT license)
 * API:    datasets-server.huggingface.co (JSON, no Parquet needed)
 * Format: question + 4 choices (A-D) + answer index 0-3
 *
 * Maps 57 MMLU subjects → our canonical subjects (Math, Biology, Chemistry,
 * Physics, Computer Science, History, English) + taxonomy-aligned tags via GPT.
 *
 * Usage:
 *   railway run node src/scripts/import-mmlu.js
 *   railway run node src/scripts/import-mmlu.js --subject=biology
 *   railway run node src/scripts/import-mmlu.js --subject=math --dry-run
 *   railway run node src/scripts/import-mmlu.js --dry-run --limit=5
 */

'use strict';

require('dotenv').config();
const https  = require('https');
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { buildTaxonomyPrompt, validateTaxonomyPath, parseWeaknessKey } = require('./taxonomy');

const DRY_RUN      = process.argv.includes('--dry-run');
const LIMIT        = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();
const SUBJ_FILTER  = (() => { const f = process.argv.find(a => a.startsWith('--subject=')); return f ? f.split('=')[1].toLowerCase() : null; })();

const TAGGING_BATCH = 10;
const EMBED_BATCH   = 20;
const HF_PAGE_SIZE  = 100;
const LETTERS       = ['A', 'B', 'C', 'D'];

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ---------------------------------------------------------------------------
// MMLU subject → { subject (our canonical), difficulty }
// Only includes subjects that map cleanly to our taxonomy.
// Difficulty: elementary=2, high_school=3, college/professional=4, research=5
// ---------------------------------------------------------------------------
const SUBJECT_MAP = {
  // Mathematics
  elementary_mathematics:              { subject: 'Math',             difficulty: 2 },
  high_school_mathematics:             { subject: 'Math',             difficulty: 3 },
  high_school_statistics:              { subject: 'Math',             difficulty: 3 },
  college_mathematics:                 { subject: 'Math',             difficulty: 4 },
  abstract_algebra:                    { subject: 'Math',             difficulty: 5 },

  // Biology
  high_school_biology:                 { subject: 'Biology',          difficulty: 3 },
  college_biology:                     { subject: 'Biology',          difficulty: 4 },
  anatomy:                             { subject: 'Biology',          difficulty: 3 },
  clinical_knowledge:                  { subject: 'Biology',          difficulty: 3 },
  medical_genetics:                    { subject: 'Biology',          difficulty: 4 },
  college_medicine:                    { subject: 'Biology',          difficulty: 4 },
  professional_medicine:               { subject: 'Biology',          difficulty: 4 },
  human_aging:                         { subject: 'Biology',          difficulty: 3 },
  nutrition:                           { subject: 'Biology',          difficulty: 3 },
  virology:                            { subject: 'Biology',          difficulty: 4 },

  // Chemistry
  high_school_chemistry:               { subject: 'Chemistry',        difficulty: 3 },
  college_chemistry:                   { subject: 'Chemistry',        difficulty: 4 },

  // Physics
  high_school_physics:                 { subject: 'Physics',          difficulty: 3 },
  college_physics:                     { subject: 'Physics',          difficulty: 4 },
  conceptual_physics:                  { subject: 'Physics',          difficulty: 3 },
  electrical_engineering:              { subject: 'Physics',          difficulty: 4 },
  astronomy:                           { subject: 'Physics',          difficulty: 3 },

  // Computer Science
  high_school_computer_science:        { subject: 'Computer Science', difficulty: 3 },
  college_computer_science:            { subject: 'Computer Science', difficulty: 4 },
  computer_security:                   { subject: 'Computer Science', difficulty: 3 },
  machine_learning:                    { subject: 'Computer Science', difficulty: 5 },

  // History / Social Studies
  high_school_us_history:              { subject: 'History',          difficulty: 3 },
  high_school_world_history:           { subject: 'History',          difficulty: 3 },
  high_school_european_history:        { subject: 'History',          difficulty: 3 },
  high_school_government_and_politics: { subject: 'History',          difficulty: 3 },
  high_school_geography:               { subject: 'History',          difficulty: 3 },
  high_school_macroeconomics:          { subject: 'History',          difficulty: 3 },
  high_school_microeconomics:          { subject: 'History',          difficulty: 3 },
  prehistory:                          { subject: 'History',          difficulty: 3 },
  world_religions:                     { subject: 'History',          difficulty: 3 },
  global_facts:                        { subject: 'History',          difficulty: 3 },
  sociology:                           { subject: 'History',          difficulty: 3 },
  us_foreign_policy:                   { subject: 'History',          difficulty: 4 },
  security_studies:                    { subject: 'History',          difficulty: 4 },
  international_law:                   { subject: 'History',          difficulty: 4 },
  jurisprudence:                       { subject: 'History',          difficulty: 4 },
  professional_law:                    { subject: 'History',          difficulty: 4 },
  professional_accounting:             { subject: 'History',          difficulty: 4 },
  econometrics:                        { subject: 'History',          difficulty: 4 },
  management:                          { subject: 'History',          difficulty: 3 },
  marketing:                           { subject: 'History',          difficulty: 3 },
  business_ethics:                     { subject: 'History',          difficulty: 3 },
  public_relations:                    { subject: 'History',          difficulty: 3 },

  // English / Logic
  formal_logic:                        { subject: 'English',          difficulty: 4 },
  logical_fallacies:                   { subject: 'English',          difficulty: 3 },
  philosophy:                          { subject: 'English',          difficulty: 4 },
  moral_disputes:                      { subject: 'English',          difficulty: 4 },
};

// Filter by --subject flag (matches our canonical subject name, lowercase)
function subjectFilter(entry) {
  if (!SUBJ_FILTER) return true;
  return entry.subject.toLowerCase() === SUBJ_FILTER ||
         entry.subject.toLowerCase().includes(SUBJ_FILTER);
}

// ---------------------------------------------------------------------------
// HuggingFace datasets-server API fetch
// ---------------------------------------------------------------------------
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function fetchJson(url, retries = 4) {
  return new Promise((resolve, reject) => {
    const attempt = (n) => {
      https.get(url, { headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; StudyAI-import/1.0)',
        'Accept': 'application/json',
      }}, res => {
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', async () => {
          const body = Buffer.concat(chunks).toString();
          // HuggingFace returns HTML on rate limit or error
          if (body.trim().startsWith('<')) {
            if (n > 0) {
              const delay = (5 - n) * 3000; // 3s, 6s, 9s, 12s
              process.stdout.write(`\r     rate limited — retrying in ${delay/1000}s…`);
              await sleep(delay);
              attempt(n - 1);
            } else {
              reject(new Error('HuggingFace returned HTML after all retries (rate limited)'));
            }
            return;
          }
          try { resolve(JSON.parse(body)); }
          catch (e) { reject(e); }
        });
        res.on('error', reject);
      }).on('error', reject);
    };
    attempt(retries);
  });
}

async function fetchMMLUSubject(config, split = 'test') {
  const rows = [];
  let offset = 0;
  while (true) {
    const url = `https://datasets-server.huggingface.co/rows?dataset=cais%2Fmmlu&config=${config}&split=${split}&offset=${offset}&length=${HF_PAGE_SIZE}`;
    const data = await fetchJson(url);
    if (!data.rows || data.rows.length === 0) break;
    rows.push(...data.rows.map(r => r.row));
    if (rows.length >= data.num_rows_total) break;
    offset += HF_PAGE_SIZE;
    await sleep(1500); // polite delay between pages
  }
  return rows;
}

// ---------------------------------------------------------------------------
// GPT taxonomy tagging — uses subject-specific taxonomy
// ---------------------------------------------------------------------------
function buildTaggingPrompt(subjectKey) {
  const taxonomyText = buildTaxonomyPrompt(subjectKey);
  return `You classify ${subjectKey} questions into the exact taxonomy below.
For each numbered question return a JSON object with "base_branch" and "detailed_branch".
Both values must EXACTLY match entries in the taxonomy (copy-paste the exact strings).

Taxonomy:
${taxonomyText}

Return ONLY a JSON array: [{"base_branch":"...","detailed_branch":"..."},...]`;
}

async function tagBatch(questions, subjectKey) {
  const systemPrompt = buildTaggingPrompt(subjectKey);
  const numbered = questions.map((q, i) => `${i + 1}. ${q.slice(0, 400)}`).join('\n\n');
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0,
    max_tokens: questions.length * 40,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: numbered },
    ],
  });
  const text = res.choices[0].message.content.trim();
  const m = text.match(/\[[\s\S]*\]/);
  if (!m) throw new Error('No JSON array');
  const parsed = JSON.parse(m[0]);
  if (parsed.length !== questions.length) throw new Error(`Count mismatch: got ${parsed.length}, expected ${questions.length}`);
  return parsed;
}

async function tagOne(question, subjectKey) {
  const systemPrompt = buildTaggingPrompt(subjectKey);
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini', temperature: 0, max_tokens: 60,
    messages: [
      { role: 'system', content: systemPrompt },
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
      r.question, r.options ? JSON.stringify(r.options) : null,
      r.correct_answer, r.explanation || null, r.embedding,
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
// Process one MMLU config
// ---------------------------------------------------------------------------
async function processConfig(client, mmluConfig, subjectInfo, totalLimit) {
  console.log(`\n  📥 ${mmluConfig} → ${subjectInfo.subject} (diff:${subjectInfo.difficulty})`);

  const rawRows = await fetchMMLUSubject(mmluConfig, 'test');
  console.log(`     ${rawRows.length} test questions`);

  const toProcess = rawRows.slice(0, totalLimit);

  // Normalize to our schema (without tags/embeddings yet)
  const normalized = toProcess.map((r, idx) => {
    const answerIdx = typeof r.answer === 'number' ? r.answer : parseInt(r.answer, 10);
    const correctLetter = LETTERS[answerIdx] || 'A';
    const options = (r.choices || []).map((text, i) => ({
      label: LETTERS[i],
      text:  String(text),
      is_correct: i === answerIdx,
    }));
    return {
      source:        'mmlu',
      source_id:     `${mmluConfig}_${idx}`,
      subject:       subjectInfo.subject,
      difficulty:    subjectInfo.difficulty,
      question_type: 'multiple_choice',
      question:      r.question,
      options,
      correct_answer: correctLetter,
      explanation:   null,
      base_branch:   null,
      detailed_branch: null,
      embedding:     null,
      topic:         null,
    };
  });

  if (DRY_RUN) {
    const sample = normalized[0];
    console.log(`     Sample Q: ${sample.question.slice(0, 80)}…`);
    console.log(`     Choices: ${sample.options.map(o => o.label).join(',')}`);
    console.log(`     Answer: ${sample.correct_answer}`);
    return normalized.length;
  }

  // Tag base_branch + detailed_branch
  const subjectKey = subjectInfo.subject === 'Math' ? 'Math' : subjectInfo.subject;
  let tagged = 0;
  for (let i = 0; i < normalized.length; i += TAGGING_BATCH) {
    const batch = normalized.slice(i, i + TAGGING_BATCH);
    let results;
    try {
      results = await tagBatch(batch.map(r => r.question), subjectKey);
    } catch {
      results = await Promise.all(batch.map(r => tagOne(r.question, subjectKey).catch(() => null)));
    }
    results.forEach((tag, j) => {
      if (tag?.base_branch) {
        batch[j].base_branch     = tag.base_branch;
        batch[j].detailed_branch = tag.detailed_branch || null;
        batch[j].topic           = tag.detailed_branch
          ? `${tag.base_branch} / ${tag.detailed_branch}`
          : tag.base_branch;
      } else {
        batch[j].topic = subjectInfo.subject;
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
    process.stdout.write(`\r     embedded ${Math.min(i + EMBED_BATCH, normalized.length)}/${normalized.length}`);
  }
  console.log();

  // Insert
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
    // Build list of configs to run
    const configs = Object.entries(SUBJECT_MAP)
      .filter(([, info]) => subjectFilter(info));

    const totalSubjects = configs.length;
    console.log(`\nMMLU import`);
    console.log(`Subjects to import : ${totalSubjects}`);
    console.log(`Subject filter     : ${SUBJ_FILTER || 'all'}`);
    console.log(`Limit per subject  : ${LIMIT}`);
    console.log(`Dry run            : ${DRY_RUN}\n`);

    let totalInserted = 0;
    for (const [mmluConfig, subjectInfo] of configs) {
      try {
        const count = await processConfig(client, mmluConfig, subjectInfo, LIMIT);
        totalInserted += count;
        await sleep(2000); // polite delay between subjects
      } catch (err) {
        console.error(`  ❌ ${mmluConfig}: ${err.message}`);
        await sleep(5000); // longer wait after error
      }
    }

    console.log(`\n${'─'.repeat(60)}`);
    console.log(`Questions processed: ${totalInserted}`);

    if (!DRY_RUN) {
      const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
      console.log(`question_bank total: ${count}`);

      const { rows: dist } = await client.query(`
        SELECT subject, COUNT(*) n FROM question_bank
        GROUP BY subject ORDER BY n DESC
      `);
      console.log('\nBy subject:');
      dist.forEach(r => console.log(`  ${String(r.n).padStart(5)} × ${r.subject}`));
    }

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
