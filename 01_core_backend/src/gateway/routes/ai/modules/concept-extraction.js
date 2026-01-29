/**
 * Concept Extraction Routes (Stateless Processor)
 *
 * IMPORTANT: This backend module is STATELESS.
 * - iOS calls this with CORRECT questions
 * - Backend forwards to AI Engine for lightweight taxonomy extraction
 * - Backend returns results (subject, base_branch, detailed_branch)
 * - Backend does NOT save to database (iOS handles storage)
 * - Backend does NOT update weakness tracking (iOS handles that)
 *
 * Purpose: Extract curriculum taxonomy for correct answers to enable
 * bidirectional weakness tracking (positive = weakness, negative = mastery)
 */

const fetch = require('node-fetch');
const { getUserId } = require('../utils/auth-helper');

module.exports = async function (fastify, opts) {
  /**
   * POST /api/ai/extract-concepts-batch
   * Stateless concept extraction processor
   *
   * Flow: iOS → Backend → AI Engine → Backend → iOS
   * Backend does NOT save results (iOS saves locally and updates status)
   *
   * Input: { questions: [{ question_text, subject }] }
   * Output: { success, concepts: [{ subject, base_branch, detailed_branch }], count }
   */
  fastify.post('/api/ai/extract-concepts-batch', async (request, reply) => {
    const userId = await getUserId(request);
    const { questions } = request.body;

    // Check authentication
    if (!userId) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    // Validate input
    if (!questions || !Array.isArray(questions) || questions.length === 0) {
      return reply.code(400).send({
        success: false,
        error: 'Questions array required'
      });
    }

    fastify.log.info(`📊 [ConceptExtraction] Request: ${questions.length} questions from user ${userId.substring(0, 8)}...`);

    try {
      // Forward to AI Engine for lightweight taxonomy extraction
      const aiEngineUrl = process.env.AI_ENGINE_URL || 'http://localhost:8000';
      const response = await fetch(`${aiEngineUrl}/api/v1/concept-extraction/extract-batch`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ questions }),
        timeout: 60000  // 60 second timeout
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`AI Engine error: HTTP ${response.status} - ${errorText}`);
      }

      const concepts = await response.json();

      // Validate response format
      if (!Array.isArray(concepts)) {
        throw new Error('AI Engine returned invalid format (expected array)');
      }

      fastify.log.info(`✅ [ConceptExtraction] Complete: ${concepts.length} concepts extracted`);

      // Return immediately to iOS - NO database writes
      return {
        success: true,
        concepts: concepts,
        count: concepts.length
      };

    } catch (error) {
      fastify.log.error(`❌ [ConceptExtraction] Failed: ${error.message}`);

      return reply.code(500).send({
        success: false,
        error: 'Concept extraction failed',
        message: error.message
      });
    }
  });
};
