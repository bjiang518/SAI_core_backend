/**
 * Session Helper Utilities
 * Database operations for session management
 * Extracted from ai-proxy.js for reusability
 */

const PIIMasking = require('../../../../utils/pii-masking');

class SessionHelper {
  constructor(fastify) {
    this.fastify = fastify;
  }

  /**
   * Get session information from database
   * @param {string} sessionId - Session ID
   * @returns {Promise<Object|null>} - Session info or null
   */
  async getSessionFromDatabase(sessionId) {
    try {
      const { db } = require('../../../../utils/railway-database');

      // First try the sessions table
      const sessionQuery = `
        SELECT s.*, u.email, u.name as user_name
        FROM sessions s
        LEFT JOIN users u ON s.user_id = u.id
        WHERE s.id = $1
      `;

      const result = await db.query(sessionQuery, [sessionId]);
      if (result.rows.length > 0) {
        return result.rows[0];
      }

      // Fallback: create minimal session info if not found
      // This handles cases where sessions are created via AI Engine but not in our DB
      // Use a valid UUID format for user_id to avoid database errors
      return {
        id: sessionId,
        user_id: '00000000-0000-0000-0000-000000000000', // Valid UUID format for unknown user
        session_type: 'conversation',
        subject: 'general',
        created_at: new Date()
      };
    } catch (error) {
      this.fastify.log.error('Database session lookup error:', error);
      return null;
    }
  }

  /**
   * Store conversation messages in database
   * @param {string} sessionId - Session ID
   * @param {string} userId - User ID
   * @param {string} userMessage - User's message
   * @param {Object} aiResponse - AI response object with response, tokensUsed, service
   */
  async storeConversation(sessionId, userId, userMessage, aiResponse, imageData = null) {
    try {
      const { db } = require('../../../../utils/railway-database');

      // ✅ NEW: Prepare user message data (include image if present)
      const userMessageData = imageData ? {
        hasImage: true,
        image_data: imageData
      } : null;

      // Store user message
      await db.addConversationMessage({
        userId: userId,
        questionId: null, // This is session-based, not question-based
        sessionId: sessionId,
        messageType: 'user',
        messageText: userMessage,
        messageData: userMessageData,  // ✅ NEW: Store image data if present
        tokensUsed: 0
      });

      // Store AI response
      await db.addConversationMessage({
        userId: userId,
        questionId: null,
        sessionId: sessionId,
        messageType: 'assistant',
        messageText: aiResponse.response,
        messageData: {
          tokensUsed: aiResponse.tokensUsed,
          service: aiResponse.service,
          compressed: aiResponse.compressed
        },
        tokensUsed: aiResponse.tokensUsed || 0
      });

      const imageIndicator = imageData ? ' (with image)' : '';
      this.fastify.log.info(`💾 Conversation stored for session: ${PIIMasking.maskUserId(sessionId)}${imageIndicator}`);
    } catch (error) {
      this.fastify.log.error('Error storing conversation:', error);
      // Don't fail the request if storage fails
    }
  }

  /**
   * Analyze conversation for archiving
   * @param {Array} conversationHistory - Array of conversation messages
   * @param {Object} sessionInfo - Session information
   * @returns {Promise<Object>} - Analysis results with summary, topics, etc.
   */
  async analyzeConversationForArchiving(conversationHistory, sessionInfo) {
    this.fastify.log.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
    this.fastify.log.info(`🤖 [AI ANALYSIS] Starting conversation analysis for archiving`);
    this.fastify.log.info(`   • Subject: ${sessionInfo.subject || 'general'}`);
    this.fastify.log.info(`   • Message count: ${conversationHistory.length}`);
    this.fastify.log.info(`   • OpenAI API Key present: ${!!process.env.OPENAI_API_KEY}`);
    this.fastify.log.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);

    try {
      if (!process.env.OPENAI_API_KEY) {
        this.fastify.log.warn(`⚠️ [AI ANALYSIS] OpenAI API key not configured - using basic analysis`);
        const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo);
        return { ...basicAnalysis, embedding: null };
      }

      const openai = require('openai');
      const client = new openai({ apiKey: process.env.OPENAI_API_KEY });

      // Build conversation text for analysis
      let conversationText = '';
      let totalTokens = 0;
      conversationHistory.forEach(msg => {
        const speaker = msg.message_type === 'user' ? 'Student' : 'StudyAI';
        conversationText += `${speaker}: ${msg.message_text}\n\n`;
        totalTokens += msg.tokens_used || 0;
      });

      this.fastify.log.info(`📝 [AI ANALYSIS] Built conversation text:`);
      this.fastify.log.info(`   • Length: ${conversationText.length} characters`);
      this.fastify.log.info(`   • Total tokens: ${totalTokens}`);
      this.fastify.log.info(`   • Preview: ${conversationText.substring(0, 200)}...`);

      const language = sessionInfo.language || 'en';
      const languageInstruction = language !== 'en'
        ? `\n\nIMPORTANT: Respond entirely in ${language === 'zh-Hans' ? 'Simplified Chinese (简体中文)' : language === 'zh-Hant' ? 'Traditional Chinese (繁體中文)' : language}. All text values in the JSON must be in that language.`
        : '';

      // Generate both analysis and embedding in parallel
      this.fastify.log.info(`🔄 [AI ANALYSIS] Calling OpenAI API...`);
      const [analysisCompletion, embeddingResponse] = await Promise.all([
        client.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `You are an AI assistant that analyzes educational conversations. Extract:
1. A concise summary (max 10 words) that captures the SPECIFIC conversation content
2. Key topics discussed (as array)
3. Learning outcomes achieved (as array)
4. Estimated conversation duration in minutes

Respond in JSON format: {"summary": "...", "keyTopics": [...], "learningOutcomes": [...], "estimatedDuration": number}

Summary guidelines:
- Max 10 words, be direct and concise
- Start immediately with the topic/concept - NO introductory phrases
- REMOVE words like "Student asked", "Explaining", "Solving", "Understanding", "Help with"
- Just state the CORE TOPIC directly

Good examples (direct and concise):
- "Math joke about equal signs"
- "Photosynthesis process and ATP production"
- "Quadratic equations using factoring method"
- "Grammar: difference between their/there/they're"
- "Python for loop syntax errors"
- "Chemical question about gas law"

Bad examples (too wordy or generic):
- "Student asked for math joke about equal signs" ❌ (remove "Student asked")
- "Explaining photosynthesis process" ❌ (remove "Explaining")
- "Math - interactive learning session" ❌ (too generic)
- "General - Q&A session" ❌ (too generic)

Be direct: state the topic, not the action.${languageInstruction}`
            },
            {
              role: 'user',
              content: `Analyze this educational conversation about ${sessionInfo.subject || 'academic topics'} with ${conversationHistory.length} messages:\n\n${conversationText}`
            }
          ],
          max_tokens: 500,
          temperature: 0.3,
        }),

        // Generate semantic embedding for the conversation
        client.embeddings.create({
          model: 'text-embedding-3-small',
          input: `Subject: ${sessionInfo.subject || 'general'}\n\nConversation Summary:\n${conversationText.substring(0, 8000)}`, // Truncate to fit embedding limits
          encoding_format: 'float'
        })
      ]);

      this.fastify.log.info(`✅ [AI ANALYSIS] OpenAI API call successful`);
      this.fastify.log.info(`   • Analysis response received: ${!!analysisCompletion.choices[0]?.message?.content}`);
      this.fastify.log.info(`   • Embedding received: ${!!embeddingResponse.data[0]?.embedding}`);

      try {
        const rawContent = analysisCompletion.choices[0]?.message?.content || '{}';
        this.fastify.log.info(`📄 [AI ANALYSIS] Parsing response: ${rawContent.substring(0, 300)}...`);

        // ✅ FIX: Strip markdown code fences before parsing
        // OpenAI often returns JSON wrapped in ```json ... ```
        let cleanedContent = rawContent.trim();
        if (cleanedContent.startsWith('```')) {
          // Remove leading ```json or ``` and trailing ```
          cleanedContent = cleanedContent
            .replace(/^```(?:json)?\s*\n?/, '')  // Remove opening fence
            .replace(/\n?```\s*$/, '');          // Remove closing fence
          this.fastify.log.info(`🧹 [AI ANALYSIS] Stripped markdown code fences`);
        }

        const analysis = JSON.parse(cleanedContent);
        const embedding = embeddingResponse.data[0]?.embedding;

        this.fastify.log.info(`✨ [AI ANALYSIS] Successfully parsed analysis:`);
        this.fastify.log.info(`   • Summary: "${analysis.summary}"`);
        this.fastify.log.info(`   • Key Topics: ${JSON.stringify(analysis.keyTopics)}`);
        this.fastify.log.info(`   • Learning Outcomes: ${JSON.stringify(analysis.learningOutcomes)}`);
        this.fastify.log.info(`   • Duration: ${analysis.estimatedDuration} minutes`);
        this.fastify.log.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);

        return {
          summary: analysis.summary || 'Conversation analysis unavailable',
          keyTopics: analysis.keyTopics || [],
          learningOutcomes: analysis.learningOutcomes || [],
          estimatedDuration: analysis.estimatedDuration || Math.ceil(conversationHistory.length * 0.5),
          totalTokens: totalTokens,
          embedding: embedding || null
        };
      } catch (parseError) {
        // Fallback if JSON parsing fails but keep embedding
        this.fastify.log.error(`❌ [AI ANALYSIS] JSON parsing failed:`, parseError);
        this.fastify.log.info(`   • Raw content: ${analysisCompletion.choices[0]?.message?.content}`);
        const embedding = embeddingResponse.data[0]?.embedding;
        const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo, totalTokens);
        this.fastify.log.warn(`⚠️ [AI ANALYSIS] Using basic analysis due to parse error`);
        return { ...basicAnalysis, embedding: embedding || null };
      }
    } catch (error) {
      this.fastify.log.error('❌ [AI ANALYSIS] Conversation analysis error:', error);
      this.fastify.log.error(`   • Error type: ${error.constructor.name}`);
      this.fastify.log.error(`   • Error message: ${error.message}`);
      if (error.response) {
        this.fastify.log.error(`   • API response status: ${error.response.status}`);
        this.fastify.log.error(`   • API response data: ${JSON.stringify(error.response.data)}`);
      }
      const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo);
      this.fastify.log.warn(`⚠️ [AI ANALYSIS] Using basic analysis due to API error`);
      this.fastify.log.info(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
      return { ...basicAnalysis, embedding: null };
    }
  }

  /**
   * Generate basic analysis when OpenAI is not available
   * @param {Array} conversationHistory - Conversation messages
   * @param {Object} sessionInfo - Session information
   * @param {number} totalTokens - Total tokens used
   * @returns {Object} - Basic analysis
   */
  generateBasicAnalysis(conversationHistory, sessionInfo, totalTokens = 0) {
    this.fastify.log.warn(`⚠️ [FALLBACK] Generating basic analysis without OpenAI`);
    this.fastify.log.info(`   • Message count: ${conversationHistory.length}`);

    // ✅ TRY TO EXTRACT MEANINGFUL SUMMARY FROM CONVERSATION
    let summary = `${sessionInfo.subject || 'General'} - interactive learning session`;

    try {
      // Get first user message (student's initial question)
      const firstUserMessage = conversationHistory.find(msg => msg.message_type === 'user');

      if (firstUserMessage && firstUserMessage.message_text) {
        const questionText = firstUserMessage.message_text.trim();

        // Extract first 10 words from user's question
        const words = questionText.split(/\s+/).slice(0, 10);
        const shortQuestion = words.join(' ');

        // Create summary from actual question
        if (shortQuestion.length > 10) {
          summary = shortQuestion + (words.length >= 10 ? '...' : '');
          this.fastify.log.info(`   ✅ Created summary from user question: "${summary}"`);
        } else {
          this.fastify.log.warn(`   ⚠️ User question too short, using generic summary`);
        }
      } else {
        this.fastify.log.warn(`   ⚠️ No user messages found, using generic summary`);
      }
    } catch (error) {
      this.fastify.log.error(`   ❌ Error extracting summary: ${error.message}`);
    }

    return {
      summary: summary,
      keyTopics: [sessionInfo.subject || 'General Discussion'],
      learningOutcomes: ['Interactive learning session completed'],
      estimatedDuration: Math.ceil(conversationHistory.length * 0.5), // Estimate 30 seconds per message
      totalTokens: totalTokens
    };
  }
}

module.exports = SessionHelper;
