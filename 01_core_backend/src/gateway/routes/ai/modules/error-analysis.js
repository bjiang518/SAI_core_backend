/**
 * Error Analysis Routes (Stateless Processor)
 *
 * IMPORTANT: This backend module is STATELESS.
 * - iOS calls this with questions
 * - Backend forwards to AI Engine
 * - Backend returns results
 * - Backend does NOT save to database (iOS handles storage)
 * - Backend does NOT queue anything (iOS handles queueing)
 */

const { getUserId } = require('../utils/auth-helper');
const tierCheck = require('../../../middleware/tier-check');

module.exports = async function (fastify, opts) {
  /**
   * POST /api/ai/analyze-errors-batch
   * Stateless error analysis processor
   *
   * Flow: iOS → Backend → AI Engine → Backend → iOS
   * Backend does NOT save results (iOS saves locally)
   */
  fastify.post('/api/ai/analyze-errors-batch', {
    preHandler: [tierCheck({ feature: 'error_analysis' })]
  }, async (request, reply) => {
    const userId = await getUserId(request);  // ✅ FIX: Validate authentication
    const { questions } = request.body;

    // Check authentication
    if (!userId) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    if (!questions || questions.length === 0) {
      return reply.code(400).send({ error: 'No questions provided' });
    }

    // ✅ NEW: Count questions with images for logging
    const questionsWithImages = questions.filter(q => q.question_image_base64 || q.questionImageBase64).length;
    const sampleLang = questions[0]?.language || 'en';

    fastify.log.info(`📊 Pass 2 analysis request: ${questions.length} questions from user ${userId.substring(0, 8)}... (lang: ${sampleLang})`);
    if (questionsWithImages > 0) {
      fastify.log.info(`   📸 Including images for ${questionsWithImages}/${questions.length} questions`);
    }

    try {
      // Forward to AI Engine for error analysis (including images if present)
      // Language is already set per-question by iOS — pass through as-is
      const aiEngineUrl = process.env.AI_ENGINE_URL || 'http://localhost:8000';
      const response = await fetch(`${aiEngineUrl}/api/v1/error-analysis/analyze-batch`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ questions })
      });

      if (!response.ok) {
        throw new Error(`AI Engine error: HTTP ${response.status}`);
      }

      const analyses = await response.json();

      fastify.log.info(`✅ Pass 2 complete: ${analyses.length} analyses returned`);

      // Return immediately to iOS - NO database writes
      return {
        success: true,
        analyses: analyses,
        count: analyses.length
      };

    } catch (error) {
      fastify.log.error(`❌ Error analysis failed: ${error.message}`);

      return reply.code(500).send({
        success: false,
        error: 'Error analysis failed',
        message: error.message
      });
    }
  });
};
