/**
 * Tag question topics using GPT-4o-mini with the app's canonical taxonomy.
 * Stores base_branch + detailed_branch matching the weaknessKey format:
 *   {subject}/{base_branch}/{detailed_branch}
 *
 * Also re-embeds with full taxonomy path for better cosine similarity retrieval.
 *
 * Usage:
 *   railway run --environment production node src/scripts/tag-question-topics.js
 *   railway run --environment production node src/scripts/tag-question-topics.js --dry-run
 *   railway run --environment production node src/scripts/tag-question-topics.js --source=sat
 *   railway run --environment production node src/scripts/tag-question-topics.js --force
 */

'use strict';

require('dotenv').config();
const { Pool }   = require('pg');
const OpenAI     = require('openai');
const { buildTaxonomyPrompt, TAXONOMY } = require('./taxonomy');

const DRY_RUN = process.argv.includes('--dry-run');
const FORCE   = process.argv.includes('--force');  // re-tag even if already tagged
const LIMIT   = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();
const SOURCE  = (() => { const f = process.argv.find(a => a.startsWith('--source=')); return f ? f.split('=')[1] : null; })();

const TAGGING_BATCH = 5;  // smaller batch = fewer count mismatches for large taxonomies
const EMBED_BATCH   = 20;

const pool   = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false, statement_timeout: 60000, query_timeout: 60000 });
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// ---------------------------------------------------------------------------
// Subject → canonical subject key used in taxonomy.js
// (question_bank.subject stores 'Mathematics' etc.)
// ---------------------------------------------------------------------------
const SUBJECT_MAP = {
  'Mathematics': 'Math',
  'Math':        'Math',
  'English':     'English',
  'Physics':     'Physics',
  'Chemistry':   'Chemistry',
  'Biology':     'Biology',
  'History':     'History',
  'Computer Science': 'Computer Science',
};

// ---------------------------------------------------------------------------
// Build GPT system prompt for a specific subject
// ---------------------------------------------------------------------------
function buildTaggingPrompt(subjectKey) {
  const taxonomyText = buildTaxonomyPrompt(subjectKey);
  return `You classify ${subjectKey} questions into the exact taxonomy below.
For each question return a JSON object with "base_branch" and "detailed_branch".
Both values must exactly match entries from the taxonomy.

Taxonomy:
${taxonomyText}

Return ONLY valid JSON with this structure for N questions:
[{"base_branch":"...","detailed_branch":"..."},...]

IMPORTANT: In JSON strings always double-escape backslashes: \\\\frac not \\frac`;
}

// ---------------------------------------------------------------------------
// Tag a batch of questions for a given subject
// ---------------------------------------------------------------------------
async function tagBatch(questions, subjectKey) {
  const systemPrompt = buildTaggingPrompt(subjectKey);
  const numbered = questions.map((q, i) => `${i + 1}. ${q.slice(0, 400)}`).join('\n\n');

  // History branch names are long (~15 tokens each) — use 120 tokens per question
  const maxTokens = questions.length * 120;
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    temperature: 0,
    max_tokens: maxTokens,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: numbered },
    ],
  });

  const text = res.choices[0].message.content.trim();
  const jsonMatch = text.match(/\[[\s\S]*\]/);
  if (!jsonMatch) throw new Error(`No JSON array: ${text.slice(0, 100)}`);
  const parsed = JSON.parse(jsonMatch[0]);
  if (!Array.isArray(parsed) || parsed.length !== questions.length) {
    throw new Error(`Expected ${questions.length} items, got ${parsed.length}`);
  }
  return parsed; // [{base_branch, detailed_branch}]
}

async function tagOne(question, subjectKey) {
  const systemPrompt = buildTaggingPrompt(subjectKey);
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    temperature: 0,
    max_tokens: 200,
    messages: [
      { role: 'system', content: systemPrompt },
      // Explicitly ask for a single-item array to avoid GPT returning a plain object
      { role: 'user', content: `Classify this 1 question. Return a JSON array with exactly 1 item:\n1. ${question.slice(0, 400)}` },
    ],
  });
  const text = res.choices[0].message.content.trim();
  // Accept both array [...] and plain object {...}
  const arrMatch = text.match(/\[[\s\S]*?\]/);
  const objMatch = text.match(/\{[\s\S]*?\}/);
  if (arrMatch) {
    try {
      const parsed = JSON.parse(arrMatch[0]);
      return Array.isArray(parsed) && parsed[0]?.base_branch ? parsed[0] : null;
    } catch { /* fall through */ }
  }
  if (objMatch) {
    try {
      const parsed = JSON.parse(objMatch[0]);
      return parsed?.base_branch ? parsed : null;
    } catch { /* fall through */ }
  }
  // Last resort: GPT sometimes returns key:value lines without JSON
  const bbMatch = text.match(/"?base_branch"?\s*:\s*"([^"]+)"/);
  const dbMatch = text.match(/"?detailed_branch"?\s*:\s*"([^"]+)"/);
  if (bbMatch) return { base_branch: bbMatch[1], detailed_branch: dbMatch?.[1] || null };
  return null;
}

// ---------------------------------------------------------------------------
// Embed with full taxonomy path for richer similarity
// Format: "{question} | Subject: {subject} | {base_branch} / {detailed_branch} | Answer: {answer}"
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
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    const sourceClause = SOURCE ? `AND source = '${SOURCE}'` : '';

    // Dirty base_branch values: placeholders or subject names used as branch names
    const DIRTY_BRANCHES = ["'...'", "'Biology'", "'Math'", "'Physics'",
                            "'Chemistry'", "'History'", "'English'", "'Computer Science'",
                            "'?'", "'N/A'", "'Unknown'"];
    const dirtyList = DIRTY_BRANCHES.join(', ');
    const forceClause = FORCE ? '' :
      `AND (base_branch IS NULL OR base_branch = '' OR base_branch IN (${dirtyList}))`;

    // Pre-clean all dirty values → NULL so they're picked up by the untagged filter
    if (!DRY_RUN) {
      const { rowCount } = await client.query(
        `UPDATE question_bank SET base_branch = NULL, detailed_branch = NULL, topic = NULL
         WHERE base_branch IN (${dirtyList}) ${sourceClause}`
      );
      if (rowCount > 0) console.log(`  Cleared ${rowCount} dirty base_branch rows → NULL`);
    }

    const { rows } = await client.query(`
      SELECT id, source, subject, question, correct_answer, base_branch, detailed_branch
      FROM question_bank
      WHERE 1=1
      ${forceClause}
      ${sourceClause}
      ORDER BY subject, source
    `);

    const targets = rows.slice(0, LIMIT);
    const bySource = targets.reduce((a, r) => { a[r.source] = (a[r.source] || 0) + 1; return a; }, {});
    console.log(`Questions to tag      : ${targets.length}`);
    console.log(`By source             :`, bySource);
    if (DRY_RUN) console.log('DRY RUN\n');

    // Group by subject so we use the right taxonomy prompt per subject
    const bySubject = {};
    for (const row of targets) {
      const key = SUBJECT_MAP[row.subject] || 'Math';
      if (!bySubject[key]) bySubject[key] = [];
      bySubject[key].push(row);
    }

    const allTagged = [];

    for (const [subjectKey, subjectRows] of Object.entries(bySubject)) {
      if (!TAXONOMY[subjectKey]) {
        console.warn(`  No taxonomy for subject "${subjectKey}" — skipping ${subjectRows.length} rows`);
        continue;
      }
      console.log(`\nTagging ${subjectRows.length} questions for ${subjectKey}…`);

      for (let i = 0; i < subjectRows.length; i += TAGGING_BATCH) {
        const batch = subjectRows.slice(i, i + TAGGING_BATCH);
        let results = null;
        try {
          results = await tagBatch(batch.map(r => r.question), subjectKey);
          batch.forEach((r, j) => allTagged.push({ ...r, newTag: results[j] }));
        } catch (batchErr) {
          process.stdout.write(` [retry individually — ${batchErr.message.slice(0, 60)}]`);
          for (const r of batch) {
            try {
              const tag = await tagOne(r.question, subjectKey);
              allTagged.push({ ...r, newTag: tag });
            } catch (oneErr) {
              if (process.env.DEBUG_TAGGING) {
                console.log(`\n  tagOne fail [${r.source}]: ${oneErr.message}`);
              }
              allTagged.push({ ...r, newTag: null });
            }
          }
        }
        process.stdout.write(`\r  tagged ${Math.min(i + TAGGING_BATCH, subjectRows.length)}/${subjectRows.length}`);
      }
      console.log();
    }

    if (DRY_RUN) {
      allTagged.slice(0, 8).forEach(r => {
        console.log(`  [${r.source}] ${r.question.slice(0, 70)}…`);
        console.log(`         base: ${r.newTag?.base_branch}`);
        console.log(`         detailed: ${r.newTag?.detailed_branch}\n`);
      });
      return;
    }

    // Re-embed and update DB
    const toUpdate = allTagged.filter(r => r.newTag?.base_branch);
    console.log(`\nRe-embedding ${toUpdate.length} tagged questions…`);

    for (let i = 0; i < toUpdate.length; i += EMBED_BATCH) {
      const batch = toUpdate.slice(i, i + EMBED_BATCH);
      const withTags = batch.map(r => ({ ...r, base_branch: r.newTag.base_branch, detailed_branch: r.newTag.detailed_branch }));
      try {
        const vectors = await embedBatch(withTags);
        for (let j = 0; j < batch.length; j++) {
          const { base_branch, detailed_branch } = batch[j].newTag;
          const topic = `${base_branch} / ${detailed_branch}`;
          await client.query(
            `UPDATE question_bank
             SET base_branch = $1, detailed_branch = $2, topic = $3, embedding = $4
             WHERE id = $5`,
            [base_branch, detailed_branch, topic, vectors[j], batch[j].id]
          );
        }
      } catch (err) {
        console.warn(`  embed batch ${i} failed: ${err.message} — updating tags only`);
        for (const row of batch) {
          const { base_branch, detailed_branch } = row.newTag;
          await client.query(
            `UPDATE question_bank SET base_branch = $1, detailed_branch = $2, topic = $3 WHERE id = $4`,
            [base_branch, detailed_branch, `${base_branch} / ${detailed_branch}`, row.id]
          );
        }
      }
      process.stdout.write(`\r  updated ${Math.min(i + EMBED_BATCH, toUpdate.length)}/${toUpdate.length}`);
    }
    console.log(`\n✅ Tagged and re-embedded ${toUpdate.length} questions.`);

    // Summary
    const { rows: dist } = await client.query(`
      SELECT base_branch, COUNT(*) n FROM question_bank
      WHERE base_branch IS NOT NULL
      GROUP BY base_branch ORDER BY n DESC LIMIT 20
    `);
    console.log('\nTop base branches:');
    dist.forEach(r => console.log(`  ${String(r.n).padStart(4)} × ${r.base_branch}`));

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
