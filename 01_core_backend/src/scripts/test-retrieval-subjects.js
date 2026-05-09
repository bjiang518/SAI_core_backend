'use strict';

require('dotenv').config();
const { retrieveQuestions, buildContextSummary } = require('../gateway/routes/ai/modules/question-bank-service');

const FAKE_USER = '00000000-0000-0000-0000-000000000000';

// ---------------------------------------------------------------------------
// Test cases: simulate realistic iOS mode=4 payloads across subjects & grades
// ---------------------------------------------------------------------------
const TEST_CASES = [

  // ── Math ────────────────────────────────────────────────────────────────
  {
    label: '[Math] Grade 2 — no context (新用户)',
    opts: { topic: 'Math', difficulty: 2, gradeLevel: '2nd Grade', count: 4 },
    expect: { maxDiff: 1, sources: ['gsm8k'] },
  },
  {
    label: '[Math] Grade 5 — no context',
    opts: { topic: 'Math', difficulty: 3, gradeLevel: '5th Grade', count: 4 },
    expect: { maxDiff: 2, sources: ['gsm8k', 'arc', 'openbookqa', 'amc8'] },
  },
  {
    label: '[Math] Grade 8 — weakness: quadratic equations',
    opts: {
      topic: 'Math', difficulty: 3, gradeLevel: '8th Grade', count: 4,
      weaknessKeys: ['Math/Algebra - Foundations/Quadratic Equations - Basics'],
    },
    expect: { maxDiff: 3 },
  },
  {
    label: '[Math] High School — SAT prep, weakness: geometry',
    opts: {
      topic: 'Math', difficulty: 4, gradeLevel: '11th Grade', count: 4,
      source: 'sat',
      conversationData: [{ topics: ['Geometry', 'Triangles'], weaknesses: ['Pythagorean theorem'] }],
    },
    expect: { sources: ['sat'] },
  },
  {
    label: '[Math] High School — AIME hard number theory',
    opts: { topic: 'Math', difficulty: 5, gradeLevel: '11th Grade', source: 'aime', count: 4 },
    expect: { minDiff: 4, sources: ['aime'] },
  },
  {
    label: '[Math] No grade (new user, beginner selection)',
    opts: { topic: 'Math', difficulty: 2, gradeLevel: null, count: 4 },
    expect: {},
  },

  // ── Biology ─────────────────────────────────────────────────────────────
  {
    label: '[Biology] Grade 8 — no context',
    opts: { topic: 'Biology', difficulty: 3, gradeLevel: '8th Grade', count: 4 },
    expect: { maxDiff: 3 },
  },
  {
    label: '[Biology] High School — weakness: cell division',
    opts: {
      topic: 'Biology', difficulty: 3, gradeLevel: '10th Grade', count: 4,
      mistakesData: [
        { base_branch: 'Cell Biology', detailed_branch: 'Mitosis and Meiosis', error_type: 'conceptual_gap' },
      ],
    },
    expect: {},
  },

  // ── Chemistry ───────────────────────────────────────────────────────────
  {
    label: '[Chemistry] Grade 10 — no context',
    opts: { topic: 'Chemistry', difficulty: 3, gradeLevel: '10th Grade', count: 4 },
    expect: {},
  },

  // ── Physics ─────────────────────────────────────────────────────────────
  {
    label: '[Physics] Grade 11 — weakness: kinematics',
    opts: {
      topic: 'Physics', difficulty: 4, gradeLevel: '11th Grade', count: 4,
      weaknessKeys: ['Physics/Kinematics/Projectile Motion'],
    },
    expect: {},
  },

  // ── English ─────────────────────────────────────────────────────────────
  {
    label: '[English] Grade 5 — no context',
    opts: { topic: 'English', difficulty: 2, gradeLevel: '5th Grade', count: 4 },
    expect: { maxDiff: 2 },
  },
  {
    label: '[English] High School — LSAT reading',
    opts: {
      topic: 'English', difficulty: 4, gradeLevel: '11th Grade', count: 4,
      conversationData: [{ topics: ['Reading Comprehension', 'Logical Reasoning'], weaknesses: [] }],
    },
    expect: {},
  },

  // ── History ─────────────────────────────────────────────────────────────
  {
    label: '[History] Grade 7 — no context',
    opts: { topic: 'History', difficulty: 3, gradeLevel: '7th Grade', count: 4 },
    expect: {},
  },

  // ── Science (multi-subject union) ───────────────────────────────────────
  {
    label: '[Science] Grade 6 — multi-subject union (Bio+Chem+Physics)',
    opts: { topic: 'Science', difficulty: 2, gradeLevel: '6th Grade', count: 4 },
    expect: {},
  },
];

// ---------------------------------------------------------------------------
// Evaluator: check results against expectations
// ---------------------------------------------------------------------------
function evaluate(questions, expect, label) {
  const issues = [];

  if (questions.length === 0) {
    issues.push('❌ 0 questions returned');
    return issues;
  }

  const diffs   = questions.map(q => parseInt(q.difficulty));
  const sources = [...new Set(questions.map(q => q.source))];
  const types   = [...new Set(questions.map(q => q.question_type))];
  const maxDiff = Math.max(...diffs);
  const minDiff = Math.min(...diffs);

  if (expect.maxDiff !== undefined && maxDiff > expect.maxDiff) {
    issues.push(`❌ difficulty too high: got max=${maxDiff}, expected max=${expect.maxDiff}`);
  }
  if (expect.minDiff !== undefined && minDiff < expect.minDiff) {
    issues.push(`❌ difficulty too low: got min=${minDiff}, expected min=${expect.minDiff}`);
  }
  if (expect.sources !== undefined) {
    const unexpected = sources.filter(s => !expect.sources.includes(s));
    if (unexpected.length) issues.push(`❌ unexpected sources: ${unexpected.join(', ')}`);
  }

  return issues;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  let passed = 0, failed = 0;

  for (const tc of TEST_CASES) {
    const { label, opts, expect } = tc;
    const line = '─'.repeat(72);
    console.log(`\n${line}`);
    console.log(`🧪 ${label}`);

    const summary = buildContextSummary({
      topic:            opts.topic,
      mistakesData:     opts.mistakesData     || [],
      conversationData: opts.conversationData || [],
      weaknessKeys:     opts.weaknessKeys     || [],
      gradeLevel:       opts.gradeLevel       || null,
    });
    console.log(`   Embedding query : "${summary}"`);

    let result;
    try {
      result = await retrieveQuestions(FAKE_USER, {
        topic:            opts.topic,
        difficulty:       opts.difficulty || 3,
        questionType:     opts.questionType || 'any',
        count:            opts.count || 4,
        mistakesData:     opts.mistakesData     || [],
        conversationData: opts.conversationData || [],
        weaknessKeys:     opts.weaknessKeys     || [],
        source:           opts.source           || null,
        gradeLevel:       opts.gradeLevel       || null,
      });
    } catch (err) {
      console.log(`   ❌ ERROR: ${err.message}`);
      failed++;
      continue;
    }

    const { questions } = result;
    const issues = evaluate(questions, expect, label);

    if (questions.length === 0) {
      console.log('   ⚠️  No questions returned');
      failed++;
      continue;
    }

    const diffs   = questions.map(q => parseInt(q.difficulty));
    const sources = [...new Set(questions.map(q => q.source))];
    const types   = [...new Set(questions.map(q => q.question_type))];
    console.log(`   Returned ${questions.length} questions | diff: ${Math.min(...diffs)}–${Math.max(...diffs)} | sources: [${sources.join(', ')}] | types: [${types.join(', ')}]`);

    questions.forEach((q, i) => {
      const snippet = q.question.slice(0, 110).replace(/\n/g, ' ');
      const src = q.source ? `[${q.source}]` : '';
      const fig = q.figure_url ? '🖼' : '';
      console.log(`   [${i+1}] ${src} diff:${q.difficulty} ${q.question_type} ${fig}`);
      console.log(`       ${snippet}${q.question.length > 110 ? '…' : ''}`);
      console.log(`       A: ${String(q.correct_answer).slice(0, 80)}`);
    });

    if (issues.length === 0) {
      console.log(`   ✅ PASS`);
      passed++;
    } else {
      issues.forEach(i => console.log(`   ${i}`));
      failed++;
    }
  }

  console.log(`\n${'═'.repeat(72)}`);
  console.log(`Results: ${passed} passed, ${failed} failed out of ${TEST_CASES.length} cases`);
  console.log(`${'═'.repeat(72)}\n`);

  process.exit(failed > 0 ? 1 : 0);
})().catch(err => {
  console.error('Fatal:', err);
  process.exit(1);
});
