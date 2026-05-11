/**
 * Grade-level retrieval validator
 *
 * 验证 question bank 的年级适配性：
 * 当用户只提供年级（不提供 topic/mistakes/conversation）时，
 * 检索结果的 difficulty 和 source 是否都在预期范围内。
 *
 * Usage:
 *   railway run --environment production node src/scripts/validate-grade-retrieval.js
 *   railway run --environment production node src/scripts/validate-grade-retrieval.js --subject=Math
 *   railway run --environment production node src/scripts/validate-grade-retrieval.js --verbose
 */

'use strict';

require('dotenv').config();
const { retrieveQuestions } = require('../gateway/routes/ai/modules/question-bank-service');

const SUBJECT_FILTER = (() => { const f = process.argv.find(a => a.startsWith('--subject=')); return f ? f.split('=')[1] : null; })();
const VERBOSE        = process.argv.includes('--verbose');
const FAKE_USER_ID   = '00000000-0000-0000-0000-000000000000'; // 不排除 seen questions

// ---------------------------------------------------------------------------
// 预期约束 — 和 gradeConstraints() 保持一致
// ---------------------------------------------------------------------------
const GRADE_EXPECTATIONS = [
  {
    grades:        ['Kindergarten', 'Grade 1', 'Grade 2'],
    label:         'K–2',
    diffMin: 1, diffMax: 1,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'scienceqa']),
  },
  {
    grades:        ['Grade 3', 'Grade 4', 'Grade 5'],
    label:         '3–5',
    diffMin: 1, diffMax: 2,
    allowedSources: new Set(['gsm8k', 'arc', 'openbookqa', 'amc8', 'scienceqa']),
  },
  {
    grades:        ['Grade 6', 'Grade 7', 'Grade 8'],
    label:         '6–8',
    diffMin: 1, diffMax: 3,
    allowedSources: null,  // 全部来源都允许
  },
  {
    grades:        ['Grade 9', 'Grade 10'],
    label:         '9–10',
    diffMin: 2, diffMax: 4,
    allowedSources: null,
  },
  {
    grades:        ['Grade 11', 'Grade 12', 'High School'],
    label:         '11–12 / HS',
    diffMin: 2, diffMax: 5,
    allowedSources: null,
  },
  {
    grades:        ['College'],
    label:         'College',
    diffMin: 3, diffMax: 5,
    allowedSources: null,
  },
];

// 测试的科目列表
const SUBJECTS = SUBJECT_FILTER
  ? [SUBJECT_FILTER]
  : ['Math', 'Biology', 'History', 'Physics', 'English'];

const QUESTIONS_PER_CASE = 5; // 每个 grade×subject 组合取 5 题验证

// ---------------------------------------------------------------------------
// 单次验证
// ---------------------------------------------------------------------------
async function validateCase(gradeLabel, subject, expectation) {
  let result;
  try {
    result = await retrieveQuestions(FAKE_USER_ID, {
      topic:      subject,
      gradeLevel: gradeLabel,
      difficulty: 3,        // 用中等难度，期望 grade constraint 覆盖它
      count:      QUESTIONS_PER_CASE,
      questionType: 'any',
    });
  } catch (e) {
    return { pass: false, error: e.message, questions: [] };
  }

  const questions = result.questions || [];
  const failures  = [];

  for (const q of questions) {
    const diff   = parseInt(q.difficulty);
    const source = q.source;

    // 检查难度范围
    if (diff < expectation.diffMin || diff > expectation.diffMax) {
      failures.push(`难度 ${diff} 超出范围 [${expectation.diffMin}–${expectation.diffMax}] (source:${source}, id:${q.bank_question_id?.slice(0,8)})`);
    }

    // 检查来源限制（只对 K-5 有严格限制）
    if (expectation.allowedSources && !expectation.allowedSources.has(source)) {
      failures.push(`来源 "${source}" 不在允许列表 [${[...expectation.allowedSources].join(',')}]`);
    }
  }

  return {
    pass:      failures.length === 0 && questions.length > 0,
    empty:     questions.length === 0,
    failures,
    questions,
    diffRange: questions.length > 0
      ? `${Math.min(...questions.map(q => q.difficulty))}–${Math.max(...questions.map(q => q.difficulty))}`
      : 'N/A',
    sources: [...new Set(questions.map(q => q.source))],
  };
}

// ---------------------------------------------------------------------------
// 主流程
// ---------------------------------------------------------------------------
(async () => {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║         GRADE-LEVEL RETRIEVAL VALIDATION                     ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log(`Subjects: ${SUBJECTS.join(', ')} | ${QUESTIONS_PER_CASE} questions per case\n`);

  let totalPass = 0, totalFail = 0, totalEmpty = 0;

  // 每个年级段
  for (const exp of GRADE_EXPECTATIONS) {
    console.log(`\n── ${exp.label} (diff ${exp.diffMin}–${exp.diffMax}${exp.allowedSources ? `, sources: [${[...exp.allowedSources].join(',')}]` : ', all sources'}) ──`);

    for (const subject of SUBJECTS) {
      // 每个年级段只测一个代表性年级，避免 API 调用太多
      const gradeLabel = exp.grades[Math.floor(exp.grades.length / 2)];

      process.stdout.write(`  ${subject.padEnd(16)} [${gradeLabel}] … `);
      const r = await validateCase(gradeLabel, subject, exp);

      if (r.error) {
        console.log(`❌ ERROR: ${r.error}`);
        totalFail++;
      } else if (r.empty) {
        console.log(`⚠️  EMPTY — 没有返回题目（可能该科目在此来源限制下无题）`);
        totalEmpty++;
      } else if (r.pass) {
        console.log(`✅ PASS  diff:${r.diffRange}  sources:[${r.sources.join(',')}]`);
        totalPass++;
      } else {
        console.log(`❌ FAIL  diff:${r.diffRange}  sources:[${r.sources.join(',')}]`);
        r.failures.forEach(f => console.log(`         ↳ ${f}`));
        totalFail++;
      }

      // verbose: 打印实际题目
      if (VERBOSE && r.questions.length > 0) {
        r.questions.slice(0, 2).forEach((q, i) => {
          console.log(`         [${i+1}] diff:${q.difficulty} src:${q.source}`);
          console.log(`             ${q.question.slice(0, 100).replace(/\n/g, ' ')}…`);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 边界场景：grade 边界值测试（只测 Math）
  // ---------------------------------------------------------------------------
  console.log('\n── 边界场景测试 (Math) ──');
  const BOUNDARY_CASES = [
    { gradeLabel: 'Kindergarten', expectation: GRADE_EXPECTATIONS[0] },
    { gradeLabel: '2nd Grade',    expectation: GRADE_EXPECTATIONS[0] },
    { gradeLabel: '5th Grade',    expectation: GRADE_EXPECTATIONS[1] },
    { gradeLabel: 'Middle School',expectation: GRADE_EXPECTATIONS[2] },
    { gradeLabel: '9th Grade',    expectation: GRADE_EXPECTATIONS[3] },
    { gradeLabel: '12th Grade',   expectation: GRADE_EXPECTATIONS[4] },
    { gradeLabel: 'College',      expectation: GRADE_EXPECTATIONS[5] },
  ];

  for (const bc of BOUNDARY_CASES) {
    process.stdout.write(`  Math              [${bc.gradeLabel}] … `);
    const r = await validateCase(bc.gradeLabel, 'Math', bc.expectation);
    if (r.error) {
      console.log(`❌ ERROR: ${r.error}`);
      totalFail++;
    } else if (r.empty) {
      console.log(`⚠️  EMPTY`);
      totalEmpty++;
    } else if (r.pass) {
      console.log(`✅ PASS  diff:${r.diffRange}  sources:[${r.sources.join(',')}]`);
      totalPass++;
    } else {
      console.log(`❌ FAIL  diff:${r.diffRange}  sources:[${r.sources.join(',')}]`);
      r.failures.forEach(f => console.log(`         ↳ ${f}`));
      totalFail++;
    }
  }

  // ---------------------------------------------------------------------------
  // 汇总
  // ---------------------------------------------------------------------------
  const total = totalPass + totalFail + totalEmpty;
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log(`║  结果汇总: ${String(totalPass).padStart(3)} PASS  ${String(totalFail).padStart(3)} FAIL  ${String(totalEmpty).padStart(3)} EMPTY   共 ${total} 个 case`);
  console.log('╚══════════════════════════════════════════════════════════════╝');

  if (totalFail > 0) {
    console.log('\n❌ 存在不符合年级要求的题目！请检查 gradeConstraints() 逻辑。');
    process.exit(1);
  } else if (totalEmpty > 0) {
    console.log('\n⚠️  部分场景无题目返回，可能需要补充数据源或放宽来源限制。');
  } else {
    console.log('\n✅ 全部通过！年级适配性验证完成。');
  }

  process.exit(0);
})().catch(err => { console.error('Fatal:', err); process.exit(1); });
