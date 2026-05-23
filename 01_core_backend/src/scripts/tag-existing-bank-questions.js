/**
 * tag-existing-bank-questions.js
 *
 * One-time script: tags existing question_bank rows with skill_tags, style_tags,
 * and mc_strategy_tags using GPT-5.2.  Stores results in the `tags` JSONB column.
 *
 * Does NOT assign error_micro_tags — those are per-student, not per-question.
 *
 * Usage:
 *   railway run node src/scripts/tag-existing-bank-questions.js
 *   railway run node src/scripts/tag-existing-bank-questions.js --subject=Math
 *   railway run node src/scripts/tag-existing-bank-questions.js --dry-run
 *   railway run node src/scripts/tag-existing-bank-questions.js --force  # re-tag already-tagged
 *   railway run node src/scripts/tag-existing-bank-questions.js --batch=20 --limit=500
 */

'use strict';

require('dotenv').config();

if (
  process.env.DATABASE_PUBLIC_URL &&
  (process.env.DATABASE_URL || '').includes('railway.internal')
) {
  process.env.DATABASE_URL = process.env.DATABASE_PUBLIC_URL;
}

const { Pool } = require('pg');
const OpenAI   = require('openai');
const { SUBJECT_TAGS, getAllowedSkillAndStyleTags } = require('./tag-taxonomy');

const DRY_RUN    = process.argv.includes('--dry-run');
const FORCE      = process.argv.includes('--force');
const SUBJECT    = (() => { const f = process.argv.find(a => a.startsWith('--subject=')); return f ? f.split('=').slice(1).join('=') : null; })();
const BATCH_SIZE = (() => { const f = process.argv.find(a => a.startsWith('--batch=')); return f ? parseInt(f.split('=')[1]) : 10; })();
const LIMIT      = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();

const pool   = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  statement_timeout: 60000,
  query_timeout: 60000,
});
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

const SUBJECT_MAP = {
  'Mathematics': 'Math', 'Math': 'Math',
  'English': 'English',
  'Physics': 'Physics',
  'Chemistry': 'Chemistry',
  'Biology': 'Biology',
  'History': 'History',
  'Computer Science': 'Computer Science',
};

function buildTaggingPrompt(subjectKey, questions) {
  const allowed = getAllowedSkillAndStyleTags(subjectKey);
  const skillList  = [...allowed.skill_tags].join(', ');
  const styleList  = [...allowed.style_tags].join(', ');
  const mcList     = [...allowed.mc_strategy_tags].join(', ');

  const questionsText = questions.map((q, i) =>
    `Q${i + 1} [type=${q.question_type}]: ${q.question.slice(0, 300)}`
  ).join('\n\n');

  return `You tag ${subjectKey} questions with predefined labels.
Return a JSON array (one object per question, in order).

Allowed skill_tags: ${skillList}
Allowed style_tags: ${styleList}
Allowed mc_strategy_tags (only for multiple_choice questions): ${mcList}

For each question return:
{
  "skill_tags": ["<1-3 from allowed list>"],
  "style_tags": ["<1-2 from allowed list>"],
  "mc_strategy_tags": []   // use mc_strategy_tags ONLY if question type is "multiple_choice", else []
}

Questions:
${questionsText}

Return ONLY a JSON array with ${questions.length} objects, no commentary.`;
}

async function tagBatch(subjectKey, questions) {
  const prompt = buildTaggingPrompt(subjectKey, questions);

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: prompt }],
    response_format: { type: 'json_object' },
    temperature: 0.1,
    max_completion_tokens: 800,
  });

  const raw = JSON.parse(response.choices[0].message.content);
  // GPT wraps array in an object key sometimes
  const arr = Array.isArray(raw) ? raw : (raw.results || raw.tags || Object.values(raw)[0]);

  if (!Array.isArray(arr) || arr.length !== questions.length) {
    throw new Error(`Expected ${questions.length} results, got ${arr?.length}`);
  }

  const allowed = getAllowedSkillAndStyleTags(subjectKey);

  return arr.map((item, i) => {
    const q = questions[i];
    // Validate — keep only tags that appear in the allowed list
    const skillTags  = (item.skill_tags || []).filter(t => allowed.skill_tags.has(t));
    const styleTags  = (item.style_tags || []).filter(t => allowed.style_tags.has(t));
    const mcTags     = q.question_type === 'multiple_choice'
      ? (item.mc_strategy_tags || []).filter(t => allowed.mc_strategy_tags.has(t))
      : [];
    return { id: q.id, tags: { skill_tags: skillTags, style_tags: styleTags, mc_strategy_tags: mcTags } };
  });
}

(async () => {
  // Build WHERE clause
  const conditions = [];
  const params = [];
  if (SUBJECT) {
    conditions.push(`subject = $${params.length + 1}`);
    params.push(SUBJECT);
  }
  if (!FORCE) {
    conditions.push(`(tags = '{}'::jsonb OR tags IS NULL OR (tags->>'skill_tags')::text = '[]')`);
  }
  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

  const { rows: allRows } = await pool.query(
    `SELECT id, subject, question, question_type FROM question_bank ${where} ORDER BY id LIMIT $${params.length + 1}`,
    [...params, isFinite(LIMIT) ? LIMIT : 999999]
  );

  if (allRows.length === 0) {
    console.log('No rows to tag.');
    process.exit(0);
  }

  console.log(`\nTagging ${allRows.length} rows${SUBJECT ? ` (subject=${SUBJECT})` : ''} | batch=${BATCH_SIZE} | dry-run=${DRY_RUN}`);

  let done = 0, errors = 0;

  for (let i = 0; i < allRows.length; i += BATCH_SIZE) {
    const batch = allRows.slice(i, i + BATCH_SIZE);

    // Group by subject within the batch
    const bySubject = {};
    for (const row of batch) {
      const key = SUBJECT_MAP[row.subject] || row.subject;
      if (!bySubject[key]) bySubject[key] = [];
      bySubject[key].push(row);
    }

    for (const [subjectKey, rows] of Object.entries(bySubject)) {
      if (!SUBJECT_TAGS[subjectKey]) {
        console.log(`  ⚠️  No tag taxonomy for subject "${subjectKey}" — skipping ${rows.length} rows`);
        continue;
      }
      try {
        const tagged = await tagBatch(subjectKey, rows);
        if (!DRY_RUN) {
          for (const { id, tags } of tagged) {
            await pool.query(
              `UPDATE question_bank SET tags = $1::jsonb WHERE id = $2`,
              [JSON.stringify(tags), id]
            );
          }
        }
        done += tagged.length;
        process.stdout.write(`\r  ✅ ${done}/${allRows.length} tagged`);
      } catch (err) {
        errors += rows.length;
        console.error(`\n  ❌ Batch error (${subjectKey}): ${err.message}`);
      }
    }

    // Polite delay between batches
    await new Promise(r => setTimeout(r, 300));
  }

  console.log(`\n\nDone. Tagged: ${done}  Errors: ${errors}${DRY_RUN ? ' (DRY RUN — nothing written)' : ''}`);
  await pool.end();
  process.exit(0);
})().catch(err => { console.error('Fatal:', err.message); process.exit(1); });
