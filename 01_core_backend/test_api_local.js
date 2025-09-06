#!/usr/bin/env node

/**
 * StudyAI Backend API Test Script
 * Tests all endpoints from laptop before iPhone testing
 */

const https = require('https');
const { URL } = require('url');

const API_BASE_URL = 'https://study-ai-backend-9w2x.vercel.app';

// Colors for console output
const colors = {
    reset: '\x1b[0m',
    green: '\x1b[32m',
    red: '\x1b[31m',
    blue: '\x1b[34m',
    yellow: '\x1b[33m',
    purple: '\x1b[35m'
};

function log(color, message) {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

// Generic HTTP request function
function makeRequest(url, options = {}) {
    return new Promise((resolve, reject) => {
        const urlObj = new URL(url);
        
        const requestOptions = {
            hostname: urlObj.hostname,
            port: urlObj.port || 443,
            path: urlObj.pathname + urlObj.search,
            method: options.method || 'GET',
            headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'StudyAI-Test-Script/1.0',
                ...options.headers
            }
        };

        const req = https.request(requestOptions, (res) => {
            let data = '';
            
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                try {
                    const jsonData = JSON.parse(data);
                    resolve({
                        statusCode: res.statusCode,
                        headers: res.headers,
                        data: jsonData
                    });
                } catch (e) {
                    resolve({
                        statusCode: res.statusCode,
                        headers: res.headers,
                        data: data,
                        parseError: true
                    });
                }
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        if (options.body) {
            req.write(JSON.stringify(options.body));
        }

        req.end();
    });
}

// Test Functions
async function testHealthCheck() {
    log('blue', '\n🔍 Testing Health Check...');
    
    try {
        const response = await makeRequest(`${API_BASE_URL}/health`);
        
        if (response.statusCode === 200) {
            log('green', '✅ Health Check: SUCCESS');
            log('green', `   Status: ${response.data.status}`);
            log('green', `   Service: ${response.data.service}`);
            log('green', `   Message: ${response.data.message}`);
            return true;
        } else {
            log('red', `❌ Health Check: FAILED (${response.statusCode})`);
            console.log('   Response:', response.data);
            return false;
        }
    } catch (error) {
        log('red', `❌ Health Check: ERROR - ${error.message}`);
        return false;
    }
}

async function testLogin() {
    log('blue', '\n🔐 Testing Login...');
    
    const loginData = {
        email: 'test@example.com',
        password: 'password123'
    };
    
    try {
        const response = await makeRequest(`${API_BASE_URL}/api/auth/login`, {
            method: 'POST',
            body: loginData
        });
        
        if (response.statusCode === 200) {
            log('green', '✅ Login: SUCCESS');
            log('green', `   Message: ${response.data.message}`);
            log('green', `   Token: ${response.data.token}`);
            log('green', `   User: ${JSON.stringify(response.data.user)}`);
            return true;
        } else {
            log('red', `❌ Login: FAILED (${response.statusCode})`);
            console.log('   Response:', response.data);
            return false;
        }
    } catch (error) {
        log('red', `❌ Login: ERROR - ${error.message}`);
        return false;
    }
}

async function testQuestionProcessing() {
    log('blue', '\n🤖 Testing Question Processing...');
    
    const questionData = {
        question: 'What is 2 + 2?',
        subject: 'mathematics'
    };
    
    try {
        const response = await makeRequest(`${API_BASE_URL}/api/questions`, {
            method: 'POST',
            body: questionData
        });
        
        if (response.statusCode === 200) {
            log('green', '✅ Question Processing: SUCCESS');
            log('green', `   Question: ${response.data.question}`);
            log('green', `   Answer: ${response.data.answer}`);
            log('green', `   Question ID: ${response.data.questionId}`);
            return true;
        } else {
            log('red', `❌ Question Processing: FAILED (${response.statusCode})`);
            console.log('   Response:', response.data);
            return false;
        }
    } catch (error) {
        log('red', `❌ Question Processing: ERROR - ${error.message}`);
        return false;
    }
}

async function testProgress() {
    log('blue', '\n📊 Testing Progress Tracking...');
    
    try {
        const response = await makeRequest(`${API_BASE_URL}/api/progress`);
        
        if (response.statusCode === 200) {
            log('green', '✅ Progress: SUCCESS');
            log('green', `   Total Questions: ${response.data.totalQuestions}`);
            log('green', `   Correct Answers: ${response.data.correctAnswers}`);
            log('green', `   Accuracy: ${response.data.accuracy}`);
            return true;
        } else {
            log('red', `❌ Progress: FAILED (${response.statusCode})`);
            console.log('   Response:', response.data);
            return false;
        }
    } catch (error) {
        log('red', `❌ Progress: ERROR - ${error.message}`);
        return false;
    }
}

async function testSessionsEndpoint() {
    log('blue', '\n📚 Testing Sessions Endpoint...');
    
    try {
        const response = await makeRequest(`${API_BASE_URL}/api/sessions`);
        
        if (response.statusCode === 200) {
            log('green', '✅ Sessions: SUCCESS');
            log('green', `   Sessions Count: ${response.data.sessions ? response.data.sessions.length : 'N/A'}`);
            return true;
        } else {
            log('red', `❌ Sessions: FAILED (${response.statusCode})`);
            console.log('   Response:', response.data);
            return false;
        }
    } catch (error) {
        log('red', `❌ Sessions: ERROR - ${error.message}`);
        return false;
    }
}

async function testCORSHeaders() {
    log('blue', '\n🌐 Testing CORS Headers...');
    
    try {
        const response = await makeRequest(`${API_BASE_URL}/health`, {
            method: 'OPTIONS'
        });
        
        const corsHeaders = {
            'access-control-allow-origin': response.headers['access-control-allow-origin'],
            'access-control-allow-methods': response.headers['access-control-allow-methods'],
            'access-control-allow-headers': response.headers['access-control-allow-headers']
        };
        
        log('green', '✅ CORS Headers:');
        Object.entries(corsHeaders).forEach(([key, value]) => {
            if (value) {
                log('green', `   ${key}: ${value}`);
            }
        });
        
        return true;
    } catch (error) {
        log('red', `❌ CORS: ERROR - ${error.message}`);
        return false;
    }
}

// Main test runner
async function runAllTests() {
    log('purple', '🚀 StudyAI Backend API Test Suite');
    log('purple', `📡 Testing: ${API_BASE_URL}`);
    log('purple', '=' .repeat(50));
    
    const startTime = Date.now();
    const results = [];
    
    // Run all tests
    results.push(await testHealthCheck());
    results.push(await testLogin());
    results.push(await testQuestionProcessing());
    results.push(await testProgress());
    results.push(await testSessionsEndpoint());
    results.push(await testCORSHeaders());
    
    // Summary
    const endTime = Date.now();
    const duration = endTime - startTime;
    const passed = results.filter(r => r).length;
    const total = results.length;
    
    log('purple', '\n' + '=' .repeat(50));
    log('purple', '📋 TEST SUMMARY');
    log('purple', '=' .repeat(50));
    
    if (passed === total) {
        log('green', `✅ ALL TESTS PASSED (${passed}/${total})`);
        log('green', `⏱️  Total time: ${duration}ms`);
        log('green', '🎉 Backend is ready for iPhone integration!');
    } else {
        log('yellow', `⚠️  SOME TESTS FAILED (${passed}/${total})`);
        log('yellow', `⏱️  Total time: ${duration}ms`);
        log('yellow', '🔧 Check failed tests before iPhone integration');
    }
    
    log('purple', '\n🔄 Next Steps:');
    if (passed === total) {
        log('green', '1. ✅ Backend verified - proceed with iPhone testing');
        log('green', '2. 📱 Run iOS app and test API connectivity');
        log('green', '3. 🔗 Integrate with real Supabase and OpenAI APIs');
    } else {
        log('red', '1. 🐛 Fix failing API endpoints');
        log('red', '2. 🔄 Re-run this test script');
        log('red', '3. 📱 Proceed with iPhone testing only after all pass');
    }
}

// Run the tests
if (require.main === module) {
    runAllTests().catch(console.error);
}

module.exports = {
    testHealthCheck,
    testLogin,
    testQuestionProcessing,
    testProgress,
    testSessionsEndpoint,
    testCORSHeaders,
    runAllTests
};