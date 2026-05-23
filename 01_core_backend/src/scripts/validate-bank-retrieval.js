/**
 * validate-bank-retrieval.js
 *
 * Retrieval quality agent for the question_bank.
 * Tests every subject × grade × topic combination and checks:
 *   1. DIFFICULTY  — all returned questions within grade's allowed diff range
 *   2. SOURCE      — no questions from grade-inappropriate sources
 *   3. COVERAGE    — fill-rate >= 70% of requested count
 *   4. RELEVANCE   — >= 40% of questions share the requested base_branch
 *
 * Usage:
 *   railway run node src/scripts/validate-bank-retrieval.js --quick
 *   railway run node src/scripts/validate-bank-retrieval.js --subject=Math
 *   railway run node src/scripts/validate-bank-retrieval.js --subject=Physics --grade="10th Grade"
 *   railway run node src/scripts/validate-bank-retrieval.js           # full audit (all subjects)
 *   railway run node src/scripts/validate-bank-retrieval.js --json    # machine-readable
 */

'use strict';

require('dotenv').config();

if (
  process.env.DATABASE_PUBLIC_URL &&
  (process.env.DATABASE_URL || '').includes('railway.internal')
) {
  process.env.DATABASE_URL = process.env.DATABASE_PUBLIC_URL;
}

// Over public internet the cache load (18K rows × 1536-dim embeddings ≈ 115 MB)
// takes 90-120s. Raise the DB timeouts before importing the service module.
process.env.PG_STATEMENT_TIMEOUT = '600000';  // 10 min
process.env.PG_QUERY_TIMEOUT     = '600000';

// Suppress internal [QuestionBank] logs — they flood the terminal
const _origLog = console.log;
console.log = (...args) => {
  if (typeof args[0] === 'string' && args[0].startsWith('[QuestionBank]')) return;
  _origLog(...args);
};

const { retrieveQuestions, warmCache } = require('../gateway/routes/ai/modules/question-bank-service');
const { TAXONOMY }                     = require('./taxonomy');

// ---------------------------------------------------------------------------
// CLI flags
// ---------------------------------------------------------------------------
const SUBJECT_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--subject=')); return f ? f.split('=').slice(1).join('=') : null; })();
const GRADE_FILTER   = (() => { const f = process.argv.find(a => a.startsWith('--grade=')); return f ? f.split('=').slice(1).join('=') : null; })();
const BRANCH_FILTER  = (() => { const f = process.argv.find(a => a.startsWith('--branch=')); return f ? f.split('=').slice(1).join('=') : null; })();
const QUICK          = process.argv.includes('--quick');
const JSON_OUT       = process.argv.includes('--json');
const VERBOSE        = process.argv.includes('--verbose');

// ---------------------------------------------------------------------------
// Grade definitions — mirrors gradeConstraints() in question-bank-service.js
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

// ---------------------------------------------------------------------------
// Per-subject config: which grades to test and which branches to spot-check
// gradeLabels: only test these grades (null = all 13)
// quickBranches: branches used in --quick mode
// sampleDetails: branch → representative detailed_branch for weaknessKey
// quantitative: true = subject has grade-level source restrictions (like Math)
// expectedCoverageGrades: grades where we expect actual content in DB
// ---------------------------------------------------------------------------
const SUBJECT_CONFIG = {
  Math: {
    gradeLabels:    null,
    quickBranches:  ['Number & Operations', 'Algebra - Foundations', 'Geometry - Foundations', 'Statistics', 'Calculus - Differential'],
    sampleDetails:  {
      'Number & Operations':                'Whole Number Operations',
      'Algebra - Foundations':              'Linear Equations - One Variable',
      'Algebra - Advanced':                 'Quadratic Functions & Equations',
      'Geometry - Foundations':             'Measurement - Length, Area, Volume',
      'Geometry - Formal':                  'Triangles',
      'Trigonometry':                       'Trigonometric Functions - Unit Circle',
      'Statistics':                         'Data Analysis & Interpretation',
      'Probability':                        'Basic Probability',
      'Calculus - Differential':            'Derivatives - Basics',
      'Calculus - Integral':                'Definite Integrals',
      'Discrete Mathematics':               'Combinatorics',
      'Mathematical Modeling & Applications': 'Real-World Problem Solving',
    },
    quantitative:         true,
    expectedCoverageGrades: null,
    // Calculus only exists at diff 3-5; K-5 is capped at diff 1-2 → no content
    expectedGapCombos: [
      { grade: 'Kindergarten', branch: 'Calculus - Differential' },
      { grade: '1st Grade',    branch: 'Calculus - Differential' },
      { grade: '2nd Grade',    branch: 'Calculus - Differential' },
      { grade: '3rd Grade',    branch: 'Calculus - Differential' },
      { grade: '4th Grade',    branch: 'Calculus - Differential' },
      { grade: '5th Grade',    branch: 'Calculus - Differential' },
      { grade: 'Kindergarten', branch: 'Calculus - Integral' },
      { grade: '1st Grade',    branch: 'Calculus - Integral' },
      { grade: '2nd Grade',    branch: 'Calculus - Integral' },
      { grade: '3rd Grade',    branch: 'Calculus - Integral' },
      { grade: '4th Grade',    branch: 'Calculus - Integral' },
      { grade: '5th Grade',    branch: 'Calculus - Integral' },
    ],
  },

  Physics: {
    // Physics content in DB starts at middle/high school level
    gradeLabels:   ['6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
    quickBranches: ['Mechanics - Kinematics', 'Electricity & Magnetism', 'Thermodynamics', 'Waves & Optics'],
    sampleDetails: {
      'Mechanics - Kinematics':   'Motion in One Dimension',
      'Mechanics - Dynamics':     "Newton's Laws of Motion",
      'Mechanics - Energy & Work':'Conservation of Energy',
      'Electricity & Magnetism':  'Circuits - Series & Parallel',
      'Waves & Optics':           'Wave Properties',
      'Thermodynamics':           'Gas Laws',
      'Modern Physics':           'Quantum Mechanics - Basics',
      'Fluids & Oscillations':    'Simple Harmonic Motion',
    },
    quantitative:         true,
    expectedCoverageGrades: ['6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
  },

  Chemistry: {
    gradeLabels:   ['7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
    quickBranches: ['Atomic Structure', 'Chemical Reactions', 'Stoichiometry', 'Solutions & Aqueous Chemistry'],
    sampleDetails: {
      'Atomic Structure':                'Electron Configuration',
      'Chemical Bonding':                'Ionic Bonding',
      'Chemical Reactions':              'Balancing Chemical Equations',
      'Stoichiometry':                   'Mole Concept',
      'Gases':                           'Combined & Ideal Gas Law',
      'Thermochemistry':                 'Enthalpy & Heat of Reaction',
      'Solutions & Aqueous Chemistry':   'Acids & Bases',
      'Equilibrium & Kinetics':          'Chemical Equilibrium & Le Chatelier\'s Principle',
      'Organic & Nuclear Chemistry':     'Organic Compounds & Functional Groups',
    },
    quantitative:         true,
    expectedCoverageGrades: ['7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
  },

  Biology: {
    gradeLabels:   ['5th Grade', '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
    quickBranches: ['Cell Biology', 'Genetics - Classical', 'Ecology', 'Anatomy & Physiology'],
    sampleDetails: {
      'Cell Biology':              'Cell Organelles & Functions',
      'Cellular Processes':        'Cellular Respiration',
      'Genetics - Classical':      'Mendelian Genetics',
      'Genetics - Molecular':      'DNA Structure & Replication',
      'Evolution & Natural Selection': 'Natural Selection',
      'Ecology':                   'Food Webs & Energy Flow',
      'Anatomy & Physiology':      'Nervous System',
      'Plants & Microorganisms':   'Plant Structure & Function',
    },
    quantitative:         true,
    expectedCoverageGrades: ['5th Grade', '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
  },

  English: {
    gradeLabels:   null,
    quickBranches: ['Reading Comprehension', 'Grammar & Mechanics', 'Literary Analysis - Fiction', 'Writing - Argumentative'],
    sampleDetails: {
      'Reading Foundations':            'Vocabulary Development',
      'Literary Analysis - Fiction':    'Character Development',
      'Literary Analysis - Nonfiction': "Author's Purpose & Perspective",
      'Reading Comprehension':          'Inferential Comprehension',
      'Writing - Narrative':            'Personal Narrative',
      'Writing - Argumentative':        'Argumentative Essays',
      'Grammar & Mechanics':            'Sentence Structure & Types',
    },
    quantitative:         false,
    expectedCoverageGrades: ['9th Grade', '10th Grade', '11th Grade', '12th Grade'],
    // SAT/LSAT/MMLU English DB is dominated by reading comprehension & argumentation;
    // grammar-specific questions are rare
    expectedGapCombos: [
      { grade: '10th Grade', branch: 'Grammar & Mechanics' },
      { grade: '11th Grade', branch: 'Grammar & Mechanics' },
      { grade: '12th Grade', branch: 'Grammar & Mechanics' },
    ],
  },

  History: {
    gradeLabels:   ['4th Grade', '5th Grade', '6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
    quickBranches: ['World History - Ancient Civilizations', 'US History - Cold War to Present', 'Government & Civics', 'Economics'],
    sampleDetails: {
      'World History - Ancient Civilizations':        'Ancient Egypt',
      'World History - Medieval & Renaissance':       'Renaissance & Reformation',
      'World History - Modern Era':                   'World War II & Holocaust',
      'US History - Colonization to Early Republic':  'American Revolution',
      'US History - Cold War to Present':             'Civil Rights Movement',
      'Government & Civics':                          'Structure of US Government',
      'Economics':                                    'Supply & Demand',
    },
    quantitative:         false,
    expectedCoverageGrades: ['7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
    // MMLU history content skews toward ancient/classical history;
    // Cold War/modern US history is underrepresented in DB
    expectedGapCombos: [
      { grade: '8th Grade',  branch: 'US History - Cold War to Present' },
      { grade: '10th Grade', branch: 'US History - Cold War to Present' },
      { grade: '12th Grade', branch: 'US History - Cold War to Present' },
    ],
  },

  'Computer Science': {
    gradeLabels:   ['6th Grade', '7th Grade', '8th Grade', '9th Grade', '10th Grade', '11th Grade', '12th Grade'],
    quickBranches: ['Programming Fundamentals', 'Data Structures', 'Algorithms'],
    sampleDetails: {
      'Programming Fundamentals': 'Control Flow',
      'Data Structures':          'Arrays & Lists',
      'Algorithms':               'Sorting Algorithms',
      'Object-Oriented Programming': 'Classes & Objects',
      'Computer Systems':         'Binary & Number Systems',
    },
    quantitative:         false,
    expectedCoverageGrades: ['9th Grade', '10th Grade', '11th Grade', '12th Grade'],
  },
};

const TEST_USER_ID   = '00000000-0000-0000-0000-000000000001'; // dummy — no seen questions
const RETRIEVE_COUNT = 5;
const CONCURRENCY    = 3;

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

// ---------------------------------------------------------------------------
// Run one retrieval and evaluate it
// ---------------------------------------------------------------------------
async function runTest(grade, baseBranch, subject, subjectCfg) {
  const detailedBranch = (subjectCfg.sampleDetails || {})[baseBranch] || null;
  const weaknessKey    = detailedBranch
    ? `${subject}/${baseBranch}/${detailedBranch}`
    : `${subject}/${baseBranch}`;

  // Check if this specific grade+branch combo is a known content gap
  const isKnownGap = (subjectCfg.expectedGapCombos || []).some(
    g => g.grade === grade.label && g.branch === baseBranch
  );
  if (isKnownGap) {
    return {
      subject, grade: grade.label, branch: baseBranch,
      status: 'EXPECTED_GAP',
      issues: ['Known content gap — DB lacks this topic for this grade level'],
      questions: [], fillRate: 0, latency: 0, expectContent: false,
      srcDist: {}, diffDist: {},
    };
  }

  // Determine if this grade+branch combo is expected to have content in the DB.
  // If not, COVERAGE failure is expected — don't count it as a real bug.
  const expectedGrades = subjectCfg.expectedCoverageGrades;
  const expectContent  = !expectedGrades || expectedGrades.includes(grade.label);

  const start = Date.now();
  let questions = [];
  let error = null;

  try {
    const result = await retrieveQuestions(TEST_USER_ID, {
      topic:        subject,
      difficulty:   3,
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
      subject, grade: grade.label, branch: baseBranch,
      status: 'ERROR', error,
      issues: [`Retrieval threw: ${error}`],
      questions: [], latency, expectContent,
    };
  }

  const issues = [];

  // 1. DIFFICULTY
  const diffViolators = questions.filter(q => {
    const d = parseInt(q.difficulty);
    return d < grade.diffMin || d > grade.diffMax;
  });
  if (diffViolators.length > 0) {
    const dists = diffViolators.map(q => `${q.source}:diff${q.difficulty}`).join(', ');
    issues.push(`DIFFICULTY: ${diffViolators.length}/${questions.length} out of range [${grade.diffMin}-${grade.diffMax}] — ${dists}`);
  }

  // 2. SOURCE (only for quantitative subjects with grade-level source restrictions)
  if (subjectCfg.quantitative && grade.allowedSources) {
    const sourceViolators = questions.filter(q => q.source && !grade.allowedSources.has(q.source));
    if (sourceViolators.length > 0) {
      const srcs = [...new Set(sourceViolators.map(q => q.source))].join(', ');
      issues.push(`SOURCE: ${sourceViolators.length}/${questions.length} from grade-inappropriate sources: ${srcs}`);
    }
  }

  // 3. COVERAGE (expected gap → mark as EXPECTED_GAP, not FAIL)
  const fillRate = questions.length / RETRIEVE_COUNT;
  if (fillRate < 0.7) {
    if (expectContent) {
      issues.push(`COVERAGE: only ${questions.length}/${RETRIEVE_COUNT} returned (${Math.round(fillRate * 100)}%)`);
    } else {
      // Expected content gap — not a system failure
      return {
        subject, grade: grade.label, branch: baseBranch,
        status: 'EXPECTED_GAP',
        issues: [`No ${subject} content expected for ${grade.label} (by design)`],
        questions, fillRate: Math.round(fillRate * 100), latency, expectContent,
        srcDist: {}, diffDist: {},
      };
    }
  }

  // 4. RELEVANCE
  if (questions.length >= 2) {
    const relevant = questions.filter(q => q.base_branch === baseBranch);
    const relRate  = relevant.length / questions.length;
    if (relRate < 0.4 && questions.length >= 3) {
      const found = [...new Set(questions.map(q => q.base_branch || 'null'))].join(', ');
      if (expectContent) {
        issues.push(`RELEVANCE: only ${Math.round(relRate * 100)}% match "${baseBranch}" (got: ${found})`);
      }
    }
  }

  const srcDist = {}, diffDist = {};
  questions.forEach(q => {
    srcDist[q.source]      = (srcDist[q.source]      || 0) + 1;
    diffDist[q.difficulty] = (diffDist[q.difficulty] || 0) + 1;
  });

  return {
    subject, grade: grade.label, branch: baseBranch,
    status:   issues.length === 0 ? 'PASS' : 'FAIL',
    issues,
    questions,
    srcDist,
    diffDist,
    fillRate: Math.round(fillRate * 100),
    latency,
    expectContent,
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
      const r    = await runTest(test.grade, test.branch, test.subject, test.cfg);
      results.push(r);
      done++;
      if (!JSON_OUT) {
        const icon = r.status === 'PASS' ? '✅' : r.status === 'EXPECTED_GAP' ? '⬜' : r.status === 'ERROR' ? '💥' : '❌';
        const line = `${icon} ${String(done).padStart(3)}/${tests.length}  ${r.subject.padEnd(14)} ${r.grade.padEnd(11)} ${r.branch.slice(0,28)}`;
        process.stdout.write(`\r${line.padEnd(72)}`);
      }
      await sleep(50);
    }
  }

  await Promise.all(Array.from({ length: CONCURRENCY }, worker));
  if (!JSON_OUT) console.log();
  return results;
}

// ---------------------------------------------------------------------------
// Format report (compact)
// ---------------------------------------------------------------------------
function printReport(results) {
  const pass  = results.filter(r => r.status === 'PASS').length;
  const fail  = results.filter(r => r.status === 'FAIL').length;
  const error = results.filter(r => r.status === 'ERROR').length;
  const gap   = results.filter(r => r.status === 'EXPECTED_GAP').length;
  const total = results.length;
  const meaningful = total - gap;
  const pct = meaningful > 0 ? Math.round(pass / meaningful * 100) : 0;

  _origLog('\n' + '═'.repeat(60));
  _origLog('  RETRIEVAL QUALITY REPORT');
  _origLog('═'.repeat(60));
  _origLog(`  Total: ${total}  ✅ ${pass}  ❌ ${fail}  💥 ${error}  ⬜ ${gap} (expected gaps)`);
  _origLog(`  Pass rate (meaningful): ${pct}%`);
  _origLog('─'.repeat(60));

  // Per-subject summary: one line each
  const subjects = [...new Set(results.map(r => r.subject))];
  for (const subj of subjects) {
    const sr = results.filter(r => r.subject === subj && r.status !== 'EXPECTED_GAP' && r.status !== 'ERROR');
    if (!sr.length) continue;
    const sp = sr.filter(r => r.status === 'PASS').length;
    const spct = Math.round(sp / sr.length * 100);
    const mark = spct === 100 ? '✅' : spct >= 70 ? '⚠️ ' : '❌';
    _origLog(`  ${mark} ${subj.padEnd(18)} ${sp}/${sr.length} pass (${spct}%)`);
  }

  // Failures: one line per failure
  const failures = results.filter(r => r.status === 'FAIL' || r.status === 'ERROR');
  if (failures.length > 0) {
    _origLog('\n  FAILURES:');
    failures.forEach(r => {
      const icon = r.status === 'ERROR' ? '💥' : '❌';
      _origLog(`  ${icon} ${r.subject.padEnd(14)} ${r.grade.padEnd(11)} ${r.branch}`);
      r.issues.forEach(i => _origLog(`      ${i}`));
    });
  } else {
    _origLog('\n  All meaningful tests passed ✨');
  }
  _origLog('─'.repeat(60));
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
(async () => {
  // Build subject list to test
  const subjectsToTest = Object.entries(SUBJECT_CONFIG).filter(([name]) => {
    if (SUBJECT_FILTER) return name.toLowerCase() === SUBJECT_FILTER.toLowerCase();
    return true;
  });
  if (subjectsToTest.length === 0) {
    console.error(`Subject "${SUBJECT_FILTER}" not found. Valid: ${Object.keys(SUBJECT_CONFIG).join(', ')}`);
    process.exit(1);
  }

  const tests = [];
  for (const [subjectName, cfg] of subjectsToTest) {
    const allSubjectBranches = Object.keys(TAXONOMY[subjectName] || {});

    // Grade filter
    const allSubjectGrades = cfg.gradeLabels
      ? GRADES.filter(g => cfg.gradeLabels.includes(g.label))
      : GRADES;
    const gradesToTest = GRADE_FILTER
      ? allSubjectGrades.filter(g => g.label.toLowerCase() === GRADE_FILTER.toLowerCase())
      : QUICK ? allSubjectGrades.filter(g => QUICK_GRADES.includes(g.label))
      : allSubjectGrades;

    // Branch filter
    const branchesToTest = BRANCH_FILTER
      ? allSubjectBranches.filter(b => b.toLowerCase().includes(BRANCH_FILTER.toLowerCase()))
      : QUICK ? cfg.quickBranches
      : allSubjectBranches;

    for (const grade of gradesToTest) {
      for (const branch of branchesToTest) {
        tests.push({ grade, branch, subject: subjectName, cfg });
      }
    }
  }

  if (!JSON_OUT) {
    const subjectNames = subjectsToTest.map(([n]) => n).join(', ');
    _origLog(`\nRetrieval validation — ${subjectNames}`);
    _origLog(`Total tests: ${tests.length}  |  Mode: ${QUICK ? 'quick' : 'full'}  |  Concurrency: ${CONCURRENCY}`);

    // Pre-warm caches serially — loading 18K+ rows over public internet takes
    // 90-150s per subject; concurrent loads all time out
    const subjectsTowarm = [...new Set(subjectsToTest.map(([n]) => n))];
    _origLog(`\nPre-warming ${subjectsTowarm.length} subject caches (sequential, may take a few minutes)…`);
    for (const subj of subjectsTowarm) {
      process.stdout.write(`  loading ${subj}…`);
      const t0 = Date.now();
      try {
        await warmCache(subj);
        _origLog(` done (${((Date.now()-t0)/1000).toFixed(1)}s)`);
      } catch (e) {
        _origLog(` ⚠️ failed: ${e.message}`);
      }
    }
    _origLog('');
  }

  const results = await runAll(tests);

  if (JSON_OUT) {
    console.log(JSON.stringify({ summary: {
      total: results.length,
      pass:  results.filter(r => r.status === 'PASS').length,
      fail:  results.filter(r => r.status === 'FAIL').length,
      error: results.filter(r => r.status === 'ERROR').length,
      gap:   results.filter(r => r.status === 'EXPECTED_GAP').length,
    }, results }, null, 2));
  } else {
    printReport(results);
  }

  process.exit(0);
})().catch(err => { console.error('Fatal:', err.message); process.exit(1); });
