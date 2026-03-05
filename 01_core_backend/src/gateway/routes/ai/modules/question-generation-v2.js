/**
 * Question Generation Routes Module - AI ENGINE ONLY
 * Handles AI-powered question generation using AI Engine (fast path)
 *
 * Features:
 * - Direct AI Engine integration
 * - Support for random, mistake-based, and conversation-based generation
 * - Performance monitoring
 * - Cost tracking
 */

const AIServiceClient = require('../../../services/ai-client');
const { getUserId } = require('../utils/auth-helper');
const { db } = require('../../../../utils/railway-database');
const crypto = require('crypto');

module.exports = async function (fastify, opts) {
  const aiClient = new AIServiceClient();

  // ============================================
  // MAIN ROUTE: Generate Practice Questions
  // ============================================

  /**
   * Generate practice questions - Unified endpoint with smart routing
   */
  fastify.post('/api/ai/generate-questions/practice', {
    schema: {
      description: 'Generate personalized practice questions',
      tags: ['AI', 'Questions', 'Practice'],
      body: {
        type: 'object',
        required: ['subject'],
        properties: {
          subject: {
            type: 'string',
            description: 'Subject name',
            examples: ['Mathematics', 'Physics', 'Chemistry']
          },
          topic: {
            type: 'string',
            description: 'Specific topic (optional)',
            examples: ['Quadratic Equations', 'Newton\'s Laws']
          },
          difficulty: {
            type: 'integer',
            minimum: 1,
            maximum: 5,
            description: 'Difficulty level (1=easiest, 5=hardest). Auto-adjusts if not provided.'
          },
          count: {
            type: 'integer',
            minimum: 1,
            maximum: 10,
            default: 5,
            description: 'Number of questions to generate'
          },
          language: {
            type: 'string',
            default: 'en',
            description: 'Question language (e.g. en, zh-Hans, zh-Hant)'
          },
          mode: {
            type: 'integer',
            enum: [1, 2, 3],
            default: 1,
            description: 'Generation mode: 1=Random Practice, 2=From Mistakes, 3=From Conversations'
          },
          mistakes_data: {
            type: 'array',
            description: 'Array of mistake objects (required for mode 2)',
            items: {
              type: 'object',
              properties: {
                original_question: { type: 'string' },
                user_answer: { type: 'string' },
                correct_answer: { type: 'string' },
                mistake_type: { type: 'string' },
                topic: { type: 'string' },
                date: { type: 'string' },
                tags: { type: 'array', items: { type: 'string' } }
              }
            }
          },
          conversation_data: {
            type: 'array',
            description: 'Array of conversation objects (required for mode 3)',
            items: {
              type: 'object',
              properties: {
                date: { type: 'string' },
                topics: { type: 'array', items: { type: 'string' } },
                student_questions: { type: 'string' },
                difficulty_level: { type: 'string' },
                strengths: { type: 'array', items: { type: 'string' } },
                weaknesses: { type: 'array', items: { type: 'string' } },
                key_concepts: { type: 'string' },
                engagement: { type: 'string' }
              }
            }
          }
        }
      },
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            questions: { type: 'array' },
            metadata: { type: 'object' },
            _performance: { type: 'object' }
          }
        }
      }
    }
  }, async (request, reply) => {
    const startTime = Date.now();
    const userId = await getUserId(request);

    if (!userId) {
      return reply.status(401).send({
        success: false,
        error: 'AUTHENTICATION_REQUIRED',
        message: 'Please log in to generate practice questions'
      });
    }

    const { subject, topic, difficulty, count = 5, language = 'en', question_type = 'any', use_personalization = false, custom_message, mode = 1, mistakes_data = [], conversation_data = [], question_data = [] } = request.body;

    // Validate mode-specific requirements
    if (mode === 2 && (!mistakes_data || mistakes_data.length === 0)) {
      return reply.status(400).send({
        success: false,
        error: 'NO_MISTAKES_PROVIDED',
        message: 'Mode 2 requires mistakes_data array with at least one mistake'
      });
    }

    if (mode === 3 && (!conversation_data || conversation_data.length === 0) && (!question_data || question_data.length === 0)) {
      return reply.status(400).send({
        success: false,
        error: 'NO_ARCHIVE_DATA_PROVIDED',
        message: 'Mode 3 requires at least one item in conversation_data or question_data'
      });
    }

    fastify.log.info({
      msg: '🎲 Generating practice questions',
      userId,
      subject,
      topic,
      count,
      questionType: question_type,
      difficulty,
      mode,
      hasCustomMessage: !!custom_message
    });

    let result;

    try {
      // UNIFIED ROUTING: All modes use AI Engine (fast path only)
      fastify.log.info(`⚡ Using AI Engine for mode ${mode}...`);

      if (mode === 2) {
        // MODE 2: Mistake-based questions via AI Engine
        result = await generateMistakeQuestionsWithAIEngine(userId, subject, mistakes_data, difficulty, count, language, question_type, aiClient);
      } else if (mode === 3) {
        // MODE 3: Archive-based questions (conversations + archived questions) via AI Engine
        result = await generateConversationQuestionsWithAIEngine(userId, subject, conversation_data, question_data, difficulty, count, language, question_type, aiClient);
      } else {
        // MODE 1: Random questions via AI Engine
        result = await generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, question_type, aiClient);
      }

      const totalLatency = Date.now() - startTime;

      // Ensure result has required structure
      if (!result || !result.questions) {
        fastify.log.error('❌ Invalid result structure from generation:', { result });
        throw new Error('Invalid response structure: missing questions array');
      }

      fastify.log.info({
        msg: '✅ Questions generated successfully',
        questionCount: result.questions.length,
        mode,
        implementation: 'ai_engine',
        latency_ms: totalLatency
      });

      // Log metrics
      await logMetrics({
        userId,
        assistantType: 'practice_generator',
        endpoint: '/api/ai/generate-questions/practice',
        totalLatency,
        inputTokens: result.tokens?.input || 0,
        outputTokens: result.tokens?.output || 0,
        model: result.model || 'gpt-4o-mini',
        wasSuccessful: true,
        useAssistantsAPI: false
      });

      return {
        success: true,
        questions: result.questions,
        metadata: {
          ...result.metadata,
          using_assistants_api: false,
          primary_engine: 'ai_engine',
          total_latency_ms: totalLatency
        },
        _performance: {
          latency_ms: totalLatency,
          implementation: 'ai_engine'
        }
      };
    } catch (error) {
      const totalLatency = Date.now() - startTime;

      fastify.log.error('❌ Question generation failed:', error);

      // Log error metrics
      await logMetrics({
        userId,
        assistantType: 'practice_generator',
        endpoint: '/api/ai/generate-questions/practice',
        totalLatency,
        inputTokens: 0,
        outputTokens: 0,
        model: 'gpt-4o-mini',
        wasSuccessful: false,
        errorCode: error.code || 'GENERATION_FAILED',
        errorMessage: error.message,
        useAssistantsAPI: false
      });

      return reply.status(500).send({
        success: false,
        error: 'GENERATION_FAILED',
        message: error.message || 'Failed to generate practice questions',
        details: process.env.NODE_ENV === 'development' ? error.stack : undefined
      });
    }
  });

  // ============================================
  // LEGACY ROUTES (redirect to unified endpoint)
  // ============================================
  // NOTE: /api/ai/generate-questions/random and /api/ai/generate-questions/conversations
  // have been moved to question-generation-v2.REDACTED.js (no iOS callers confirmed).

  /**
   * Legacy: Mistake-based questions → redirect to unified mode 2
   */
  fastify.post('/api/ai/generate-questions/mistakes', async (request, reply) => {
    const { subject, mistakes_data = [], config = {} } = request.body;
    const userId = await getUserId(request);

    if (!userId) {
      return reply.status(401).send({
        success: false,
        error: 'AUTHENTICATION_REQUIRED',
        message: 'Please log in to generate practice questions'
      });
    }

    const count = config.question_count || 5;
    const language = config.language || 'en';
    const questionType = config.question_type || 'any';
    const difficulty = config.difficulty || 3;

    if (!mistakes_data || mistakes_data.length === 0) {
      return reply.status(400).send({
        success: false,
        error: 'NO_MISTAKES_PROVIDED',
        message: 'Mode 2 requires mistakes_data array with at least one mistake'
      });
    }

    const startTime = Date.now();
    try {
      const result = await generateMistakeQuestionsWithAIEngine(userId, subject, mistakes_data, difficulty, count, language, questionType, aiClient);
      const totalLatency = Date.now() - startTime;
      return {
        success: true,
        questions: result.questions,
        metadata: { ...result.metadata, total_latency_ms: totalLatency },
        _performance: { latency_ms: totalLatency, implementation: 'ai_engine' }
      };
    } catch (error) {
      fastify.log.error('❌ Mistake question generation failed:', error);
      return reply.status(500).send({
        success: false,
        error: 'GENERATION_FAILED',
        message: error.message || 'Failed to generate practice questions'
      });
    }
  });

};
// NOTE: /api/ai/generate-questions/conversations moved to question-generation-v2.REDACTED.js

// ============================================
// Implementation Functions
// ============================================

/**
 * Shared helper: call the unified Gemini question generation endpoint
 */
async function callUnifiedEndpoint(subject, questionType, count, contextType, contextData, language, aiClient) {
  const qt = (questionType === 'any' || !questionType) ? 'multiple_choice' : questionType;
  const response = await aiClient.proxyRequest(
    'POST',
    '/api/v1/generate-questions',
    {
      subject,
      question_type: qt,
      count: count || 5,
      context_type: contextType,
      context_data: contextData,
      user_profile: { grade: 'High School' },
      language: language || 'en'
    }
  );
  const data = response.data || response;
  if (!data || !data.questions) {
    throw new Error('AI Engine returned invalid response: missing questions array');
  }
  return data;
}

/**
 * Generate random questions using AI Engine (MODE 1)
 */
async function generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, questionType, aiClient) {
  try {
    console.log('🔄 Calling AI Engine /api/v1/generate-questions (random)...');
    const aiEngineData = await callUnifiedEndpoint(
      subject, questionType, count, 'random',
      { topics: topic ? [topic] : [], grade: 'High School' },
      language, aiClient
    );
    console.log(`✅ AI Engine returned ${aiEngineData.questions.length} questions`);
    return {
      questions: aiEngineData.questions,
      metadata: {
        total_questions: aiEngineData.questions.length,
        language,
        tokens_used: aiEngineData.tokens_used,
        generation_type: aiEngineData.generation_type
      },
      model: 'gemini-3-flash-preview',
      tokens: { input: 0, output: aiEngineData.tokens_used || 0 }
    };
  } catch (error) {
    console.error('❌ AI Engine request failed:', error);
    throw new Error(`AI Engine request failed: ${error.message}`);
  }
}

/**
 * Generate mistake-based questions using AI Engine (MODE 2)
 */
async function generateMistakeQuestionsWithAIEngine(userId, subject, mistakes_data, difficulty, count, language, questionType, aiClient) {
  try {
    console.log('🔄 Calling AI Engine /api/v1/generate-questions (mistake)...');
    const aiEngineData = await callUnifiedEndpoint(
      subject, questionType, count, 'mistake',
      { mistakes_data: mistakes_data || [], grade: 'High School' },
      language, aiClient
    );
    console.log(`✅ AI Engine returned ${aiEngineData.questions.length} mistake-based questions`);
    return {
      questions: aiEngineData.questions,
      metadata: {
        total_questions: aiEngineData.questions.length,
        language,
        tokens_used: aiEngineData.tokens_used,
        generation_type: aiEngineData.generation_type || 'mistake_based',
        mistakes_analyzed: mistakes_data?.length || 0
      },
      model: 'gemini-3-flash-preview',
      tokens: { input: 0, output: aiEngineData.tokens_used || 0 }
    };
  } catch (error) {
    console.error('❌ AI Engine mistake questions failed:', error);
    throw error;
  }
}

/**
 * Generate archive-based questions using AI Engine (MODE 3)
 */
async function generateConversationQuestionsWithAIEngine(userId, subject, conversation_data, question_data, difficulty, count, language, questionType, aiClient) {
  try {
    console.log('🔄 Calling AI Engine /api/v1/generate-questions (archive)...');
    const aiEngineData = await callUnifiedEndpoint(
      subject, questionType, count, 'archive',
      { conversation_data: conversation_data || [], question_data: question_data || [], grade: 'High School' },
      language, aiClient
    );
    console.log(`✅ AI Engine returned ${aiEngineData.questions.length} archive-based questions`);

    if (!aiEngineData || !aiEngineData.questions) {
      console.error('❌ AI Engine response invalid:', { aiEngineData });
      throw new Error('AI Engine returned invalid response: missing questions array');
    }

    return {
      questions: aiEngineData.questions,
      metadata: {
        total_questions: aiEngineData.questions.length,
        language,
        tokens_used: aiEngineData.tokens_used,
        generation_type: aiEngineData.generation_type || 'archive_based',
        conversations_analyzed: conversation_data?.length || 0,
        questions_analyzed: question_data?.length || 0
      },
      model: 'gemini-3-flash-preview',
      tokens: { input: 0, output: aiEngineData.tokens_used || 0 }
    };
  } catch (error) {
    console.error('❌ AI Engine archive questions failed:', error);
    throw error;
  }
}

// mapDifficultyToNumber() moved to question-generation-v2.REDACTED.js
// (was only used by the /random legacy route, which was redacted)

/**
 * Log metrics to database
 */
async function logMetrics(data) {
  try {
    // Calculate cost
    const estimatedCost = calculateCost(
      data.model,
      data.inputTokens,
      data.outputTokens
    );

    await db.query(`
      INSERT INTO assistant_metrics (
        user_id, assistant_type, endpoint, total_latency_ms,
        input_tokens, output_tokens, estimated_cost_usd,
        was_successful, error_code, error_message,
        use_assistants_api, experiment_group,
        thread_id, run_id, model
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
    `, [
      data.userId,
      data.assistantType,
      data.endpoint,
      data.totalLatency,
      data.inputTokens,
      data.outputTokens,
      estimatedCost,
      data.wasSuccessful,
      data.errorCode || null,
      data.errorMessage || null,
      data.useAssistantsAPI,
      data.experimentGroup || null,
      data.threadId || null,
      data.runId || null,
      data.model
    ]);

    // Update daily costs
    await db.query(`
      SELECT update_daily_costs($1, $2, $3, $4)
    `, [
      estimatedCost,
      data.useAssistantsAPI,
      data.inputTokens + data.outputTokens,
      data.wasSuccessful
    ]);
  } catch (error) {
    console.error('Failed to log metrics:', error);
    // Don't throw - metrics logging should not break the request
  }
}

/**
 * Calculate cost based on model and tokens
 */
function calculateCost(model, inputTokens, outputTokens) {
  const pricing = {
    'gpt-4o-mini': { input: 0.000150 / 1000, output: 0.000600 / 1000 },
    'gpt-4o': { input: 0.00250 / 1000, output: 0.01000 / 1000 },
    'gpt-3.5-turbo': { input: 0.000500 / 1000, output: 0.001500 / 1000 }
  };

  const price = pricing[model] || pricing['gpt-4o-mini'];
  return (price.input * inputTokens) + (price.output * outputTokens);
}
