/**
 * OpenAI Assistants API Service
 *
 * Provides core functionality for interacting with OpenAI Assistants API:
 * - Thread management
 * - Message handling
 * - Run orchestration
 * - Function calling
 * - Cost tracking
 * - Performance monitoring
 */

const OpenAI = require('openai');
const crypto = require('crypto');
const { db } = require('../utils/railway-database');
const logger = require('../utils/logger');  // PRODUCTION: Structured logging

class AssistantsService {
  constructor() {
    this.client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
      timeout: parseInt(process.env.ASSISTANT_TIMEOUT_MS || '60000'),
      maxRetries: parseInt(process.env.ASSISTANT_MAX_RETRIES || '2')
    });

    this.pollingInterval = parseInt(process.env.ASSISTANT_POLLING_INTERVAL_MS || '500');
    this.assistantCache = new Map(); // Cache assistant IDs
    this.functionCallCache = new Map(); // Cache function results
    this.consecutiveErrors = 0;
    this.errorThreshold = parseInt(process.env.FALLBACK_ERROR_THRESHOLD || '5');

    logger.debug('✅ AssistantsService initialized');
  }

  // ============================================
  // Thread Management
  // ============================================

  /**
   * Create a new OpenAI thread
   * @param {Object} metadata - Thread metadata (user_id, subject, purpose, etc.)
   * @returns {Promise<Object>} Thread object with id
   */
  async createThread(metadata = {}) {
    try {
      // OpenAI metadata only accepts strings, convert all values
      const stringMetadata = {};
      for (const [key, value] of Object.entries(metadata)) {
        stringMetadata[key] = String(value);
      }
      stringMetadata.created_at = new Date().toISOString();

      const thread = await this.client.beta.threads.create({
        metadata: stringMetadata
      });

      // Store thread metadata in database (original values)
      await this.storeThreadMetadata(thread.id, metadata);

      logger.debug(`📝 Created thread: ${thread.id}`);
      return thread;
    } catch (error) {
      logger.error('❌ Failed to create thread:', error);
      this.consecutiveErrors++;
      throw this.formatError(error, 'CREATE_THREAD_FAILED');
    }
  }

  /**
   * Retrieve an existing thread
   * @param {string} threadId - Thread ID
   * @returns {Promise<Object>} Thread object
   */
  async getThread(threadId) {
    try {
      const thread = await this.client.beta.threads.retrieve(threadId);
      return thread;
    } catch (error) {
      logger.error(`❌ Failed to retrieve thread ${threadId}:`, error);
      throw this.formatError(error, 'GET_THREAD_FAILED');
    }
  }

  /**
   * Delete a thread
   * @param {string} threadId - Thread ID
   */
  async deleteThread(threadId) {
    try {
      await this.client.beta.threads.del(threadId);

      // Delete from database
      await db.query(
        'DELETE FROM openai_threads WHERE openai_thread_id = $1',
        [threadId]
      );

      logger.debug(`🗑️  Deleted thread: ${threadId}`);
    } catch (error) {
      logger.error(`❌ Failed to delete thread ${threadId}:`, error);
      // Non-critical error, don't throw
    }
  }

  // ============================================
  // Message Management
  // ============================================

  /**
   * Send a message to a thread
   * @param {string} threadId - Thread ID
   * @param {string} content - Message content
   * @param {Array<string>} fileIds - Optional file IDs (legacy, will be converted to attachments)
   * @param {Object} metadata - Message metadata
   * @returns {Promise<Object>} Message object
   */
  async sendMessage(threadId, content, fileIds = [], metadata = {}) {
    try {
      const messageParams = {
        role: 'user',
        content
      };

      // Convert metadata to strings (OpenAI only accepts strings)
      if (metadata && Object.keys(metadata).length > 0) {
        const stringMetadata = {};
        for (const [key, value] of Object.entries(metadata)) {
          stringMetadata[key] = String(value);
        }
        messageParams.metadata = stringMetadata;
      }

      // Handle file attachments (new API format)
      if (fileIds && fileIds.length > 0) {
        messageParams.attachments = fileIds.map(fileId => ({
          file_id: fileId,
          tools: [{ type: 'file_search' }]
        }));
      }

      const message = await this.client.beta.threads.messages.create(threadId, messageParams);

      // Update message count
      await this.incrementMessageCount(threadId);

      logger.debug(`💬 Sent message to thread ${threadId}`);
      return message;
    } catch (error) {
      logger.error(`❌ Failed to send message to thread ${threadId}:`, error);
      this.consecutiveErrors++;
      throw this.formatError(error, 'SEND_MESSAGE_FAILED');
    }
  }

  /**
   * Get messages from a thread
   * @param {string} threadId - Thread ID
   * @param {number} limit - Number of messages to retrieve
   * @returns {Promise<Array>} Array of messages
   */
  async getMessages(threadId, limit = 100) {
    try {
      const messages = await this.client.beta.threads.messages.list(threadId, {
        order: 'desc',
        limit
      });
      return messages.data;
    } catch (error) {
      logger.error(`❌ Failed to get messages from thread ${threadId}:`, error);
      throw this.formatError(error, 'GET_MESSAGES_FAILED');
    }
  }

  // ============================================
  // Run Management
  // ============================================

  /**
   * Run an assistant on a thread
   * @param {string} threadId - Thread ID
   * @param {string} assistantId - Assistant ID
   * @param {string|null} instructions - Additional instructions (optional)
   * @returns {Promise<Object>} Run object
   */
  async runAssistant(threadId, assistantId, instructions = null) {
    try {
      const runParams = {
        assistant_id: assistantId
      };

      if (instructions) {
        runParams.additional_instructions = instructions;
      }

      const run = await this.client.beta.threads.runs.create(threadId, runParams);

      logger.debug(`🏃 Started run ${run.id} on thread ${threadId}`);
      return run;
    } catch (error) {
      logger.error(`❌ Failed to run assistant ${assistantId}:`, error);
      this.consecutiveErrors++;
      throw this.formatError(error, 'RUN_ASSISTANT_FAILED');
    }
  }

  /**
   * Wait for a run to complete (with function calling support)
   * @param {string} threadId - Thread ID
   * @param {string} runId - Run ID
   * @param {number} timeout - Timeout in milliseconds
   * @returns {Promise<Object>} Completed run object
   */
  async waitForCompletion(threadId, runId, timeout = 60000) {
    const startTime = Date.now();

    while (Date.now() - startTime < timeout) {
      const run = await this.client.beta.threads.runs.retrieve(threadId, runId);

      logger.debug(`🔄 Run ${runId} status: ${run.status}`);

      // Success
      if (run.status === 'completed') {
        this.consecutiveErrors = 0; // Reset error counter on success
        return { success: true, run };
      }

      // Failed
      if (run.status === 'failed') {
        const errorMsg = run.last_error?.message || 'Unknown error';
        logger.error(`❌ Run ${runId} failed: ${errorMsg}`);
        this.consecutiveErrors++;
        throw new Error(`Run failed: ${errorMsg}`);
      }

      // Cancelled or expired
      if (run.status === 'cancelled' || run.status === 'expired') {
        throw new Error(`Run ${run.status}: ${runId}`);
      }

      // Requires action (function calling)
      if (run.status === 'requires_action') {
        logger.debug('📞 Run requires function calling');
        await this.handleFunctionCalling(threadId, runId, run);
        continue; // Continue polling
      }

      // Still running, wait and poll again
      await this.sleep(this.pollingInterval);
    }

    throw new Error(`Run ${runId} timeout after ${timeout}ms`);
  }

  /**
   * Stream assistant run (for real-time responses)
   * @param {string} threadId - Thread ID
   * @param {string} assistantId - Assistant ID
   * @param {string|null} instructions - Additional instructions
   * @returns {Promise<EventStream>} Streaming event source
   */
  async streamAssistantRun(threadId, assistantId, instructions = null) {
    try {
      const runParams = { assistant_id: assistantId };
      if (instructions) runParams.additional_instructions = instructions;

      const stream = await this.client.beta.threads.runs.stream(threadId, runParams);

      return stream;
    } catch (error) {
      logger.error(`❌ Failed to stream assistant run:`, error);
      this.consecutiveErrors++;
      throw this.formatError(error, 'STREAM_RUN_FAILED');
    }
  }

  // ============================================
  // Function Calling
  // ============================================

  /**
   * Handle function calling during run execution
   * @param {string} threadId - Thread ID
   * @param {string} runId - Run ID
   * @param {Object} run - Run object with required_action
   */
  async handleFunctionCalling(threadId, runId, run) {
    const toolCalls = run.required_action.submit_tool_outputs.tool_calls;

    logger.debug(`📞 Handling ${toolCalls.length} function calls`);

    const toolOutputs = await Promise.all(
      toolCalls.map(async (toolCall) => {
        const functionName = toolCall.function.name;
        const functionArgs = JSON.parse(toolCall.function.arguments);

        logger.debug(`  → Calling ${functionName} with args:`, functionArgs);

        let output;

        try {
          // Check cache first
          const cacheKey = this.getFunctionCacheKey(functionName, functionArgs);
          const cachedResult = await this.getCachedFunctionResult(cacheKey);

          if (cachedResult) {
            logger.debug(`  ✅ Cache hit for ${functionName}`);
            output = cachedResult;
          } else {
            // Execute function
            output = await this.executeFunction(functionName, functionArgs);

            // Cache result (5 minutes TTL)
            await this.cacheFunctionResult(cacheKey, functionName, functionArgs, output);
          }
        } catch (error) {
          logger.error(`❌ Function ${functionName} failed:`, error);
          output = {
            error: error.message,
            function: functionName
          };
        }

        return {
          tool_call_id: toolCall.id,
          output: JSON.stringify(output)
        };
      })
    );

    // Submit tool outputs
    await this.client.beta.threads.runs.submitToolOutputs(threadId, runId, {
      tool_outputs: toolOutputs
    });

    logger.debug(`✅ Submitted ${toolOutputs.length} tool outputs`);
  }

  /**
   * Execute a function by name
   * @param {string} functionName - Function name
   * @param {Object} args - Function arguments
   * @returns {Promise<Object>} Function result
   */
  async executeFunction(functionName, args) {
    switch (functionName) {
      case 'get_student_performance':
        return await this.getStudentPerformance(args);

      case 'get_common_mistakes':
        return await this.getCommonMistakes(args);

      default:
        throw new Error(`Unknown function: ${functionName}`);
    }
  }

  /**
   * Get student performance data
   * @param {Object} args - { user_id, subject, topic? }
   * @returns {Promise<Object>} Performance data
   */
  async getStudentPerformance({ user_id, subject, topic = null }) {
    let query = `
      SELECT
        sp.subject,
        sp.total_questions_attempted,
        sp.total_questions_correct,
        sp.accuracy_rate,
        sp.last_activity_date
      FROM subject_progress sp
      WHERE sp.user_id = $1 AND sp.subject = $2
    `;

    const params = [user_id, subject];

    const result = await db.query(query, params);

    if (result.rows.length === 0) {
      return {
        user_id,
        subject,
        topic,
        performance_data: null,
        message: "No performance data found for this subject"
      };
    }

    const data = result.rows[0];

    // Calculate proficiency level
    let proficiency_level;
    const accuracy = parseFloat(data.accuracy_rate || 0);
    if (accuracy >= 90) proficiency_level = "advanced";
    else if (accuracy >= 70) proficiency_level = "intermediate";
    else if (accuracy >= 50) proficiency_level = "beginner";
    else proficiency_level = "novice";

    return {
      user_id,
      subject,
      topic,
      performance_data: {
        questions_attempted: data.total_questions_attempted,
        questions_correct: data.total_questions_correct,
        accuracy: accuracy,
        proficiency_level,
        last_activity: data.last_activity_date
      }
    };
  }

  /**
   * Get common mistakes for a student
   * @param {Object} args - { user_id, subject, topic?, limit }
   * @returns {Promise<Object>} Common mistakes
   */
  async getCommonMistakes({ user_id, subject, topic = null, limit = 5 }) {
    // First, check which columns exist in the questions table
    const columnCheck = await db.query(`
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name = 'questions'
        AND column_name IN ('student_answer', 'is_correct', 'ai_answer')
    `);

    const existingColumns = columnCheck.rows.map(row => row.column_name);
    const hasStudentAnswer = existingColumns.includes('student_answer');
    const hasIsCorrect = existingColumns.includes('is_correct');
    const hasAIAnswer = existingColumns.includes('ai_answer');

    // Build query based on available columns
    let query;
    if (hasStudentAnswer && hasIsCorrect && hasAIAnswer) {
      // Full query with all columns
      query = `
        SELECT
          question_text,
          student_answer,
          ai_answer,
          created_at
        FROM questions
        WHERE user_id = $1
          AND subject = $2
          AND is_correct = false
        ORDER BY created_at DESC
        LIMIT $3
      `;
    } else {
      // Fallback query - get questions without filtering by correctness
      logger.warn('⚠️ Questions table missing columns: student_answer, is_correct, or ai_answer');
      logger.warn('⚠️ Returning all questions for this subject instead of just incorrect ones');
      query = `
        SELECT
          question_text,
          created_at
        FROM questions
        WHERE user_id = $1
          AND subject = $2
        ORDER BY created_at DESC
        LIMIT $3
      `;
    }

    const params = [user_id, subject, limit];

    try {
      const result = await db.query(query, params);

      return {
        user_id,
        subject,
        topic,
        common_mistakes: result.rows.map(row => ({
          question: row.question_text,
          student_answer: hasStudentAnswer ? row.student_answer : 'N/A (data not available)',
          correct_answer: hasAIAnswer ? row.ai_answer : 'N/A (data not available)',
          date: row.created_at,
          _note: !hasStudentAnswer ? 'Database schema missing student_answer column' : undefined
        })),
        total_mistakes_found: result.rows.length,
        _schema_warning: !hasStudentAnswer ? 'Questions table is missing required columns. Please run database migration.' : undefined
      };
    } catch (error) {
      logger.error('❌ Error in getCommonMistakes:', error);
      // Return empty result instead of throwing
      return {
        user_id,
        subject,
        topic,
        common_mistakes: [],
        total_mistakes_found: 0,
        _error: error.message
      };
    }
  }

  // ============================================
  // Helper Functions
  // ============================================

  /**
   * Store thread metadata in database
   */
  async storeThreadMetadata(threadId, metadata) {
    const { user_id, session_id, subject, language, purpose, is_ephemeral } = metadata;

    await db.query(`
      INSERT INTO openai_threads (
        openai_thread_id, user_id, session_id, subject, language, purpose, is_ephemeral, metadata
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ON CONFLICT (openai_thread_id) DO UPDATE SET
        updated_at = NOW()
    `, [
      threadId,
      user_id || null,
      session_id || null,
      subject || null,
      language || 'en',
      purpose || 'general',
      is_ephemeral || false,
      JSON.stringify(metadata)
    ]);
  }

  /**
   * Increment message count for a thread
   */
  async incrementMessageCount(threadId) {
    await db.query(`
      UPDATE openai_threads
      SET message_count = message_count + 1,
          last_message_at = NOW()
      WHERE openai_thread_id = $1
    `, [threadId]);
  }

  /**
   * Get function cache key
   */
  getFunctionCacheKey(functionName, args) {
    const argsString = JSON.stringify(args);
    return crypto.createHash('sha256').update(`${functionName}:${argsString}`).digest('hex');
  }

  /**
   * Get cached function result
   */
  async getCachedFunctionResult(cacheKey) {
    const result = await db.query(`
      SELECT result, hit_count
      FROM function_call_cache
      WHERE cache_key = $1 AND expires_at > NOW()
    `, [cacheKey]);

    if (result.rows.length > 0) {
      // Increment hit count
      await db.query(`
        UPDATE function_call_cache
        SET hit_count = hit_count + 1
        WHERE cache_key = $1
      `, [cacheKey]);

      return result.rows[0].result;
    }

    return null;
  }

  /**
   * Cache function result
   */
  async cacheFunctionResult(cacheKey, functionName, args, result) {
    const expiresAt = new Date(Date.now() + 5 * 60 * 1000); // 5 minutes

    await db.query(`
      INSERT INTO function_call_cache (cache_key, function_name, arguments, result, expires_at)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (cache_key) DO UPDATE SET
        result = $4,
        expires_at = $5,
        hit_count = 0
    `, [cacheKey, functionName, JSON.stringify(args), JSON.stringify(result), expiresAt]);
  }

  /**
   * Sleep helper
   */
  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * Format error for consistent error handling
   */
  formatError(error, code) {
    return {
      error: true,
      code,
      message: error.message,
      details: error.response?.data || null,
      shouldFallback: this.shouldFallback()
    };
  }

  /**
   * Check if should fallback to AI Engine
   */
  shouldFallback() {
    return this.consecutiveErrors >= this.errorThreshold;
  }

  /**
   * Reset error counter
   */
  resetErrorCounter() {
    this.consecutiveErrors = 0;
  }

  /**
   * Get assistant ID by purpose
   */
  async getAssistantId(purpose) {
    // Check cache
    if (this.assistantCache.has(purpose)) {
      return this.assistantCache.get(purpose);
    }

    // Check database
    const result = await db.query(`
      SELECT openai_assistant_id
      FROM assistants_config
      WHERE purpose = $1 AND is_active = true
      LIMIT 1
    `, [purpose]);

    if (result.rows.length === 0) {
      throw new Error(`No active assistant found for purpose: ${purpose}`);
    }

    const assistantId = result.rows[0].openai_assistant_id;
    this.assistantCache.set(purpose, assistantId);

    return assistantId;
  }
}

// Singleton instance
const assistantsService = new AssistantsService();

module.exports = { assistantsService, AssistantsService };
