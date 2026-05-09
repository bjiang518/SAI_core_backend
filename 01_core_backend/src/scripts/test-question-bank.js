/**
 * Two purposes:
 * 1. Flag and remove figure-dependent questions from question_bank
 * 2. Test retrieval quality by printing what comes back for sample contexts
 *
 * Usage:
 *   railway run --environment staging node src/scripts/test-question-bank.js
 *   railway run --environment staging node src/scripts/test-question-bank.js --purge-figures
 */

'use strict';

require('dotenv').config();
const { Pool } = require('pg');
const { buildContextSummary, retrieveQuestions } = require('../gateway/routes/ai/modules/question-bank-service');

const PURGE = process.argv.includes('--purge-figures');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

// ---------------------------------------------------------------------------
// Figure detection — patterns that indicate a missing diagram
// ---------------------------------------------------------------------------
const FIGURE_PATTERNS = [
  /\bfigure\b/i,
  /\bdiagram\b/i,
  /\bshown (above|below|at right|at left)\b/i,
  /\bas shown\b/i,
  /\bin the (graph|chart|table|image|picture)\b/i,
  /\bsee (figure|diagram|graph|image)\b/i,
  /\brefer to\b/i,
  /\bthe (graph|chart) (above|below)\b/i,
];

function hasFigureReference(question) {
  return FIGURE_PATTERNS.some(p => p.test(question));
}

// ---------------------------------------------------------------------------
// Step 1: Scan and report figure-dependent questions
// ---------------------------------------------------------------------------
async function scanFigures(client) {
  const { rows } = await client.query(
    'SELECT id, source, source_id, question FROM question_bank ORDER BY source'
  );

  const flagged = rows.filter(r => hasFigureReference(r.question));

  console.log(`\n📊 Figure scan results:`);
  console.log(`  Total questions : ${rows.length}`);
  console.log(`  Figure-dependent: ${flagged.length} (${((flagged.length / rows.length) * 100).toFixed(1)}%)`);

  const bySource = flagged.reduce((acc, r) => {
    acc[r.source] = (acc[r.source] || 0) + 1;
    return acc;
  }, {});
  console.log(`  By source:`, bySource);

  console.log(`\n  Sample flagged questions:`);
  flagged.slice(0, 5).forEach(r => {
    const snippet = r.question.slice(0, 120).replace(/\n/g, ' ');
    console.log(`  [${r.source}] ${snippet}…`);
  });

  return flagged.map(r => r.id);
}

async function purgeFigures(client, ids) {
  if (ids.length === 0) { console.log('\nNothing to purge.'); return; }
  await client.query(
    'DELETE FROM question_bank WHERE id = ANY($1::uuid[])',
    [ids]
  );
  console.log(`\n🗑  Purged ${ids.length} figure-dependent questions.`);
  const { rows: [{ count }] } = await client.query('SELECT COUNT(*) FROM question_bank');
  console.log(`   Remaining: ${count} questions`);
}

// ---------------------------------------------------------------------------
// Step 2: Retrieval quality test — run several realistic contexts and print results
// ---------------------------------------------------------------------------
const TEST_CASES = [
  {
    label: 'Grade 2 — basic math (expect GSM8K/ARC only, diff=1)',
    opts: { topic: 'Mathematics', difficulty: 3, gradeLevel: 'Grade 2' },
  },
  {
    label: 'Grade 5 — elementary math (expect GSM8K/ARC/AMC8, diff=1-2)',
    opts: { topic: 'Mathematics', difficulty: 3, gradeLevel: 'Grade 5' },
  },
  {
    label: 'Grade 8 — middle school math (expect AMC8/MMLU, diff=1-3)',
    opts: { topic: 'Mathematics', difficulty: 3, gradeLevel: 'Grade 8' },
  },
  {
    label: 'High School — no grade cap (expect full range)',
    opts: { topic: 'Mathematics', difficulty: 3, gradeLevel: 'High School' },
  },
  {
    label: 'Student struggling with quadratic equations',
    opts: {
      topic: 'Mathematics',   // subject, not branch — branch comes from mistakesData
      difficulty: 3,
      mistakesData: [
        { detailed_branch: 'Quadratic Equations - Basics', base_branch: 'Algebra - Foundations', error_type: 'execution_error' },
        { detailed_branch: 'Quadratic Equations - Basics', base_branch: 'Algebra - Foundations', error_type: 'execution_error' },
      ],
    },
  },
  {
    label: 'Student weak on geometry (SAT prep)',
    opts: {
      topic: 'Mathematics',
      difficulty: 3,
      source: 'sat',
      conversationData: [
        { topics: ['Geometry', 'Triangles', 'Area'], weaknesses: ['triangle area formula', 'Pythagorean theorem'] },
      ],
    },
  },
  {
    label: 'Strong student, hard AIME number theory',
    opts: {
      topic: 'Mathematics',
      difficulty: 5,
      source: 'aime',
    },
  },
  {
    label: 'No context — general AMC12 medium',
    opts: {
      topic: 'Mathematics',
      difficulty: 3,
      source: 'amc12',
    },
  },
];

async function testRetrieval() {
  for (const tc of TEST_CASES) {
    console.log(`\n${'─'.repeat(70)}`);
    console.log(`🧪 Context: "${tc.label}"`);

    const summary = buildContextSummary({
      topic:            tc.opts.topic,
      mistakesData:     tc.opts.mistakesData     || [],
      conversationData: tc.opts.conversationData || [],
      weaknessKeys:     tc.opts.weaknessKeys     || [],
      gradeLevel:       tc.opts.gradeLevel       || null,
    });
    console.log(`   Embedded query: "${summary}"`);

    // Use a fake userId so no seen-question exclusion applies
    const result = await retrieveQuestions('00000000-0000-0000-0000-000000000000', {
      ...tc.opts,
      count: 3,
      questionType: 'any',
    });

    result.questions.forEach((q, i) => {
      console.log(`\n   [${i + 1}] [${q.source}] [diff:${q.difficulty}] [${q.question_type}] ${q.figure_url ? '🖼' : '  '}`);
      console.log(`       Topic: ${q.topic || '—'}`);
      console.log(`       Q: ${q.question.slice(0, 140).replace(/\n/g, ' ')}${q.question.length > 140 ? '…' : ''}`);
      console.log(`       A: ${q.correct_answer}`);
    });

    // Grade check: verify sources and difficulty are in expected ranges
    if (tc.opts.gradeLevel && result.questions.length > 0) {
      const sources = [...new Set(result.questions.map(q => q.source))];
      const diffs   = result.questions.map(q => parseInt(q.difficulty));
      const maxDiff = Math.max(...diffs);
      const minDiff = Math.min(...diffs);
      console.log(`\n   📊 Grade check for "${tc.opts.gradeLevel}":`);
      console.log(`       Sources returned: ${sources.join(', ')}`);
      console.log(`       Difficulty range: ${minDiff}–${maxDiff}`);
    }

    if (result.questions.length === 0) {
      console.log('   ⚠️  No questions returned — check difficulty range or source filter');
    }
  }
  console.log(`\n${'─'.repeat(70)}\n`);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const client = await pool.connect();
  try {
    const flaggedIds = await scanFigures(client);

    if (PURGE) {
      await purgeFigures(client, flaggedIds);
    } else if (flaggedIds.length > 0) {
      console.log(`\n💡 Run with --purge-figures to remove them.`);
    }

    console.log('\n\n=== RETRIEVAL QUALITY TEST ===');
    await testRetrieval();
  } finally {
    client.release();
    await pool.end();
  }
})().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
