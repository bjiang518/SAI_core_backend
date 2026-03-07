/**
 * API Contract Tests
 *
 * These tests hit the LIVE backend and verify that responses match
 * the JSON shapes iOS expects. Run before deploying to catch breaking changes.
 *
 * Usage:
 *   npm run test:contracts
 *
 * Configuration:
 *   BACKEND_URL  — target server (default: http://localhost:3002)
 *   TEST_EMAIL   — test account email (default: test@studyai.com)
 *   TEST_PASSWORD — test account password (default: test123456)
 *
 * These tests are intentionally simple — no mocks, no Fastify injection,
 * just HTTP requests verifying response shapes.
 */

const BACKEND_URL = process.env.BACKEND_URL || 'http://localhost:3002';
const TEST_EMAIL = process.env.TEST_EMAIL || 'test@studyai.com';
const TEST_PASSWORD = process.env.TEST_PASSWORD || 'test123456';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let authToken = null;
let testSessionId = null;

async function post(path, body, { token, stream } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(`${BACKEND_URL}${path}`, {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
  });
  if (stream) return res;
  const json = await res.json();
  return { status: res.status, body: json };
}

async function get(path, { token } = {}) {
  const headers = {};
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const res = await fetch(`${BACKEND_URL}${path}`, { headers });
  const json = await res.json();
  return { status: res.status, body: json };
}

function assert(condition, message) {
  if (!condition) throw new Error(`ASSERTION FAILED: ${message}`);
}

function assertType(value, type, fieldName) {
  const actual = typeof value;
  assert(actual === type, `${fieldName} should be ${type}, got ${actual} (value: ${JSON.stringify(value)})`);
}

function assertPresent(obj, field) {
  assert(obj[field] !== undefined && obj[field] !== null, `Missing required field: ${field}`);
}

// ---------------------------------------------------------------------------
// Test runner
// ---------------------------------------------------------------------------

const results = [];

async function test(name, fn) {
  try {
    await fn();
    results.push({ name, passed: true });
    console.log(`  ✅ ${name}`);
  } catch (err) {
    results.push({ name, passed: false, error: err.message });
    console.log(`  ❌ ${name}`);
    console.log(`     ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

async function run() {
  console.log(`\n📋 API Contract Tests — ${BACKEND_URL}\n`);

  // ---- 1. Health ----
  console.log('1. Health');
  await test('GET /health returns status ok', async () => {
    const { status, body } = await get('/health');
    assert(status === 200, `Expected 200, got ${status}`);
    assertPresent(body, 'status');
    assert(body.status === 'ok', `Expected status "ok", got "${body.status}"`);
    assertPresent(body, 'timestamp');
  });

  // ---- 2. Auth — get a token for remaining tests ----
  console.log('\n2. Authentication');
  await test('POST /api/auth/login returns expected shape', async () => {
    const { status, body } = await post('/api/auth/login', {
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
    });
    if (status === 200) {
      assertPresent(body, 'token');
      assertType(body.token, 'string', 'token');
      authToken = body.token;
      if (body.user) {
        assertPresent(body.user, 'id');
      }
    } else if (status === 401) {
      // 401 is expected when test account doesn't exist — just verify shape
      assertPresent(body, 'success');
      assert(body.success === false, 'Expected success: false on 401');
      assertPresent(body, 'message');
      console.log('     ⚠️  Login returned 401 (test account may not exist) — skipping auth-required tests');
    } else {
      assert(false, `Unexpected status ${status}: ${JSON.stringify(body)}`);
    }
  });

  if (!authToken) {
    console.log('\n⚠️  No auth token — skipping authenticated endpoint tests.');
    console.log('   Create a test account or set TEST_EMAIL / TEST_PASSWORD.\n');
    printSummary();
    return;
  }

  // ---- 3. Session Create ----
  console.log('\n3. Session Create');
  await test('POST /api/ai/sessions/create returns session shape', async () => {
    const { status, body } = await post('/api/ai/sessions/create', {
      subject: 'Math',
      language: 'en',
    }, { token: authToken });

    assert(status === 200, `Expected 200, got ${status}`);

    // These fields are what iOS reads in NetworkService.swift
    assertPresent(body, 'success');
    assert(body.success === true, 'Expected success: true');
    assertPresent(body, 'session_id');
    assertType(body.session_id, 'string', 'session_id');

    // Store for message test
    testSessionId = body.session_id;
  });

  // ---- 4. Session Message Stream (SSE) ----
  console.log('\n4. Session Message Stream');
  if (testSessionId) {
    await test('POST /api/ai/sessions/:id/message/stream returns valid SSE', async () => {
      const res = await post(`/api/ai/sessions/${testSessionId}/message/stream`, {
        message: 'What is 2+2?',
        language: 'en',
      }, { token: authToken, stream: true });

      // 500/503 = AI Engine unreachable (expected locally) — skip, not a contract failure
      if (res.status === 500 || res.status === 503) {
        const body = await res.json();
        const msg = JSON.stringify(body).toLowerCase();
        if (msg.includes('unavailable') || msg.includes('enotfound') || msg.includes('circuit')) {
          console.log('     ⚠️  AI Engine unreachable — skipping (run against production for full test)');
          return;
        }
        assert(false, `Unexpected 500: ${JSON.stringify(body).slice(0, 200)}`);
      }

      assert(res.status === 200, `Expected 200, got ${res.status}`);
      const contentType = res.headers.get('content-type');
      assert(
        contentType && contentType.includes('text/event-stream'),
        `Expected text/event-stream, got ${contentType}`
      );

      // Read the SSE stream and validate event shapes
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';
      let sawStart = false;
      let sawContent = false;
      let sawEnd = false;
      const timeout = setTimeout(() => { reader.cancel(); }, 30000); // 30s max

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });

          // Parse SSE lines
          const lines = buffer.split('\n');
          buffer = lines.pop(); // keep incomplete line

          for (const line of lines) {
            if (!line.startsWith('data: ')) continue;
            const jsonStr = line.slice(6).trim();
            if (!jsonStr) continue;

            let event;
            try { event = JSON.parse(jsonStr); } catch { continue; }

            if (event.type === 'start') {
              sawStart = true;
              assertPresent(event, 'session_id');
            } else if (event.type === 'content') {
              sawContent = true;
              assertPresent(event, 'delta');
              assertPresent(event, 'content');
            } else if (event.type === 'end') {
              sawEnd = true;
              assertPresent(event, 'content');
              reader.cancel();
              break;
            } else if (event.type === 'suggestions') {
              assert(Array.isArray(event.suggestions), 'suggestions should be array');
            } else if (event.type === 'error') {
              // Error events are valid — just verify shape
              assertPresent(event, 'error');
            }
          }
          if (sawEnd) break;
        }
      } finally {
        clearTimeout(timeout);
      }

      assert(sawStart, 'SSE stream must contain a "start" event');
      assert(sawContent || sawEnd, 'SSE stream must contain "content" or "end" event');
    });
  } else {
    console.log('  ⏭️  Skipped (no session created)');
  }

  // ---- 5. Question Generation ----
  console.log('\n5. Question Generation');
  await test('POST /api/ai/generate-questions/practice/v2 returns questions array', async () => {
    const { status, body } = await post('/api/ai/generate-questions/practice/v2', {
      subject: 'Math',
      mode: 1,
      count: 2,
      question_type: 'multiple_choice',
      difficulty: 2,
      language: 'en',
    }, { token: authToken });

    // 500/503 = AI Engine unreachable (expected locally)
    if (status === 500 || status === 503) {
      const msg = JSON.stringify(body).toLowerCase();
      if (msg.includes('unavailable') || msg.includes('enotfound') || msg.includes('circuit')) {
        console.log('     ⚠️  AI Engine unreachable — skipping (run against production for full test)');
        return;
      }
      assert(false, `Unexpected 500: ${JSON.stringify(body).slice(0, 200)}`);
    }

    assert(status === 200, `Expected 200, got ${status}`);
    assertPresent(body, 'success');
    assert(body.success === true, `Expected success: true, got ${JSON.stringify(body).slice(0, 200)}`);
    assertPresent(body, 'questions');
    assert(Array.isArray(body.questions), 'questions should be array');
    assert(body.questions.length > 0, 'questions array should not be empty');

    // Validate individual question shape (what iOS QuestionGenerationService expects)
    const q = body.questions[0];
    assertPresent(q, 'question');
    assertPresent(q, 'type');
    assert(
      ['multiple_choice', 'true_false', 'short_answer'].includes(q.type),
      `Unexpected question type: ${q.type}`
    );

    // Metadata
    assertPresent(body, 'metadata');
    assertPresent(body.metadata, 'total_questions');
    assertType(body.metadata.total_questions, 'number', 'metadata.total_questions');
  });

  // ---- 6. Question Generation — validation errors ----
  console.log('\n6. Error Shape Validation');
  await test('Missing auth returns 401 with error field', async () => {
    const { status, body } = await post('/api/ai/generate-questions/practice/v2', {
      subject: 'Math',
    });
    assert(status === 401, `Expected 401, got ${status}`);
    assertPresent(body, 'error');
  });

  await test('Mode 2 without mistakes_data returns 400', async () => {
    const { status, body } = await post('/api/ai/generate-questions/practice/v2', {
      subject: 'Math',
      mode: 2,
      count: 2,
    }, { token: authToken });
    assert(status === 400, `Expected 400, got ${status}`);
    assertPresent(body, 'success');
    assert(body.success === false, 'Expected success: false');
    assertPresent(body, 'error');
  });

  // ---- Done ----
  printSummary();
}

function printSummary() {
  const passed = results.filter((r) => r.passed).length;
  const failed = results.filter((r) => !r.passed).length;
  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Results: ${passed} passed, ${failed} failed, ${results.length} total`);
  if (failed > 0) {
    console.log('\nFailed tests:');
    results.filter((r) => !r.passed).forEach((r) => {
      console.log(`  ❌ ${r.name}: ${r.error}`);
    });
    process.exit(1);
  } else {
    console.log('All contract tests passed.\n');
    process.exit(0);
  }
}

run().catch((err) => {
  console.error('Test runner crashed:', err);
  process.exit(1);
});
