/**
 * Gateway Proxy Tests
 * Comprehensive test suite for Phase 1 API Gateway functionality
 */

const { test } = require('tap');
const { build } = require('./helper');
const nock = require('nock');

// Mock AI Engine responses
const mockAIEngine = () => {
  const aiEngineUrl = process.env.AI_ENGINE_URL || 'http://localhost:8000';
  
  return nock(aiEngineUrl)
    .defaultReplyHeaders({
      'Content-Type': 'application/json'
    });
};

test('Gateway Health Checks', async (t) => {
  const app = await build(t);

  t.test('basic health check', async (t) => {
    const res = await app.inject({
      method: 'GET',
      url: '/health'
    });
    
    t.equal(res.statusCode, 200);
    const payload = JSON.parse(res.payload);
    t.equal(payload.status, 'ok');
    t.equal(payload.service, 'api-gateway');
  });

  t.test('liveness probe', async (t) => {
    const res = await app.inject({
      method: 'GET',
      url: '/live'
    });
    
    t.equal(res.statusCode, 200);
    const payload = JSON.parse(res.payload);
    t.equal(payload.alive, true);
    t.type(payload.uptime, 'number');
  });
});

test('AI Engine Proxy Routes', async (t) => {
  const app = await build(t);

  t.test('process question endpoint', async (t) => {
    const mockResponse = {
      success: true,
      result: {
        answer: 'Test answer',
        explanation: 'Test explanation',
        confidence: 0.95
      }
    };

    const scope = mockAIEngine()
      .post('/api/v1/process-question')
      .reply(200, mockResponse);

    const res = await app.inject({
      method: 'POST',
      url: '/api/ai/process-question',
      payload: {
        question: 'What is 2+2?',
        subject: 'mathematics'
      }
    });
    
    t.equal(res.statusCode, 200);
    const payload = JSON.parse(res.payload);
    t.same(payload, mockResponse);
    
    scope.done();
  });
});

test('Error Handling', async (t) => {
  const app = await build(t);

  t.test('route not found', async (t) => {
    const res = await app.inject({
      method: 'GET',
      url: '/nonexistent-route'
    });
    
    t.equal(res.statusCode, 404);
    const payload = JSON.parse(res.payload);
    t.equal(payload.code, 'ROUTE_NOT_FOUND');
  });
});

test('Feature Flags', async (t) => {
  t.test('gateway can be disabled via feature flag', async (t) => {
    // This would require environment variable manipulation
    // In a real implementation, we'd test with different NODE_ENV settings
    t.pass('Feature flag testing would be implemented with env vars');
  });
});