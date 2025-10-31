/**
 * PII Masking Utility
 * Provides functions to mask sensitive information in logs
 * Ensures GDPR/CCPA compliance by preventing PII exposure
 */

class PIIMasking {
  /**
   * Mask user ID - show only first 8 characters
   * @param {string} userId - User ID to mask
   * @returns {string} Masked user ID
   */
  static maskUserId(userId) {
    if (!userId || typeof userId !== 'string') return '[no-user]';
    if (userId.length <= 8) return userId;
    return `${userId.substring(0, 8)}...`;
  }

  /**
   * Mask email address - show only first 2 chars before @ and domain
   * @param {string} email - Email to mask
   * @returns {string} Masked email
   */
  static maskEmail(email) {
    if (!email || typeof email !== 'string') return '[no-email]';
    const parts = email.split('@');
    if (parts.length !== 2) return '***@***';
    const localPart = parts[0];
    const domain = parts[1];
    return `${localPart.substring(0, 2)}***@${domain}`;
  }

  /**
   * Truncate long text - show only first N characters
   * @param {string} text - Text to truncate
   * @param {number} maxLength - Maximum length (default 100)
   * @returns {string} Truncated text
   */
  static truncateText(text, maxLength = 100) {
    if (!text || typeof text !== 'string') return '[no-text]';
    if (text.length <= maxLength) return text;
    return `${text.substring(0, maxLength)}... [truncated ${text.length - maxLength} chars]`;
  }

  /**
   * Mask sensitive object properties before logging
   * @param {object} obj - Object to mask
   * @param {array} sensitiveKeys - Keys to mask (default: common PII fields)
   * @returns {object} Masked object
   */
  static maskObject(obj, sensitiveKeys = ['password', 'token', 'api_key', 'email', 'phone', 'ssn']) {
    if (!obj || typeof obj !== 'object') return obj;

    const masked = { ...obj };

    // Recursively mask sensitive keys
    for (const key in masked) {
      // Check if this key is sensitive
      const isSensitive = sensitiveKeys.some(sensitiveKey =>
        key.toLowerCase().includes(sensitiveKey.toLowerCase())
      );

      if (isSensitive) {
        masked[key] = '[REDACTED]';
      } else if (typeof masked[key] === 'object' && masked[key] !== null) {
        // Recursively mask nested objects
        masked[key] = this.maskObject(masked[key], sensitiveKeys);
      } else if (typeof masked[key] === 'string' && masked[key].length > 500) {
        // Truncate very long strings
        masked[key] = this.truncateText(masked[key], 500);
      }
    }

    return masked;
  }

  /**
   * Mask conversation content - show only metadata, not content
   * @param {object} conversation - Conversation object
   * @returns {object} Masked conversation
   */
  static maskConversation(conversation) {
    if (!conversation) return null;

    return {
      id: conversation.id ? this.maskUserId(conversation.id) : '[no-id]',
      user_id: conversation.user_id ? this.maskUserId(conversation.user_id) : '[no-user]',
      subject: conversation.subject || '[no-subject]',
      message_count: conversation.message_count || 0,
      created_at: conversation.created_at || '[no-date]',
      // Don't log conversation_content - it's PII
      conversation_content: '[REDACTED]'
    };
  }

  /**
   * Mask AI request payload for logging
   * @param {object} payload - AI request payload
   * @returns {object} Masked payload
   */
  static maskAIPayload(payload) {
    if (!payload) return null;

    return {
      question: payload.question ? this.truncateText(payload.question, 100) : '[no-question]',
      subject: payload.subject || '[no-subject]',
      student_id: payload.student_id ? this.maskUserId(payload.student_id) : '[no-student]',
      context: payload.context ? {
        session_id: payload.context.session_id ? this.maskUserId(payload.context.session_id) : '[no-session]',
        has_conversation_history: payload.context.has_conversation_history || false
      } : null,
      // Don't log full conversation history or prompts
      conversation_history: payload.conversation_history ? `[${payload.conversation_history.length} messages]` : '[]'
    };
  }

  /**
   * Mask AI response for logging
   * @param {object} response - AI response
   * @returns {object} Masked response
   */
  static maskAIResponse(response) {
    if (!response) return null;

    return {
      success: response.success || false,
      // Don't log full AI response content
      data: response.data ? {
        response_type: response.data.response_type || '[unknown]',
        tokens_used: response.data.tokens_used || 0,
        compressed: response.data.compressed || false,
        // Truncate actual response
        response: '[REDACTED - see database for full response]'
      } : null,
      error: response.error || null
    };
  }

  /**
   * Create a safe log message with masked PII
   * @param {string} message - Log message
   * @param {object} data - Data to include (will be masked)
   * @returns {string} Safe log message
   */
  static createSafeLogMessage(message, data = null) {
    if (!data) return message;

    const maskedData = this.maskObject(data);
    return `${message} ${JSON.stringify(maskedData, null, 2)}`;
  }
}

module.exports = PIIMasking;
