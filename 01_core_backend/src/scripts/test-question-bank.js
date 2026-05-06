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
    label: 'Student struggling with quadratic equations',
    opts: {
      topic: 'Algebra',
      difficulty: 3,
      mistakesData: [
        { detailed_branch: 'Algebra - Quadratic Equations', base_branch: 'Algebra', error_type: 'execution_error' },
        { detailed_branch: 'Algebra - Quadratic Equations', base_branch: 'Algebra', error_type: 'execution_error' },
      ],
    },
  },
  {
    label: 'Student weak on geometry (SAT prep)',
    opts: {
      topic: 'Geometry',
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
      topic: 'Number Theory',
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
    });
    console.log(`   Embedded query: "${summary}"`);

    // Use a fake userId so no seen-question exclusion applies
    const result = await retrieveQuestions('00000000-0000-0000-0000-000000000000', {
      ...tc.opts,
      count: 3,
      questionType: 'any',
    });

    result.questions.forEach((q, i) => {
      console.log(`\n   [${i + 1}] [${q.source}] [diff:${q.difficulty}] [${q.question_type}]`);
      console.log(`       Topic: ${q.topic || '—'}`);
      console.log(`       Q: ${q.question.slice(0, 140).replace(/\n/g, ' ')}${q.question.length > 140 ? '…' : ''}`);
      console.log(`       A: ${q.correct_answer}`);
    });

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
