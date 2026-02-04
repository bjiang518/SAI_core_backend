/**
 * Interactive Streaming TTS Module
 * Handles dual-stream orchestration: OpenAI (text) + ElevenLabs (audio)
 *
 * Phase 1: Basic route structure with test endpoint
 * Phase 2+: Full dual-stream implementation
 *
 * Created: 2026-02-03
 */

const ElevenLabsWebSocketClient = require('../../../services/ElevenLabsWebSocketClient');
const AuthHelper = require('../utils/auth-helper');

module.exports = async function (fastify, opts) {
  const authHelper = new AuthHelper(fastify);

  /**
   * POST /api/ai/sessions/:sessionId/interactive-stream
   * Starts interactive mode streaming with synchronized text and audio
   *
   * Phase 1: Basic connection test
   * Phase 2+: Full OpenAI + ElevenLabs orchestration
   */
  fastify.post('/api/ai/sessions/:sessionId/interactive-stream', async (request, reply) => {
    try {
      // Authentication
      const userId = authHelper.getUserId(request);
      const { sessionId } = request.params;
      const {
        message,
        voiceId = 'zZLmKvCp1i04X8E0FJ8B', // Default: Max voice
        modelId = 'eleven_turbo_v2_5',
        systemPrompt = 'You are a helpful AI tutor.'
      } = request.body;

      fastify.log.info(`🎙️ Interactive streaming request - Session: ${sessionId}, Voice: ${voiceId}`);

      // Validate inputs
      if (!message || message.trim().length === 0) {
        return reply.status(400).send({
          success: false,
          message: 'Message is required',
          code: 'MISSING_MESSAGE'
        });
      }

      // Set up SSE response headers
      reply.raw.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no'
      });

      // Send connection success event
      reply.raw.write(`data: ${JSON.stringify({
        type: 'connected',
        sessionId: sessionId,
        timestamp: new Date().toISOString()
      })}\n\n`);

      // ═══════════════════════════════════════════════════════════
      // PHASE 1: Basic test - Echo message back
      // ═══════════════════════════════════════════════════════════
      fastify.log.info(`📝 Phase 1 Test: Echoing message back to client`);

      // Simulate streaming text by sending character by character
      const words = message.split(' ');
      let accumulatedText = '';

      for (let i = 0; i < words.length; i++) {
        accumulatedText += (i > 0 ? ' ' : '') + words[i];

        reply.raw.write(`data: ${JSON.stringify({
          type: 'text_delta',
          content: accumulatedText
        })}\n\n`);

        // Small delay to simulate streaming
        await new Promise(resolve => setTimeout(resolve, 50));
      }

      // Send completion event
      reply.raw.write(`data: ${JSON.stringify({
        type: 'complete',
        fullText: accumulatedText
      })}\n\n`);

      fastify.log.info(`✅ Phase 1 Test: Streaming complete`);

      reply.raw.end();

    } catch (error) {
      fastify.log.error('❌ Interactive streaming error:', error);

      // Send error event if headers already sent
      if (reply.raw.headersSent) {
        reply.raw.write(`data: ${JSON.stringify({
          type: 'error',
          error: error.message
        })}\n\n`);
        reply.raw.end();
      } else {
        return reply.status(500).send({
          success: false,
          message: 'Interactive streaming failed',
          code: 'STREAMING_ERROR',
          error: error.message
        });
      }
    }
  });

  /**
   * GET /api/ai/interactive-stream/test
   * Test endpoint to verify ElevenLabs WebSocket connectivity
   */
  fastify.get('/api/ai/interactive-stream/test', async (request, reply) => {
    try {
      const elevenlabsApiKey = process.env.ELEVENLABS_API_KEY;

      if (!elevenlabsApiKey || elevenlabsApiKey === 'your-elevenlabs-api-key-here') {
        return reply.status(503).send({
          success: false,
          message: 'ElevenLabs API key not configured',
          code: 'API_KEY_MISSING'
        });
      }

      fastify.log.info('🧪 Testing ElevenLabs WebSocket connection...');

      // Test connection
      const client = new ElevenLabsWebSocketClient(
        'zZLmKvCp1i04X8E0FJ8B', // Max voice
        'eleven_turbo_v2_5',
        elevenlabsApiKey
      );

      const audioChunks = [];

      client.onAudioChunk = (chunk) => {
        audioChunks.push(chunk);
        fastify.log.info(`🔊 Test: Received audio chunk #${audioChunks.length}`);
      };

      await client.connect();

      // Send test text
      client.sendTextChunk('Hello, this is a test.', true);

      // Wait for audio chunks
      await new Promise(resolve => setTimeout(resolve, 2000));

      // Send end signal
      client.sendEndOfInput();

      // Wait a bit more
      await new Promise(resolve => setTimeout(resolve, 1000));

      client.close();

      const metrics = client.getMetrics();

      return reply.send({
        success: true,
        message: 'ElevenLabs WebSocket test successful',
        audioChunksReceived: audioChunks.length,
        metrics: metrics
      });

    } catch (error) {
      fastify.log.error('❌ ElevenLabs test failed:', error);
      return reply.status(500).send({
        success: false,
        message: 'ElevenLabs WebSocket test failed',
        error: error.message
      });
    }
  });

  fastify.log.info('✅ Interactive streaming routes registered (Phase 1)');
};
