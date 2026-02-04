/**
 * Interactive Streaming TTS Module
 * Handles dual-stream orchestration: OpenAI (text) + ElevenLabs (audio)
 *
 * Phase 2: Full dual-stream implementation
 *
 * Created: 2026-02-03
 */

const ElevenLabsWebSocketClient = require('../../../services/ElevenLabsWebSocketClient');
const TextChunker = require('../../../utils/TextChunker');
const AuthHelper = require('../utils/auth-helper');
const SessionHelper = require('../utils/session-helper');

module.exports = async function (fastify, opts) {
  const authHelper = new AuthHelper(fastify);
  const sessionHelper = new SessionHelper(fastify);

  /**
   * POST /api/ai/sessions/:sessionId/interactive-stream
   * Starts interactive mode streaming with synchronized text and audio
   *
   * Flow:
   * 1. Fetch session history (text-only context)
   * 2. Stream from OpenAI with full context
   * 3. Chunk text at sentence boundaries
   * 4. Send chunks to ElevenLabs for TTS
   * 5. Forward both text and audio to iOS client
   */
  fastify.post('/api/ai/sessions/:sessionId/interactive-stream', async (request, reply) => {
    const controller = new AbortController();
    let elevenWs = null;
    const chunker = new TextChunker({
      minChars: 30,
      maxChars: 120
    });

    try {
      // ═══════════════════════════════════════════════════════
      // 1. AUTHENTICATION & VALIDATION
      // ═══════════════════════════════════════════════════════
      const userId = authHelper.getUserId(request);
      const { sessionId } = request.params;
      const {
        message,
        voiceId = 'zZLmKvCp1i04X8E0FJ8B', // Default: Max voice
        modelId = 'eleven_turbo_v2_5',
        systemPrompt = 'You are a helpful AI tutor.',
        deepMode = false
      } = request.body;

      fastify.log.info(`🎙️ Interactive streaming - Session: ${sessionId}, Voice: ${voiceId}, Deep: ${deepMode}`);

      // Validate inputs
      if (!message || message.trim().length === 0) {
        return reply.status(400).send({
          success: false,
          message: 'Message is required',
          code: 'MISSING_MESSAGE'
        });
      }

      // Check ElevenLabs API key
      const elevenlabsApiKey = process.env.ELEVENLABS_API_KEY;
      if (!elevenlabsApiKey || elevenlabsApiKey === 'your-elevenlabs-api-key-here') {
        fastify.log.warn('⚠️ ElevenLabs API key not configured, falling back to text-only streaming');
        // Could fallback to regular streaming here
        return reply.status(503).send({
          success: false,
          message: 'Interactive mode not available - ElevenLabs API key not configured',
          code: 'SERVICE_UNAVAILABLE'
        });
      }

      // ═══════════════════════════════════════════════════════
      // 2. SET UP SSE RESPONSE
      // ═══════════════════════════════════════════════════════
      reply.raw.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no'
      });

      // Send connection event
      reply.raw.write(`data: ${JSON.stringify({
        type: 'connected',
        sessionId: sessionId,
        mode: 'interactive',
        timestamp: new Date().toISOString()
      })}\n\n`);

      // ═══════════════════════════════════════════════════════
      // 3. FETCH SESSION HISTORY (TEXT CONTEXT)
      // ═══════════════════════════════════════════════════════
      const sessionData = await sessionHelper.getSessionWithMessages(sessionId, userId);
      const previousMessages = sessionData?.messages || [];

      fastify.log.info(`📜 Loaded ${previousMessages.length} previous messages for context`);

      // ═══════════════════════════════════════════════════════
      // 4. CONNECT TO ELEVENLABS WEBSOCKET
      // ═══════════════════════════════════════════════════════
      fastify.log.info('🔌 Connecting to ElevenLabs WebSocket...');

      elevenWs = new ElevenLabsWebSocketClient(
        voiceId,
        modelId,
        elevenlabsApiKey
      );

      // Set up audio chunk forwarding
      elevenWs.onAudioChunk = (chunk) => {
        reply.raw.write(`data: ${JSON.stringify({
          type: 'audio_chunk',
          audio: chunk.audio,
          alignment: chunk.alignment,
          isFinal: chunk.isFinal
        })}\n\n`);
      };

      elevenWs.onError = (error) => {
        fastify.log.error('❌ ElevenLabs WebSocket error:', error);
        reply.raw.write(`data: ${JSON.stringify({
          type: 'error',
          error: 'Audio generation error',
          message: error.message
        })}\n\n`);
      };

      try {
        await elevenWs.connect();
        fastify.log.info('✅ ElevenLabs WebSocket connected');
      } catch (wsError) {
        fastify.log.error('❌ Failed to connect to ElevenLabs:', wsError);
        reply.raw.write(`data: ${JSON.stringify({
          type: 'error',
          error: 'Failed to connect to audio service',
          message: wsError.message
        })}\n\n`);
        reply.raw.end();
        return;
      }

      // ═══════════════════════════════════════════════════════
      // 5. BUILD OPENAI CONTEXT (FULL TEXT HISTORY)
      // ═══════════════════════════════════════════════════════
      const openAIMessages = [
        { role: 'system', content: systemPrompt },
        ...previousMessages, // Full conversation history
        { role: 'user', content: message }
      ];

      fastify.log.info(`📤 Sending to OpenAI: ${openAIMessages.length} messages (${message.length} chars new)`);

      // ═══════════════════════════════════════════════════════
      // 6. STREAM FROM OPENAI
      // ═══════════════════════════════════════════════════════
      const AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'http://localhost:8001';
      const streamUrl = `${AI_ENGINE_URL}/api/v1/sessions/${sessionId}/message/stream`;

      const openAIResponse = await fetch(streamUrl, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'Content-Type': 'application/json',
          'X-Service-Auth': process.env.SERVICE_AUTH_SECRET || ''
        },
        body: JSON.stringify({
          message: message,
          system_prompt: systemPrompt,
          deep_mode: deepMode
        })
      });

      if (!openAIResponse.ok) {
        throw new Error(`OpenAI stream failed: ${openAIResponse.status}`);
      }

      let accumulatedText = '';
      let buffer = '';
      let streamStartTime = Date.now();
      let firstTokenTime = null;

      // ═══════════════════════════════════════════════════════
      // 7. DUAL-STREAM PROCESSING
      // ═══════════════════════════════════════════════════════
      const reader = openAIResponse.body;

      for await (const chunk of reader) {
        buffer += chunk.toString();

        // Process complete SSE events (ending with \n\n)
        if (buffer.includes('\n\n')) {
          const lines = buffer.split('\n');

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const jsonStr = line.substring(6);

              try {
                const event = JSON.parse(jsonStr);

                // ─────────────────────────────────────────────
                // CONTENT EVENT: Text delta from OpenAI
                // ─────────────────────────────────────────────
                if (event.type === 'content') {
                  if (!firstTokenTime) {
                    firstTokenTime = Date.now();
                    const latency = firstTokenTime - streamStartTime;
                    fastify.log.info(`⚡ First token: ${latency}ms`);
                  }

                  accumulatedText = event.content;

                  // Forward text to iOS immediately
                  reply.raw.write(`data: ${JSON.stringify({
                    type: 'text_delta',
                    content: accumulatedText
                  })}\n\n`);

                  // Process for TTS chunks
                  const newChunks = chunker.processNewText(accumulatedText);

                  // Send each new chunk to ElevenLabs
                  for (const chunk of newChunks) {
                    fastify.log.info(`📤 TTS chunk ${chunker.totalChunks}: "${chunk.substring(0, 50)}${chunk.length > 50 ? '...' : ''}"`);
                    elevenWs.sendTextChunk(chunk, true);
                  }
                }

                // ─────────────────────────────────────────────
                // END EVENT: OpenAI stream complete
                // ─────────────────────────────────────────────
                else if (event.type === 'end') {
                  fastify.log.info('🏁 OpenAI stream complete, flushing final chunks...');

                  // Flush remaining text
                  const finalChunks = chunker.flush();
                  for (const chunk of finalChunks) {
                    fastify.log.info(`📤 Final TTS chunk: "${chunk.substring(0, 50)}${chunk.length > 50 ? '...' : ''}"`);
                    elevenWs.sendTextChunk(chunk, true);
                  }

                  // Signal end to ElevenLabs
                  elevenWs.sendEndOfInput();

                  // Wait for final audio chunks (2 seconds)
                  await new Promise(resolve => setTimeout(resolve, 2000));

                  // Send completion event
                  const totalTime = Date.now() - streamStartTime;
                  const chunkerStats = chunker.getStats();
                  const wsMetrics = elevenWs.getMetrics();

                  reply.raw.write(`data: ${JSON.stringify({
                    type: 'complete',
                    fullText: accumulatedText,
                    metrics: {
                      totalTime: totalTime,
                      firstTokenLatency: firstTokenTime ? firstTokenTime - streamStartTime : null,
                      textChunks: chunkerStats.totalChunks,
                      audioChunks: wsMetrics.audioChunksReceived,
                      ttfa: wsMetrics.ttfa
                    }
                  })}\n\n`);

                  fastify.log.info(`✅ Interactive streaming complete - ${totalTime}ms, ${chunkerStats.totalChunks} text chunks, ${wsMetrics.audioChunksReceived} audio chunks`);
                }

                // ─────────────────────────────────────────────
                // SUGGESTIONS EVENT: Follow-up suggestions
                // ─────────────────────────────────────────────
                else if (event.type === 'suggestions' && event.suggestions) {
                  reply.raw.write(`data: ${JSON.stringify({
                    type: 'suggestions',
                    suggestions: event.suggestions
                  })}\n\n`);
                }

                // ─────────────────────────────────────────────
                // ERROR EVENT
                // ─────────────────────────────────────────────
                else if (event.type === 'error') {
                  fastify.log.error('❌ OpenAI error:', event.error);
                  reply.raw.write(`data: ${JSON.stringify({
                    type: 'error',
                    error: event.error || 'OpenAI streaming error'
                  })}\n\n`);
                }

              } catch (parseError) {
                // Skip invalid JSON
              }
            }
          }

          buffer = '';
        }
      }

      // ═══════════════════════════════════════════════════════
      // 8. STORE CONVERSATION (TEXT ONLY)
      // ═══════════════════════════════════════════════════════
      if (accumulatedText.length > 0) {
        await sessionHelper.storeConversation(
          sessionId,
          userId,
          message,
          { response: accumulatedText },
          null // No image data
        );
        fastify.log.info('💾 Conversation stored (text only)');
      }

    } catch (error) {
      fastify.log.error('❌ Interactive streaming error:', error);

      if (reply.raw.headersSent) {
        reply.raw.write(`data: ${JSON.stringify({
          type: 'error',
          error: error.message
        })}\n\n`);
      } else {
        return reply.status(500).send({
          success: false,
          message: 'Interactive streaming failed',
          code: 'STREAMING_ERROR',
          error: error.message
        });
      }
    } finally {
      // Clean up
      if (elevenWs) {
        elevenWs.close();
      }
      reply.raw.end();
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

      const client = new ElevenLabsWebSocketClient(
        'zZLmKvCp1i04X8E0FJ8B',
        'eleven_turbo_v2_5',
        elevenlabsApiKey
      );

      const audioChunks = [];

      client.onAudioChunk = (chunk) => {
        audioChunks.push(chunk);
        fastify.log.info(`🔊 Test: Received audio chunk #${audioChunks.length}`);
      };

      await client.connect();

      client.sendTextChunk('Hello, this is a test.', true);

      await new Promise(resolve => setTimeout(resolve, 2000));

      client.sendEndOfInput();

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

  fastify.log.info('✅ Interactive streaming routes registered (Phase 2 - Full Dual-Stream)');
};
