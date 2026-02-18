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
            logger.info('Connecting to Gemini Live API...');

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
            geminiSocket.on('open', () => {
                logger.info({ userId }, 'Connected to Gemini Live API');
                isGeminiConnected = true;

                // Flush queued messages
                while (messageQueue.length > 0) {
                    const queuedMessage = messageQueue.shift();
                    logger.debug('Processing queued message');
                    handleClientMessage(queuedMessage);
                }
            });

            geminiSocket.on('message', (data) => {
                try {
                    const message = JSON.parse(data.toString());
                    handleGeminiMessage(message);
                } catch (error) {
                    logger.error({ error }, 'Failed to parse Gemini message');
                }
            });

            geminiSocket.on('error', (error) => {
                logger.error({ error, userId }, 'Gemini WebSocket error');
                clientSocket.send(JSON.stringify({
                    type: 'error',
                    error: 'Connection to AI service failed'
                }));
            });

            geminiSocket.on('close', (code, reason) => {
                logger.info({ code, reason: reason.toString(), userId }, 'Gemini WebSocket closed');
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

                    // Queue messages if Gemini not connected yet
                    if (!isGeminiConnected) {
                        logger.debug('Queuing message until Gemini connects');
                        messageQueue.push(message);
                        return;
                    }

                    await handleClientMessage(message);
                } catch (error) {
                    logger.error({ error }, 'Error processing client message');
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
                const setupMessage = {
                    setup: {
                        model: 'models/gemini-2.5-flash-native-audio-preview-12-2025',
                        generationConfig: {
                            responseModalities: ['AUDIO', 'TEXT'],
                            speechConfig: {
                                voiceConfig: {
                                    prebuiltVoiceConfig: {
                                        voiceName: 'Puck' // Friendly AI tutor voice
                                    }
                                }
                            }
                        },
                        systemInstruction: {
                            parts: [{
                                text: systemInstruction
                            }]
                        },
                        tools: [
                            {
                                functionDeclarations: [
                                    {
                                        name: 'fetch_homework_context',
                                        description: 'Retrieves the homework question and context from the current study session',
                                        parameters: {
                                            type: 'OBJECT',
                                            properties: {
                                                sessionId: {
                                                    type: 'STRING',
                                                    description: 'The session ID to retrieve context from'
                                                }
                                            },
                                            required: ['sessionId']
                                        }
                                    },
                                    {
                                        name: 'search_archived_conversations',
                                        description: 'Searches previous study conversations for relevant information',
                                        parameters: {
                                            type: 'OBJECT',
                                            properties: {
                                                query: {
                                                    type: 'STRING',
                                                    description: 'Search query for archived conversations'
                                                },
                                                subject: {
                                                    type: 'STRING',
                                                    description: 'Subject filter (optional)'
                                                }
                                            },
                                            required: ['query']
                                        }
                                    }
                                ]
                            }
                        ]
                    }
                };

                // Send setup to Gemini
                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(setupMessage));
                    logger.info({ userId }, 'Setup message sent to Gemini');
                } else {
                    throw new Error('Gemini connection not ready');
                }
            }

            /**
             * HANDLER: Audio Chunk
             * Translates iOS audio to official realtimeInput message
             * NOTE: Input audio is natively 16kHz (output is 24kHz)
             */
            function handleAudioChunk(data) {
                const { audio } = data; // Base64 encoded audio

                // Build official BidiGenerateContentRealtimeInput message
                const realtimeInput = {
                    realtimeInput: {
                        audio: {
                            data: audio,
                            mimeType: 'audio/pcm;rate=16000' // Input is 16kHz (output is 24kHz)
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
             * HANDLER: Text Message
             * Translates iOS text to official clientContent message
             */
            function handleTextMessage(data) {
                const { text } = data;

                // Build official BidiGenerateContentClientContent message
                const clientContent = {
                    clientContent: {
                        turns: [{
                            role: 'user',
                            parts: [{
                                text: text
                            }]
                        }],
                        turnComplete: true
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
             * Sends activity end signal to stop AI response
             */
            function handleInterrupt() {
                logger.info({ userId }, 'User interrupted AI');

                // Send activity end to stop generation
                const activityEnd = {
                    realtimeInput: {
                        activityEnd: {}
                    }
                };

                if (geminiSocket && geminiSocket.readyState === WebSocket.OPEN) {
                    geminiSocket.send(JSON.stringify(activityEnd));
                }

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
            function handleGeminiMessage(message) {
                logger.debug({ messageType: Object.keys(message)[0] }, 'Received Gemini message');

                // Handle setupComplete
                if (message.setupComplete) {
                    isSetupComplete = true;
                    logger.info({ userId }, 'Gemini setup complete');

                    clientSocket.send(JSON.stringify({
                        type: 'session_ready',
                        sessionId: sessionId
                    }));
                }

                // Handle serverContent (AI response)
                if (message.serverContent) {
                    const { modelTurn, generationComplete, turnComplete, interrupted } = message.serverContent;

                    // Send text transcription
                    if (modelTurn && modelTurn.parts) {
                        for (const part of modelTurn.parts) {
                            if (part.text) {
                                clientSocket.send(JSON.stringify({
                                    type: 'text_chunk',
                                    text: part.text
                                }));
                            }

                            // Send audio chunk
                            if (part.inlineData && part.inlineData.mimeType.startsWith('audio/')) {
                                clientSocket.send(JSON.stringify({
                                    type: 'audio_chunk',
                                    data: part.inlineData.data // Base64 audio
                                }));
                            }
                        }
                    }

                    // Send input transcription (user's speech recognized)
                    if (message.serverContent.inputTranscription) {
                        clientSocket.send(JSON.stringify({
                            type: 'user_transcription',
                            text: message.serverContent.inputTranscription.text
                        }));
                    }

                    // Signal turn complete
                    if (turnComplete) {
                        clientSocket.send(JSON.stringify({
                            type: 'turn_complete'
                        }));

                        // Store AI response
                        if (modelTurn && modelTurn.parts) {
                            const responseText = modelTurn.parts
                                .filter(p => p.text)
                                .map(p => p.text)
                                .join(' ');
                            if (responseText) {
                                storeMessage('assistant', responseText);
                            }
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
                if (message.toolCall) {
                    handleToolCall(message.toolCall);
                }

                // Handle toolCallCancellation
                if (message.toolCallCancellation) {
                    const { ids } = message.toolCallCancellation;
                    logger.info({ ids }, 'Tool calls cancelled by server');

                    // Notify iOS that tool calls were cancelled
                    clientSocket.send(JSON.stringify({
                        type: 'tool_call_cancelled',
                        ids: ids
                    }));

                    // TODO: Attempt to undo side effects if possible
                }

                // Handle goAway (server requests disconnect)
                if (message.goAway) {
                    const { timeLeft } = message.goAway;
                    logger.warn({ timeLeft }, 'Server sent goAway - will disconnect soon');

                    // Notify iOS to prepare for reconnection
                    clientSocket.send(JSON.stringify({
                        type: 'go_away',
                        timeLeft: timeLeft,
                        message: 'Server requesting disconnect - please reconnect'
                    }));

                    // Close connection gracefully after a brief delay
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
                if (message.sessionResumptionUpdate) {
                    const { newHandle, resumable } = message.sessionResumptionUpdate;
                    logger.debug({ newHandle, resumable }, 'Session resumption state update');

                    // Store resumption token if available (for future reconnection)
                    if (resumable && newHandle) {
                        // TODO: Store newHandle in database for session resumption
                        logger.info({ userId, sessionId, newHandle }, 'Session resumption token available');
                    }
                }

                // Handle usage metadata
                if (message.usageMetadata) {
                    logger.debug({ usage: message.usageMetadata }, 'Token usage');
                }
            }

            /**
             * Handle function calls from Gemini
             */
            async function handleToolCall(toolCall) {
                const { functionCalls } = toolCall;

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
                        const toolResponse = {
                            toolResponse: {
                                functionResponses: [{
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
                            toolResponse: {
                                functionResponses: [{
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
            en: `You are an expert AI tutor specializing in ${subjectContext}. Your teaching philosophy:

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

            'zh-Hans': `你是一位专精于${subjectContext}的AI导师。教学理念：

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

            'zh-Hant': `你是一位專精於${subjectContext}的AI導師。教學理念：

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
