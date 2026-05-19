/**
 * validate-bank-retrieval.js
 *
 * Retrieval quality agent for the question_bank.
 * Tests every grade × Math topic combination and checks:
 *   1. DIFFICULTY  — all returned questions within grade's allowed diff range
 *   2. SOURCE      — no questions from grade-inappropriate sources
 *   3. COVERAGE    — fill-rate >= 70% of requested count
 *   4. RELEVANCE   — >= 40% of questions share the requested base_branch
 *
 * Usage:
 *   node src/scripts/validate-bank-retrieval.js                   # full Math audit
 *   node src/scripts/validate-bank-retrieval.js --grade="5th Grade"
 *   node src/scripts/validate-bank-retrieval.js --branch="Algebra - Foundations"
 *   node src/scripts/validate-bank-retrieval.js --quick           # spot-check only
 *   node src/scripts/validate-bank-retrieval.js --json            # machine-readable output
 *   railway run node src/scripts/validate-bank-retrieval.js
 */

'use strict';

require('dotenv').config();

// Railway internal hostname is only reachable from within the Railway network.
// When running locally, override DATABASE_URL with the public URL if available.
if (
  process.env.DATABASE_PUBLIC_URL &&
  (process.env.DATABASE_URL || '').includes('railway.internal')
) {
  process.env.DATABASE_URL = process.env.DATABASE_PUBLIC_URL;
  console.log('[validate] Using DATABASE_PUBLIC_URL for local execution');
}

const { retrieveQuestions } = require('../gateway/routes/ai/modules/question-bank-service');
const { TAXONOMY }          = require('./taxonomy');

// ---------------------------------------------------------------------------
// CLI flags
// ---------------------------------------------------------------------------
const GRADE_FILTER  = (() => { const f = process.argv.find(a => a.startsWith('--grade=')); return f ? f.split('=').slice(1).join('=') : null; })();
const BRANCH_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--branch=')); return f ? f.split('=').slice(1).join('=') : null; })();
const QUICK         = process.argv.includes('--quick');
const JSON_OUT      = process.argv.includes('--json');
const VERBOSE       = process.argv.includes('--verbose');

// ---------------------------------------------------------------------------
// Grade definitions — mirrors gradeConstraints() in question-bank-service.js
// plus the QUANTITATIVE_SUBJECTS source rules
// ---------------------------------------------------------------------------
const GRADES = [
  { label: 'Kindergarten', diffMin: 1, diffMax: 1,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'scienceqa', 'kangaroo']) },
  { label: '1st Grade',    diffMin: 1, diffMax: 1,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'scienceqa', 'kangaroo']) },
  { label: '2nd Grade',    diffMin: 1, diffMax: 1,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'scienceqa', 'kangaroo']) },
  { label: '3rd Grade',    diffMin: 1, diffMax: 2,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'amc8', 'scienceqa', 'kangaroo']) },
  { label: '4th Grade',    diffMin: 1, diffMax: 2,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'amc8', 'scienceqa', 'kangaroo']) },
  { label: '5th Grade',    diffMin: 1, diffMax: 2,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'amc8', 'scienceqa', 'kangaroo']) },
  { label: '6th Grade',    diffMin: 1, diffMax: 3, allowedSources: null },
  { label: '7th Grade',    diffMin: 1, diffMax: 3, allowedSources: null },
  { label: '8th Grade',    diffMin: 1, diffMax: 3, allowedSources: null },
  { label: '9th Grade',    diffMin: 2, diffMax: 4, allowedSources: null },
  { label: '10th Grade',   diffMin: 2, diffMax: 4, allowedSources: null },
  { label: '11th Grade',   diffMin: 2, diffMax: 5, allowedSources: null },
  { label: '12th Grade',   diffMin: 2, diffMax: 5, allowedSources: null },
];

// Spot-check subset: representative grades only
const QUICK_GRADES = ['2nd Grade', '5th Grade', '8th Grade', '10th Grade', '12th Grade'];

// Math base_branches to test (in --quick mode we test fewer)
const ALL_BRANCHES = Object.keys(TAXONOMY.Math);
const QUICK_BRANCHES = [
  'Number & Operations',
  'Algebra - Foundations',
  'Geometry - Foundations',
  'Statistics',
  'Calculus - Differential',
];

// Map branch → one representative detailed_branch (used as weaknessKey)
const BRANCH_SAMPLE_DETAIL = {
  'Number & Operations':              'Whole Number Operations',
  'Algebra - Foundations':            'Linear Equations - One Variable',
  'Algebra - Advanced':               'Quadratic Functions & Equations',
  'Geometry - Foundations':           'Measurement - Length, Area, Volume',
  'Geometry - Formal':                'Triangles',
  'Trigonometry':                     'Trigonometric Functions - Unit Circle',
  'Statistics':                       'Data Analysis & Interpretation',
  'Probability':                      'Basic Probability',
  'Calculus - Differential':          'Derivatives - Basics',
  'Calculus - Integral':              'Definite Integrals',
  'Discrete Mathematics':             'Combinatorics',
  'Mathematical Modeling & Applications': 'Real-World Problem Solving',
};

const TEST_USER_ID = '00000000-0000-0000-0000-000000000001'; // dummy — no real seen questions
const RETRIEVE_COUNT = 5;
const CONCURRENCY = 3; // parallel calls to retrieveQuestions

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------------------------------------------------------------------------
// Run one retrieval and evaluate it
// ---------------------------------------------------------------------------
async function runTest(grade, baseBranch) {
  const detailedBranch = BRANCH_SAMPLE_DETAIL[baseBranch] || null;
  const weaknessKey    = detailedBranch
    ? `Math/${baseBranch}/${detailedBranch}`
    : `Math/${baseBranch}`;

  const start = Date.now();
  let questions = [];
  let error = null;

  try {
    const result = await retrieveQuestions(TEST_USER_ID, {
      topic:        'Math',
      difficulty:   3,            // midpoint; grade constraints override anyway
      questionType: 'any',
      count:        RETRIEVE_COUNT,
      weaknessKeys: [weaknessKey],
      gradeLevel:   grade.label,
    });
    questions = result.questions || [];
  } catch (e) {
    error = e.message;
  }

  const latency = Date.now() - start;

  if (error) {
    return {
      grade: grade.label, branch: baseBranch,
      status: 'ERROR', error,
      issues: [`Retrieval threw: ${error}`],
      questions: [], latency,
    };
  }

  // ── Checks ──────────────────────────────────────────────────────────────

  const issues = [];

  // 1. DIFFICULTY — every question must be within grade's allowed range
  const diffViolators = questions.filter(q => {
    const d = parseInt(q.difficulty);
    return d < grade.diffMin || d > grade.diffMax;
  });
  if (diffViolators.length > 0) {
    const dists = diffViolators.map(q => `${q.source}:diff${q.difficulty}`).join(', ');
    issues.push(`DIFFICULTY: ${diffViolators.length}/${questions.length} out of range [${grade.diffMin}-${grade.diffMax}] — ${dists}`);
  }

  // 2. SOURCE — when the grade has allowedSources, enforce it
  if (grade.allowedSources) {
    const sourceViolators = questions.filter(q => q.source && !grade.allowedSources.has(q.source));
    if (sourceViolators.length > 0) {
      const srcs = [...new Set(sourceViolators.map(q => q.source))].join(', ');
      issues.push(`SOURCE: ${sourceViolators.length}/${questions.length} from grade-inappropriate sources: ${srcs}`);
    }
  }

  // 3. COVERAGE — fill-rate
  const fillRate = questions.length / RETRIEVE_COUNT;
  if (fillRate < 0.7) {
    issues.push(`COVERAGE: only ${questions.length}/${RETRIEVE_COUNT} returned (${Math.round(fillRate * 100)}%)`);
  }

  // 4. RELEVANCE — fraction of questions that match the requested branch
  //    (only meaningful when coverage is OK)
  if (questions.length >= 2) {
    const relevant = questions.filter(q => q.base_branch === baseBranch);
    const relRate = relevant.length / questions.length;
    if (relRate < 0.4 && questions.length >= 3) {
      const found = [...new Set(questions.map(q => q.base_branch || 'null'))].join(', ');
      issues.push(`RELEVANCE: only ${Math.round(relRate * 100)}% match "${baseBranch}" (got: ${found})`);
    }
  }

  // ── Source / difficulty distribution (for verbose) ───────────────────────
  const srcDist = {};
  const diffDist = {};
  questions.forEach(q => {
    srcDist[q.source]   = (srcDist[q.source]  || 0) + 1;
    diffDist[q.difficulty] = (diffDist[q.difficulty] || 0) + 1;
  });

  return {
    grade:     grade.label,
    branch:    baseBranch,
    status:    issues.length === 0 ? 'PASS' : 'FAIL',
    issues,
    questions,
    srcDist,
    diffDist,
    fillRate:  Math.round(fillRate * 100),
    latency,
  };
}

// ---------------------------------------------------------------------------
// Run tests with bounded concurrency
// ---------------------------------------------------------------------------
async function runAll(tests) {
  const results = [];
  const queue   = [...tests];
  let done = 0;

  async function worker() {
    while (queue.length > 0) {
      const test = queue.shift();
      const r    = await runTest(test.grade, test.branch);
      results.push(r);
      done++;
      if (!JSON_OUT) {
        const icon = r.status === 'PASS' ? '✅' : r.status === 'ERROR' ? '💥' : '❌';
        process.stdout.write(`\r  ${icon} ${done}/${tests.length}  ${r.grade.padEnd(12)} ${r.branch.slice(0, 35).padEnd(35)}`);
      }
      await sleep(50); // avoid hammering the embedding API
    }
  }

  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  if (!JSON_OUT) console.log();
  return results;
}

// ---------------------------------------------------------------------------
// Format report
// ---------------------------------------------------------------------------
function printReport(results) {
  const pass  = results.filter(r => r.status === 'PASS').length;
  const fail  = results.filter(r => r.status === 'FAIL').length;
  const error = results.filter(r => r.status === 'ERROR').length;
  const total = results.length;

  console.log('\n' + '═'.repeat(70));
  console.log('  QUESTION BANK RETRIEVAL QUALITY REPORT — Math');
  console.log('═'.repeat(70));
  console.log(`  Tests run : ${total}`);
  console.log(`  ✅ PASS   : ${pass}  (${Math.round(pass/total*100)}%)`);
  console.log(`  ❌ FAIL   : ${fail}`);
  console.log(`  💥 ERROR  : ${error}`);
  console.log('─'.repeat(70));

  // Group failures by grade
  const failures = results.filter(r => r.status !== 'PASS');
  if (failures.length === 0) {
    console.log('\n  All tests passed! ✨\n');
    return;
  }

  console.log('\n  FAILURES / ERRORS:\n');
  const byGrade = {};
  failures.forEach(r => {
    if (!byGrade[r.grade]) byGrade[r.grade] = [];
    byGrade[r.grade].push(r);
  });

  for (const [grade, items] of Object.entries(byGrade)) {
    console.log(`  ── ${grade} ──`);
    for (const r of items) {
      const icon = r.status === 'ERROR' ? '💥' : '❌';
      console.log(`    ${icon} ${r.branch}`);
      r.issues.forEach(issue => console.log(`        • ${issue}`));
    }
    console.log();
  }

  // Coverage summary table
  console.log('  COVERAGE BY GRADE (fill-rate %):\n');
  const grades = [...new Set(results.map(r => r.grade))];
  for (const grade of grades) {
    const gradeResults = results.filter(r => r.grade === grade && r.status !== 'ERROR');
    if (gradeResults.length === 0) continue;
    const avgFill = Math.round(gradeResults.reduce((s, r) => s + r.fillRate, 0) / gradeResults.length);
    const passCount = gradeResults.filter(r => r.status === 'PASS').length;
    const bar  = '█'.repeat(Math.round(avgFill / 5)) + '░'.repeat(20 - Math.round(avgFill / 5));
    const mark = passCount === gradeResults.length ? '✅' : '⚠️ ';
    console.log(`    ${mark} ${grade.padEnd(12)} ${bar} ${avgFill}% fill  (${passCount}/${gradeResults.length} branch tests pass)`);
  }

  if (VERBOSE) {
    console.log('\n  SOURCE DISTRIBUTION (all passing tests):\n');
    const passing = results.filter(r => r.status === 'PASS');
    const srcTotal = {};
    passing.forEach(r => Object.entries(r.srcDist || {}).forEach(([s, n]) => { srcTotal[s] = (srcTotal[s] || 0) + n; }));
    Object.entries(srcTotal).sort((a,b) => b[1]-a[1]).forEach(([src, n]) => {
      console.log(`    ${src.padEnd(15)} ${n}`);
    });
  }

  console.log('\n' + '─'.repeat(70));

  // Actionable findings
  const diffIssues   = failures.filter(r => r.issues.some(i => i.startsWith('DIFFICULTY')));
  const srcIssues    = failures.filter(r => r.issues.some(i => i.startsWith('SOURCE')));
  const covIssues    = failures.filter(r => r.issues.some(i => i.startsWith('COVERAGE')));
  const relIssues    = failures.filter(r => r.issues.some(i => i.startsWith('RELEVANCE')));

  if (diffIssues.length || srcIssues.length || covIssues.length || relIssues.length) {
    console.log('\n  FINDINGS SUMMARY:\n');
    if (diffIssues.length)
      console.log(`  ⚠️  DIFFICULTY violations in ${diffIssues.length} case(s) → gradeConstraints() may need updating`);
    if (srcIssues.length)
      console.log(`  ⚠️  SOURCE violations in ${srcIssues.length} case(s) → allowedSources set may be incomplete`);
    if (covIssues.length)
      console.log(`  ⚠️  COVERAGE gaps in ${covIssues.length} case(s) → not enough questions for these grade+topic combos`);
    if (relIssues.length)
      console.log(`  ⚠️  RELEVANCE issues in ${relIssues.length} case(s) → branch targeting (Stage 1/2) may be falling through`);
    console.log();
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  const gradesToTest  = (GRADE_FILTER
    ? GRADES.filter(g => g.label.toLowerCase() === GRADE_FILTER.toLowerCase())
    : QUICK ? GRADES.filter(g => QUICK_GRADES.includes(g.label))
    : GRADES
  );
  const branchesToTest = (BRANCH_FILTER
    ? ALL_BRANCHES.filter(b => b.toLowerCase().includes(BRANCH_FILTER.toLowerCase()))
    : QUICK ? QUICK_BRANCHES
    : ALL_BRANCHES
  );

  if (gradesToTest.length === 0) {
    console.error(`Grade "${GRADE_FILTER}" not found. Valid: ${GRADES.map(g => g.label).join(', ')}`);
    process.exit(1);
  }

  const tests = [];
  for (const grade of gradesToTest) {
    for (const branch of branchesToTest) {
      tests.push({ grade, branch });
    }
  }

  if (!JSON_OUT) {
    console.log(`\nRetrieval validation — subject: Math`);
    console.log(`Grades: ${gradesToTest.length}  ×  Branches: ${branchesToTest.length}  =  ${tests.length} tests`);
    console.log(`Mode: ${QUICK ? 'quick' : 'full'}  |  Concurrency: ${CONCURRENCY}\n`);
  }

  const results = await runAll(tests);

  if (JSON_OUT) {
    console.log(JSON.stringify({ summary: {
      total: results.length,
      pass:  results.filter(r => r.status === 'PASS').length,
      fail:  results.filter(r => r.status === 'FAIL').length,
      error: results.filter(r => r.status === 'ERROR').length,
    }, results }, null, 2));
  } else {
    printReport(results);
  }

  process.exit(0);
})().catch(err => { console.error('Fatal:', err.message); process.exit(1); });
