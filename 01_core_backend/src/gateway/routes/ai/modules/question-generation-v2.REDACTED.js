/**
 * REDACTED — question-generation-v2.js
 *
 * Moved here: 2026-02-24
 * Reason: No iOS callers found for these two legacy routes. iOS exclusively uses
 *         POST /api/ai/generate-questions/practice (unified, modes 1/2/3).
 *
 * To restore: copy the route handler back into question-generation-v2.js inside
 *             the module.exports async function, before the closing `};`.
 */

// ---------------------------------------------------------------------------
// REDACTED ROUTE 1: POST /api/ai/generate-questions/random
// Zero iOS callers. iOS uses /practice mode 1 instead.
// ---------------------------------------------------------------------------
/*
  fastify.post('/api/ai/generate-questions/random', async (request, reply) => {
    const { subject, difficulty, count, topics } = request.body;
    const userId = await getUserId(request);

    if (!userId) {
      return reply.status(401).send({
        success: false,
        error: 'AUTHENTICATION_REQUIRED',
        message: 'Please log in to generate practice questions'
      });
    }

    const startTime = Date.now();
    try {
      const result = await generateQuestionsWithAIEngine(
        userId, subject, topics?.[0],
        mapDifficultyToNumber(difficulty), count || 5, 'en', 'any', aiClient
      );
      const totalLatency = Date.now() - startTime;
      return {
        success: true,
        questions: result.questions,
        metadata: { ...result.metadata, total_latency_ms: totalLatency },
        _performance: { latency_ms: totalLatency, implementation: 'ai_engine' }
      };
    } catch (error) {
      fastify.log.error('❌ Random question generation failed:', error);
      return reply.status(500).send({
        success: false,
        error: 'GENERATION_FAILED',
        message: error.message || 'Failed to generate practice questions'
      });
    }
  });
*/

// ---------------------------------------------------------------------------
// REDACTED ROUTE 2: POST /api/ai/generate-questions/conversations
// Zero iOS callers. iOS uses /practice mode 3 instead.
// ---------------------------------------------------------------------------
/*
  fastify.post('/api/ai/generate-questions/conversations', async (request, reply) => {
    const { subject, conversation_data = [], question_data = [], config = {} } = request.body;
    const userId = await getUserId(request);

    if (!userId) {
      return reply.status(401).send({
        success: false,
        error: 'AUTHENTICATION_REQUIRED',
        message: 'Please log in to generate practice questions'
      });
    }

    if ((!conversation_data || conversation_data.length === 0) && (!question_data || question_data.length === 0)) {
      return reply.status(400).send({
        success: false,
        error: 'NO_ARCHIVE_DATA_PROVIDED',
        message: 'Mode 3 requires at least one item in conversation_data or question_data'
      });
    }

    const count = config.question_count || 5;
    const language = config.language || 'en';
    const questionType = config.question_type || 'any';
    const difficulty = config.difficulty || 3;

    const startTime = Date.now();
    try {
      const result = await generateConversationQuestionsWithAIEngine(userId, subject, conversation_data, question_data, difficulty, count, language, questionType, aiClient);
      const totalLatency = Date.now() - startTime;
      return {
        success: true,
        questions: result.questions,
        metadata: { ...result.metadata, total_latency_ms: totalLatency },
        _performance: { latency_ms: totalLatency, implementation: 'ai_engine' }
      };
    } catch (error) {
      fastify.log.error('❌ Archive question generation failed:', error);
      return reply.status(500).send({
        success: false,
        error: 'GENERATION_FAILED',
        message: error.message || 'Failed to generate practice questions'
      });
    }
  });
*/

// ---------------------------------------------------------------------------
// REDACTED HELPER: mapDifficultyToNumber()
// Was only used by the /random route above. Moved here alongside it.
// ---------------------------------------------------------------------------
/*
function mapDifficultyToNumber(difficulty) {
  const map = {
    'easy': 2,
    'medium': 3,
    'hard': 4
  };
  return map[difficulty] || 3;
}
*/
