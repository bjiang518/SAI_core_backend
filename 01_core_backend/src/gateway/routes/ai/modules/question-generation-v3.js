/**
 * Question Generation V3 — Typed Parallel Requests
 *
 * Registers: POST /api/ai/generate-questions/practice/v2
 *
 * Improvements over /practice:
 * - Splits "any" type into parallel per-type AI engine calls (focused prompts)
 * - Each call targets the new /api/v1/generate-questions unified endpoint
 * - Results are merged and shuffled so types are interleaved
 * - Old /practice endpoint is untouched for backward compatibility
 */

const AIServiceClient = require('../../../services/ai-client');
const { getUserId } = require('../utils/auth-helper');
const { db } = require('../../../../utils/railway-database');

// ---------------------------------------------------------------------------
// Subject split table — determines type distribution for "any" mode
// ---------------------------------------------------------------------------
const SUBJECT_SPLIT_TABLE = {
  // Math-heavy subjects: skip T/F (doesn't suit quantitative topics)
  mathematics: [
    { type: 'multiple_choice', weight: 6 },
    { type: 'short_answer', weight: 4 },
  ],
  math: [
    { type: 'multiple_choice', weight: 6 },
    { type: 'short_answer', weight: 4 },
  ],
  physics: [
    { type: 'multiple_choice', weight: 6 },
    { type: 'short_answer', weight: 4 },
  ],
  chemistry: [
    { type: 'multiple_choice', weight: 6 },
    { type: 'short_answer', weight: 4 },
  ],
  // Default (language arts, humanities, biology, etc.): MC + T/F + short answer
  default: [
    { type: 'multiple_choice', weight: 5 },
    { type: 'true_false', weight: 2 },
    { type: 'short_answer', weight: 3 },
  ],
};

/**
 * Compute how many questions of each type to generate.
 * Returns an array of { type, count } with counts summing to `total`.
 * Minimum total before split: 3. Below this → all multiple_choice.
 */
function computeTypeSplit(subject, total) {
  if (total < 3) {
    return [{ type: 'multiple_choice', count: total }];
  }

  const subjectKey = (subject || '').toLowerCase();
  const distribution = SUBJECT_SPLIT_TABLE[subjectKey] || SUBJECT_SPLIT_TABLE.default;

  const totalWeight = distribution.reduce((s, d) => s + d.weight, 0);

  // Base counts by weight
  let counts = distribution.map(d => ({
    type: d.type,
    count: Math.floor((d.weight / totalWeight) * total),
  }));

  // Distribute remainders round-robin
  let distributed = counts.reduce((s, c) => s + c.count, 0);
  let i = 0;
  while (distributed < total) {
    counts[i % counts.length].count += 1;
    distributed += 1;
    i += 1;
  }

  // Remove types with 0 count
  return counts.filter(c => c.count > 0);
}

/**
 * Shuffle an array in place (Fisher-Yates).
 */
function shuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// ---------------------------------------------------------------------------
// Build context_data for the AI engine call
// ---------------------------------------------------------------------------
function buildContextData(mode, body, grade) {
  if (mode === 2) {
    return {
      grade,
      mistakes_data: body.mistakes_data || [],
    };
  }
  if (mode === 3) {
    return {
      grade,
      conversation_data: body.conversation_data || [],
      question_data: body.question_data || [],
    };
  }
  // mode === 1 (random)
  return {
    grade,
    topics: body.topic ? [body.topic] : [],
    short_term_context: body.short_term_context || [],
  };
}

function modeToContextType(mode) {
  if (mode === 2) return 'mistake';
  if (mode === 3) return 'archive';
  return 'random';
}

// ---------------------------------------------------------------------------
// Call AI engine for a single type
// ---------------------------------------------------------------------------
async function callAIEngineForType(aiClient, subject, questionType, count, contextType, contextData, language, userProfile) {
  const response = await aiClient.proxyRequest(
    'POST',
    '/api/v1/generate-questions',
    {
      subject,
      question_type: questionType,
      count,
      context_type: contextType,
      context_data: contextData,
      user_profile: userProfile,
      language,
    }
  );

  const data = response.data || response;

  if (!data || !data.questions) {
    throw new Error(`AI engine returned no questions for type=${questionType}`);
  }

  // No type name translation needed — iOS and AI engine now use the same names
  return data.questions;
}

// ---------------------------------------------------------------------------
// Metrics helper
// ---------------------------------------------------------------------------
async function logMetricsV3({ userId, endpoint, totalLatency, tokensUsed, wasSuccessful, errorCode, errorMessage }) {
  try {
    await db.query(`
      INSERT INTO assistant_metrics (
        user_id, assistant_type, endpoint, total_latency_ms,
        input_tokens, output_tokens, estimated_cost_usd,
        was_successful, error_code, error_message,
        use_assistants_api, model
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
    `, [
      userId,
      'practice_generator_v3',
      endpoint,
      totalLatency,
      0,
      tokensUsed || 0,
      0,
      wasSuccessful,
      errorCode || null,
      errorMessage || null,
      false,
      'gpt-4o-mini',
    ]);
  } catch {
    // Metrics failure should never break the request
  }
}

// ---------------------------------------------------------------------------
// Route registration
// ---------------------------------------------------------------------------
module.exports = async function (fastify, opts) {
  const aiClient = new AIServiceClient();

  fastify.post('/api/ai/generate-questions/practice/v2', {
    schema: {
      description: 'Generate practice questions — typed parallel requests (v2)',
      tags: ['AI', 'Questions', 'Practice'],
      body: {
        type: 'object',
        required: ['subject'],
        properties: {
          subject: { type: 'string' },
          mode: { type: 'integer', enum: [1, 2, 3], default: 1 },
          count: { type: 'integer', minimum: 1, maximum: 10, default: 5 },
          question_type: { type: 'string', default: 'any' },
          difficulty: { type: 'integer', minimum: 1, maximum: 5 },
          language: { type: 'string', default: 'en' },
          topic: { type: 'string' },
          short_term_context: { type: 'array' },
          mistakes_data: { type: 'array' },
          conversation_data: { type: 'array' },
          question_data: { type: 'array' },
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
        message: 'Please log in to generate practice questions',
      });
    }

    const {
      subject,
      mode = 1,
      count = 5,
      question_type: question_type_raw = 'any',
      difficulty,
      language = 'en',
      topic,
      short_term_context = [],
      mistakes_data = [],
      conversation_data = [],
      question_data = [],
    } = request.body;

    // Normalize legacy type names (none needed currently; kept for future-proofing)
    const TYPE_ALIASES = {};
    const question_type = TYPE_ALIASES[question_type_raw] || question_type_raw;

    // Mode-specific validation
    if (mode === 2 && (!mistakes_data || mistakes_data.length === 0)) {
      return reply.status(400).send({
        success: false,
        error: 'NO_MISTAKES_PROVIDED',
        message: 'Mode 2 requires mistakes_data array with at least one mistake',
      });
    }

    if (mode === 3 && (!conversation_data || conversation_data.length === 0) && (!question_data || question_data.length === 0)) {
      return reply.status(400).send({
        success: false,
        error: 'NO_ARCHIVE_DATA_PROVIDED',
        message: 'Mode 3 requires at least one item in conversation_data or question_data',
      });
    }

    fastify.log.info({
      msg: '🎲 Generating practice questions (v2)',
      userId,
      subject,
      count,
      question_type,
      difficulty,
      mode,
      language,
    });

    const userProfile = { grade: 'High School', location: 'US', subject_proficiency: {} };
    const contextType = modeToContextType(mode);
    const contextData = buildContextData(mode, request.body, userProfile.grade);

    try {
      let allQuestions = [];
      let typesGenerated = {};
      let generationMode = 'single_type';

      const SUPPORTED_TYPES = new Set(['multiple_choice', 'true_false', 'short_answer']);

      if (question_type !== 'any' && SUPPORTED_TYPES.has(question_type)) {
        // === SINGLE TYPE ===
        fastify.log.info(`⚡ Single type: ${question_type} x${count}`);
        allQuestions = await callAIEngineForType(aiClient, subject, question_type, count, contextType, contextData, language, userProfile);
        typesGenerated[question_type] = allQuestions.length;

      } else if (question_type !== 'any' && !SUPPORTED_TYPES.has(question_type)) {
        // Unknown type → fall back to multiple_choice
        fastify.log.info(`⚠️ Unknown type "${question_type}" → fallback to multiple_choice`);
        allQuestions = await callAIEngineForType(aiClient, subject, 'multiple_choice', count, contextType, contextData, language, userProfile);
        typesGenerated['multiple_choice'] = allQuestions.length;

      } else if (question_type === 'any' && count < 3) {
        // Small count → single MC call
        fastify.log.info(`⚡ Small count (${count}) → multiple_choice only`);
        allQuestions = await callAIEngineForType(aiClient, subject, 'multiple_choice', count, contextType, contextData, language, userProfile);
        typesGenerated['multiple_choice'] = allQuestions.length;

      } else if (question_type === 'any' && mode === 2) {
        // Mistake-based with "any" → use MC (mistakes have natural type from context)
        fastify.log.info(`⚡ Mistake-based + "any" → multiple_choice`);
        allQuestions = await callAIEngineForType(aiClient, subject, 'multiple_choice', count, contextType, contextData, language, userProfile);
        typesGenerated['multiple_choice'] = allQuestions.length;

      } else {
        // === MIXED PARALLEL ===
        generationMode = 'mixed_parallel';
        const split = computeTypeSplit(subject, count);

        fastify.log.info({
          msg: `🔀 Mixed parallel generation`,
          split: split.map(s => `${s.type}x${s.count}`).join(', '),
        });

        const results = await Promise.all(
          split.map(s =>
            callAIEngineForType(aiClient, subject, s.type, s.count, contextType, contextData, language, userProfile)
              .then(qs => {
                typesGenerated[s.type] = qs.length;
                return qs;
              })
              .catch(err => {
                fastify.log.error(`❌ Failed to generate ${s.type}: ${err.message}`);
                return []; // don't fail the entire request if one type fails
              })
          )
        );

        allQuestions = results.flat();
        shuffle(allQuestions); // interleave types
      }

      const totalLatency = Date.now() - startTime;

      fastify.log.info({
        msg: '✅ Questions generated (v2)',
        count: allQuestions.length,
        generationMode,
        typesGenerated,
        latency_ms: totalLatency,
      });

      await logMetricsV3({
        userId,
        endpoint: '/api/ai/generate-questions/practice/v2',
        totalLatency,
        tokensUsed: 0,
        wasSuccessful: true,
      });

      return {
        success: true,
        questions: allQuestions,
        metadata: {
          total_questions: allQuestions.length,
          generation_type: generationMode,
          types_generated: typesGenerated,
          total_latency_ms: totalLatency,
          primary_engine: 'ai_engine_v2',
        },
        _performance: {
          latency_ms: totalLatency,
          implementation: 'typed_parallel',
        },
      };

    } catch (error) {
      const totalLatency = Date.now() - startTime;
      fastify.log.error('❌ Question generation v2 failed:', error);

      await logMetricsV3({
        userId,
        endpoint: '/api/ai/generate-questions/practice/v2',
        totalLatency,
        tokensUsed: 0,
        wasSuccessful: false,
        errorCode: error.code || 'GENERATION_FAILED',
        errorMessage: error.message,
      });

      return reply.status(500).send({
        success: false,
        error: 'GENERATION_FAILED',
        message: error.message || 'Failed to generate practice questions',
        details: process.env.NODE_ENV === 'development' ? error.stack : undefined,
      });
    }
  });
};
