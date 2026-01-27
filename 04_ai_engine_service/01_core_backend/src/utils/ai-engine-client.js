/**
 * AI Engine Circuit Breaker
 *
 * Prevents cascade failures when AI Engine is unavailable by implementing
 * circuit breaker pattern with automatic recovery.
 *
 * States:
 * - CLOSED: Normal operation, requests pass through
 * - OPEN: Circuit is open, all requests fail immediately
 * - HALF_OPEN: Testing recovery, single request allowed
 */

class AIEngineCircuitBreaker {
    constructor(options = {}) {
        this.failureThreshold = options.failureThreshold || 3;
        this.resetTimeout = options.resetTimeout || 30000; // 30 seconds
        this.monitoringPeriod = options.monitoringPeriod || 60000; // 1 minute

        this.state = 'CLOSED';
        this.failureCount = 0;
        this.lastFailureTime = null;
        this.nextAttemptTime = null;
        this.successCount = 0;

        // Statistics
        this.stats = {
            totalRequests: 0,
            successfulRequests: 0,
            failedRequests: 0,
            circuitOpenCount: 0,
            lastStateChange: new Date()
        };
    }

    /**
     * Execute a fetch request with circuit breaker protection
     */
    async call(url, options = {}) {
        this.stats.totalRequests++;

        // Check circuit state
        if (this.state === 'OPEN') {
            const now = Date.now();

            // Check if it's time to attempt recovery
            if (now >= this.nextAttemptTime) {
                console.log('🔄 Circuit breaker entering HALF_OPEN state - attempting recovery');
                this.state = 'HALF_OPEN';
                this.stats.lastStateChange = new Date();
            } else {
                const waitTime = Math.ceil((this.nextAttemptTime - now) / 1000);
                throw new Error(`Circuit breaker OPEN - AI Engine unavailable. Retry in ${waitTime}s`);
            }
        }

        try {
            // Make the actual request
            const response = await fetch(url, options);

            // Check response status
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            // Success! Handle state transitions
            this.onSuccess();

            return response;

        } catch (error) {
            // Failure! Handle state transitions
            this.onFailure(error);

            throw error;
        }
    }

    /**
     * Handle successful request
     */
    onSuccess() {
        this.stats.successfulRequests++;

        if (this.state === 'HALF_OPEN') {
            // Recovery successful - close circuit
            console.log('✅ Circuit breaker HALF_OPEN → CLOSED (recovery successful)');
            this.state = 'CLOSED';
            this.failureCount = 0;
            this.successCount = 0;
            this.lastFailureTime = null;
            this.nextAttemptTime = null;
            this.stats.lastStateChange = new Date();
        } else if (this.state === 'CLOSED') {
            // Normal operation - reset failure count on success
            this.failureCount = 0;
        }
    }

    /**
     * Handle failed request
     */
    onFailure(error) {
        this.stats.failedRequests++;
        this.failureCount++;
        this.lastFailureTime = Date.now();

        console.log(`❌ Circuit breaker failure (${this.failureCount}/${this.failureThreshold}): ${error.message}`);

        if (this.state === 'HALF_OPEN') {
            // Recovery failed - reopen circuit
            console.log('❌ Circuit breaker HALF_OPEN → OPEN (recovery failed)');
            this.openCircuit();
        } else if (this.state === 'CLOSED' && this.failureCount >= this.failureThreshold) {
            // Threshold exceeded - open circuit
            console.log(`❌ Circuit breaker CLOSED → OPEN (${this.failureCount} consecutive failures)`);
            this.openCircuit();
        }
    }

    /**
     * Open the circuit breaker
     */
    openCircuit() {
        this.state = 'OPEN';
        this.nextAttemptTime = Date.now() + this.resetTimeout;
        this.stats.circuitOpenCount++;
        this.stats.lastStateChange = new Date();

        const resetDate = new Date(this.nextAttemptTime);
        console.log(`🚫 Circuit breaker OPEN until ${resetDate.toLocaleTimeString()}`);
    }

    /**
     * Get current circuit breaker status
     */
    getStatus() {
        return {
            state: this.state,
            failureCount: this.failureCount,
            failureThreshold: this.failureThreshold,
            lastFailureTime: this.lastFailureTime ? new Date(this.lastFailureTime) : null,
            nextAttemptTime: this.nextAttemptTime ? new Date(this.nextAttemptTime) : null,
            stats: this.stats
        };
    }

    /**
     * Manually reset circuit breaker (for testing/admin purposes)
     */
    reset() {
        console.log('🔄 Circuit breaker manually reset');
        this.state = 'CLOSED';
        this.failureCount = 0;
        this.lastFailureTime = null;
        this.nextAttemptTime = null;
        this.successCount = 0;
        this.stats.lastStateChange = new Date();
    }
}

// Create singleton instance
const aiEngineCircuitBreaker = new AIEngineCircuitBreaker({
    failureThreshold: 3,
    resetTimeout: 30000, // 30 seconds
    monitoringPeriod: 60000 // 1 minute
});

module.exports = aiEngineCircuitBreaker;
