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
    try {
      if (!process.env.OPENAI_API_KEY) {
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

      // Generate both analysis and embedding in parallel
      const [analysisCompletion, embeddingResponse] = await Promise.all([
        client.chat.completions.create({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `You are an AI assistant that analyzes educational conversations. Extract:
1. A 2-3 paragraph summary
2. Key topics discussed (as array)
3. Learning outcomes achieved (as array)
4. Estimated conversation duration in minutes

Respond in JSON format: {"summary": "...", "keyTopics": [...], "learningOutcomes": [...], "estimatedDuration": number}`
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

      try {
        const analysis = JSON.parse(analysisCompletion.choices[0]?.message?.content || '{}');
        const embedding = embeddingResponse.data[0]?.embedding;

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
        const embedding = embeddingResponse.data[0]?.embedding;
        const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo, totalTokens);
        return { ...basicAnalysis, embedding: embedding || null };
      }
    } catch (error) {
      this.fastify.log.error('Conversation analysis error:', error);
      const basicAnalysis = this.generateBasicAnalysis(conversationHistory, sessionInfo);
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
    return {
      summary: `Educational conversation about ${sessionInfo.subject || 'academic topics'} with ${conversationHistory.length} messages exchanged between student and AI tutor.`,
      keyTopics: [sessionInfo.subject || 'General Discussion'],
      learningOutcomes: ['Interactive learning session completed'],
      estimatedDuration: Math.ceil(conversationHistory.length * 0.5), // Estimate 30 seconds per message
      totalTokens: totalTokens
    };
  }
}

module.exports = SessionHelper;
