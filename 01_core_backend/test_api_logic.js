#!/usr/bin/env node

/**
 * Local API Logic Test
 * Tests the API handler logic without network calls
 */

const { URL } = require('url');

// Import our API handler
const apiHandler = require('./api/index.js');

// Mock Express res object
function createMockResponse() {
    const res = {
        statusCode: 200,
        headers: {},
        body: null,
        setHeader(name, value) {
            this.headers[name] = value;
        },
        status(code) {
            this.statusCode = code;
            return this;
        },
        json(data) {
            this.body = data;
            return this;
        }
    };
    return res;
}

// Mock Express req object
function createMockRequest(method, url, body = null) {
    return {
        method,
        url,
        body,
        headers: {
            'content-type': 'application/json'
        }
    };
}

// Test runner
async function testAPILogic() {
    console.log('🧪 Testing API Logic Locally');
    console.log('=' .repeat(40));
    
    const tests = [
        {
            name: '🔍 Health Check',
            req: createMockRequest('GET', '/health'),
            expectedStatus: 200
        },
        {
            name: '🔐 Login',
            req: createMockRequest('POST', '/api/auth/login', {
                email: 'test@example.com',
                password: 'password123'
            }),
            expectedStatus: 200
        },
        {
            name: '🤖 Question Processing',
            req: createMockRequest('POST', '/api/questions', {
                question: 'What is 2 + 2?',
                subject: 'mathematics'
            }),
            expectedStatus: 200
        },
        {
            name: '📊 Progress Tracking',
            req: createMockRequest('GET', '/api/progress'),
            expectedStatus: 200
        },
        {
            name: '📚 Sessions',
            req: createMockRequest('GET', '/api/sessions'),
            expectedStatus: 200
        },
        {
            name: '🌐 CORS Preflight',
            req: createMockRequest('OPTIONS', '/health'),
            expectedStatus: 200
        }
    ];
    
    let passed = 0;
    
    for (const test of tests) {
        try {
            const res = createMockResponse();
            await apiHandler(test.req, res);
            
            if (res.statusCode === test.expectedStatus && res.body) {
                console.log(`✅ ${test.name}: PASS`);
                console.log(`   Status: ${res.statusCode}`);
                console.log(`   Response: ${JSON.stringify(res.body).substring(0, 100)}...`);
                passed++;
            } else {
                console.log(`❌ ${test.name}: FAIL`);
                console.log(`   Expected: ${test.expectedStatus}, Got: ${res.statusCode}`);
                console.log(`   Response: ${JSON.stringify(res.body)}`);
            }
        } catch (error) {
            console.log(`❌ ${test.name}: ERROR - ${error.message}`);
        }
        console.log();
    }
    
    console.log('=' .repeat(40));
    console.log(`📋 Results: ${passed}/${tests.length} tests passed`);
    
    if (passed === tests.length) {
        console.log('🎉 All API logic tests PASSED!');
        console.log('✅ Backend logic is working correctly');
        console.log('📱 Ready for iPhone testing!');
    } else {
        console.log('⚠️  Some tests failed - check API logic');
    }
    
    return passed === tests.length;
}

// Run the tests
if (require.main === module) {
    testAPILogic().catch(console.error);
}

module.exports = { testAPILogic };