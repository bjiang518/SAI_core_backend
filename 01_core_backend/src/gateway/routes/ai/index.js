/**
 * AI Routes Module Index
 * Registers all AI-related routes in a modular way
 *
 * This file replaces the monolithic ai-proxy.js (3,393 lines)
 * with focused, maintainable modules.
 *
 * Usage in gateway/index.js:
 *   const aiRoutes = require('./routes/ai');
 *   await fastify.register(aiRoutes);
 */

const HomeworkProcessingRoutes = require('./modules/homework-processing');
// DISABLED: chat-image endpoints (/api/ai/chat-image, /api/ai/chat-image-stream)
// Not called by iOS — QuestionView.swift (only caller) is orphaned dead code.
// Reactivate by uncommenting this import and the classModules entry below.
// const ChatImageRoutes = require('./modules/chat-image');
const QuestionProcessingRoutes = require('./modules/question-processing');
const SessionManagementRoutes = require('./modules/session-management');
const ArchiveRetrievalRoutes = require('./modules/archive-retrieval');
// REMOVED: Legacy question generation (moved to question-generation.js.legacy)
// const QuestionGenerationRoutes = require('./modules/question-generation');
const QuestionGenerationV2Routes = require('./modules/question-generation-v2'); // NEW: Assistants API support
const QuestionGenerationV3Routes = require('./modules/question-generation-v3'); // NEW: Typed parallel requests
const TTSRoutes = require('./modules/tts');
const AnalyticsRoutes = require('./modules/analytics');
const DiagramGenerationRoutes = require('./modules/diagram-generation'); // NEW: AI diagram generation
const VideoSearchRoutes = require('./modules/video-search'); // NEW: Educational video search
const ErrorAnalysisRoutes = require('./modules/error-analysis'); // NEW: Pass 2 error analysis
const WeaknessDescriptionRoutes = require('./modules/weakness-description'); // NEW: Weakness description generation
const ConceptExtractionRoutes = require('./modules/concept-extraction'); // NEW: Bidirectional status tracking
const InteractiveStreamingRoutes = require('./modules/interactive-streaming'); // NEW: Interactive Mode (Phase 1)
const GeminiLiveRoutes = require('./modules/gemini-live-v2'); // NEW: Gemini Live API voice chat (v2 - official protocol)

/**
 * Register all AI routes
 * @param {FastifyInstance} fastify - Fastify instance
 * @param {Object} opts - Options
 */
async function aiRoutes(fastify, opts) {
  fastify.log.info('🤖 Registering AI routes (modular architecture)...');

  // Initialize and register all route modules (class-based)
  const classModules = [
    { name: 'Homework Processing', Class: HomeworkProcessingRoutes },
    // DISABLED: { name: 'Chat Image', Class: ChatImageRoutes },  // Dead — reactivate with import above if needed
    { name: 'Question Processing', Class: QuestionProcessingRoutes },
    { name: 'Session Management', Class: SessionManagementRoutes },
    { name: 'Archive Retrieval', Class: ArchiveRetrievalRoutes },
    // REMOVED: Legacy question generation replaced by V2 (Assistants API)
    // iOS now uses /api/ai/generate-questions/* endpoints from question-generation-v2.js
    { name: 'Text-to-Speech', Class: TTSRoutes },
    { name: 'Analytics', Class: AnalyticsRoutes },
    { name: 'Diagram Generation', Class: DiagramGenerationRoutes }, // NEW: AI diagram generation
    { name: 'Video Search', Class: VideoSearchRoutes }, // NEW: Educational video search
  ];

  for (const module of classModules) {
    try {
      const routeModule = new module.Class(fastify);
      routeModule.registerRoutes();
      fastify.log.info(`  ✅ ${module.name} routes registered`);
    } catch (error) {
      fastify.log.error(`  ❌ Failed to register ${module.name} routes:`, error);
      throw error;
    }
  }

  // Register plugin-based modules (NEW: Assistants API)
  try {
    await fastify.register(QuestionGenerationV2Routes);
    fastify.log.info(`  ✅ Question Generation V2 (Assistants API) routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register Question Generation V2 routes:`, error);
    // Don't throw - allow app to continue with legacy routes
  }

  // Register v3 routes (NEW: Typed parallel requests)
  try {
    await fastify.register(QuestionGenerationV3Routes);
    fastify.log.info(`  ✅ Question Generation V3 (Typed Parallel) routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register Question Generation V3 routes:`, error);
  }

  // Register error analysis routes (NEW: Two-Pass Grading)
  try {
    await fastify.register(ErrorAnalysisRoutes);
    fastify.log.info(`  ✅ Error Analysis (Pass 2) routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register Error Analysis routes:`, error);
  }

  // Register weakness description routes (NEW: Short-Term Status Architecture)
  try {
    await fastify.register(WeaknessDescriptionRoutes);
    fastify.log.info(`  ✅ Weakness Description Generation routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register Weakness Description routes:`, error);
  }

  // Register concept extraction routes (NEW: Bidirectional Status Tracking)
  try {
    await fastify.register(ConceptExtractionRoutes);
    fastify.log.info(`  ✅ Concept Extraction (Bidirectional Tracking) routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register Concept Extraction routes:`, error);
  }

  // Register interactive streaming routes (NEW: Interactive Mode - Phase 1)
  try {
    await fastify.register(InteractiveStreamingRoutes);
    fastify.log.info(`  ✅ Interactive Streaming (Phase 1) routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register Interactive Streaming routes:`, error);
  }

  // Register Gemini Live routes (NEW: Real-time voice chat)
  try {
    await fastify.register(GeminiLiveRoutes);
    fastify.log.info(`  ✅ Gemini Live API (Voice Chat) routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register Gemini Live routes:`, error);
  }

  fastify.log.info('✅ All AI routes registered successfully');
}

module.exports = aiRoutes;

/**
 * Migration Notes:
 *
 * ✅ ALL MODULES CREATED AND READY TO USE!
 *
 * To migrate from old ai-proxy.js:
 *
 * 1. In gateway/index.js, replace:
 *       const aiProxy = require('./routes/ai-proxy');
 *       await fastify.register(aiProxy);
 *
 *    With:
 *       const aiRoutes = require('./routes/ai');
 *       await fastify.register(aiRoutes);
 *
 * 2. Test all endpoints to ensure they work correctly
 *
 * 3. Keep old ai-proxy.js as backup until fully tested
 *
 * 4. Create backup copy:
 *       cp src/gateway/routes/ai-proxy.js src/gateway/routes/ai-proxy.js.backup
 *
 * 5. After successful testing, remove old file:
 *       git rm src/gateway/routes/ai-proxy.js
 */
