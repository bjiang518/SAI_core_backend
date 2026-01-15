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

    const { subject, topic, difficulty, count = 5, language = 'en', question_type = 'any', force_assistants_api, force_ai_engine, use_personalization = false, custom_message, mode = 1, mistakes_data = [], conversation_data = [] } = request.body;

    // Validate mode-specific requirements
    if (mode === 2 && (!mistakes_data || mistakes_data.length === 0)) {
      return reply.status(400).send({
        success: false,
        error: 'NO_MISTAKES_PROVIDED',
        message: 'Mode 2 requires mistakes_data array with at least one mistake'
      });
    }

    if (mode === 3 && (!conversation_data || conversation_data.length === 0)) {
      return reply.status(400).send({
        success: false,
        error: 'NO_CONVERSATIONS_PROVIDED',
        message: 'Mode 3 requires conversation_data array with at least one conversation'
      });
    }

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
      difficulty,
      mode,
      useAssistantsAPI,
      hasCustomMessage: !!custom_message,
      experimentGroup
    });

    let result;
    let usedAssistantsAPI = false;

    try {
      // UNIFIED ROUTING: All modes now use AI Engine (fast path only)
      fastify.log.info(`⚡ Using AI Engine for mode ${mode} (Assistants API disabled)...`);

      if (mode === 2) {
        // MODE 2: Mistake-based questions via AI Engine
        result = await generateMistakeQuestionsWithAIEngine(userId, subject, mistakes_data, difficulty, count, language, question_type, aiClient);
      } else if (mode === 3) {
        // MODE 3: Conversation-based questions via AI Engine
        result = await generateConversationQuestionsWithAIEngine(userId, subject, conversation_data, difficulty, count, language, question_type, aiClient);
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
        implementation: usedAssistantsAPI ? 'assistants_api (fallback)' : 'ai_engine (primary)',
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
        useAssistantsAPI: usedAssistantsAPI,
        experimentGroup,
        threadId: result.thread_id,
        runId: result.run_id
      });

      return {
        success: true,
        questions: result.questions,
        metadata: {
          ...result.metadata,
          using_assistants_api: usedAssistantsAPI,
          primary_engine: 'ai_engine',
          experiment_group: experimentGroup,
          total_latency_ms: totalLatency
        },
        _performance: {
          latency_ms: totalLatency,
          implementation: usedAssistantsAPI ? 'assistants_api (fallback)' : 'ai_engine (primary)'
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
    const startTime = Date.now();
    const userId = await getUserId(request);

    if (!userId) {
      return reply.status(401).send({
        success: false,
        error: 'AUTHENTICATION_REQUIRED',
        message: 'Please log in to generate practice questions'
      });
    }

    const { subject, mistakes_data = [], config = {}, user_profile = {} } = request.body;

    fastify.log.info({
      msg: '🔄 Mistakes endpoint called',
      userId,
      subject,
      mistakesCount: mistakes_data.length,
      configReceived: !!config
    });

    if (!mistakes_data || mistakes_data.length === 0) {
      return reply.status(400).send({
        success: false,
        error: 'NO_MISTAKES_PROVIDED',
        message: 'No mistakes data provided. Please select mistakes from your practice history.'
      });
    }

    try {
      const questionCount = config.question_count || 5;
      const questionType = config.question_type || 'any';
      const difficulty = config.difficulty || 3;
      const language = config.language || 'en';

      // Extract unique tags from all mistakes
      const allTags = mistakes_data.flatMap(m => m.tags || []);
      const uniqueTags = [...new Set(allTags)];

      // Build mistakes context
      const mistakesContext = mistakes_data.map((m, i) => `
Mistake #${i+1}:
- Original Question: ${m.original_question || 'N/A'}
- Your Answer: ${m.user_answer || 'N/A'}
- Correct Answer: ${m.correct_answer || 'N/A'}
- Mistake Type: ${m.mistake_type || 'Unknown'}
- Topic: ${m.topic || subject}
- Date: ${m.date || 'Unknown'}
- Tags: ${(m.tags || []).join(', ')}
      `).join('\n');

      // Use AI Engine directly (fast path, no Assistants API)
      fastify.log.info('⚡ Using AI Engine for mistake-based questions (fast path)...');

      const result = await generateMistakeQuestionsWithAIEngine(
        userId,
        subject,
        mistakes_data,
        difficulty,
        questionCount,
        language,
        questionType,
        aiClient
      );

      const totalLatency = Date.now() - startTime;

      // Log metrics (AI Engine, not Assistants API)
      await logMetrics({
        userId,
        assistantType: 'practice_generator',
        endpoint: '/api/ai/generate-questions/mistakes',
        totalLatency,
        inputTokens: result.tokens?.input || 0,
        outputTokens: result.tokens?.output || 0,
        model: result.model || 'gpt-4o-mini',
        wasSuccessful: true,
        useAssistantsAPI: false, // Changed from true
        experimentGroup: 'ai_engine_fast_path'
      });

      return {
        success: true,
        questions: result.questions,
        metadata: {
          ...result.metadata,
          using_assistants_api: false, // Changed from true
          using_ai_engine: true, // Added
          mode: 2,
          total_latency_ms: totalLatency
        }
      };
    } catch (error) {
      fastify.log.error('❌ Mistake-based generation failed:', error);

      return reply.status(500).send({
        success: false,
        error: 'GENERATION_FAILED',
        message: error.message || 'Failed to generate questions from mistakes'
      });
    }
  });

  /**
   * Generate questions based on conversations/archives (iOS sends local data)
   * Supports: conversations, questions (archived), or both combined
   */
  fastify.post('/api/ai/generate-questions/conversations', async (request, reply) => {
    const startTime = Date.now();
    const userId = await getUserId(request);

    if (!userId) {
      return reply.status(401).send({
        success: false,
        error: 'AUTHENTICATION_REQUIRED',
        message: 'Please log in to generate practice questions'
      });
    }

    const { subject, conversation_data = [], question_data = [], config = {}, user_profile = {} } = request.body;

    fastify.log.info({
      msg: '🔄 Archive/Conversation endpoint called',
      userId,
      subject,
      conversationsCount: conversation_data.length,
      questionsCount: question_data.length,
      configReceived: !!config
    });

    // Check if at least one type of data is provided
    const hasConversations = conversation_data && conversation_data.length > 0;
    const hasQuestions = question_data && question_data.length > 0;

    if (!hasConversations && !hasQuestions) {
      return reply.status(400).send({
        success: false,
        error: 'NO_DATA_PROVIDED',
        message: 'No conversation data or question data provided. Please select items from your archives.'
      });
    }

    try {
      const questionCount = config.question_count || 5;
      const questionType = config.question_type || 'any';
      const difficulty = config.difficulty || 3;
      const language = config.language || 'en';

      // Build context from conversations
      let conversationsContext = '';
      if (hasConversations) {
        conversationsContext = conversation_data.map((c, i) => `
Conversation #${i+1} (${c.date || 'Unknown date'}):
- Topics Discussed: ${Array.isArray(c.topics) ? c.topics.join(', ') : (c.topics || 'N/A')}
- Student Questions: ${c.student_questions || 'N/A'}
- Difficulty Level: ${c.difficulty_level || 'intermediate'}
- Strengths Observed: ${Array.isArray(c.strengths) ? c.strengths.join(', ') : (c.strengths || 'N/A')}
- Areas for Improvement: ${Array.isArray(c.weaknesses) ? c.weaknesses.join(', ') : (c.weaknesses || 'N/A')}
- Key Concepts: ${c.key_concepts || 'N/A'}
- Engagement Level: ${c.engagement || 'medium'}
        `).join('\n');
      }

      // Build context from archived questions
      let questionsContext = '';
      if (hasQuestions) {
        questionsContext = question_data.map((q, i) => `
Archived Question #${i+1}:
- Question: ${q.question_text || q.question || 'N/A'}
- Student Answer: ${q.student_answer || q.user_answer || 'N/A'}
- Correct Answer: ${q.correct_answer || q.ai_answer || 'N/A'}
- Was Correct: ${q.is_correct || q.was_correct || 'unknown'}
- Topic: ${q.topic || subject}
- Date: ${q.date || q.created_at || 'Unknown'}
- Tags: ${(q.tags || []).join(', ')}
        `).join('\n');
      }

      // Build combined message
      let contextSection = '';
      if (hasConversations && hasQuestions) {
        contextSection = `
PREVIOUS_CONVERSATIONS (analyze learning patterns):
${conversationsContext}

ARCHIVED_QUESTIONS (review past practice):
${questionsContext}

Analyze BOTH the conversations and questions to understand the student's learning journey.`;
      } else if (hasConversations) {
        contextSection = `
PREVIOUS_CONVERSATIONS (build upon these learning interactions):
${conversationsContext}`;
      } else {
        contextSection = `
ARCHIVED_QUESTIONS (build upon past practice):
${questionsContext}`;
      }

      const customMessage = `Generate ${questionCount} practice questions for ${subject}.

${contextSection}

Requirements:
- Question Type: ${questionType}
- Count: ${questionCount}
- Language: ${language}
- Difficulty: ${difficulty}

Create personalized questions that:
1. Build upon concepts the student has shown interest in
2. Address knowledge gaps identified in their history
3. Match the student's demonstrated ability level
4. Connect to topics they've previously engaged with successfully

Generate questions that feel like a natural continuation of their learning journey.`;

      // Use AI Engine directly (fast path, no Assistants API)
      fastify.log.info('⚡ Using AI Engine for conversation/archive-based questions (fast path)...');

      // Combine conversation_data and question_data for AI Engine
      const combinedData = [
        ...conversation_data.map(c => ({ type: 'conversation', ...c })),
        ...question_data.map(q => ({ type: 'question', ...q }))
      ];

      const result = await generateConversationQuestionsWithAIEngine(
        userId,
        subject,
        combinedData,
        difficulty,
        questionCount,
        language,
        questionType,
        aiClient
      );

      const totalLatency = Date.now() - startTime;

      // Log metrics (AI Engine, not Assistants API)
      await logMetrics({
        userId,
        assistantType: 'practice_generator',
        endpoint: '/api/ai/generate-questions/conversations',
        totalLatency,
        inputTokens: result.tokens?.input || 0,
        outputTokens: result.tokens?.output || 0,
        model: result.model || 'gpt-4o-mini',
        wasSuccessful: true,
        useAssistantsAPI: false, // Changed from true
        experimentGroup: 'ai_engine_fast_path'
      });

      return {
        success: true,
        questions: result.questions,
        metadata: {
          ...result.metadata,
          using_assistants_api: false, // Changed from true
          using_ai_engine: true, // Added
          mode: 3,
          sources: {
            conversations: conversation_data.length,
            questions: question_data.length
          },
          total_latency_ms: totalLatency
        }
      };
    } catch (error) {
      fastify.log.error('❌ Archive-based generation failed:', error);

      return reply.status(500).send({
        success: false,
        error: 'GENERATION_FAILED',
        message: error.message || 'Failed to generate questions from archives'
      });
    }
  });
};

// ============================================
// Implementation Functions
// ============================================

/**
 * Generate questions using OpenAI Assistants API
 */
async function generateQuestionsWithAssistant(userId, subject, topic, difficulty, count, language, questionType = 'any', customMessage = null, mode = 1, mistakesData = [], conversationData = []) {
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
    // Build request message based on mode
    let requestMessage;

    if (customMessage) {
      // Custom message takes precedence (for backward compatibility)
      requestMessage = customMessage;
    } else if (mode === 2) {
      // Mode 2: From Mistakes
      const allTags = mistakesData.flatMap(m => m.tags || []);
      const uniqueTags = [...new Set(allTags)];

      const mistakesContext = mistakesData.map((m, i) => `
Mistake #${i+1}:
- Original Question: ${m.original_question}
- Your Answer: ${m.user_answer}
- Correct Answer: ${m.correct_answer}
- Mistake Type: ${m.mistake_type || 'Unknown'}
- Topic: ${m.topic}
- Date: ${m.date}
- Tags: ${(m.tags || []).join(', ')}
      `).join('\n');

      requestMessage = `Generate ${count} practice questions for ${subject}.

PREVIOUS_MISTAKES (analyze these and create targeted remedial practice):
${mistakesContext}

Requirements:
- Question Type: ${questionType}
- Count: ${count}
- Language: ${language}
- Difficulty: ${difficulty || 'adaptive'}
- IMPORTANT: Use EXACTLY these tags: ${JSON.stringify(uniqueTags)}. Do NOT create new tags.

Focus on helping the student overcome these specific error patterns. Generate questions that address the same concepts but with different contexts.`;
    } else if (mode === 3) {
      // Mode 3: From Conversations
      const conversationsContext = conversationData.map((c, i) => `
Conversation #${i+1} (${c.date}):
- Topics Discussed: ${Array.isArray(c.topics) ? c.topics.join(', ') : c.topics}
- Student Questions: ${c.student_questions}
- Difficulty Level: ${c.difficulty_level}
- Strengths Observed: ${Array.isArray(c.strengths) ? c.strengths.join(', ') : c.strengths}
- Areas for Improvement: ${Array.isArray(c.weaknesses) ? c.weaknesses.join(', ') : c.weaknesses}
- Key Concepts: ${c.key_concepts}
- Engagement Level: ${c.engagement}
      `).join('\n');

      requestMessage = `Generate ${count} practice questions for ${subject}.

PREVIOUS_CONVERSATIONS (build upon these learning interactions):
${conversationsContext}

Requirements:
- Question Type: ${questionType}
- Count: ${count}
- Language: ${language}
- Difficulty: ${difficulty || 'adaptive'}

Create personalized questions that:
1. Build upon concepts the student has shown interest in
2. Address knowledge gaps identified in conversations
3. Match the student's demonstrated ability level
4. Connect to topics they've previously engaged with successfully

Generate questions that feel like a natural continuation of their learning journey.`;
    } else {
      // Mode 1: Random Practice (default)
      requestMessage = buildPracticeRequestMessage(subject, topic, difficulty, count, language, questionType);
    }

    // Send message
    await assistantsService.sendMessage(thread.id, requestMessage);

    // Run assistant
    const run = await assistantsService.runAssistant(thread.id, assistantId);

    // Wait for completion with extended timeout for question generation (120 seconds)
    // Question generation can take longer due to multiple questions being created
    const result = await assistantsService.waitForCompletion(thread.id, run.id, 120000);

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
async function generateQuestionsWithAIEngine(userId, subject, topic, difficulty, count, language, questionType, aiClient) {
  try {
    console.log('🔄 Calling AI Engine /api/v1/generate-questions/random...');
    console.log('📊 Parameters:', { userId, subject, topic, difficulty, count, language, questionType });

    // Map questionType to AI Engine format
    let questionTypes = [];
    if (questionType === 'any' || !questionType) {
      // Mixed types - let AI choose
      questionTypes = ['multiple_choice', 'short_answer', 'calculation', 'fill_blank'];
    } else {
      // Specific type requested
      questionTypes = [questionType];
    }

    const response = await aiClient.proxyRequest(
      'POST',
      '/api/v1/generate-questions/random',
      {
        student_id: userId,
        subject,
        config: {
          topics: topic ? [topic] : [],
          question_count: count || 5,  // ✅ AI Engine expects this in config
          difficulty: difficulty || 'intermediate',
          question_types: questionTypes,  // ✅ Dynamic question types from iOS
          include_hints: true,
          include_explanations: true
        },
        user_profile: {
          grade: 'High School',
          location: 'US',
          subject_proficiency: {}
        }
      }
    );

    // AI Engine wraps response in a 'data' field
    const aiEngineData = response.data || response;

    console.log(`✅ AI Engine returned ${aiEngineData?.questions?.length || 0} questions`);

    // Validate response
    if (!aiEngineData || !aiEngineData.questions) {
      console.error('❌ AI Engine response invalid:', { response, aiEngineData });
      throw new Error('AI Engine returned invalid response: missing questions array');
    }

    return {
      questions: aiEngineData.questions || [],
      metadata: {
        total_questions: aiEngineData.questions?.length || 0,
        language,
        tokens_used: aiEngineData.tokens_used,
        generation_type: aiEngineData.generation_type
      },
      model: aiEngineData.model || 'gpt-4o-mini',
      tokens: {
        input: aiEngineData.input_tokens || 0,
        output: aiEngineData.output_tokens || 0
      }
    };
  } catch (error) {
    console.error('❌ AI Engine request failed:', error);
    throw new Error(`AI Engine fallback failed: ${error.message}`);
  }
}

/**
 * Generate mistake-based questions using AI Engine (MODE 2)
 */
async function generateMistakeQuestionsWithAIEngine(userId, subject, mistakes_data, difficulty, count, language, questionType, aiClient) {
  try {
    console.log('🔄 Calling AI Engine /api/v1/generate-questions/mistakes...');
    console.log('📊 Parameters:', { userId, subject, mistakesCount: mistakes_data?.length, difficulty, count, language, questionType });

    const response = await aiClient.proxyRequest(
      'POST',
      '/api/v1/generate-questions/mistakes',
      {
        subject,
        mistakes_data: mistakes_data || [],
        config: {
          question_count: count || 5,
          difficulty: difficulty || 'intermediate',
          question_type: questionType || 'any'
        },
        user_profile: {
          grade: 'High School',
          location: 'US',
          subject_proficiency: {}
        }
      }
    );

    const aiEngineData = response.data || response;
    console.log(`✅ AI Engine returned ${aiEngineData?.questions?.length || 0} mistake-based questions`);

    if (!aiEngineData || !aiEngineData.questions) {
      console.error('❌ AI Engine response invalid:', { response, aiEngineData });
      throw new Error('AI Engine returned invalid response: missing questions array');
    }

    return {
      questions: aiEngineData.questions || [],
      metadata: {
        total_questions: aiEngineData.questions?.length || 0,
        language,
        tokens_used: aiEngineData.tokens_used,
        generation_type: aiEngineData.generation_type || 'mistake_based',
        mistakes_analyzed: mistakes_data?.length || 0
      },
      model: aiEngineData.model || 'gpt-4o-mini',
      tokens: {
        input: aiEngineData.input_tokens || 0,
        output: aiEngineData.output_tokens || 0
      }
    };
  } catch (error) {
    console.error('❌ AI Engine mistake questions failed:', error);
    throw error;
  }
}

/**
 * Generate conversation-based questions using AI Engine (MODE 3)
 */
async function generateConversationQuestionsWithAIEngine(userId, subject, conversation_data, difficulty, count, language, questionType, aiClient) {
  try {
    console.log('🔄 Calling AI Engine /api/v1/generate-questions/conversations...');
    console.log('📊 Parameters:', { userId, subject, conversationsCount: conversation_data?.length, difficulty, count, language, questionType });

    const response = await aiClient.proxyRequest(
      'POST',
      '/api/v1/generate-questions/conversations',
      {
        subject,
        conversation_data: conversation_data || [],
        config: {
          question_count: count || 5,
          difficulty: difficulty || 'intermediate',
          question_type: questionType || 'any'
        },
        user_profile: {
          grade: 'High School',
          location: 'US',
          subject_proficiency: {}
        }
      }
    );

    const aiEngineData = response.data || response;
    console.log(`✅ AI Engine returned ${aiEngineData?.questions?.length || 0} conversation-based questions`);

    if (!aiEngineData || !aiEngineData.questions) {
      console.error('❌ AI Engine response invalid:', { response, aiEngineData });
      throw new Error('AI Engine returned invalid response: missing questions array');
    }

    return {
      questions: aiEngineData.questions || [],
      metadata: {
        total_questions: aiEngineData.questions?.length || 0,
        language,
        tokens_used: aiEngineData.tokens_used,
        generation_type: aiEngineData.generation_type || 'conversation_based',
        conversations_analyzed: conversation_data?.length || 0
      },
      model: aiEngineData.model || 'gpt-4o-mini',
      tokens: {
        input: aiEngineData.input_tokens || 0,
        output: aiEngineData.output_tokens || 0
      }
    };
  } catch (error) {
    console.error('❌ AI Engine conversation questions failed:', error);
    throw error;
  }
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
