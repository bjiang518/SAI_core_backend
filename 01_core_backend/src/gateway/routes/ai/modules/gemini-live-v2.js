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
        let currentSubject = null; // Set on start_session; used to give image context

        // Accumulators for the current turn — reset on turn_complete / interrupted
        let currentUserTranscript = '';   // built from inputTranscription chunks
        let currentAiTranscript = '';     // built from outputTranscription chunks

        try {
            // ============================================
            // STEP 1: Authenticate iOS Client (BLOCKING)
            // ============================================
            const token = req.query.token;
            sessionId = req.query.sessionId;

            if (!token) {
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
                    clientSocket.send(JSON.stringify({
                        type: 'error',
                        error: 'Invalid or expired authentication token'
                    }));
                    clientSocket.close(1008, 'Unauthorized');
                    return;
                }

                userId = sessionData.user_id;
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
                    clientSocket.send(JSON.stringify({
                        type: 'error',
                        error: 'Session not found or unauthorized'
                    }));
                    clientSocket.close(1008, 'Unauthorized');
                    return;
                }
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

            try {
                geminiSocket = new WebSocket(geminiUrl);
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
                isGeminiConnected = true;

                // If start_session arrived before Gemini opened, process it now
                if (pendingStartSession) {
                    const msg = pendingStartSession;
                    pendingStartSession = null;
                    await handleClientMessage(msg);
                }
            });

            geminiSocket.on('message', (data) => {
                try {
                    const message = JSON.parse(data.toString());
                    handleGeminiMessage(message);
                } catch (error) {
                    logger.error({ error: error.message }, 'Failed to parse Gemini message');
                }
            });

            geminiSocket.on('error', (error) => {
                logger.error({ error: error.message, userId }, 'Gemini WebSocket error');
                clientSocket.send(JSON.stringify({
                    type: 'error',
                    error: 'Connection to AI service failed'
                }));
            });

            geminiSocket.on('close', (code, reason) => {
                const reasonStr = reason ? reason.toString() : 'No reason provided';
                logger.warn({ code, reason: reasonStr, sessionId, userId }, '[Live] Gemini WebSocket closed');
                if (code !== 1000) {
                    logger.error({ code, reason: reasonStr, userId }, 'Gemini WebSocket closed unexpectedly');
                }
                clearInterval(geminiKeepAliveInterval);
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
                    const message = JSON.parse(data.toString());

                    // Gate start_session on Gemini WS being open
                    if (message.type === 'start_session') {
                        if (!isGeminiConnected || !geminiSocket || geminiSocket.readyState !== WebSocket.OPEN) {
                            pendingStartSession = message;
                            return;
                        }
                        await handleClientMessage(message);
                        return;
                    }

                    // Queue other messages until setupComplete
                    if (!isSetupComplete) {
                        messageQueue.push(message);
                        return;
                    }

                    await handleClientMessage(message);
                } catch (error) {
                    logger.error({ error: error.message }, 'Error processing client message');
                    clientSocket.send(JSON.stringify({
                        type: 'error',
                        error: error.message
                    }));
                }
            });

            clientSocket.on('close', () => {
                clearInterval(keepAliveInterval);
                clearInterval(geminiKeepAliveInterval);
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.close(1000, 'Client disconnected');
                }
            });

            clientSocket.on('error', (error) => {
                logger.error({ error: error.message, userId }, 'iOS client WebSocket error');
            });

            // Keep-alive ping every 20s to prevent Railway/proxy from closing idle connections
            const keepAliveInterval = setInterval(() => {
                if (clientSocket.readyState === WebSocket.OPEN) {
                    clientSocket.ping();
                } else {
                    clearInterval(keepAliveInterval);
                }
            }, 20000);

            // Keep-alive ping toward Gemini every 20s — prevents Gemini's idle timeout from
            // closing the connection during long AI audio responses (especially multilingual,
            // which produces larger audio bursts with longer silent gaps between iOS sends).
            const geminiKeepAliveInterval = setInterval(() => {
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.ping();
                } else {
                    clearInterval(geminiKeepAliveInterval);
                }
            }, 20000);

            // ============================================
            // Message Handler: iOS Client → Google Gemini
            // ============================================
            async function handleClientMessage(message) {
                const { type, ...data } = message;

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

                    case 'image_message':
                        handleImageChunk(data);
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
                        break;
                }
            }

            /**
             * HANDLER: Start Session
             * Translates iOS "start_session" to official "setup" message
             */
            async function handleStartSession(data) {
                const { subject, language, character } = data;
                logger.info({ sessionId, subject, language, character }, '[Live] handleStartSession');

                currentSubject = subject || null;

                // Map iOS character to Gemini prebuilt voice name
                const geminiVoiceMap = {
                    adam: 'Schedar',
                    eva:  'Despina',
                    max:  'Fenrir',
                    mia:  'Zephyr'
                };
                const voiceName = geminiVoiceMap[character] || 'Puck';

                const systemInstruction = buildSystemInstruction(subject, language);

                const setupMessage = {
                    setup: {
                        model: "models/gemini-2.5-flash-native-audio-preview-12-2025",
                        generationConfig: {
                            responseModalities: ["AUDIO"],
                            speechConfig: {
                                voiceConfig: {
                                    prebuiltVoiceConfig: {
                                        voiceName: voiceName
                                    }
                                }
                            }
                        },
                        // outputAudioTranscription gives clean spoken-text-only transcription,
                        // with no chain-of-thought content — the right source for text display.
                        inputAudioTranscription: {},
                        outputAudioTranscription: {},
                        systemInstruction: {
                            parts: [{ text: systemInstruction }]
                        }
                    }
                };

                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(setupMessage));

                    // If Gemini doesn't confirm setup within 8s, notify iOS so it can show
                    // "Tap to Reactivate" rather than hanging indefinitely in .connecting state.
                    setTimeout(() => {
                        if (!isSetupComplete) {
                            logger.error({ userId, sessionId }, 'Gemini did not respond to setup after 8 seconds');
                            if (clientSocket.readyState === WebSocket.OPEN) {
                                clientSocket.send(JSON.stringify({
                                    type: 'error',
                                    error: 'Connection to AI timed out. Tap to retry.'
                                }));
                            }
                        }
                    }, 8000);
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
                            mimeType: 'audio/pcm;rate=24000'  // ✅ Match iOS recording rate (24kHz)
                        }
                    }
                };

                // Forward to Gemini
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(realtimeInput));
                }
            }

            /**
             * HANDLER: Audio Stream End
             *
             * ✅ FIX: Send audioStreamEnd when mic stops to flush cached audio
             */
            function handleAudioStreamEnd() {
                logger.info({ sessionId }, '[Live] handleAudioStreamEnd: flushing audio to Gemini');
                const streamEnd = {
                    realtimeInput: {
                        audioStreamEnd: true
                    }
                };

                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(streamEnd));
                }
            }

            /**
             * HANDLER: Image Message
             * Sends image + subject-anchored prompt as a clientContent turn so Gemini
             * stores it in session history and can reference it in all subsequent turns.
             */
            function handleImageChunk(data) {
                const { imageBase64, mimeType = 'image/jpeg' } = data;

                if (!imageBase64) return;

                if (!geminiSocket || geminiSocket.readyState !== WebSocket.OPEN) return;

                const subjectHint = currentSubject ? `This is a ${currentSubject} problem.` : '';
                const instruction = `${subjectHint} Please look at this image carefully and help me with it. I may ask follow-up questions by voice.`.trim();

                // text part BEFORE inlineData (BidiGenerateContentClientContent spec order)
                const clientContent = {
                    clientContent: {
                        turns: [{
                            role: 'user',
                            parts: [
                                { text: instruction },
                                {
                                    inlineData: {
                                        mimeType: mimeType,
                                        data: imageBase64
                                    }
                                }
                            ]
                        }],
                        turnComplete: true
                    }
                };

                geminiSocket.send(JSON.stringify(clientContent));
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

                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(clientContent));
                    storeMessage('user', text);
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
                clientSocket.send(JSON.stringify({ type: 'interrupted' }));
            }

            function handleEndSession() {
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.close(1000, 'Session ended by user');
                }
                clientSocket.send(JSON.stringify({ type: 'session_ended' }));
                clientSocket.close(1000, 'Session ended');
            }

            // ============================================
            // Message Handler: Google Gemini → iOS Client
            // ============================================
            async function handleGeminiMessage(message) {
                // Handle setupComplete
                if (message.setupComplete || message.setup_complete) {
                    isSetupComplete = true;
                    logger.info({ sessionId }, '[Live] Gemini setupComplete received');

                    // Replay prior turns for this session so Gemini has full context.
                    // This is a no-op on first connect (no rows yet); on reconnect it restores
                    // everything the student said and Gemini answered before the drop.
                    await replaySessionContext();

                    clientSocket.send(JSON.stringify({
                        type: 'session_ready',
                        sessionId: sessionId
                    }));

                    // Flush queued messages after setupComplete
                    while (messageQueue.length > 0) {
                        await handleClientMessage(messageQueue.shift());
                    }
                }

                // Handle serverContent (AI response)
                const serverContent = message.serverContent || message.server_content;
                if (serverContent) {
                    const modelTurn = serverContent.modelTurn || serverContent.model_turn;
                    const turnComplete = serverContent.turnComplete || serverContent.turn_complete;
                    const interrupted = serverContent.interrupted;

                    // outputAudioTranscription (set up at session level) delivers clean spoken-text-only
                    // transcription with no chain-of-thought content. This is the correct and sole
                    // source for text display and storage. modelTurn.parts[].text contains COT and
                    // must NOT be used for text_chunk messages or transcript accumulation.
                    const outputTranscription = serverContent.outputTranscription || serverContent.output_transcription;
                    if (outputTranscription && outputTranscription.text) {
                        currentAiTranscript += outputTranscription.text;
                        clientSocket.send(JSON.stringify({
                            type: 'text_chunk',
                            text: outputTranscription.text
                        }));
                    }

                    // Process modelTurn parts for audio only — text parts are intentionally ignored
                    // here because they contain COT. Text comes exclusively from outputTranscription above.
                    if (modelTurn && modelTurn.parts) {
                        for (const part of modelTurn.parts) {
                            // Audio part — forward to iOS for playback
                            const inlineData = part.inlineData || part.inline_data;
                            if (inlineData) {
                                const mimeType = inlineData.mimeType || inlineData.mime_type;
                                if (mimeType && mimeType.startsWith('audio/')) {
                                    const bufferedAmount = clientSocket.bufferedAmount || 0;
                                    if (bufferedAmount > 65536) {
                                        logger.error({ userId, bufferKB: Math.round(bufferedAmount / 1024) }, 'WebSocket backpressure: client buffer full');
                                    }
                                    clientSocket.send(JSON.stringify({
                                        type: 'audio_chunk',
                                        data: inlineData.data
                                    }));
                                }
                            }
                        }
                    }

                    // Accumulate user speech transcript chunks
                    const inputTranscription = serverContent.inputTranscription || serverContent.input_transcription;
                    if (inputTranscription && inputTranscription.text) {
                        currentUserTranscript += inputTranscription.text;
                        clientSocket.send(JSON.stringify({
                            type: 'user_transcription',
                            text: inputTranscription.text
                        }));
                    }

                    // On turn_complete: persist one row each for user and AI, then reset accumulators
                    if (turnComplete) {
                        clientSocket.send(JSON.stringify({
                            type: 'turn_complete'
                        }));

                        const userText = currentUserTranscript.trim();
                        const aiText = currentAiTranscript.trim();
                        currentUserTranscript = '';
                        currentAiTranscript = '';

                        logger.info({ sessionId, userChars: userText.length, aiChars: aiText.length }, '[Live] turn_complete: storing');
                        if (userText) {
                            await storeMessage('user', `🎙️ ${userText}`);
                        }
                        if (aiText) {
                            await storeMessage('assistant', aiText);
                        }
                    }

                    // Signal interrupted — reset AI accumulator (incomplete response discarded)
                    if (interrupted) {
                        clientSocket.send(JSON.stringify({
                            type: 'interrupted'
                        }));
                        // Save any user speech that arrived before the interrupt
                        const userText = currentUserTranscript.trim();
                        if (userText) {
                            await storeMessage('user', `🎙️ ${userText}`);
                        }
                        currentUserTranscript = '';
                        currentAiTranscript = '';
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
                    clientSocket.send(JSON.stringify({
                        type: 'tool_call_cancelled',
                        ids: toolCallCancellation.ids
                    }));
                }

                // Handle goAway (server requests disconnect)
                const goAway = message.goAway || message.go_away;
                if (goAway) {
                    clientSocket.send(JSON.stringify({
                        type: 'go_away',
                        timeLeft: goAway.timeLeft || goAway.time_left,
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

                // Handle sessionResumptionUpdate (no action needed, token managed server-side)
                // Handle usageMetadata (no action needed)
            }

            /**
             * Handle function calls from Gemini
             */
            async function handleToolCall(toolCall) {
                const functionCalls = toolCall.functionCalls || toolCall.function_calls;

                for (const call of functionCalls) {
                    const { name, args, id } = call;
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
                    // Write into `conversations` — the same table getConversationHistory reads,
                    // so the standard archive endpoint can find Live voice messages.
                    await db.addConversationMessage({
                        userId,
                        sessionId,
                        questionId: null,
                        messageType: role,       // 'user' | 'assistant'
                        messageText: text,
                        messageData: null,
                        tokensUsed: 0
                    });
                } catch (error) {
                    logger.error({ error }, 'Error storing message');
                }
            }

            /**
             * Replay prior conversation turns into Gemini after setupComplete.
             *
             * Called on every connect — is a no-op when there are no stored rows yet (first
             * connect). On reconnect it sends a single multi-turn clientContent message so
             * Gemini has the full prior conversation in its context window.
             *
             * Capped at the 50 most recent turns to stay within Gemini's context limit.
             */
            async function replaySessionContext() {
                if (!sessionId) return;
                try {
                    const result = await db.query(`
                        SELECT message_type, message_text
                        FROM conversations
                        WHERE session_id = $1
                        ORDER BY created_at ASC
                        LIMIT 50
                    `, [sessionId]);

                    if (result.rows.length === 0) {
                        logger.info({ sessionId }, '[Live] replaySessionContext: no prior turns, starting fresh');
                        return;
                    }

                    logger.info({ sessionId, rows: result.rows.length }, '[Live] replaySessionContext: replaying turns');

                    // Sanitize stored text before replaying.
                    // Non-live streaming path stores raw SSE bytes if the extraction failed.
                    // AI Engine SSE event types: start (ignore), content (delta), end (full text)
                    function sanitizeMessageText(raw) {
                        if (!raw) return '';
                        if (!raw.includes('data: {')) return raw; // already clean text
                        let endContent = '';
                        let deltaAccum = '';
                        for (const line of raw.split('\n')) {
                            if (!line.startsWith('data: ')) continue;
                            try {
                                const event = JSON.parse(line.slice(6));
                                if (event.type === 'end' && event.content) {
                                    endContent = event.content; // canonical — prefer this
                                } else if (event.type === 'content' && event.delta) {
                                    deltaAccum += event.delta;  // fallback accumulation
                                }
                            } catch (_) {}
                        }
                        const extracted = endContent || deltaAccum;
                        return extracted || raw; // last resort: pass raw so Gemini can try
                    }

                    // Build multi-turn history as clientContent turns, skipping empty rows
                    const turns = [];
                    for (const row of result.rows) {
                        const cleanText = sanitizeMessageText(row.message_text);
                        if (!cleanText.trim()) continue;
                        const preview = cleanText.slice(0, 100).replace(/\n/g, ' ');
                        logger.info({ role: row.message_type, preview }, '[Live] replay turn');
                        turns.push({
                            role: row.message_type === 'user' ? 'user' : 'model',
                            parts: [{ text: cleanText }]
                        });
                    }

                    if (turns.length === 0) {
                        logger.info({ sessionId }, '[Live] replaySessionContext: all rows empty after sanitize, skipping');
                        return;
                    }

                    // Append a silent primer as the final model turn so Gemini doesn't
                    // immediately respond to the history injection ("talk-back").
                    turns.push({
                        role: 'model',
                        parts: [{ text: 'I have reviewed our previous conversation and I\'m ready to continue.' }]
                    });

                    // turnComplete: true — history injection, not an open user turn.
                    // With false, Gemini treats the batch as incomplete and waits for
                    // continuation instead of committing the turns to session memory.
                    const replayMessage = {
                        clientContent: {
                            turns,
                            turnComplete: true
                        }
                    };

                    if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                        geminiSocket.send(JSON.stringify(replayMessage));
                        logger.info({ sessionId, turns: turns.length }, '[Live] replaySessionContext: sent to Gemini');
                    }
                } catch (error) {
                    // Non-fatal — Gemini starts fresh if replay fails
                    logger.error({ error }, '[Live] replaySessionContext: error');
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
                        LEFT JOIN conversations cm ON cm.session_id = s.id
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
};
