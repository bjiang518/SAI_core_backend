/**
 * fill-question-tags.js
 *
 * Fills the `tags` JSONB column in question_bank with:
 *   skill_tags, style_tags, mc_strategy_tags
 * using gpt-4o-mini and the canonical tag sets in tag-taxonomy.js.
 *
 * Cost estimate: ~$1.50 for all 55K questions (gpt-4o-mini)
 * Time estimate: ~45 min for full run
 *
 * Usage:
 *   OPENAI_API_KEY=sk-xxx node src/scripts/fill-question-tags.js --dry-run --limit=5
 *   OPENAI_API_KEY=sk-xxx node src/scripts/fill-question-tags.js --subject=Math
 *   OPENAI_API_KEY=sk-xxx node src/scripts/fill-question-tags.js --source=kangaroo
 *   OPENAI_API_KEY=sk-xxx node src/scripts/fill-question-tags.js           # full run
 *   OPENAI_API_KEY=sk-xxx node src/scripts/fill-question-tags.js --force   # re-tag all
 *
 * Can use a different API key from .env:
 *   OPENAI_API_KEY=sk-different-key node src/scripts/fill-question-tags.js
 */

'use strict';

require('dotenv').config();
const { Pool }  = require('pg');
const OpenAI    = require('openai');
const { getAllowedSkillAndStyleTags } = require('./tag-taxonomy');

const DRY_RUN        = process.argv.includes('--dry-run');
const FORCE          = process.argv.includes('--force');
const SUBJECT_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--subject=')); return f ? f.split('=').slice(1).join('=') : null; })();
const SOURCE_FILTER  = (() => { const f = process.argv.find(a => a.startsWith('--source=')); return f ? f.split('=')[1] : null; })();
const LIMIT          = (() => { const f = process.argv.find(a => a.startsWith('--limit=')); return f ? parseInt(f.split('=')[1]) : Infinity; })();

const BATCH_SIZE  = 10;
const UPDATE_BATCH = 50;
const DELAY_MS    = 500;

// Use OPENAI_API_KEY from environment (can override .env by passing before command)
const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
const pool   = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  statement_timeout: 120000,
  query_timeout:     120000,
});

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------------------------------------------------------------------------
// Build the GPT system prompt for a subject's tag taxonomy
// ---------------------------------------------------------------------------
function buildPrompt(subject) {
  const allowed = getAllowedSkillAndStyleTags(subject);
  const skillList  = [...allowed.skill_tags].join(', ');
  const styleList  = [...allowed.style_tags].join(', ');
  const mcList     = [...allowed.mc_strategy_tags].join(', ');

  return `You assign predefined tags to ${subject} multiple-choice questions.
For each numbered question, choose ONLY from these exact tags (pick 1-3 per category, fewer is better):

skill_tags    : ${skillList}
style_tags    : ${styleList}
mc_strategy_tags: ${mcList}

Return ONLY a JSON array, one object per question:
[{"skill_tags":["..."],"style_tags":["..."],"mc_strategy_tags":["..."]},...]

Rules:
- Only use tags from the lists above — no invented tags
- skill_tags: what cognitive skill does answering this require?
- style_tags: what format/style is this question?
- mc_strategy_tags: what MC test-taking strategy helps here?
- If a category genuinely doesn't apply, use []`;
}

// ---------------------------------------------------------------------------
// Tag a batch of questions for a subject
// ---------------------------------------------------------------------------
async function tagBatch(questions, subject) {
  const systemPrompt = buildPrompt(subject);
  const numbered = questions.map((q, i) => `${i + 1}. ${q.slice(0, 350)}`).join('\n\n');

  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    temperature: 0,
    max_tokens: questions.length * 60,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: numbered },
    ],
  });

  const text = res.choices[0].message.content.trim();
  const m = text.match(/\[[\s\S]*\]/);
  if (!m) throw new Error(`No JSON array in response: ${text.slice(0, 100)}`);
  const parsed = JSON.parse(m[0]);
  if (parsed.length !== questions.length) {
    throw new Error(`Expected ${questions.length} items, got ${parsed.length}`);
  }
  return parsed;
}

// Fallback: tag a single question
async function tagOne(question, subject) {
  const systemPrompt = buildPrompt(subject);
  const res = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    temperature: 0,
    max_tokens: 80,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: `1. ${question.slice(0, 350)}` },
    ],
  });
  const text = res.choices[0].message.content.trim();
  const m = text.match(/\[[\s\S]*\]/);
  if (!m) return null;
  const parsed = JSON.parse(m[0]);
  return Array.isArray(parsed) ? parsed[0] : parsed;
}

// ---------------------------------------------------------------------------
// Validate tags against allowed sets (strip invalid ones)
// ---------------------------------------------------------------------------
function validateTags(rawTags, subject) {
  const allowed = getAllowedSkillAndStyleTags(subject);
  return {
    skill_tags:      (rawTags.skill_tags      || []).filter(t => allowed.skill_tags.has(t)),
    style_tags:      (rawTags.style_tags      || []).filter(t => allowed.style_tags.has(t)),
    mc_strategy_tags:(rawTags.mc_strategy_tags|| []).filter(t => allowed.mc_strategy_tags.has(t)),
  };
}

// ---------------------------------------------------------------------------
// Bulk update tags in DB
// ---------------------------------------------------------------------------
async function flushUpdates(client, updates) {
  for (let i = 0; i < updates.length; i += UPDATE_BATCH) {
    const batch = updates.slice(i, i + UPDATE_BATCH);
    // Build a single multi-row update with CASE
    const ids    = batch.map(u => u.id);
    const tags   = batch.map(u => JSON.stringify(u.tags));
    const phIds  = ids.map((_, k) => `$${k * 2 + 1}`).join(', ');
    const cases  = ids.map((_, k) => `WHEN id = $${k * 2 + 1} THEN $${k * 2 + 2}::jsonb`).join(' ');
    const params = ids.flatMap((id, k) => [id, tags[k]]);
    await client.query(
      `UPDATE question_bank SET tags = CASE ${cases} ELSE tags END WHERE id IN (${phIds})`,
      params
    );
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    // Build WHERE clause
    const conditions = ['1=1'];
    if (!FORCE) conditions.push(`tags = '{}'::jsonb`);
    if (SUBJECT_FILTER) conditions.push(`subject ILIKE '%${SUBJECT_FILTER.replace(/'/g, "''")}%'`);
    if (SOURCE_FILTER)  conditions.push(`source = '${SOURCE_FILTER.replace(/'/g, "''")}'`);
    const where = conditions.join(' AND ');

    const { rows: countRows } = await client.query(
      `SELECT COUNT(*) n FROM question_bank WHERE ${where}`
    );
    const total = Math.min(parseInt(countRows[0].n), LIMIT);

    console.log(`\nfill-question-tags`);
    console.log(`OPENAI_API_KEY : ${process.env.OPENAI_API_KEY ? process.env.OPENAI_API_KEY.slice(0,8) + '…' : '❌ not set'}`);
    console.log(`Questions      : ${total}`);
    console.log(`Subject filter : ${SUBJECT_FILTER || 'all'}`);
    console.log(`Source filter  : ${SOURCE_FILTER  || 'all'}`);
    console.log(`Force re-tag   : ${FORCE}`);
    console.log(`Dry run        : ${DRY_RUN}`);
    console.log(`Est. cost      : ~$${(total / 10 * 0.00028).toFixed(2)}`);
    console.log(`Est. time      : ~${Math.round(total / 10 * DELAY_MS / 60000)} min\n`);

    if (!process.env.OPENAI_API_KEY) {
      console.error('Set OPENAI_API_KEY before running:');
      console.error('  OPENAI_API_KEY=sk-xxx node src/scripts/fill-question-tags.js');
      process.exit(1);
    }

    // Fetch in pages to avoid holding all 55K rows in memory
    const PAGE_SIZE = 500;
    let processed = 0;
    let offset = 0;
    const pendingUpdates = [];

    while (processed < total) {
      const { rows } = await client.query(
        `SELECT id, subject, question FROM question_bank
         WHERE ${where} ORDER BY subject, id LIMIT $1 OFFSET $2`,
        [Math.min(PAGE_SIZE, total - processed), offset]
      );
      if (rows.length === 0) break;

      // Group page by subject
      const bySubject = {};
      for (const row of rows) {
        const s = row.subject || 'Math';
        if (!bySubject[s]) bySubject[s] = [];
        bySubject[s].push(row);
      }

      for (const [subject, subjectRows] of Object.entries(bySubject)) {
        for (let i = 0; i < subjectRows.length; i += BATCH_SIZE) {
          const batch = subjectRows.slice(i, i + BATCH_SIZE);

          if (DRY_RUN) {
            if (processed < 5) {
              console.log(`\n[${subject}] ${batch[0].question.slice(0, 80)}…`);
              console.log(`  → would assign tags from ${subject} tag set`);
            }
            processed += batch.length;
            continue;
          }

          let results;
          try {
            results = await tagBatch(batch.map(r => r.question), subject);
          } catch {
            results = await Promise.all(
              batch.map(r => tagOne(r.question, subject).catch(() => null))
            );
          }

          results.forEach((raw, j) => {
            if (!raw) return;
            const tags = validateTags(raw, subject);
            if (tags.skill_tags.length + tags.style_tags.length > 0) {
              pendingUpdates.push({ id: batch[j].id, tags });
            }
          });

          processed += batch.length;
          process.stdout.write(
            `\r  [${subject.padEnd(18)}] ${processed}/${total}` +
            `  queued=${pendingUpdates.length}`
          );

          // Flush to DB in chunks to avoid unbounded memory
          if (pendingUpdates.length >= 500) {
            await flushUpdates(client, pendingUpdates.splice(0));
          }

          await sleep(DELAY_MS);
        }
      }

      offset += rows.length;
    }

    if (!DRY_RUN && pendingUpdates.length > 0) {
      await flushUpdates(client, pendingUpdates);
    }

    console.log(`\n\n✅ Done. ${processed} questions processed.`);

    if (!DRY_RUN) {
      // Summary of tagged questions
      const { rows: dist } = await client.query(`
        SELECT subject, COUNT(*) total,
               COUNT(*) FILTER (WHERE tags != '{}'::jsonb) tagged
        FROM question_bank GROUP BY subject ORDER BY total DESC
      `);
      console.log('\nTagging coverage:');
      dist.forEach(r => {
        const pct = r.total > 0 ? Math.round(r.tagged / r.total * 100) : 0;
        console.log(`  ${r.subject.padEnd(18)} ${r.tagged}/${r.total} (${pct}%)`);
      });
    }

  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => { console.error('Fatal:', err.message); process.exit(1); });
