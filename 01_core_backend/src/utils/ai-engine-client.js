/**
 * AI Engine Circuit Breaker
 * Prevents cascade failures when AI Engine is unavailable
 *
 * Circuit Breaker States:
 * - CLOSED: Normal operation, requests pass through
 * - OPEN: AI Engine unavailable, requests fail fast
 * - HALF_OPEN: Testing if AI Engine recovered
 */

const fetch = require('node-fetch');

class AIEngineCircuitBreaker {
  constructor() {
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
    this.failureCount = 0;
    this.successCount = 0;
    this.failureThreshold = 3; // Open circuit after 3 failures
    this.successThreshold = 2; // Close circuit after 2 successes in HALF_OPEN
    this.resetTimeout = 30000; // 30 seconds before trying HALF_OPEN
    this.lastFailureTime = null;
    this.lastStateChange = Date.now();
  }

  /**
   * Make HTTP request with circuit breaker protection
   * @param {string} url - Request URL
   * @param {object} options - Fetch options
   * @returns {Promise<Response>} - Fetch response
   */
  async call(url, options = {}) {
    // Check if circuit should transition from OPEN to HALF_OPEN
    if (this.state === 'OPEN') {
      const timeSinceLastFailure = Date.now() - this.lastFailureTime;

      if (timeSinceLastFailure >= this.resetTimeout) {
        console.log('🔄 Circuit breaker: OPEN → HALF_OPEN (testing recovery)');
        this.state = 'HALF_OPEN';
        this.successCount = 0;
        this.lastStateChange = Date.now();
      } else {
        const remainingTime = Math.ceil((this.resetTimeout - timeSinceLastFailure) / 1000);
        throw new Error(`Circuit breaker OPEN - AI Engine unavailable. Retry in ${remainingTime}s`);
      }
    }

    // Attempt the request
    try {
      const response = await fetch(url, options);

      // Check if response is successful
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
      }

      // Success - handle state transitions
      this.onSuccess();
      return response;

    } catch (error) {
      // Failure - handle state transitions
      this.onFailure();
      throw error;
    }
  }

  /**
   * Handle successful request
   */
  onSuccess() {
    if (this.state === 'HALF_OPEN') {
      this.successCount++;
      console.log(`✅ Circuit breaker HALF_OPEN: Success ${this.successCount}/${this.successThreshold}`);

      if (this.successCount >= this.successThreshold) {
        console.log('✅ Circuit breaker: HALF_OPEN → CLOSED (AI Engine recovered)');
        this.state = 'CLOSED';
        this.failureCount = 0;
        this.successCount = 0;
        this.lastStateChange = Date.now();
      }
    } else if (this.state === 'CLOSED') {
      // Reset failure count on success in CLOSED state
      this.failureCount = 0;
    }
  }

  /**
   * Handle failed request
   */
  onFailure() {
    this.lastFailureTime = Date.now();

    if (this.state === 'HALF_OPEN') {
      // Failure in HALF_OPEN - go back to OPEN
      console.log('❌ Circuit breaker: HALF_OPEN → OPEN (recovery failed)');
      this.state = 'OPEN';
      this.failureCount = 0;
      this.successCount = 0;
      this.lastStateChange = Date.now();

    } else if (this.state === 'CLOSED') {
      this.failureCount++;
      console.log(`⚠️ Circuit breaker CLOSED: Failure ${this.failureCount}/${this.failureThreshold}`);

      if (this.failureCount >= this.failureThreshold) {
        console.log('❌ Circuit breaker: CLOSED → OPEN (AI Engine unavailable)');
        this.state = 'OPEN';
        this.lastStateChange = Date.now();
      }
    }
  }

  /**
   * Get current circuit breaker state
   */
  getState() {
    return {
      state: this.state,
      failureCount: this.failureCount,
      successCount: this.successCount,
      lastStateChange: this.lastStateChange,
      lastFailureTime: this.lastFailureTime
    };
  }

  /**
   * Reset circuit breaker to CLOSED state
   */
  reset() {
    console.log('🔄 Circuit breaker manually reset to CLOSED');
    this.state = 'CLOSED';
    this.failureCount = 0;
    this.successCount = 0;
    this.lastFailureTime = null;
    this.lastStateChange = Date.now();
  }
}

// Export singleton instance
module.exports = new AIEngineCircuitBreaker();
