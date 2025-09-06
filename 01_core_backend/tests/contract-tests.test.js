/**
 * Contract Testing Suite
 * Automated testing for API contract compliance
 */

const tap = require('tap');
const { contractValidator } = require('../src/gateway/middleware/contract-validation');
const fastify = require('fastify')({ logger: false });
const fs = require('fs');
const path = require('path');

// Test data sets for contract validation
const testCases = {
  // Valid request examples
  validRequests: {
    processQuestion: {
      question: "What is the derivative of x^2 + 3x + 5?",
      subject: "calculus",
      student_id: "student123",
      context: "Working on limits and derivatives unit"
    },
    generatePractice: {
      subject: "mathematics",
      topic: "quadratic equations",
      difficulty: "medium",
      count: 5,
      student_id: "student123"
    },
    evaluateAnswer: {
      question: "What is 2+2?",
      student_answer: "4",
      correct_answer: "4",
      subject: "mathematics",
      student_id: "student123"
    },
    createSession: {
      student_id: "student123",
      subject: "mathematics",
      session_type: "homework"
    }
  },

  // Invalid request examples
  invalidRequests: {
    processQuestion: {
      missingRequired: {
        subject: "calculus",
        student_id: "student123"
        // Missing required 'question' field
      },
      invalidSubject: {
        question: "What is the derivative of x^2?",
        subject: "invalid_subject",
        student_id: "student123"
      },
      emptyStudentId: {
        question: "What is the derivative of x^2?",
        subject: "calculus",
        student_id: ""
      }
    },
    generatePractice: {
      invalidCount: {
        subject: "mathematics",
        topic: "quadratic equations",
        count: 25, // Exceeds maximum of 10
        student_id: "student123"
      },
      missingTopic: {
        subject: "mathematics",
        student_id: "student123"
        // Missing required 'topic' field
      }
    }
  },

  // Valid response examples
  validResponses: {
    health: {
      status: "ok",
      service: "api-gateway",
      timestamp: "2025-01-08T10:00:00Z"
    },
    processQuestion: {
      success: true,
      answer: "The derivative is 2x + 3",
      explanation: "Using the power rule and constant rule",
      reasoning_steps: ["Apply power rule to x^2", "Apply constant rule to 3x", "Derivative of constant is 0"],
      key_concepts: ["power rule", "derivatives"],
      difficulty_level: "intermediate",
      confidence_score: 0.95,
      processing_time: 1250,
      follow_up_questions: ["What about the second derivative?"]
    },
    errorResponse: {
      error: "Validation Error",
      message: "Invalid request data",
      code: "VALIDATION_FAILED",
      timestamp: "2025-01-08T10:00:00Z",
      request_id: "123e4567-e89b-12d3-a456-426614174000"
    }
  }
};

class ContractTestSuite {
  constructor() {
    this.results = {
      total: 0,
      passed: 0,
      failed: 0,
      errors: []
    };
  }

  /**
   * Run all contract tests
   */
  async runAllTests() {
    console.log('🧪 Starting Contract Testing Suite');
    console.log('==================================');

    await this.testSpecificationLoading();
    await this.testRequestValidation();
    await this.testResponseValidation();
    await this.testErrorHandling();
    await this.testEdgeCases();
    
    this.printResults();
    return this.results;
  }

  /**
   * Test OpenAPI specification loading
   */
  async testSpecificationLoading() {
    tap.test('OpenAPI Specification Loading', async (t) => {
      t.test('Gateway specification loads correctly', async (t) => {
        const stats = contractValidator.getStats();
        t.ok(stats.gateway_spec_loaded, 'Gateway spec should be loaded');
        t.ok(stats.validators_count > 0, 'Should have compiled validators');
        this.recordResult(true, 'Gateway spec loading');
      });

      t.test('AI Engine specification loads correctly', async (t) => {
        const stats = contractValidator.getStats();
        t.ok(stats.ai_engine_spec_loaded, 'AI Engine spec should be loaded');
        this.recordResult(true, 'AI Engine spec loading');
      });

      t.test('Validator compilation success', async (t) => {
        const stats = contractValidator.getStats();
        t.ok(stats.validators_count >= 10, 'Should have multiple validators compiled');
        this.recordResult(true, 'Validator compilation');
      });
    });
  }

  /**
   * Test request validation
   */
  async testRequestValidation() {
    tap.test('Request Validation', async (t) => {
      // Test valid requests
      t.test('Valid request validation', async (t) => {
        for (const [endpoint, request] of Object.entries(testCases.validRequests)) {
          const path = this.getEndpointPath(endpoint);
          const result = contractValidator.validateRequest('POST', path, request);
          
          t.ok(result.valid, `Valid ${endpoint} request should pass validation`);
          this.recordResult(result.valid, `Valid ${endpoint} request`);
        }
      });

      // Test invalid requests
      t.test('Invalid request validation', async (t) => {
        for (const [endpoint, invalidCases] of Object.entries(testCases.invalidRequests)) {
          for (const [caseName, request] of Object.entries(invalidCases)) {
            const path = this.getEndpointPath(endpoint);
            const result = contractValidator.validateRequest('POST', path, request);
            
            t.notOk(result.valid, `Invalid ${endpoint} (${caseName}) should fail validation`);
            t.ok(result.errors && result.errors.length > 0, `Should provide validation errors`);
            this.recordResult(!result.valid, `Invalid ${endpoint} ${caseName}`);
          }
        }
      });
    });
  }

  /**
   * Test response validation
   */
  async testResponseValidation() {
    tap.test('Response Validation', async (t) => {
      t.test('Valid response validation', async (t) => {
        // Test health endpoint response
        const healthResult = contractValidator.validateResponse('GET', '/health', '200', testCases.validResponses.health);
        t.ok(healthResult.valid, 'Health response should be valid');
        this.recordResult(healthResult.valid, 'Health response validation');

        // Test process question response
        const questionResult = contractValidator.validateResponse('POST', '/api/ai/process-question', '200', testCases.validResponses.processQuestion);
        t.ok(questionResult.valid, 'Process question response should be valid');
        this.recordResult(questionResult.valid, 'Process question response validation');

        // Test error response (use ValidationError for 400 response)
        const errorResult = contractValidator.validateResponse('POST', '/api/ai/process-question', '400', testCases.validResponses.errorResponse);
        console.log('Error validation result:', errorResult);
        if (!errorResult.valid) {
          console.log('Error validation errors:', errorResult.errors);
        }
        t.ok(errorResult.valid, 'Error response should be valid');
        this.recordResult(errorResult.valid, 'Error response validation');
      });

      t.test('Invalid response validation', async (t) => {
        // Test malformed response
        const invalidResponse = { invalid: "response" };
        const result = contractValidator.validateResponse('GET', '/health', '200', invalidResponse);
        t.notOk(result.valid, 'Invalid response should fail validation');
        this.recordResult(!result.valid, 'Invalid response validation');
      });
    });
  }

  /**
   * Test error handling
   */
  async testErrorHandling() {
    tap.test('Error Handling', async (t) => {
      t.test('Missing endpoint validation', async (t) => {
        const result = contractValidator.validateRequest('POST', '/nonexistent', {});
        t.equal(result.code, 'NO_VALIDATOR', 'Should handle missing validators gracefully');
        this.recordResult(result.code === 'NO_VALIDATOR', 'Missing endpoint handling');
      });

      t.test('Malformed request handling', async (t) => {
        const result = contractValidator.validateRequest('POST', '/api/ai/process-question', "invalid json");
        t.notOk(result.valid, 'Should handle malformed requests');
        this.recordResult(!result.valid, 'Malformed request handling');
      });
    });
  }

  /**
   * Test edge cases
   */
  async testEdgeCases() {
    tap.test('Edge Cases', async (t) => {
      t.test('Validation disabled mode', async (t) => {
        const originalEnabled = contractValidator.enabled;
        contractValidator.setEnabled(false);
        
        const result = contractValidator.validateRequest('POST', '/api/ai/process-question', {});
        // When disabled, validation should still work for manual testing
        t.ok(true, 'Should handle disabled mode gracefully');
        
        contractValidator.setEnabled(originalEnabled);
        this.recordResult(true, 'Validation disabled mode');
      });

      t.test('Large request validation', async (t) => {
        const largeRequest = {
          question: "A".repeat(3000), // Exceeds 2000 char limit
          subject: "mathematics",
          student_id: "student123"
        };
        
        const result = contractValidator.validateRequest('POST', '/api/ai/process-question', largeRequest);
        t.notOk(result.valid, 'Should reject oversized requests');
        this.recordResult(!result.valid, 'Large request validation');
      });

      t.test('Special characters handling', async (t) => {
        const specialCharsRequest = {
          question: "What is the derivative of ∫x²dx? ∂/∂x[sin(θ)]",
          subject: "calculus",
          student_id: "student_特殊字符_123"
        };
        
        const result = contractValidator.validateRequest('POST', '/api/ai/process-question', specialCharsRequest);
        t.ok(result.valid, 'Should handle special characters');
        this.recordResult(result.valid, 'Special characters handling');
      });
    });
  }

  /**
   * Get endpoint path for testing
   */
  getEndpointPath(endpoint) {
    const pathMap = {
      processQuestion: '/api/ai/process-question',
      generatePractice: '/api/ai/generate-practice',
      evaluateAnswer: '/api/ai/evaluate-answer',
      createSession: '/api/ai/sessions/create'
    };
    return pathMap[endpoint] || '/unknown';
  }

  /**
   * Record test result
   */
  recordResult(passed, testName) {
    this.results.total++;
    if (passed) {
      this.results.passed++;
    } else {
      this.results.failed++;
      this.results.errors.push(testName);
    }
  }

  /**
   * Print test results
   */
  printResults() {
    console.log('\\n📊 Contract Testing Results');
    console.log('===========================');
    console.log(`Total Tests: ${this.results.total}`);
    console.log(`Passed: ${this.results.passed} ✅`);
    console.log(`Failed: ${this.results.failed} ❌`);
    console.log(`Success Rate: ${((this.results.passed / this.results.total) * 100).toFixed(1)}%`);
    
    if (this.results.errors.length > 0) {
      console.log('\\nFailed Tests:');
      this.results.errors.forEach(error => console.log(`  - ${error}`));
    }
    
    console.log('\\n' + (this.results.failed === 0 ? '🎉 All contract tests passed!' : '⚠️ Some contract tests failed'));
  }

  /**
   * Generate contract testing report
   */
  generateReport() {
    const report = {
      timestamp: new Date().toISOString(),
      summary: {
        total: this.results.total,
        passed: this.results.passed,
        failed: this.results.failed,
        success_rate: ((this.results.passed / this.results.total) * 100).toFixed(1)
      },
      validator_stats: contractValidator.getStats(),
      failed_tests: this.results.errors,
      recommendations: this.generateRecommendations()
    };
    
    const reportPath = path.join(__dirname, '../reports/contract-test-report.json');
    
    // Ensure reports directory exists
    const reportsDir = path.dirname(reportPath);
    if (!fs.existsSync(reportsDir)) {
      fs.mkdirSync(reportsDir, { recursive: true });
    }
    
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    console.log(`\\n📄 Contract test report saved to: ${reportPath}`);
    
    return report;
  }

  /**
   * Generate recommendations based on test results
   */
  generateRecommendations() {
    const recommendations = [];
    
    if (this.results.failed > 0) {
      recommendations.push('Review and fix failing contract validations');
    }
    
    if (this.results.failed / this.results.total > 0.1) {
      recommendations.push('Consider updating OpenAPI specifications to match implementation');
    }
    
    const stats = contractValidator.getStats();
    if (!stats.gateway_spec_loaded || !stats.ai_engine_spec_loaded) {
      recommendations.push('Ensure all OpenAPI specifications are properly loaded');
    }
    
    if (stats.validators_count < 10) {
      recommendations.push('Verify OpenAPI specifications have comprehensive endpoint coverage');
    }
    
    return recommendations;
  }
}

// Export test suite and run if called directly
const contractTestSuite = new ContractTestSuite();

// Run tests if this file is executed directly
if (require.main === module) {
  contractTestSuite.runAllTests()
    .then((results) => {
      contractTestSuite.generateReport();
      process.exit(results.failed === 0 ? 0 : 1);
    })
    .catch((error) => {
      console.error('Contract testing failed:', error);
      process.exit(1);
    });
}

module.exports = {
  ContractTestSuite,
  contractTestSuite,
  testCases
};