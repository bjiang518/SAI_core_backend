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
const tierCheck = require('../../../middleware/tier-check');
const { db } = require('../../../../utils/railway-database');
const { formatGradeLevel } = require('../utils/prompts');
const questionBank = require('./question-bank-service');

// Maps iOS difficulty int (2/3/4) to string expected by AI engine
const DIFFICULTY_MAP = { 1: 'beginner', 2: 'beginner', 3: 'intermediate', 4: 'advanced', 5: 'advanced' };

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
    focus_notes: body.focus_notes || undefined,
  };
}

function modeToContextType(mode) {
  if (mode === 2) return 'mistake';
  if (mode === 3) return 'archive';
  return 'random';
}

// ---------------------------------------------------------------------------
// Auto-detect subject from free-text (focus_notes / chat content)
// Used when caller passes subject="" or omits it
// ---------------------------------------------------------------------------
function detectSubjectFromText(text) {
  if (!text) return null;
  const t = text.toLowerCase();
  if (/\b(math|algebra|calculus|geometry|trigonometry|equation|derivative|integral|数学)\b/.test(t)) return 'Math';
  if (/\b(physics|mechanics|thermodynamics|optics|电磁|物理|velocity|acceleration|newton)\b/.test(t)) return 'Physics';
  if (/\b(chemistry|chemical|molecule|atom|reaction|acid|base|periodic|化学)\b/.test(t)) return 'Chemistry';
  if (/\b(biology|cell|dna|rna|evolution|ecosystem|photosynthesis|生物)\b/.test(t)) return 'Biology';
  if (/\b(english|grammar|essay|vocabulary|literature|writing|reading|英语)\b/.test(t)) return 'English';
  if (/\b(语文|作文|古诗|文言文|阅读理解|chinese language)\b/.test(t)) return 'Chinese';
  if (/\b(history|历史|dynasty|revolution|war|empire|civilization)\b/.test(t)) return 'History';
  if (/\b(geography|地理|climate|continent|latitude|longitude|ecosystem)\b/.test(t)) return 'Geography';
  if (/\b(computer|programming|algorithm|code|software|data structure|计算机)\b/.test(t)) return 'Computer Science';
  if (/\b(economics|supply|demand|inflation|gdp|market|经济)\b/.test(t)) return 'Economics';
  if (/\b(psychology|behavior|cognition|emotion|mental|心理)\b/.test(t)) return 'Psychology';
  if (/\b(science|experiment|hypothesis|scientific)\b/.test(t)) return 'Science';
  return null;
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

  return data.questions;
}

/**
 * Fire `count` parallel single-question requests for one type.
 * Each request lands on a separate Gunicorn worker for true parallelism.
 * A per-question timeout prevents one slow/failing request from blocking
 * the entire Promise.all.
 */
async function callAIEngineParallel(aiClient, subject, questionType, count, contextType, contextData, language, userProfile) {
  const PER_QUESTION_TIMEOUT_MS = 20000;
  const STAGGER_MS = 250; // spread requests to avoid Gemini rate limiting

  const tasks = Array.from({ length: count }, (_, i) =>
    new Promise(resolve => setTimeout(resolve, i * STAGGER_MS))
      .then(() => Promise.race([
        callAIEngineForType(aiClient, subject, questionType, 1, contextType, contextData, language, userProfile),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error('per-question timeout')), PER_QUESTION_TIMEOUT_MS)
        ),
      ]))
      .catch(() => [])
  );
  const results = await Promise.all(tasks);
  return results.flat();
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

  // Pre-warm the most-requested subject caches in the background so the first
  // real user doesn't wait 40–50s for the cold-load.
  const WARM_SUBJECTS = ['Math', 'Biology', 'Chemistry', 'Physics', 'English'];
  setImmediate(() => {
    (async () => {
      for (const subj of WARM_SUBJECTS) {
        try {
          await questionBank.warmCache(subj);
        } catch (err) {
          fastify.log.warn({ msg: `⚠️ Cache warm-up failed for "${subj}"`, err: err.message });
        }
      }
      fastify.log.info({ msg: '✅ Question bank cache pre-warmed', subjects: WARM_SUBJECTS });
    })();
  });

  fastify.post('/api/ai/generate-questions/practice/v2', {
    schema: {
      description: 'Generate practice questions — typed parallel requests (v2)',
      tags: ['AI', 'Questions', 'Practice'],
      body: {
        type: 'object',
        properties: {
          subject: { type: 'string', default: '' },
          mode: { type: 'integer', enum: [1, 2, 3, 4], default: 1 },
          count: { type: 'integer', minimum: 1, maximum: 10, default: 5 },
          question_type: { type: 'string', default: 'any' },
          difficulty: { type: 'integer', minimum: 1, maximum: 5 },
          language: { type: 'string', default: 'en' },
          topic: { type: 'string' },
          focus_notes: { type: 'string' },
          short_term_context: { type: 'array' },
          mistakes_data: { type: 'array' },
          conversation_data: { type: 'array' },
          question_data: { type: 'array' },
          bank_source: { type: 'string', enum: ['amc8', 'amc10', 'amc12', 'aime', 'sat', 'mmlu', 'arc', 'openbookqa', 'gsm8k', 'agieval', 'scienceqa', 'mathvista', 'kangaroo'] },
        }
      }
    },
    preHandler: [tierCheck({ feature: 'questions', getCount: req => req.body.count ?? 1 })]
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
      subject: subjectRaw = '',
      mode = 1,
      count = 5,
      question_type: question_type_raw = 'any',
      difficulty,
      language = 'en',
      topic,
      focus_notes,
      short_term_context = [],
      mistakes_data = [],
      conversation_data = [],
      question_data = [],
      bank_source,
      grade_level,
    } = request.body;

    // Auto-detect subject from focus_notes when caller omits it or sends "General"
    const isAutoSubject = !subjectRaw || subjectRaw.toLowerCase() === 'general';
    const subject = isAutoSubject
      ? (detectSubjectFromText(focus_notes || topic || '') || 'General')
      : subjectRaw;

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

    // Use iOS-supplied grade_level first (local, no DB lag), fall back to DB value
    const rawProfile = await db.getEnhancedUserProfile(userId).catch(() => null);
    const gradeLabel = (grade_level ? formatGradeLevel(grade_level) : null)
      || formatGradeLevel(rawProfile?.grade_level)
      || null;
    const difficultyStr = DIFFICULTY_MAP[difficulty] || 'intermediate';

    const userProfile = { grade: gradeLabel, location: 'US', subject_proficiency: {} };
    const contextType = modeToContextType(mode);
    const contextData = { ...buildContextData(mode, request.body, gradeLabel), difficulty: difficultyStr };

    try {
      let allQuestions = [];
      let typesGenerated = {};
      let generationMode = 'single_type';

      const SUPPORTED_TYPES = new Set(['multiple_choice', 'true_false', 'short_answer']);

      // === MODE 4: Question Bank (curated AMC/AIME/SAT) ===
      if (mode === 4) {
        fastify.log.info({ msg: '📚 Question bank retrieval (mode 4)', userId, subject, count, bank_source });

        const weaknessKeys = (short_term_context || [])
          .map(c => c.weakness_key || c.weaknessKey)
          .filter(Boolean);

        const bankResult = await questionBank.retrieveQuestions(userId, {
          topic:            topic || subject,
          difficulty:       difficulty || 3,
          questionType:     question_type,
          count,
          mistakesData:     mistakes_data,
          conversationData: conversation_data,
          weaknessKeys,
          source:           bank_source || null,
          gradeLevel:       gradeLabel,   // ← grade-aware difficulty capping
        });

        allQuestions = bankResult.questions;
        generationMode = 'question_bank';
        typesGenerated = allQuestions.reduce((acc, q) => {
          acc[q.question_type] = (acc[q.question_type] || 0) + 1;
          return acc;
        }, {});

        const totalLatency = Date.now() - startTime;

        fastify.log.info({ msg: '✅ Bank questions retrieved', count: allQuestions.length, latency_ms: totalLatency });

        await logMetricsV3({ userId, endpoint: '/api/ai/generate-questions/practice/v2?mode=4', totalLatency, wasSuccessful: true });

        return {
          success: true,
          questions: allQuestions,
          metadata: {
            total_questions:  allQuestions.length,
            generation_type:  generationMode,
            types_generated:  typesGenerated,
            total_latency_ms: totalLatency,
            primary_engine:   'question_bank',
            bank_source:      bankResult.source,
          },
          _performance: {
            latency_ms:     totalLatency,
            implementation: 'vector_retrieval',
          },
        };
      }

      if (question_type !== 'any' && SUPPORTED_TYPES.has(question_type)) {
        // === SINGLE TYPE — parallel per question ===
        fastify.log.info(`⚡ Single type: ${question_type} x${count} (parallel)`);
        allQuestions = await callAIEngineParallel(aiClient, subject, question_type, count, contextType, contextData, language, userProfile);
        typesGenerated[question_type] = allQuestions.length;

      } else if (question_type !== 'any' && !SUPPORTED_TYPES.has(question_type)) {
        // Unknown type → fall back to multiple_choice
        fastify.log.info(`⚠️ Unknown type "${question_type}" → fallback to multiple_choice`);
        allQuestions = await callAIEngineParallel(aiClient, subject, 'multiple_choice', count, contextType, contextData, language, userProfile);
        typesGenerated['multiple_choice'] = allQuestions.length;

      } else if (question_type === 'any' && count < 3) {
        // Small count → single MC call (not worth splitting)
        fastify.log.info(`⚡ Small count (${count}) → multiple_choice only`);
        allQuestions = await callAIEngineForType(aiClient, subject, 'multiple_choice', count, contextType, contextData, language, userProfile);
        typesGenerated['multiple_choice'] = allQuestions.length;

      } else if (question_type === 'any' && mode === 2) {
        // Mistake-based with "any" → MC only, parallel
        fastify.log.info(`⚡ Mistake-based + "any" → multiple_choice (parallel)`);
        allQuestions = await callAIEngineParallel(aiClient, subject, 'multiple_choice', count, contextType, contextData, language, userProfile);
        typesGenerated['multiple_choice'] = allQuestions.length;

      } else {
        // === MIXED PARALLEL — each question is its own request ===
        generationMode = 'mixed_parallel';
        const split = computeTypeSplit(subject, count);

        fastify.log.info({
          msg: `🔀 Mixed parallel generation`,
          split: split.map(s => `${s.type}x${s.count}`).join(', '),
        });

        const results = await Promise.all(
          split.map(s =>
            callAIEngineParallel(aiClient, subject, s.type, s.count, contextType, contextData, language, userProfile)
              .then(qs => {
                typesGenerated[s.type] = qs.length;
                return qs;
              })
              .catch(err => {
                fastify.log.error(`❌ Failed to generate ${s.type}: ${err.message}`);
                return [];
              })
          )
        );

        allQuestions = results.flat();
        shuffle(allQuestions);

        if (allQuestions.length === 0) {
          throw new Error('All question type calls failed — AI engine returned no questions');
        }
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
        detectedSubject: subject,  // always returned so iOS can label the session correctly
        metadata: {
          total_questions: allQuestions.length,
          generation_type: generationMode,
          types_generated: typesGenerated,
          total_latency_ms: totalLatency,
          primary_engine: 'ai_engine_v2',
          auto_detected_subject: isAutoSubject,
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

  // ---------------------------------------------------------------------------
  // GET /api/ai/question-bank/figure/:questionId
  // Serves the stored base64 figure as raw image bytes.
  // Aggressively cached — figures never change once scraped.
  // ---------------------------------------------------------------------------
  fastify.get('/api/ai/question-bank/figure/:questionId', async (request, reply) => {
    const { questionId } = request.params;
    const { rows } = await db.query(
      `SELECT figure_data, figure_mime FROM question_bank WHERE id = $1`,
      [questionId]
    );

    if (!rows.length || !rows[0].figure_data) {
      return reply.status(404).send({ success: false, error: 'FIGURE_NOT_FOUND' });
    }

    const { figure_data, figure_mime } = rows[0];
    const imageBuffer = Buffer.from(figure_data, 'base64');

    reply
      .header('Content-Type', figure_mime || 'image/png')
      .header('Cache-Control', 'public, max-age=31536000, immutable')
      .header('Content-Length', imageBuffer.length)
      .send(imageBuffer);
  });

  // ---------------------------------------------------------------------------
  // POST /api/ai/question-bank/record-result
  // Called by iOS after a bank question is graded, to mark it seen and update
  // the times_used counter.
  // ---------------------------------------------------------------------------
  fastify.post('/api/ai/question-bank/record-result', {
    schema: {
      body: {
        type: 'object',
        required: ['question_id', 'was_correct'],
        properties: {
          question_id: { type: 'string' },
          was_correct: { type: 'boolean' },
        },
      },
    },
  }, async (request, reply) => {
    const userId = await getUserId(request);
    if (!userId) return reply.status(401).send({ success: false, error: 'AUTHENTICATION_REQUIRED' });

    const { question_id, was_correct } = request.body;
    await questionBank.recordGradingResult(userId, question_id, was_correct);
    return { success: true };
  });

  // ---------------------------------------------------------------------------
  // POST /api/ai/question-bank/invalidate-cache
  // Called after import scripts to clear stale in-memory embedding cache.
  // Requires X-Admin-Secret header matching ADMIN_SECRET env var.
  // ---------------------------------------------------------------------------
  fastify.post('/api/ai/question-bank/invalidate-cache', async (request, reply) => {
    const secret = request.headers['x-admin-secret'];
    if (!secret || secret !== process.env.ADMIN_SECRET) {
      return reply.status(403).send({ success: false, error: 'FORBIDDEN' });
    }
    const { subject } = request.body || {};
    questionBank.invalidateCache(subject || undefined);
    fastify.log.info({ msg: '🗑 Question bank cache invalidated', subject: subject || 'all' });
    return { success: true, invalidated: subject || 'all' };
  });
};

// Export pure functions for unit testing
module.exports.computeTypeSplit = computeTypeSplit;
module.exports.buildContextData = buildContextData;
module.exports.modeToContextType = modeToContextType;
module.exports.shuffle = shuffle;
module.exports.SUBJECT_SPLIT_TABLE = SUBJECT_SPLIT_TABLE;
