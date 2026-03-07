/**
 * Backend Logic Tests
 *
 * Pure function unit tests — no server, no database, runs instantly.
 *
 * Usage:
 *   node tests/logic.test.js
 */

// ---------------------------------------------------------------------------
// Test runner
// ---------------------------------------------------------------------------
const results = [];

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertEqual(actual, expected, label) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  assert(a === e, `${label}: expected ${e}, got ${a}`);
}

function test(name, fn) {
  try {
    fn();
    results.push({ name, passed: true });
    console.log(`  ✅ ${name}`);
  } catch (err) {
    results.push({ name, passed: false, error: err.message });
    console.log(`  ❌ ${name}`);
    console.log(`     ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Import pure functions
// ---------------------------------------------------------------------------
const {
  computeTypeSplit,
  buildContextData,
  modeToContextType,
  shuffle,
  SUBJECT_SPLIT_TABLE,
} = require('../src/gateway/routes/ai/modules/question-generation-v3');

const {
  buildSystemPrompt,
  formatGradeLevel,
  TUTORING_SYSTEM_PROMPT_HEURISTIC,
  TUTORING_SYSTEM_PROMPT_STRAIGHTFORWARD,
} = require('../src/gateway/routes/ai/utils/prompts');

// ===========================================================================
// computeTypeSplit tests
// ===========================================================================
console.log('\n📋 Backend Logic Tests\n');
console.log('1. computeTypeSplit');

test('count < 3 returns all multiple_choice', () => {
  assertEqual(
    computeTypeSplit('math', 2),
    [{ type: 'multiple_choice', count: 2 }],
    'math count=2'
  );
  assertEqual(
    computeTypeSplit('english', 1),
    [{ type: 'multiple_choice', count: 1 }],
    'english count=1'
  );
});

test('math subject: 60% MC + 40% short answer', () => {
  const result = computeTypeSplit('math', 10);
  assertEqual(result, [
    { type: 'multiple_choice', count: 6 },
    { type: 'short_answer', count: 4 },
  ], 'math 10');
});

test('physics subject uses math split table', () => {
  const result = computeTypeSplit('physics', 10);
  assertEqual(result, [
    { type: 'multiple_choice', count: 6 },
    { type: 'short_answer', count: 4 },
  ], 'physics 10');
});

test('default subject: 50% MC + 20% TF + 30% short', () => {
  const result = computeTypeSplit('english', 10);
  assertEqual(result, [
    { type: 'multiple_choice', count: 5 },
    { type: 'true_false', count: 2 },
    { type: 'short_answer', count: 3 },
  ], 'english 10');
});

test('total counts always sum correctly', () => {
  for (const subject of ['math', 'english', 'history', 'physics', 'unknown']) {
    for (let total = 1; total <= 10; total++) {
      const result = computeTypeSplit(subject, total);
      const sum = result.reduce((s, r) => s + r.count, 0);
      assert(sum === total, `${subject} total=${total}: sum was ${sum}`);
    }
  }
});

test('no zero-count entries in result', () => {
  const result = computeTypeSplit('english', 3);
  for (const r of result) {
    assert(r.count > 0, `type ${r.type} has count 0`);
  }
});

// ===========================================================================
// modeToContextType tests
// ===========================================================================
console.log('\n2. modeToContextType');

test('mode 1 → random', () => assertEqual(modeToContextType(1), 'random', 'mode 1'));
test('mode 2 → mistake', () => assertEqual(modeToContextType(2), 'mistake', 'mode 2'));
test('mode 3 → archive', () => assertEqual(modeToContextType(3), 'archive', 'mode 3'));

// ===========================================================================
// buildContextData tests
// ===========================================================================
console.log('\n3. buildContextData');

test('mode 1 (random) includes topics and short_term_context', () => {
  const result = buildContextData(1, { topic: 'Algebra', short_term_context: [{ id: 1 }] }, '5th Grade');
  assertEqual(result.grade, '5th Grade', 'grade');
  assertEqual(result.topics, ['Algebra'], 'topics');
  assertEqual(result.short_term_context, [{ id: 1 }], 'short_term_context');
  assert(!result.mistakes_data, 'should not have mistakes_data');
});

test('mode 1 without topic → empty topics array', () => {
  const result = buildContextData(1, {}, 'High School');
  assertEqual(result.topics, [], 'topics empty');
});

test('mode 2 (mistakes) includes mistakes_data', () => {
  const result = buildContextData(2, { mistakes_data: [{ err: 'wrong' }] }, '9th Grade');
  assertEqual(result.mistakes_data, [{ err: 'wrong' }], 'mistakes_data');
  assert(!result.topics, 'should not have topics');
});

test('mode 3 (archive) includes conversation_data and question_data', () => {
  const result = buildContextData(3, {
    conversation_data: [{ msg: 'hi' }],
    question_data: [{ q: 'x' }],
  }, '10th Grade');
  assertEqual(result.conversation_data, [{ msg: 'hi' }], 'conversation_data');
  assertEqual(result.question_data, [{ q: 'x' }], 'question_data');
});

// ===========================================================================
// shuffle tests
// ===========================================================================
console.log('\n4. shuffle');

test('shuffle preserves all elements', () => {
  const arr = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const original = [...arr];
  shuffle(arr);
  assertEqual(arr.sort(), original.sort(), 'sorted arrays match');
});

test('shuffle handles empty array', () => {
  const arr = [];
  shuffle(arr);
  assertEqual(arr, [], 'empty');
});

test('shuffle handles single element', () => {
  const arr = [42];
  shuffle(arr);
  assertEqual(arr, [42], 'single');
});

// ===========================================================================
// formatGradeLevel tests
// ===========================================================================
console.log('\n5. formatGradeLevel');

test('0 → Kindergarten', () => assertEqual(formatGradeLevel(0), 'Kindergarten', 'K'));
test('1 → 1st Grade', () => assertEqual(formatGradeLevel(1), '1st Grade', '1'));
test('2 → 2nd Grade', () => assertEqual(formatGradeLevel(2), '2nd Grade', '2'));
test('3 → 3rd Grade', () => assertEqual(formatGradeLevel(3), '3rd Grade', '3'));
test('5 → 5th Grade', () => assertEqual(formatGradeLevel(5), '5th Grade', '5'));
test('12 → 12th Grade', () => assertEqual(formatGradeLevel(12), '12th Grade', '12'));
test('13 → University/College', () => assertEqual(formatGradeLevel(13), 'University/College', '13'));
test('null → null', () => assertEqual(formatGradeLevel(null), null, 'null'));
test('string "10" → 10th Grade', () => assertEqual(formatGradeLevel('10'), '10th Grade', '"10"'));

// ===========================================================================
// buildSystemPrompt tests
// ===========================================================================
console.log('\n6. buildSystemPrompt');

test('heuristic style with name and grade', () => {
  const result = buildSystemPrompt({ style: 'heuristic', studentName: 'Alice', gradeLevel: 5 });
  assert(result.includes(TUTORING_SYSTEM_PROMPT_HEURISTIC), 'contains heuristic prompt');
  assert(result.includes('Alice'), 'contains name');
  assert(result.includes('5th Grade'), 'contains grade');
  assert(result.includes('STUDENT CONTEXT:'), 'contains context header');
});

test('straightforward style', () => {
  const result = buildSystemPrompt({ style: 'straightforward', studentName: 'Bob', gradeLevel: 9 });
  assert(result.includes(TUTORING_SYSTEM_PROMPT_STRAIGHTFORWARD), 'contains straightforward prompt');
  assert(!result.includes(TUTORING_SYSTEM_PROMPT_HEURISTIC) ||
         TUTORING_SYSTEM_PROMPT_STRAIGHTFORWARD.includes(TUTORING_SYSTEM_PROMPT_HEURISTIC),
         'does not contain heuristic');
});

test('no personalization returns base prompt only', () => {
  const result = buildSystemPrompt({ style: 'heuristic', studentName: null, gradeLevel: null });
  assertEqual(result, TUTORING_SYSTEM_PROMPT_HEURISTIC, 'base prompt only');
  assert(!result.includes('STUDENT CONTEXT:'), 'no context section');
});

test('unknown style defaults to heuristic', () => {
  const result = buildSystemPrompt({ style: 'unknown', studentName: 'Test', gradeLevel: 1 });
  assert(result.includes(TUTORING_SYSTEM_PROMPT_HEURISTIC), 'defaults to heuristic');
});

// ===========================================================================
// Summary
// ===========================================================================
const passed = results.filter((r) => r.passed).length;
const failed = results.filter((r) => !r.passed).length;
console.log(`\n${'─'.repeat(50)}`);
console.log(`Results: ${passed} passed, ${failed} failed, ${results.length} total`);
if (failed > 0) {
  console.log('\nFailed:');
  results.filter((r) => !r.passed).forEach((r) => console.log(`  ❌ ${r.name}: ${r.error}`));
  process.exit(1);
} else {
  console.log('All logic tests passed.\n');
  process.exit(0);
}
