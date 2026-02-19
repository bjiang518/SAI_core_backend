/**
 * Gemini Live API Integration Module (v2 - Official Protocol)
 *
 * Implements a WebSocket proxy between iOS client and Google's official Gemini Live API.
 * Uses the official BidiGenerateContent WebSocket protocol.
 *
 * Official API: wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent
 *
 * Message Protocol:
 * - iOS → Backend: Custom simplified messages
 * - Backend → Google: Official BidiGenerateContent protocol
 * - Google → Backend: Official server messages
 * - Backend → iOS: Simplified response messages
 */

const WebSocket = require('ws');

module.exports = async function (fastify, opts) {
    const { db } = require('../../../../utils/railway-database');
    const logger = fastify.log;

    // Google Gemini Live API WebSocket endpoint
    const GEMINI_LIVE_ENDPOINT = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

    /**
     * WebSocket proxy endpoint for Gemini Live
     *
     * Acts as a bridge between iOS client and Google's Gemini Live API.
     * Handles authentication, message translation, and bidirectional streaming.
     */
    fastify.get('/api/ai/gemini-live/connect', { websocket: true }, async (connection, req) => {
        // In @fastify/websocket, connection itself is the WebSocket (not connection.socket)
        const clientSocket = connection;
        let geminiSocket = null;
        let userId = null;
        let sessionId = null;
        let isSetupComplete = false;
        let isGeminiConnected = false;
        const messageQueue = []; // Queue messages until Gemini is ready
        let pendingStartSession = null; // Store start_session until Gemini WS is open

        logger.info('New Gemini Live connection request');

        try {
            // ============================================
            // STEP 1: Authenticate iOS Client (BLOCKING)
            // ============================================
            const token = req.query.token;
            sessionId = req.query.sessionId;

            if (!token) {
                logger.warn('Missing authentication token');
                clientSocket.send(JSON.stringify({
                    type: 'error',
                    error: 'Missing authentication token'
                }));
                clientSocket.close(1008, 'Unauthorized');
                return;
            }

            // Verify session token (64-character hex format)
            try {
                const sessionData = await db.verifyUserSession(token);

                if (!sessionData || !sessionData.user_id) {
                    logger.warn('Invalid or expired session token');
                    clientSocket.send(JSON.stringify({
                        type: 'error',
                        error: 'Invalid or expired authentication token'
                    }));
                    clientSocket.close(1008, 'Unauthorized');
                    return;
                }

                userId = sessionData.user_id;
                logger.info({ userId, sessionId }, 'iOS client authenticated via session token');
            } catch (error) {
                logger.error({ error }, 'Session verification failed');
                clientSocket.send(JSON.stringify({
                    type: 'error',
                    error: 'Authentication failed'
                }));
                clientSocket.close(1008, 'Unauthorized');
                return;
            }

            // Verify session ownership (BLOCKING - prevent race condition)
            if (sessionId) {
                const result = await db.query('SELECT user_id FROM sessions WHERE id = $1', [sessionId]);

                if (result.rows.length === 0 || result.rows[0].user_id !== userId) {
                    logger.warn({ userId, sessionId }, 'Session not found or unauthorized');
                    clientSocket.send(JSON.stringify({
                        type: 'error',
                        error: 'Session not found or unauthorized'
                    }));
                    clientSocket.close(1008, 'Unauthorized');
                    return;
                }

                logger.info({ userId, sessionId }, 'Session ownership verified');
            }

            // ============================================
            // STEP 2: Connect to Google Gemini Live API
            // ============================================
            const apiKey = process.env.GEMINI_API_KEY;
            if (!apiKey) {
                logger.error('GEMINI_API_KEY not configured');
                clientSocket.send(JSON.stringify({
                    type: 'error',
                    error: 'Server configuration error'
                }));
                clientSocket.close(1011, 'Configuration error');
                return;
            }

            // Connect to Google's WebSocket with API key
            const geminiUrl = `${GEMINI_LIVE_ENDPOINT}?key=${apiKey}`;
            logger.info({
                endpoint: GEMINI_LIVE_ENDPOINT,
                apiKeyPrefix: apiKey ? `${apiKey.substring(0, 10)}...` : 'MISSING'
            }, 'Connecting to Gemini Live API...');

            try {
                geminiSocket = new WebSocket(geminiUrl);
                logger.debug('WebSocket object created successfully');
            } catch (wsError) {
                logger.error({ wsError }, 'Failed to create WebSocket connection');
                clientSocket.send(JSON.stringify({
                    type: 'error',
                    error: 'Failed to connect to AI service'
                }));
                clientSocket.close(1011, 'Connection failed');
                return;
            }

            // ============================================
            // STEP 3: Handle Gemini Connection Events
            // ============================================
            geminiSocket.on('open', async () => {
                const timestamp = new Date().toISOString();
                logger.info({
                    userId,
                    timestamp,
                    readyState: geminiSocket.readyState
                }, '✅ Connected to Gemini Live API');

                isGeminiConnected = true;

                // ✅ FIX: If start_session arrived before Gemini opened, process it now
                if (pendingStartSession) {
                    logger.info({
                        userId,
                        sessionId
                    }, '📤 Sending queued start_session now that Gemini is open');

                    const msg = pendingStartSession;
                    pendingStartSession = null;
                    await handleClientMessage(msg);
                } else {
                    logger.info({
                        userId,
                        queuedMessages: messageQueue.length
                    }, '🔔 Gemini connected - waiting for iOS start_session...');
                }

                // Messages will be flushed after receiving setupComplete from Gemini
            });

            geminiSocket.on('message', (data) => {
                try {
                    const rawData = data.toString();
                    const message = JSON.parse(rawData);

                    // ✅ PERFORMANCE: Only log type, NEVER log full message (contains huge Base64 audio)
                    const messageType = Object.keys(message)[0];
                    logger.debug({
                        userId,
                        messageType
                    }, '📨 Received from Gemini');

                    handleGeminiMessage(message);
                } catch (error) {
                    logger.error({
                        error: error.message,
                        stack: error.stack,
                        rawData: data.toString()
                    }, '❌ Failed to parse Gemini message');
                }
            });

            geminiSocket.on('error', (error) => {
                logger.error({
                    error: error.message,
                    stack: error.stack,
                    errorCode: error.code,
                    userId
                }, '🔴 Gemini WebSocket error');

                clientSocket.send(JSON.stringify({
                    type: 'error',
                    error: 'Connection to AI service failed'
                }));
            });

            geminiSocket.on('close', (code, reason) => {
                const reasonStr = reason ? reason.toString() : 'No reason provided';
                logger.error({
                    code,
                    reason: reasonStr,
                    wasSetupComplete: isSetupComplete,
                    userId
                }, '🔴 Gemini WebSocket closed');

                // 🔍 DEBUG: Explain close codes
                const closeCodeExplanation = {
                    1000: 'Normal closure',
                    1001: 'Going away',
                    1002: 'Protocol error',
                    1003: 'Unsupported data',
                    1006: 'Abnormal closure (no close frame)',
                    1007: 'Invalid frame payload data',
                    1008: 'Policy violation',
                    1009: 'Message too big',
                    1011: 'Internal server error'
                };

                logger.error({
                    closeCodeMeaning: closeCodeExplanation[code] || 'Unknown code'
                }, `Close code ${code} meaning`);

                clientSocket.send(JSON.stringify({
                    type: 'session_ended',
                    reason: 'AI service disconnected'
                }));
                clientSocket.close(1000, 'Gemini session ended');
            });

            // ============================================
            // STEP 4: Handle iOS Client Messages
            // ============================================
            clientSocket.on('message', async (data) => {
                try {
                    const rawData = data.toString();
                    const message = JSON.parse(rawData);

                    // 🔍 DEBUG: Log incoming client messages
                    logger.info({
                        userId,
                        messageType: message.type,
                        fullMessage: JSON.stringify(message, null, 2)
                    }, '📥 Received from iOS client');

                    // ✅ CRITICAL FIX: Gate start_session on Gemini WS being open
                    // If Gemini not connected yet, queue start_session
                    if (message.type === 'start_session') {
                        if (!isGeminiConnected || !geminiSocket || geminiSocket.readyState !== WebSocket.OPEN) {
                            logger.info({
                                userId,
                                sessionId,
                                geminiReadyState: geminiSocket?.readyState
                            }, '⏳ start_session received before Gemini open; queueing');
                            pendingStartSession = message;  // Keep only latest
                            return;
                        }

                        logger.info({
                            userId,
                            sessionId
                        }, '🚀 Processing start_session (Gemini is open)');
                        await handleClientMessage(message);
                        return;
                    }

                    // ✅ FIX: Queue OTHER messages until setupComplete
                    if (!isSetupComplete) {
                        logger.info({
                            messageType: message.type
                        }, '⏸️ Queuing message until Gemini setup completes');
                        messageQueue.push(message);
                        return;
                    }

                    await handleClientMessage(message);
                } catch (error) {
                    logger.error({
                        error: error.message,
                        stack: error.stack,
                        rawData: data.toString()
                    }, '❌ Error processing client message');

                    clientSocket.send(JSON.stringify({
                        type: 'error',
                        error: error.message
                    }));
                }
            });

            clientSocket.on('close', (code, reason) => {
                logger.info({ code, reason: reason.toString(), userId }, 'iOS client disconnected');
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.close(1000, 'Client disconnected');
                }
            });

            clientSocket.on('error', (error) => {
                logger.error({ error, userId }, 'iOS client WebSocket error');
            });

            // ============================================
            // Message Handler: iOS Client → Google Gemini
            // ============================================
            async function handleClientMessage(message) {
                const { type, ...data } = message;

                logger.debug({ type, userId }, 'Received client message');

                switch (type) {
                    case 'start_session':
                        await handleStartSession(data);
                        break;

                    case 'audio_chunk':
                        handleAudioChunk(data);
                        break;

                    case 'audio_stream_end':
                        handleAudioStreamEnd();
                        break;

                    case 'text_message':
                        handleTextMessage(data);
                        break;

                    case 'interrupt':
                        handleInterrupt();
                        break;

                    case 'end_session':
                        handleEndSession();
                        break;

                    default:
                        logger.warn({ type }, 'Unknown client message type');
                }
            }

            /**
             * HANDLER: Start Session
             * Translates iOS "start_session" to official "setup" message
             */
            async function handleStartSession(data) {
                const { subject, language } = data;

                logger.info({ userId, sessionId, subject, language }, 'Starting Gemini Live session');

                // Build system instruction
                const systemInstruction = buildSystemInstruction(subject, language);

                // Build official BidiGenerateContentSetup message
                // ✅ CRITICAL: Must add inputAudioTranscription and outputAudioTranscription at setup level
                const setupMessage = {
                    setup: {
                        model: "models/gemini-2.5-flash-native-audio-preview-12-2025",
                        generationConfig: {
                            responseModalities: ["AUDIO"], // Keep AUDIO only, transcription has dedicated config
                            speechConfig: {
                                voiceConfig: {
                                    prebuiltVoiceConfig: {
                                        voiceName: "Puck"
                                    }
                                }
                            }
                        },
                        // ✅ CRITICAL: These MUST be at setup level to enable outputTranscription
                        inputAudioTranscription: {},  // Enable user speech-to-text
                        outputAudioTranscription: {}, // Enable AI speech-to-text (required for iOS display)
                        systemInstruction: {
                            parts: [{ text: systemInstruction }]
                        }
                    }
                };

                // Send setup to Gemini
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    const setupJson = JSON.stringify(setupMessage);

                    // 🔍 DEBUG: Log the exact setup message being sent
                    logger.info({
                        userId,
                        sessionId,
                        setupMessage: JSON.stringify(setupMessage, null, 2)
                    }, '📤 Sending setup message to Gemini');

                    geminiSocket.send(setupJson);
                    logger.info({ userId }, '✅ Setup message sent to Gemini');

                    // 🔍 DEBUG: Set timeout to detect if Gemini never responds
                    setTimeout(() => {
                        if (!isSetupComplete) {
                            logger.error({
                                userId,
                                sessionId,
                                elapsedSeconds: 5
                            }, '⏰ TIMEOUT: Gemini did not respond to setup after 5 seconds');
                        }
                    }, 5000);
                } else {
                    throw new Error('Gemini connection not ready');
                }
            }

            /**
             * HANDLER: Audio Chunk
             * Translates iOS audio to official realtimeInput message
             * NOTE: Input audio is 16kHz PCM
             */
            function handleAudioChunk(data) {
                const { audio } = data; // Base64 encoded audio

                // Build official BidiGenerateContentRealtimeInput message
                // ✅ Official protocol uses camelCase and audio field (not media_chunks)
                const realtimeInput = {
                    realtimeInput: {  // ✅ camelCase
                        audio: {  // ✅ Use audio field, not media_chunks
                            data: audio,
                            mimeType: 'audio/pcm;rate=16000'  // ✅ camelCase
                        }
                    }
                };

                // Forward to Gemini
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(realtimeInput));
                } else {
                    logger.warn('Cannot send audio: Gemini connection not ready');
                }
            }

            /**
             * HANDLER: Audio Stream End
             *
             * ✅ FIX: Send audioStreamEnd when mic stops to flush cached audio
             *
             * When to send:
             * - Push-to-talk released
             * - User mutes microphone
             * - App backgrounds
             * - Audio stream pauses for >1 second
             */
            function handleAudioStreamEnd() {
                logger.info({ userId }, 'Audio stream ended - flushing cached audio');

                const streamEnd = {
                    realtimeInput: {
                        audioStreamEnd: true
                    }
                };

                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(streamEnd));
                } else {
                    logger.warn('Cannot send audioStreamEnd: Gemini connection not ready');
                }
            }

            /**
             * HANDLER: Text Message
             * Translates iOS text to official clientContent message
             */
            function handleTextMessage(data) {
                const { text } = data;

                // Build official BidiGenerateContentClientContent message
                // ✅ Official protocol uses camelCase
                const clientContent = {
                    clientContent: {  // ✅ camelCase
                        turns: [{
                            role: 'user',
                            parts: [{
                                text: text
                            }]
                        }],
                        turnComplete: true  // ✅ camelCase
                    }
                };

                // Forward to Gemini
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(clientContent));

                    // Store in database
                    storeMessage('user', text);
                } else {
                    logger.warn('Cannot send text: Gemini connection not ready');
                }
            }

            /**
             * HANDLER: Interrupt
             *
             * ✅ FIX: With automatic VAD enabled (default), barge-in happens naturally
             * when new user audio/text is sent. Don't send activityEnd in this mode.
             *
             * If you need explicit control, set:
             * realtimeInputConfig.automaticActivityDetection.disabled = true
             * in setup, then use activityStart/activityEnd explicitly.
             */
            function handleInterrupt() {
                logger.info({ userId }, 'User interrupted AI (automatic VAD barge-in)');

                // With auto VAD (default), interruption happens when iOS sends new audio/text
                // No need to send activityEnd - just notify iOS that we acknowledge the interrupt

                // Notify iOS
                clientSocket.send(JSON.stringify({
                    type: 'interrupted'
                }));
            }

            /**
             * HANDLER: End Session
             * Closes both connections gracefully
             */
            function handleEndSession() {
                logger.info({ userId, sessionId }, 'Ending session');

                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.close(1000, 'Session ended by user');
                }

                clientSocket.send(JSON.stringify({
                    type: 'session_ended'
                }));

                clientSocket.close(1000, 'Session ended');
            }

            // ============================================
            // Message Handler: Google Gemini → iOS Client
            // ============================================
            async function handleGeminiMessage(message) {
                logger.debug({ messageType: Object.keys(message)[0] }, 'Received Gemini message');

                // Handle setupComplete
                if (message.setupComplete || message.setup_complete) {
                    isSetupComplete = true;
                    logger.info({ userId }, '✅ Gemini setup complete - ready for messages');

                    clientSocket.send(JSON.stringify({
                        type: 'session_ready',
                        sessionId: sessionId
                    }));

                    // ✅ FIX: Now flush queued messages after setupComplete (with await)
                    if (messageQueue.length > 0) {
                        logger.info({
                            queueLength: messageQueue.length
                        }, 'Processing queued messages after setupComplete');

                        while (messageQueue.length > 0) {
                            const queuedMessage = messageQueue.shift();
                            logger.debug({ messageType: queuedMessage.type }, 'Processing queued message');
                            await handleClientMessage(queuedMessage);  // ✅ await for proper ordering
                        }
                    }
                }

                // Handle serverContent (AI response)
                const serverContent = message.serverContent || message.server_content;
                if (serverContent) {
                    // 🔍 DEBUG: Log what fields Gemini is actually returning
                    logger.info({
                        userId,
                        serverContentKeys: Object.keys(serverContent),
                        hasOutputTranscription: !!(serverContent.outputTranscription || serverContent.output_transcription),
                        hasModelTurn: !!(serverContent.modelTurn || serverContent.model_turn)
                    }, '📦 serverContent received from Gemini');

                    const modelTurn = serverContent.modelTurn || serverContent.model_turn;
                    const turnComplete = serverContent.turnComplete || serverContent.turn_complete;
                    const interrupted = serverContent.interrupted;

                    // ✅ CRITICAL: Use outputTranscription for text display (not modelTurn.parts.text)
                    // outputTranscription contains ONLY the spoken text without internal thinking
                    // modelTurn.parts.text contains internal reasoning/thinking that should NOT be displayed
                    const outputTranscription = serverContent.outputTranscription || serverContent.output_transcription;
                    if (outputTranscription && outputTranscription.text) {
                        // Send as text_chunk so iOS displays it
                        logger.info({
                            userId,
                            textLength: outputTranscription.text.length,
                            textPreview: outputTranscription.text.substring(0, 100)
                        }, '📝 Sending text_chunk from outputTranscription');

                        clientSocket.send(JSON.stringify({
                            type: 'text_chunk',
                            text: outputTranscription.text
                        }));
                        logger.debug(`📝 Sent outputTranscription text (${outputTranscription.text.length} chars)`);
                    } else {
                        logger.warn({
                            userId,
                            hasModelTurn: !!modelTurn,
                            modelTurnHasText: modelTurn?.parts?.some(p => p.text)
                        }, '⚠️ No outputTranscription in serverContent - text will not display on iOS');
                    }

                    // Send audio chunks from modelTurn (still needed for playback)
                    if (modelTurn && modelTurn.parts) {
                        for (const part of modelTurn.parts) {
                            // ❌ SKIP text from modelTurn - it contains internal thinking
                            // ✅ ONLY send audio chunks

                            // Send audio chunk
                            const inlineData = part.inlineData || part.inline_data;
                            if (inlineData) {
                                const mimeType = inlineData.mimeType || inlineData.mime_type;
                                if (mimeType && mimeType.startsWith('audio/')) {
                                    // ✅ Check backpressure before sending audio
                                    // If bufferedAmount > 64KB, client can't keep up - log warning
                                    const bufferedAmount = clientSocket.bufferedAmount || 0;
                                    if (bufferedAmount > 65536) {
                                        logger.warn({
                                            userId,
                                            bufferedAmount,
                                            bufferKB: Math.round(bufferedAmount / 1024)
                                        }, '⚠️ WebSocket backpressure detected - client buffer full');
                                    }

                                    clientSocket.send(JSON.stringify({
                                        type: 'audio_chunk',
                                        data: inlineData.data // Base64 audio - passed through directly
                                    }));
                                }
                            }
                        }
                    }

                    // Send input transcription (user's speech recognized)
                    const inputTranscription = serverContent.inputTranscription || serverContent.input_transcription;
                    if (inputTranscription && inputTranscription.text) {
                        clientSocket.send(JSON.stringify({
                            type: 'user_transcription',
                            text: inputTranscription.text
                        }));
                    }

                    // Signal turn complete
                    if (turnComplete) {
                        clientSocket.send(JSON.stringify({
                            type: 'turn_complete'
                        }));

                        // Store AI response (prefer outputTranscription, fallback to modelTurn text)
                        let responseText = '';
                        if (outputTranscription && outputTranscription.text) {
                            responseText = outputTranscription.text;
                        } else if (modelTurn && modelTurn.parts) {
                            responseText = modelTurn.parts
                                .filter(p => p.text)
                                .map(p => p.text)
                                .join(' ');
                        }

                        if (responseText) {
                            storeMessage('assistant', responseText);
                        }
                    }

                    // Signal interrupted
                    if (interrupted) {
                        clientSocket.send(JSON.stringify({
                            type: 'interrupted'
                        }));
                    }
                }

                // Handle toolCall (function calling)
                const toolCall = message.toolCall || message.tool_call;
                if (toolCall) {
                    handleToolCall(toolCall);
                }

                // Handle toolCallCancellation
                const toolCallCancellation = message.toolCallCancellation || message.tool_call_cancellation;
                if (toolCallCancellation) {
                    const { ids } = toolCallCancellation;
                    logger.info({ ids }, 'Tool calls cancelled by server');

                    clientSocket.send(JSON.stringify({
                        type: 'tool_call_cancelled',
                        ids: ids
                    }));
                }

                // Handle goAway (server requests disconnect)
                const goAway = message.goAway || message.go_away;
                if (goAway) {
                    const timeLeft = goAway.timeLeft || goAway.time_left;
                    logger.warn({ timeLeft }, 'Server sent goAway - will disconnect soon');

                    clientSocket.send(JSON.stringify({
                        type: 'go_away',
                        timeLeft: timeLeft,
                        message: 'Server requesting disconnect - please reconnect'
                    }));

                    setTimeout(() => {
                        if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                            geminiSocket.close(1000, 'goAway received');
                        }
                        if (clientSocket.readyState === WebSocket.OPEN) {
                            clientSocket.close(1000, 'Server requested disconnect');
                        }
                    }, 1000);
                }

                // Handle sessionResumptionUpdate
                const sessionUpdate = message.sessionResumptionUpdate || message.session_resumption_update;
                if (sessionUpdate) {
                    const newHandle = sessionUpdate.newHandle || sessionUpdate.new_handle;
                    const resumable = sessionUpdate.resumable;
                    logger.debug({ newHandle, resumable }, 'Session resumption state update');

                    if (resumable && newHandle) {
                        logger.info({ userId, sessionId, newHandle }, 'Session resumption token available');
                    }
                }

                // Handle usage metadata
                const usageMetadata = message.usageMetadata || message.usage_metadata;
                if (usageMetadata) {
                    logger.debug({ usage: usageMetadata }, 'Token usage');
                }
            }

            /**
             * Handle function calls from Gemini
             */
            async function handleToolCall(toolCall) {
                const functionCalls = toolCall.functionCalls || toolCall.function_calls;

                for (const call of functionCalls) {
                    const { name, args, id } = call;

                    logger.info({ name, args, id }, 'Executing function call');

                    let result;
                    try {
                        switch (name) {
                            case 'fetch_homework_context':
                                result = await fetchHomeworkContext(args.sessionId);
                                break;

                            case 'search_archived_conversations':
                                result = await searchArchivedConversations(args.query, args.subject);
                                break;

                            default:
                                result = { error: 'Unknown function' };
                        }

                        // Send function response back to Gemini
                        // ✅ Official protocol uses camelCase
                        const toolResponse = {
                            toolResponse: {  // ✅ camelCase
                                functionResponses: [{  // ✅ camelCase
                                    id: id,
                                    name: name,
                                    response: result
                                }]
                            }
                        };

                        if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                            geminiSocket.send(JSON.stringify(toolResponse));
                        }

                    } catch (error) {
                        logger.error({ error, name }, 'Error executing function call');

                        // Send error response
                        const errorResponse = {
                            toolResponse: {  // ✅ camelCase
                                functionResponses: [{  // ✅ camelCase
                                    id: id,
                                    name: name,
                                    response: { error: error.message }
                                }]
                            }
                        };

                        if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                            geminiSocket.send(JSON.stringify(errorResponse));
                        }
                    }
                }
            }

            // ============================================
            // Database Functions
            // ============================================
            async function storeMessage(role, text) {
                if (!sessionId) return;

                try {
                    await db.query(`
                        INSERT INTO conversation_messages
                        (session_id, user_id, message_type, message_text, tokens_used, created_at)
                        VALUES ($1, $2, $3, $4, $5, NOW())
                    `, [sessionId, userId, role, text, 0]);
                } catch (error) {
                    logger.error({ error }, 'Error storing message');
                }
            }

            async function fetchHomeworkContext(sessionId) {
                try {
                    const result = await db.query(`
                        SELECT
                            s.subject,
                            s.created_at,
                            s.metadata,
                            array_agg(
                                json_build_object(
                                    'role', cm.message_type,
                                    'content', cm.message_text,
                                    'timestamp', cm.created_at
                                ) ORDER BY cm.created_at
                            ) as messages
                        FROM sessions s
                        LEFT JOIN conversation_messages cm ON cm.session_id = s.id
                        WHERE s.id = $1 AND s.user_id = $2
                        GROUP BY s.id
                    `, [sessionId, userId]);

                    if (result.rows.length === 0) {
                        return { error: 'Session not found' };
                    }

                    return result.rows[0];
                } catch (error) {
                    logger.error({ error }, 'Error fetching homework context');
                    return { error: 'Failed to fetch context' };
                }
            }

            async function searchArchivedConversations(query, subject) {
                try {
                    let sql = `
                        SELECT
                            id,
                            subject,
                            conversation_content,
                            archived_date,
                            ts_rank(
                                to_tsvector('english', conversation_content),
                                plainto_tsquery('english', $1)
                            ) as relevance
                        FROM archived_conversations_new
                        WHERE user_id = $2
                        AND to_tsvector('english', conversation_content) @@ plainto_tsquery('english', $1)
                    `;

                    const params = [query, userId];

                    if (subject) {
                        sql += ' AND subject = $3';
                        params.push(subject);
                    }

                    sql += ' ORDER BY relevance DESC, archived_date DESC LIMIT 5';

                    const result = await db.query(sql, params);

                    return {
                        results: result.rows,
                        count: result.rows.length
                    };
                } catch (error) {
                    logger.error({ error }, 'Error searching archived conversations');
                    return { error: 'Failed to search archives' };
                }
            }

        } catch (error) {
            logger.error({
                error: error.message,
                stack: error.stack,
                userId
            }, 'Fatal error in WebSocket handler');

            // Safely close client socket if still open
            try {
                if (clientSocket && clientSocket.readyState === WebSocket.OPEN) {
                    clientSocket.send(JSON.stringify({
                        type: 'error',
                        error: 'Internal server error'
                    }));
                    clientSocket.close(1011, 'Internal error');
                }
            } catch (closeError) {
                logger.error({ closeError }, 'Error closing client socket');
            }
        }
    });

    /**
     * Build system instruction for educational tutor
     */
    function buildSystemInstruction(subject, language = 'en') {
        const subjectContext = subject || 'General';

        const prompts = {
            en: `You are an expert AI tutor specializing in ${subjectContext}.

🚨 CRITICAL INSTRUCTION - READ FIRST 🚨
You are speaking OUT LOUD to a student via voice. NEVER say things like:
- "I've taken the user's feedback..."
- "I'm focusing on..."
- "I'm exploring ways to..."
- "My goal is to..."
- "I want to reassure them..."
- ANY form of self-reflection or meta-commentary

This is a LIVE VOICE conversation. The student can ONLY hear what you say out loud. Speak DIRECTLY and NATURALLY as a tutor would in person.

❌ BAD (meta-commentary): "I've taken the user's feedback about clarity to heart and am actively exploring ways to improve my communication."
✅ GOOD (direct response): "I can hear you clearly now! What math topic would you like help with today?"

Your teaching philosophy:

1. Socratic Method: Guide students to discover answers through thoughtful questions
2. Scaffolding: Break complex problems into manageable steps
3. Patience: Never rush or show frustration, celebrate progress
4. Clarity: Use age-appropriate language and real-world examples
5. Engagement: Make learning interactive and fun

For math/science problems:
- Show step-by-step reasoning
- Explain the "why" behind each step
- Use analogies to clarify abstract concepts

For essays/analysis:
- Help organize thoughts and structure arguments
- Provide constructive feedback
- Encourage critical thinking

Always encourage the student and adapt your teaching style to their needs.`,

            'zh-Hans': `你是一位专精于${subjectContext}的AI导师。

🚨 关键指示 - 首先阅读 🚨
你正在通过语音与学生进行现场对话。永远不要说类似以下的话：
- "我已经听取了用户的反馈..."
- "我正在专注于..."
- "我正在探索方法..."
- "我的目标是..."
- "我想让他们放心..."
- 任何形式的自我反思或元评论

这是现场语音对话。学生只能听到你大声说出的话。像面对面的导师一样直接、自然地说话。

❌ 错误（元评论）："我已经听取了用户关于清晰度的反馈，正在积极探索改进沟通的方法。"
✅ 正确（直接回应）："我现在能清楚地听到你了！今天你想学习什么数学题目？"

教学理念：

1. 苏格拉底式教学：通过提问引导学生发现答案
2. 脚手架教学：将复杂问题分解为可管理的步骤
3. 耐心：从不急躁或表现挫折感，庆祝进步
4. 清晰：使用适龄语言和现实例子
5. 互动：让学习变得有趣和互动

对于数学/科学问题：
- 展示逐步推理
- 解释每一步的"为什么"
- 使用类比阐明抽象概念

对于作文/分析：
- 帮助组织思路和结构论点
- 提供建设性反馈
- 鼓励批判性思维

始终鼓励学生，根据他们的需求调整教学方式。`,

            'zh-Hant': `你是一位專精於${subjectContext}的AI導師。

🚨 關鍵指示 - 首先閱讀 🚨
你正在透過語音與學生進行現場對話。永遠不要說類似以下的話：
- "我已經聽取了用戶的反饋..."
- "我正在專注於..."
- "我正在探索方法..."
- "我的目標是..."
- "我想讓他們放心..."
- 任何形式的自我反思或元評論

這是現場語音對話。學生只能聽到你大聲說出的話。像面對面的導師一樣直接、自然地說話。

❌ 錯誤（元評論）："我已經聽取了用戶關於清晰度的反饋，正在積極探索改進溝通的方法。"
✅ 正確（直接回應）："我現在能清楚地聽到你了！今天你想學習什麼數學題目？"

教學理念：

1. 蘇格拉底式教學：通過提問引導學生發現答案
2. 鷹架教學：將複雜問題分解為可管理的步驟
3. 耐心：從不急躁或表現挫折感，慶祝進步
4. 清晰：使用適齡語言和現實例子
5. 互動：讓學習變得有趣和互動

對於數學/科學問題：
- 展示逐步推理
- 解釋每一步的「為什麼」
- 使用類比闡明抽象概念

對於作文/分析：
- 幫助組織思路和結構論點
- 提供建設性回饋
- 鼓勵批判性思維

始終鼓勵學生，根據他們的需求調整教學方式。`
        };

        return prompts[language] || prompts.en;
    }

    /**
     * Health check endpoint
     */
    fastify.get('/api/ai/gemini-live/health', async (request, reply) => {
        return {
            status: 'ok',
            service: 'gemini-live-v2',
            apiKeyConfigured: !!process.env.GEMINI_API_KEY,
            endpoint: GEMINI_LIVE_ENDPOINT
        };
    });

    logger.info('Gemini Live v2 module registered (official API protocol)');
};
