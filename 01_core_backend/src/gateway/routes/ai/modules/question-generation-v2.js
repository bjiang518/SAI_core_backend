/**
 * Question Generation Routes Module - WITH ASSISTANTS API SUPPORT
 * Handles AI-powered question generation with fallback to AI Engine
 *
 * Features:
 * - OpenAI Assistants API integration (Practice Generator)
 * - Automatic fallback to AI Engine on errors
 * - A/B testing support
 * - Performance monitoring
 * - Cost tracking
 */

const AIServiceClient = require('../../../services/ai-client');
const { assistantsService } = require('../../../../services/openai-assistants-service');
const { getUserId } = require('../utils/auth-helper');
const { db } = require('../../../../utils/railway-database');
const crypto = require('crypto');

// Feature flags
const USE_ASSISTANTS_API = process.env.USE_ASSISTANTS_API === 'true';
const ROLLOUT_PERCENTAGE = parseInt(process.env.ASSISTANTS_ROLLOUT_PERCENTAGE || '0');
const AB_TEST_ENABLED = process.env.AB_TEST_ENABLED === 'true';
const AUTO_FALLBACK = process.env.AUTO_FALLBACK_ON_ERROR !== 'false';

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
            enum: ['en', 'zh-CN', 'zh-TW'],
            default: 'en',
            description: 'Question language'
          },
          force_assistants_api: {
            type: 'boolean',
            description: 'Force use of Assistants API (for testing)'
          },
          force_ai_engine: {
            type: 'boolean',
            description: 'Force use of AI Engine (for testing)'
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

    const { subject, topic, difficulty, count = 5, language = 'en', question_type = 'any', force_assistants_api, force_ai_engine, use_personalization = false, custom_message } = request.body;

    // Determine which implementation to use
    const useAssistantsAPI = shouldUseAssistantsAPI(userId, force_assistants_api, force_ai_engine);
    const experimentGroup = AB_TEST_ENABLED ? (useAssistantsAPI ? 'treatment' : 'control') : null;

    fastify.log.info({
      msg: '🎲 Generating practice questions',
      userId,
      subject,
      topic,
      count,
      questionType: question_type,
      useAssistantsAPI,
      hasCustomMessage: !!custom_message,
      experimentGroup
    });

    let result;
    let usedFallback = false;

    try {
      if (useAssistantsAPI) {
        // Try Assistants API first
        try {
          result = await generateQuestionsWithAssistant(userId, subject, topic, difficulty, count, language, question_type, custom_message);
        } catch (error) {
          fastify.log.error('❌ Assistants API failed, falling back to AI Engine:', error);

          if (AUTO_FALLBACK) {
            usedFallback = true;
            result = await generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, aiClient);
          } else {
            throw error;
          }
        }
      } else {
        // Use AI Engine directly
        result = await generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, aiClient);
      }

      const totalLatency = Date.now() - startTime;

      // Log metrics
      await logMetrics({
        userId,
        assistantType: 'practice_generator',
        endpoint: '/api/ai/generate-questions/practice',
        totalLatency,
        inputTokens: result.tokens?.input || 0,
        outputTokens: result.tokens?.output || 0,
        model: result.model || (useAssistantsAPI ? 'gpt-4o-mini' : 'unknown'),
        wasSuccessful: true,
        useAssistantsAPI: useAssistantsAPI && !usedFallback,
        experimentGroup,
        threadId: result.thread_id,
        runId: result.run_id
      });

      return {
        success: true,
        questions: result.questions,
        metadata: {
          ...result.metadata,
          using_assistants_api: useAssistantsAPI && !usedFallback,
          used_fallback: usedFallback,
          experiment_group: experimentGroup,
          total_latency_ms: totalLatency
        },
        _performance: {
          latency_ms: totalLatency,
          implementation: usedFallback ? 'ai_engine (fallback)' : (useAssistantsAPI ? 'assistants_api' : 'ai_engine')
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
        model: useAssistantsAPI ? 'gpt-4o-mini' : 'unknown',
        wasSuccessful: false,
        errorCode: error.code || 'GENERATION_FAILED',
        errorMessage: error.message,
        useAssistantsAPI,
        experimentGroup
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
  // LEGACY ROUTES (for backward compatibility)
  // ============================================

  /**
   * Legacy: Generate random questions
   */
  fastify.post('/api/ai/generate-questions/random', async (request, reply) => {
    // Map to new unified endpoint
    const { subject, grade_level, difficulty, count, topics } = request.body;

    const mappedBody = {
      subject,
      topic: topics?.[0],
      difficulty: mapDifficultyToNumber(difficulty),
      count
    };

    request.body = mappedBody;
    return await fastify.inject({
      method: 'POST',
      url: '/api/ai/generate-questions/practice',
      headers: request.headers,
      payload: mappedBody
    });
  });

  /**
   * Generate questions based on mistakes (iOS sends local mistake data)
   */
  fastify.post('/api/ai/generate-questions/mistakes', async (request, reply) => {
    const userId = await getUserId(request);
    const { subject, mistakes_data = [], config = {}, user_profile = {} } = request.body;

    if (!mistakes_data || mistakes_data.length === 0) {
      return reply.status(400).send({
        success: false,
        error: 'NO_MISTAKES_PROVIDED',
        message: 'No mistakes data provided. Please select mistakes from your practice history.'
      });
    }

    const questionCount = config.question_count || 5;
    const questionType = config.question_type || 'any';

    // Extract unique tags from all mistakes
    const allTags = mistakes_data.flatMap(m => m.tags || []);
    const uniqueTags = [...new Set(allTags)];

    // Build mistakes context
    const mistakesContext = mistakes_data.map((m, i) => `
Mistake #${i+1}:
- Original Question: ${m.original_question}
- Your Answer: ${m.user_answer}
- Correct Answer: ${m.correct_answer}
- Mistake Type: ${m.mistake_type}
- Topic: ${m.topic}
- Date: ${m.date}
- Tags: ${(m.tags || []).join(', ')}
    `).join('\n');

    const customMessage = `Generate ${questionCount} practice questions for ${subject}.

PREVIOUS_MISTAKES (analyze these and create targeted remedial practice):
${mistakesContext}

Requirements:
- Question Type: ${questionType}
- Count: ${questionCount}
- Language: en
- IMPORTANT: Use EXACTLY these tags: ${JSON.stringify(uniqueTags)}. Do NOT create new tags.

Focus on helping the student overcome these specific error patterns. Generate questions that address the same concepts but with different contexts.`;

    // Forward to unified endpoint
    const response = await fastify.inject({
      method: 'POST',
      url: '/api/ai/generate-questions/practice',
      headers: request.headers,
      payload: {
        subject,
        count: questionCount,
        question_type: questionType,
        force_assistants_api: true,
        custom_message: customMessage
      }
    });

    return JSON.parse(response.body);
  });

  /**
   * Generate questions based on conversations (iOS sends local conversation data)
   */
  fastify.post('/api/ai/generate-questions/conversations', async (request, reply) => {
    const userId = await getUserId(request);
    const { subject, conversation_data = [], config = {}, user_profile = {} } = request.body;

    if (!conversation_data || conversation_data.length === 0) {
      return reply.status(400).send({
        success: false,
        error: 'NO_CONVERSATIONS_PROVIDED',
        message: 'No conversation data provided. Please select conversations from your chat history.'
      });
    }

    const questionCount = config.question_count || 5;
    const questionType = config.question_type || 'any';

    // Build conversations context
    const conversationsContext = conversation_data.map((c, i) => `
Conversation #${i+1} (${c.date}):
- Topics Discussed: ${Array.isArray(c.topics) ? c.topics.join(', ') : c.topics}
- Student Questions: ${c.student_questions}
- Difficulty Level: ${c.difficulty_level}
- Strengths Observed: ${Array.isArray(c.strengths) ? c.strengths.join(', ') : c.strengths}
- Areas for Improvement: ${Array.isArray(c.weaknesses) ? c.weaknesses.join(', ') : c.weaknesses}
- Key Concepts: ${c.key_concepts}
- Engagement Level: ${c.engagement}
    `).join('\n');

    const customMessage = `Generate ${questionCount} practice questions for ${subject}.

PREVIOUS_CONVERSATIONS (build upon these learning interactions):
${conversationsContext}

Requirements:
- Question Type: ${questionType}
- Count: ${questionCount}
- Language: en

Create personalized questions that:
1. Build upon concepts the student has shown interest in
2. Address knowledge gaps identified in conversations
3. Match the student's demonstrated ability level
4. Connect to topics they've previously engaged with successfully

Generate questions that feel like a natural continuation of their learning journey.`;

    // Forward to unified endpoint
    const response = await fastify.inject({
      method: 'POST',
      url: '/api/ai/generate-questions/practice',
      headers: request.headers,
      payload: {
        subject,
        count: questionCount,
        question_type: questionType,
        force_assistants_api: true,
        custom_message: customMessage
      }
    });

    return JSON.parse(response.body);
  });
};

// ============================================
// Implementation Functions
// ============================================

/**
 * Generate questions using OpenAI Assistants API
 */
async function generateQuestionsWithAssistant(userId, subject, topic, difficulty, count, language, questionType = 'any', customMessage = null) {
  const startTime = Date.now();

  // Get Practice Generator assistant ID
  const assistantId = await assistantsService.getAssistantId('practice_generator');

  // Create ephemeral thread (will be deleted after use)
  const thread = await assistantsService.createThread({
    user_id: userId,
    purpose: 'practice_generation',
    subject,
    topic,
    is_ephemeral: true
  });

  try {
    // Build request message
    const requestMessage = customMessage || buildPracticeRequestMessage(subject, topic, difficulty, count, language, questionType);

    // Send message
    await assistantsService.sendMessage(thread.id, requestMessage);

    // Run assistant
    const run = await assistantsService.runAssistant(thread.id, assistantId);

    // Wait for completion
    const result = await assistantsService.waitForCompletion(thread.id, run.id);

    // Get generated questions (JSON response)
    const messages = await assistantsService.getMessages(thread.id, 1);
    const responseText = messages[0].content[0].text.value;

    let parsedResponse;
    try {
      parsedResponse = JSON.parse(responseText);
    } catch (parseError) {
      console.error('❌ Failed to parse assistant response:', responseText);
      throw new Error('Invalid JSON response from assistant');
    }

    // Check for error response
    if (parsedResponse.error) {
      throw new Error(parsedResponse.message || 'Assistant returned error');
    }

    return {
      questions: parsedResponse.questions || [],
      metadata: parsedResponse.metadata || {},
      thread_id: thread.id,
      run_id: run.id,
      model: 'gpt-4o-mini',
      tokens: {
        input: result.run.usage?.prompt_tokens || 0,
        output: result.run.usage?.completion_tokens || 0
      }
    };
  } finally {
    // Cleanup: Delete ephemeral thread
    await assistantsService.deleteThread(thread.id);
  }
}

/**
 * Generate questions using AI Engine (fallback/legacy)
 */
async function generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, aiClient) {
  const response = await aiClient.proxyRequest(
    'POST',
    '/api/v1/generate-questions/random',
    {
      student_id: userId,
      subject,
      topic,
      difficulty: difficulty || 3,
      count,
      language,
      user_profile: {
        subject_proficiency: {}
      },
      config: {
        include_hints: true,
        include_explanations: true,
        question_types: ['multiple_choice', 'short_answer', 'calculation']
      }
    }
  );

  return {
    questions: response.questions || [],
    metadata: {
      total_questions: response.questions?.length || 0,
      language
    },
    model: response.model || 'gpt-4o-mini',
    tokens: {
      input: response.input_tokens || 0,
      output: response.output_tokens || 0
    }
  };
}

/**
 * Build request message for Practice Generator assistant (Mode 1: Random Practice)
 */
function buildPracticeRequestMessage(subject, topic, difficulty, count, language, questionType = 'any') {
  const languageMap = {
    'en': 'English',
    'zh-CN': 'Simplified Chinese',
    'zh-TW': 'Traditional Chinese'
  };

  let message = `Generate ${count} practice questions for ${subject}.\n\n`;

  message += `Requirements:\n`;
  message += `- Subject: ${subject}\n`;
  if (topic) message += `- Topic: ${topic}\n`;
  if (difficulty) message += `- Difficulty: ${difficulty}/5\n`;
  message += `- Question Type: ${questionType}\n`;
  message += `- Language: ${languageMap[language] || 'English'}\n`;
  message += `- Count: ${count}\n\n`;

  message += `Generate diverse, high-quality practice questions that match these requirements. Return the questions in JSON format.`;

  return message;
}

/**
 * Decide whether to use Assistants API
 */
function shouldUseAssistantsAPI(userId, forceAssistants, forceAIEngine) {
  // Explicit override for testing
  if (forceAssistants) return true;
  if (forceAIEngine) return false;

  // Feature flag disabled
  if (!USE_ASSISTANTS_API) return false;

  // Gradual rollout based on user ID hash
  if (ROLLOUT_PERCENTAGE < 100) {
    const hash = crypto.createHash('md5').update(userId).digest('hex');
    const hashInt = parseInt(hash.substring(0, 8), 16);
    const bucket = hashInt % 100;
    return bucket < ROLLOUT_PERCENTAGE;
  }

  return true;
}

/**
 * Map legacy difficulty string to number
 */
function mapDifficultyToNumber(difficulty) {
  const map = {
    'easy': 2,
    'medium': 3,
    'hard': 4
  };
  return map[difficulty] || 3;
}

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
