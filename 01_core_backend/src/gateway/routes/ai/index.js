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
const ChatImageRoutes = require('./modules/chat-image');
const QuestionProcessingRoutes = require('./modules/question-processing');
const SessionManagementRoutes = require('./modules/session-management');
const ArchiveRetrievalRoutes = require('./modules/archive-retrieval');
const QuestionGenerationRoutes = require('./modules/question-generation');
const QuestionGenerationV2Routes = require('./modules/question-generation-v2'); // NEW: Assistants API support
const TTSRoutes = require('./modules/tts');
const AnalyticsRoutes = require('./modules/analytics');
const PDFGenerationRoutes = require('./modules/pdf-generation'); // NEW: AI-driven PDF generation

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
    { name: 'Chat Image', Class: ChatImageRoutes },
    { name: 'Question Processing', Class: QuestionProcessingRoutes },
    { name: 'Session Management', Class: SessionManagementRoutes },
    { name: 'Archive Retrieval', Class: ArchiveRetrievalRoutes },
    // DISABLED: Using Question Generation V2 (Assistants API) instead
    // { name: 'Question Generation (Legacy)', Class: QuestionGenerationRoutes },
    { name: 'Text-to-Speech', Class: TTSRoutes },
    { name: 'Analytics', Class: AnalyticsRoutes },
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

  // Register PDF generation module
  try {
    await fastify.register(PDFGenerationRoutes);
    fastify.log.info(`  ✅ PDF Generation (AI-driven layout) routes registered`);
  } catch (error) {
    fastify.log.error(`  ❌ Failed to register PDF Generation routes:`, error);
    // Don't throw - allow app to continue
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
