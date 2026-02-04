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
      fastify.log.info('🔐 [STEP 1] Starting authentication...');
      const userId = await authHelper.requireAuth(request, reply);
      if (!userId) {
        fastify.log.error('❌ [STEP 1] Authentication failed');
        return; // Already sent 401 response
      }
      fastify.log.info(`✅ [STEP 1] Authentication successful - User: ${userId.substring(0, 8)}...`);

      const { sessionId } = request.params;
      const {
        message,
        voiceId = 'zZLmKvCp1i04X8E0FJ8B', // Default: Max voice
        modelId = 'eleven_turbo_v2_5',
        systemPrompt = 'You are a helpful AI tutor.',
        deepMode = false
      } = request.body;

      fastify.log.info(`🎙️ [REQUEST] Interactive streaming request:
        - Session: ${sessionId}
        - User: ${userId.substring(0, 8)}...
        - Voice: ${voiceId}
        - Model: ${modelId}
        - Message: "${message.substring(0, 100)}${message.length > 100 ? '...' : ''}"
        - Message length: ${message.length} chars
        - Deep mode: ${deepMode}`);

      // Validate inputs
      fastify.log.info('📋 [STEP 2] Validating input message...');
      if (!message || message.trim().length === 0) {
        fastify.log.error('❌ [STEP 2] Validation failed - empty message');
        return reply.status(400).send({
          success: false,
          message: 'Message is required',
          code: 'MISSING_MESSAGE'
        });
      }
      fastify.log.info('✅ [STEP 2] Input validation passed');

      // Check ElevenLabs API key
      fastify.log.info('🔑 [STEP 3] Checking ElevenLabs API key...');
      const elevenlabsApiKey = process.env.ELEVENLABS_API_KEY;
      if (!elevenlabsApiKey || elevenlabsApiKey === 'your-elevenlabs-api-key-here') {
        fastify.log.error('❌ [STEP 3] ElevenLabs API key not configured');
        fastify.log.warn('⚠️ ElevenLabs API key not configured, falling back to text-only streaming');
        // Could fallback to regular streaming here
        return reply.status(503).send({
          success: false,
          message: 'Interactive mode not available - ElevenLabs API key not configured',
          code: 'SERVICE_UNAVAILABLE'
        });
      }
      fastify.log.info(`✅ [STEP 3] ElevenLabs API key found: ${elevenlabsApiKey.substring(0, 8)}...`);

      // ═══════════════════════════════════════════════════════
      // 2. SET UP SSE RESPONSE
      // ═══════════════════════════════════════════════════════
      fastify.log.info('📡 [STEP 4] Setting up SSE response stream...');
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
      fastify.log.info('✅ [STEP 4] SSE stream established and connected event sent');

      // ═══════════════════════════════════════════════════════
      // 3. FETCH SESSION HISTORY (TEXT CONTEXT)
      // ═══════════════════════════════════════════════════════
      fastify.log.info(`💾 [STEP 5] Fetching conversation history from database...`);
      const { db } = require('../../../../utils/railway-database');

      let conversationRows;
      try {
        conversationRows = await db.getConversationHistory(sessionId, 50);
        fastify.log.info(`✅ [STEP 5] Database query successful - ${conversationRows.length} messages found`);
      } catch (dbError) {
        fastify.log.error(`❌ [STEP 5] Database query failed:`, dbError);
        throw new Error(`Failed to load conversation history: ${dbError.message}`);
      }

      // Transform database rows to OpenAI format: {role: 'user'|'assistant', content: 'text'}
      const previousMessages = conversationRows.map(row => ({
        role: row.message_type, // 'user' or 'assistant'
        content: row.message_text
      }));

      fastify.log.info(`📜 [STEP 5] Loaded ${previousMessages.length} previous messages for context`);

      // ═══════════════════════════════════════════════════════
      // 4. CONNECT TO ELEVENLABS WEBSOCKET
      // ═══════════════════════════════════════════════════════
      fastify.log.info(`🔌 [STEP 6] Connecting to ElevenLabs WebSocket...`);
      fastify.log.info(`   - Voice ID: ${voiceId}`);
      fastify.log.info(`   - Model ID: ${modelId}`);

      elevenWs = new ElevenLabsWebSocketClient(
        voiceId,
        modelId,
        elevenlabsApiKey
      );

      // Set up audio chunk forwarding
      elevenWs.onAudioChunk = (chunk) => {
        fastify.log.debug(`🔊 [AUDIO] Received audio chunk - Size: ${chunk.audio?.length || 0} bytes, Final: ${chunk.isFinal}`);
        reply.raw.write(`data: ${JSON.stringify({
          type: 'audio_chunk',
          audio: chunk.audio,
          alignment: chunk.alignment,
          isFinal: chunk.isFinal
        })}\n\n`);
      };

      elevenWs.onError = (error) => {
        fastify.log.error('❌ [STEP 6] ElevenLabs WebSocket error:', error);
        reply.raw.write(`data: ${JSON.stringify({
          type: 'error',
          error: 'Audio generation error',
          message: error.message
        })}\n\n`);
      };

      try {
        await elevenWs.connect();
        fastify.log.info('✅ [STEP 6] ElevenLabs WebSocket connected successfully');
      } catch (wsError) {
        fastify.log.error(`❌ [STEP 6] Failed to connect to ElevenLabs:`, wsError);
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
      fastify.log.info('🧠 [STEP 7] Building OpenAI context...');
      const openAIMessages = [
        { role: 'system', content: systemPrompt },
        ...previousMessages, // Full conversation history
        { role: 'user', content: message }
      ];

      fastify.log.info(`📤 [STEP 7] OpenAI context ready:
        - System prompt: ${systemPrompt.substring(0, 50)}...
        - Previous messages: ${previousMessages.length}
        - New user message: "${message.substring(0, 100)}${message.length > 100 ? '...' : ''}"
        - Total messages: ${openAIMessages.length}`);

      // ═══════════════════════════════════════════════════════
      // 6. STREAM FROM OPENAI
      // ═══════════════════════════════════════════════════════
      const AI_ENGINE_URL = process.env.AI_ENGINE_URL || 'http://localhost:8001';
      const streamUrl = `${AI_ENGINE_URL}/api/v1/sessions/${sessionId}/message/stream`;

      fastify.log.info(`🌐 [STEP 8] Connecting to AI Engine...`);
      fastify.log.info(`   - URL: ${streamUrl}`);
      fastify.log.info(`   - Deep mode: ${deepMode}`);

      let openAIResponse;
      try {
        openAIResponse = await fetch(streamUrl, {
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

        fastify.log.info(`✅ [STEP 8] AI Engine response received - Status: ${openAIResponse.status}`);

        if (!openAIResponse.ok) {
          const errorText = await openAIResponse.text();
          fastify.log.error(`❌ [STEP 8] AI Engine returned error: ${openAIResponse.status} - ${errorText}`);
          throw new Error(`OpenAI stream failed: ${openAIResponse.status} - ${errorText}`);
        }
      } catch (fetchError) {
        fastify.log.error(`❌ [STEP 8] Failed to connect to AI Engine:`, fetchError);
        throw new Error(`AI Engine connection failed: ${fetchError.message}`);
      }

      let accumulatedText = '';
      let buffer = '';
      let streamStartTime = Date.now();
      let firstTokenTime = null;
      let chunkCount = 0;
      let ttsChunkCount = 0;

      // ═══════════════════════════════════════════════════════
      // 7. DUAL-STREAM PROCESSING
      // ═══════════════════════════════════════════════════════
      fastify.log.info('⚡ [STEP 9] Starting dual-stream processing (OpenAI + ElevenLabs)...');
      fastify.log.info(`📊 [STEP 9] Response body type: ${typeof openAIResponse.body}`);
      fastify.log.info(`📊 [STEP 9] Response body is ReadableStream: ${openAIResponse.body instanceof ReadableStream}`);

      const reader = openAIResponse.body;

      fastify.log.info('🔄 [STEP 9] Entering stream iteration loop...');
      for await (const chunk of reader) {
        chunkCount++;
        fastify.log.info(`📦 [STEP 9] Received chunk #${chunkCount}, size: ${chunk.length} bytes`);
        buffer += chunk.toString();

        // Process complete SSE events (ending with \n\n)
        if (buffer.includes('\n\n')) {
          const lines = buffer.split('\n');
          fastify.log.info(`🔍 [PARSE] Processing ${lines.length} lines from buffer`);

          let dataLineCount = 0;
          let parsedEventCount = 0;

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              dataLineCount++;
              const jsonStr = line.substring(6);
              fastify.log.debug(`📋 [PARSE] Data line #${dataLineCount}: ${jsonStr.substring(0, 100)}${jsonStr.length > 100 ? '...' : ''}`);

              try {
                const event = JSON.parse(jsonStr);
                parsedEventCount++;
                fastify.log.info(`📨 [PARSE] Event #${parsedEventCount} - type: ${event.type}, keys: ${Object.keys(event).join(', ')}`);

                // ─────────────────────────────────────────────
                // CONTENT EVENT: Text delta from OpenAI
                // ─────────────────────────────────────────────
                if (event.type === 'content') {
                  if (!firstTokenTime) {
                    firstTokenTime = Date.now();
                    const latency = firstTokenTime - streamStartTime;
                    fastify.log.info(`⚡ [STEP 9] First token received! Latency: ${latency}ms`);
                  }

                  accumulatedText = event.content;
                  fastify.log.debug(`📝 [TEXT] Chunk ${chunkCount}: Accumulated ${accumulatedText.length} chars`);

                  // Forward text to iOS immediately
                  reply.raw.write(`data: ${JSON.stringify({
                    type: 'text_delta',
                    content: accumulatedText
                  })}\n\n`);

                  // Process for TTS chunks
                  const newChunks = chunker.processNewText(accumulatedText);

                  // Send each new chunk to ElevenLabs
                  for (const chunk of newChunks) {
                    ttsChunkCount++;
                    fastify.log.info(`📤 [TTS] Chunk ${ttsChunkCount}/${chunker.totalChunks}: "${chunk.substring(0, 50)}${chunk.length > 50 ? '...' : ''}" (${chunk.length} chars)`);
                    elevenWs.sendTextChunk(chunk, true);
                  }
                }

                // ─────────────────────────────────────────────
                // END EVENT: OpenAI stream complete
                // ─────────────────────────────────────────────
                else if (event.type === 'end') {
                  fastify.log.info(`🏁 [STEP 9] OpenAI stream complete! Total chunks: ${chunkCount}, Total text: ${accumulatedText.length} chars`);
                  fastify.log.info('📤 [TTS] Flushing remaining text chunks to ElevenLabs...');

                  // Flush remaining text
                  const finalChunks = chunker.flush();
                  fastify.log.info(`📤 [TTS] Final flush returned ${finalChunks.length} chunks`);

                  for (const chunk of finalChunks) {
                    ttsChunkCount++;
                    fastify.log.info(`📤 [TTS] Final chunk ${ttsChunkCount}: "${chunk.substring(0, 50)}${chunk.length > 50 ? '...' : ''}" (${chunk.length} chars)`);
                    elevenWs.sendTextChunk(chunk, true);
                  }

                  // Signal end to ElevenLabs
                  fastify.log.info('🔚 [TTS] Sending end-of-input signal to ElevenLabs...');
                  elevenWs.sendEndOfInput();

                  // Wait for final audio chunks (2 seconds)
                  fastify.log.info('⏳ [TTS] Waiting 2 seconds for final audio chunks...');
                  await new Promise(resolve => setTimeout(resolve, 2000));
                  fastify.log.info('✅ [TTS] Wait complete');

                  // Send completion event
                  const totalTime = Date.now() - streamStartTime;
                  const chunkerStats = chunker.getStats();
                  const wsMetrics = elevenWs.getMetrics();

                  fastify.log.info(`✅ [STEP 9] Streaming complete! Metrics:
        - Total time: ${totalTime}ms
        - First token latency: ${firstTokenTime ? firstTokenTime - streamStartTime : 'N/A'}ms
        - Text chunks: ${chunkerStats.totalChunks}
        - Audio chunks: ${wsMetrics.audioChunksReceived}
        - TTFA: ${wsMetrics.ttfa}ms`);

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
                fastify.log.warn(`⚠️ [PARSE] JSON parse error on line #${dataLineCount}: ${parseError.message}`);
                fastify.log.debug(`⚠️ [PARSE] Failed JSON: ${jsonStr.substring(0, 200)}`);
              }
            }
          }

          fastify.log.info(`📊 [PARSE] Summary: ${lines.length} total lines, ${dataLineCount} data lines, ${parsedEventCount} parsed events`);

          buffer = '';
        } else {
          fastify.log.debug(`⏳ [PARSE] Buffer doesn't contain \\n\\n yet, waiting for more data (buffer size: ${buffer.length})`);
        }
      }

      fastify.log.info(`🏁 [STEP 9] Stream iteration loop completed`);
      fastify.log.info(`📊 [STEP 9] Final state: chunkCount=${chunkCount}, accumulatedText.length=${accumulatedText.length}, buffer.length=${buffer.length}`);

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
