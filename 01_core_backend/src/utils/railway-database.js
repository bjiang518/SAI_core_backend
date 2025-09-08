/**
 * Railway PostgreSQL Database Configuration
 * Replaces Supabase with Railway-hosted PostgreSQL
 */

const { Pool } = require('pg');
const crypto = require('crypto');

// Create PostgreSQL connection pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  max: 20, // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // Close idle clients after 30 seconds
  connectionTimeoutMillis: 10000, // Return an error after 10 seconds if connection could not be established
});

// Test connection on startup
pool.on('connect', (client) => {
  console.log('✅ New PostgreSQL client connected');
});

pool.on('error', (err, client) => {
  console.error('❌ Unexpected error on idle PostgreSQL client', err);
  process.exit(-1);
});

// Database utility functions
const db = {
  /**
   * Execute a query with parameters
   */
  async query(text, params = []) {
    const start = Date.now();
    try {
      const result = await pool.query(text, params);
      const duration = Date.now() - start;
      console.log(`📊 Query executed in ${duration}ms: ${text.substring(0, 50)}...`);
      return result;
    } catch (error) {
      console.error('❌ Database query error:', error);
      throw error;
    }
  },

  /**
   * Get a client from the pool for transactions
   */
  async getClient() {
    return await pool.connect();
  },

  /**
   * Execute multiple queries in a transaction
   */
  async transaction(callback) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const result = await callback(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  },

  /**
   * User Management Functions
   */

  /**
   * Create or update user (for Google/Apple OAuth)
   */
  async createOrUpdateUser(userData) {
    const {
      email,
      name,
      profileImageUrl,
      authProvider,
      googleId,
      appleId
    } = userData;

    const query = `
      INSERT INTO users (
        email, 
        name, 
        profile_image_url, 
        auth_provider, 
        google_id, 
        apple_id,
        email_verified,
        last_login_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
      ON CONFLICT (email) 
      DO UPDATE SET 
        name = EXCLUDED.name,
        profile_image_url = EXCLUDED.profile_image_url,
        google_id = COALESCE(EXCLUDED.google_id, users.google_id),
        apple_id = COALESCE(EXCLUDED.apple_id, users.apple_id),
        last_login_at = NOW(),
        updated_at = NOW()
      RETURNING *
    `;

    const values = [
      email,
      name,
      profileImageUrl,
      authProvider,
      googleId,
      appleId,
      true // email_verified for OAuth providers
    ];

    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Create user session token
   */
  async createUserSession(userId, deviceInfo = null, ipAddress = null) {
    // Generate secure token
    const token = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    
    // Token expires in 30 days
    const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

    const query = `
      INSERT INTO user_sessions (
        user_id, 
        token_hash, 
        expires_at, 
        device_info, 
        ip_address
      ) VALUES ($1, $2, $3, $4, $5)
      RETURNING id
    `;

    const values = [
      userId,
      tokenHash,
      expiresAt,
      deviceInfo ? JSON.stringify(deviceInfo) : null,
      ipAddress
    ];

    const result = await this.query(query, values);
    return {
      sessionId: result.rows[0].id,
      token: token,
      expiresAt: expiresAt
    };
  },

  /**
   * Verify user session token
   */
  async verifyUserSession(token) {
    const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
    
    const query = `
      SELECT 
        us.id as session_id,
        us.user_id,
        us.expires_at,
        u.email,
        u.name,
        u.profile_image_url,
        u.auth_provider
      FROM user_sessions us
      JOIN users u ON us.user_id = u.id
      WHERE us.token_hash = $1 
        AND us.expires_at > NOW()
        AND u.is_active = true
    `;

    const result = await this.query(query, [tokenHash]);
    return result.rows[0];
  },

  /**
   * Get user by email
   */
  async getUserByEmail(email) {
    const query = `
      SELECT * FROM users 
      WHERE email = $1 AND is_active = true
    `;
    
    const result = await this.query(query, [email]);
    return result.rows[0];
  },

  /**
   * Create new user (for email/password registration)
   */
  async createUser(userData) {
    const {
      email,
      name,
      password,
      authProvider = 'email'
    } = userData;

    // Hash the password using bcryptjs
    const bcrypt = require('bcryptjs');
    const saltRounds = 12;
    const passwordHash = await bcrypt.hash(password, saltRounds);

    const query = `
      INSERT INTO users (
        email, 
        name, 
        password_hash, 
        auth_provider, 
        email_verified,
        last_login_at
      ) VALUES ($1, $2, $3, $4, $5, NOW())
      RETURNING *
    `;

    const values = [
      email,
      name,
      passwordHash,
      authProvider,
      false // email_verified - false for email/password auth until verified
    ];

    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Verify user credentials (for email/password login)
   */
  async verifyUserCredentials(email, password) {
    const user = await this.getUserByEmail(email);
    if (!user || !user.password_hash) {
      return null; // User not found or no password set (OAuth user)
    }

    // Verify password using bcryptjs
    const bcrypt = require('bcryptjs');
    const isValidPassword = await bcrypt.compare(password, user.password_hash);
    
    if (isValidPassword) {
      // Update last login time
      await this.query(
        'UPDATE users SET last_login_at = NOW() WHERE id = $1',
        [user.id]
      );
      return user;
    }
    
    return null; // Invalid password
  },

  /**
   * Get user by ID
   */
  async getUserById(userId) {
    const query = `
      SELECT * FROM users 
      WHERE id = $1 AND is_active = true
    `;
    
    const result = await this.query(query, [userId]);
    return result.rows[0];
  },
  /**
   * Profile Management Functions (for compatibility with existing Supabase code)
   */

  /**
   * Create or update user profile
   */
  async createOrUpdateProfile(profileData) {
    const {
      email,
      role = 'student',
      parentId,
      firstName,
      lastName,
      gradeLevel,
      school
    } = profileData;

    const query = `
      INSERT INTO profiles (
        email, 
        role, 
        parent_id, 
        first_name, 
        last_name, 
        grade_level, 
        school
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      ON CONFLICT (email) 
      DO UPDATE SET 
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        grade_level = EXCLUDED.grade_level,
        school = EXCLUDED.school,
        updated_at = NOW()
      RETURNING *
    `;

    const values = [email, role, parentId, firstName, lastName, gradeLevel, school];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get profile by email
   */
  async getProfileByEmail(email) {
    const query = `
      SELECT * FROM profiles 
      WHERE email = $1
    `;
    
    const result = await this.query(query, [email]);
    return result.rows[0];
  },

  /**
   * Session Management Functions
   */

  /**
   * Create new study session
   */
  async createSession(sessionData) {
    const {
      userId,
      parentId,
      sessionType = 'homework',
      title,
      description,
      subject
    } = sessionData;

    const query = `
      INSERT INTO sessions (
        user_id, 
        parent_id, 
        session_type, 
        title, 
        description, 
        subject
      ) VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `;

    const values = [userId, parentId, sessionType, title, description, subject];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get sessions for user
   */
  async getUserSessions(userId, limit = 20, offset = 0) {
    const query = `
      SELECT * FROM sessions 
      WHERE user_id = $1 
      ORDER BY created_at DESC 
      LIMIT $2 OFFSET $3
    `;
    
    const result = await this.query(query, [userId, limit, offset]);
    return result.rows;
  },

  /**
   * End session
   */
  async endSession(sessionId) {
    const query = `
      UPDATE sessions 
      SET 
        end_time = NOW(),
        status = 'completed',
        updated_at = NOW()
      WHERE id = $1
      RETURNING *
    `;
    
    const result = await this.query(query, [sessionId]);
    return result.rows[0];
  },

  /**
   * Question Management Functions
   */

  /**
   * Create new question
   */
  async createQuestion(questionData) {
    const {
      userId,
      sessionId,
      imageData,
      imageUrl,
      questionText,
      subject,
      topic,
      difficultyLevel = 3,
      aiSolution,
      explanation,
      confidenceScore = 0.0,
      processingTime = 0.0
    } = questionData;

    const query = `
      INSERT INTO questions (
        user_id, 
        session_id, 
        image_data, 
        image_url, 
        question_text, 
        subject, 
        topic, 
        difficulty_level, 
        ai_solution, 
        explanation, 
        confidence_score, 
        processing_time
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
      RETURNING *
    `;

    const values = [
      userId, sessionId, imageData, imageUrl, questionText, 
      subject, topic, difficultyLevel, JSON.stringify(aiSolution), 
      explanation, confidenceScore, processingTime
    ];
    
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get questions for user
   */
  async getUserQuestions(userId, limit = 20, offset = 0) {
    const query = `
      SELECT * FROM questions 
      WHERE user_id = $1 
      ORDER BY created_at DESC 
      LIMIT $2 OFFSET $3
    `;
    
    const result = await this.query(query, [userId, limit, offset]);
    return result.rows;
  },

  /**
   * Get question by ID
   */
  async getQuestionById(questionId) {
    const query = `
      SELECT * FROM questions 
      WHERE id = $1
    `;
    
    const result = await this.query(query, [questionId]);
    return result.rows[0];
  },

  /**
   * Delete question
   */
  async deleteQuestion(questionId, userId) {
    const query = `
      DELETE FROM questions 
      WHERE id = $1 AND user_id = $2
      RETURNING id
    `;
    
    const result = await this.query(query, [questionId, userId]);
    return result.rows[0];
  },

  /**
   * Conversation Management Functions
   */

  /**
   * Add conversation message
   */
  async addConversationMessage(messageData) {
    const {
      userId,
      questionId,
      sessionId,
      messageType,
      messageText,
      messageData: msgData,
      tokensUsed = 0
    } = messageData;

    const query = `
      INSERT INTO conversations (
        user_id, 
        question_id, 
        session_id, 
        message_type, 
        message_text, 
        message_data, 
        tokens_used
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `;

    const values = [
      userId, questionId, sessionId, messageType, 
      messageText, msgData ? JSON.stringify(msgData) : null, tokensUsed
    ];
    
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get conversation history
   */
  async getConversationHistory(questionIdOrSessionId, limit = 50) {
    // Support both question-based and session-based conversations
    const query = `
      SELECT * FROM conversations 
      WHERE (question_id = $1 OR session_id = $1)
      ORDER BY created_at ASC 
      LIMIT $2
    `;
    
    const result = await this.query(query, [questionIdOrSessionId, limit]);
    return result.rows;
  },

  /**
   * Evaluation Management Functions
   */

  /**
   * Create evaluation
   */
  async createEvaluation(evaluationData) {
    const {
      sessionId,
      questionId,
      userId,
      studentAnswer,
      aiFeedback,
      score,
      maxScore = 100.0,
      timeSpent,
      isCorrect,
      rubric
    } = evaluationData;

    const query = `
      INSERT INTO evaluations (
        session_id, 
        question_id, 
        user_id, 
        student_answer, 
        ai_feedback, 
        score, 
        max_score, 
        time_spent, 
        is_correct, 
        rubric
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const values = [
      sessionId, questionId, userId, studentAnswer, 
      aiFeedback ? JSON.stringify(aiFeedback) : null, 
      score, maxScore, timeSpent, isCorrect, 
      rubric ? JSON.stringify(rubric) : null
    ];
    
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get evaluations for session
   */
  async getSessionEvaluations(sessionId) {
    const query = `
      SELECT * FROM evaluations 
      WHERE session_id = $1 
      ORDER BY created_at DESC
    `;
    
    const result = await this.query(query, [sessionId]);
    return result.rows;
  },

  /**
   * Progress Management Functions
   */

  /**
   * Update user progress
   */
  async updateProgress(progressData) {
    const {
      userId,
      subject,
      topic,
      skillLevel,
      masteryLevel,
      questionsAttempted,
      questionsCorrect,
      timeSpent,
      streakCount
    } = progressData;

    const query = `
      INSERT INTO progress (
        user_id, 
        subject, 
        topic, 
        skill_level, 
        mastery_level, 
        questions_attempted, 
        questions_correct, 
        total_time_spent, 
        last_practiced_at, 
        streak_count
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), $9)
      ON CONFLICT (user_id, subject, topic) 
      DO UPDATE SET 
        skill_level = EXCLUDED.skill_level,
        mastery_level = EXCLUDED.mastery_level,
        questions_attempted = progress.questions_attempted + EXCLUDED.questions_attempted,
        questions_correct = progress.questions_correct + EXCLUDED.questions_correct,
        total_time_spent = progress.total_time_spent + EXCLUDED.total_time_spent,
        last_practiced_at = NOW(),
        streak_count = EXCLUDED.streak_count,
        updated_at = NOW()
      RETURNING *
    `;

    const values = [
      userId, subject, topic, skillLevel, masteryLevel, 
      questionsAttempted, questionsCorrect, timeSpent, streakCount
    ];
    
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get user progress
   */
  async getUserProgress(userId, subject = null) {
    let query = `
      SELECT * FROM progress 
      WHERE user_id = $1
    `;
    let values = [userId];

    if (subject) {
      query += ` AND subject = $2`;
      values.push(subject);
    }

    query += ` ORDER BY last_practiced_at DESC`;
    
    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Session Summary Management Functions
   */

  /**
   * Create session summary
   */
  async createSessionSummary(summaryData) {
    const {
      sessionId,
      userId,
      totalQuestions,
      questionsCorrect,
      totalTimeSpent,
      averageScore,
      subjectsCovered,
      keyTopics,
      areasForImprovement,
      summaryData: sumData
    } = summaryData;

    const query = `
      INSERT INTO sessions_summaries (
        session_id, 
        user_id, 
        total_questions, 
        questions_correct, 
        total_time_spent, 
        average_score, 
        subjects_covered, 
        key_topics, 
        areas_for_improvement, 
        summary_data
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const values = [
      sessionId, userId, totalQuestions, questionsCorrect, totalTimeSpent,
      averageScore, subjectsCovered, keyTopics, areasForImprovement,
      sumData ? JSON.stringify(sumData) : null
    ];
    
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get session summary
   */
  async getSessionSummary(sessionId) {
    const query = `
      SELECT * FROM sessions_summaries 
      WHERE session_id = $1
    `;
    
    const result = await this.query(query, [sessionId]);
    return result.rows[0];
  },

  /**
   * Archive Session Management (Legacy compatibility for homework/questions)
   */
  async archiveSession(sessionData) {
    const {
      userId,
      subject,
      title,
      originalImageUrl,
      thumbnailUrl,
      aiParsingResult,
      processingTime,
      overallConfidence,
      studentAnswers,
      notes
    } = sessionData;

    const query = `
      INSERT INTO archived_sessions (
        user_id, 
        subject, 
        title, 
        original_image_url, 
        thumbnail_url,
        ai_parsing_result, 
        processing_time, 
        overall_confidence,
        student_answers,
        notes
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;

    const values = [
      userId,
      subject,
      title,
      originalImageUrl,
      thumbnailUrl,
      JSON.stringify(aiParsingResult),
      processingTime,
      overallConfidence,
      JSON.stringify(studentAnswers),
      notes
    ];

    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Archive Conversation Management (NEW - for session conversations)
   */
  async archiveConversation(conversationData) {
    const {
      userId,
      sessionId,
      subject,
      title,
      summary,
      messageCount,
      totalTokens,
      conversationHistory,
      keyTopics,
      learningOutcomes,
      notes,
      duration,
      embedding // NEW: Semantic embedding vector
    } = conversationData;

    const query = `
      INSERT INTO archived_conversations (
        user_id,
        session_id,
        subject,
        title,
        summary,
        message_count,
        total_tokens,
        conversation_history,
        key_topics,
        learning_outcomes,
        notes,
        duration_minutes,
        content_embedding
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
      RETURNING *
    `;

    const values = [
      userId,
      sessionId,
      subject,
      title,
      summary,
      messageCount,
      totalTokens || 0,
      JSON.stringify(conversationHistory),
      keyTopics || [],
      learningOutcomes || [],
      notes,
      duration || 0,
      embedding ? JSON.stringify(embedding) : null // Store as JSON array since pgvector not available
    ];

    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Enhanced semantic search for conversations using JSON array similarity
   * (fallback implementation without pgvector)
   */
  async searchConversationsSemantic(userId, searchEmbedding, limit = 10, filters = {}) {
    // Since pgvector is not available, we'll use a simpler approach
    // Get all conversations with embeddings and calculate similarity in JavaScript
    let query = `
      SELECT 
        *
      FROM archived_conversations
      WHERE user_id = $1
        AND content_embedding IS NOT NULL
    `;
    
    const values = [userId];
    let paramIndex = 2;

    // Add filters
    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND archived_at >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND archived_at <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    if (filters.minMessages) {
      query += ` AND message_count >= $${paramIndex}`;
      values.push(filters.minMessages);
      paramIndex++;
    }

    query += ` ORDER BY archived_at DESC`;

    const result = await this.query(query, values);
    
    // Calculate cosine similarity in JavaScript
    const conversations = result.rows.map(row => {
      try {
        const embedding = JSON.parse(row.content_embedding);
        const similarity = this.calculateCosineSimilarity(searchEmbedding, embedding);
        return {
          ...row,
          similarity_distance: 1 - similarity // Convert to distance for consistency
        };
      } catch (error) {
        // Skip rows with invalid embeddings
        return null;
      }
    }).filter(Boolean);

    // Sort by similarity and limit
    return conversations
      .sort((a, b) => a.similarity_distance - b.similarity_distance)
      .slice(0, limit);
  },

  /**
   * Calculate cosine similarity between two vectors
   */
  calculateCosineSimilarity(vecA, vecB) {
    if (vecA.length !== vecB.length) return 0;
    
    let dotProduct = 0;
    let normA = 0;
    let normB = 0;
    
    for (let i = 0; i < vecA.length; i++) {
      dotProduct += vecA[i] * vecB[i];
      normA += vecA[i] * vecA[i];
      normB += vecB[i] * vecB[i];
    }
    
    const magnitude = Math.sqrt(normA) * Math.sqrt(normB);
    return magnitude === 0 ? 0 : dotProduct / magnitude;
  },

  /**
   * Advanced date-based retrieval with flexible patterns
   */
  async searchConversationsByDatePattern(userId, datePattern, limit = 20, filters = {}) {
    let query = `
      SELECT *
      FROM archived_conversations
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    // Apply date pattern matching
    switch (datePattern.type) {
      case 'today':
        query += ` AND DATE(archived_at) = CURRENT_DATE`;
        break;
      case 'yesterday':
        query += ` AND DATE(archived_at) = CURRENT_DATE - INTERVAL '1 day'`;
        break;
      case 'this_week':
        query += ` AND archived_at >= DATE_TRUNC('week', CURRENT_DATE)`;
        break;
      case 'last_week':
        query += ` AND archived_at >= DATE_TRUNC('week', CURRENT_DATE) - INTERVAL '1 week'
                   AND archived_at < DATE_TRUNC('week', CURRENT_DATE)`;
        break;
      case 'this_month':
        query += ` AND archived_at >= DATE_TRUNC('month', CURRENT_DATE)`;
        break;
      case 'last_month':
        query += ` AND archived_at >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
                   AND archived_at < DATE_TRUNC('month', CURRENT_DATE)`;
        break;
      case 'last_n_days':
        query += ` AND archived_at >= CURRENT_DATE - INTERVAL '${datePattern.days} days'`;
        break;
      case 'between':
        query += ` AND archived_at BETWEEN $${paramIndex} AND $${paramIndex + 1}`;
        values.push(datePattern.startDate, datePattern.endDate);
        paramIndex += 2;
        break;
      case 'on_date':
        query += ` AND DATE(archived_at) = $${paramIndex}`;
        values.push(datePattern.date);
        paramIndex++;
        break;
      case 'day_of_week':
        query += ` AND EXTRACT(DOW FROM archived_at) = $${paramIndex}`; // 0=Sunday, 1=Monday, etc.
        values.push(datePattern.dayOfWeek);
        paramIndex++;
        break;
    }

    // Add other filters
    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.search) {
      query += ` AND (
        title ILIKE $${paramIndex} OR 
        summary ILIKE $${paramIndex} OR 
        key_topics::text ILIKE $${paramIndex}
      )`;
      values.push(`%${filters.search}%`);
      paramIndex++;
    }

    query += ` ORDER BY archived_at DESC LIMIT $${paramIndex}`;
    values.push(limit);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Hybrid search combining keyword, semantic, and date relevance
   * (without pgvector - simplified implementation)
   */
  async hybridSearchConversations(userId, searchParams, limit = 20) {
    const {
      query: searchQuery,
      embedding,
      datePattern,
      subject,
      minMessages,
      includeKeyword = true,
      includeSemantic = true,
      includeDate = true
    } = searchParams;

    // Since we can't do complex scoring in SQL without pgvector,
    // we'll get the data and score in JavaScript
    let query = `
      SELECT *
      FROM archived_conversations
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    // Add filters
    if (subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(subject);
      paramIndex++;
    }

    if (minMessages) {
      query += ` AND message_count >= $${paramIndex}`;
      values.push(minMessages);
      paramIndex++;
    }

    // Apply date pattern if specified
    if (datePattern && includeDate) {
      switch (datePattern.type) {
        case 'recent':
          query += ` AND archived_at >= CURRENT_DATE - INTERVAL '30 days'`;
          break;
        case 'this_week':
          query += ` AND archived_at >= DATE_TRUNC('week', CURRENT_DATE)`;
          break;
        case 'this_month':
          query += ` AND archived_at >= DATE_TRUNC('month', CURRENT_DATE)`;
          break;
      }
    }

    query += ` ORDER BY archived_at DESC`;

    const result = await this.query(query, values);
    
    // Calculate hybrid scores in JavaScript
    const scoredConversations = result.rows.map(row => {
      let relevanceScore = 0;

      // Keyword relevance (0-1) * 0.3
      if (includeKeyword && searchQuery) {
        const searchLower = searchQuery.toLowerCase();
        if (row.title && row.title.toLowerCase().includes(searchLower)) {
          relevanceScore += 1.0 * 0.3;
        } else if (row.summary && row.summary.toLowerCase().includes(searchLower)) {
          relevanceScore += 0.8 * 0.3;
        } else if (row.key_topics && JSON.stringify(row.key_topics).toLowerCase().includes(searchLower)) {
          relevanceScore += 0.6 * 0.3;
        }
      }

      // Semantic similarity (0-1) * 0.4
      if (includeSemantic && embedding && row.content_embedding) {
        try {
          const rowEmbedding = JSON.parse(row.content_embedding);
          const similarity = this.calculateCosineSimilarity(embedding, rowEmbedding);
          relevanceScore += similarity * 0.4;
        } catch (error) {
          // Skip semantic scoring if embedding is invalid
        }
      }

      // Date recency (0-1) * 0.3
      if (includeDate) {
        const now = new Date();
        const archivedAt = new Date(row.archived_at);
        const daysDiff = (now - archivedAt) / (1000 * 60 * 60 * 24);
        
        if (daysDiff <= 7) {
          relevanceScore += 1.0 * 0.3;
        } else if (daysDiff <= 30) {
          relevanceScore += 0.7 * 0.3;
        } else if (daysDiff <= 90) {
          relevanceScore += 0.4 * 0.3;
        } else {
          relevanceScore += 0.1 * 0.3;
        }
      }

      return {
        ...row,
        relevance_score: relevanceScore
      };
    });

    // Sort by relevance score and limit
    return scoredConversations
      .sort((a, b) => b.relevance_score - a.relevance_score)
      .slice(0, limit);
  },

  /**
   * Fetch archived homework sessions (questions/images)
   */
  async fetchUserSessions(userId, limit = 50, offset = 0, filters = {}) {
    let query = `
      SELECT 
        id,
        subject,
        session_date,
        title,
        ai_parsing_result,
        overall_confidence,
        thumbnail_url,
        review_count,
        created_at
      FROM archived_sessions 
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    // Add optional filters
    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND session_date >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND session_date <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    query += ` ORDER BY session_date DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    values.push(limit, offset);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Fetch archived conversations (chat sessions)
   */
  async fetchUserConversations(userId, limit = 50, offset = 0, filters = {}) {
    let query = `
      SELECT 
        id,
        session_id,
        subject,
        title,
        summary,
        message_count,
        total_tokens,
        key_topics,
        learning_outcomes,
        duration_minutes,
        archived_at,
        review_count,
        last_reviewed_at
      FROM archived_conversations
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    // Add optional filters
    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND archived_at >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND archived_at <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    if (filters.minMessages) {
      query += ` AND message_count >= $${paramIndex}`;
      values.push(filters.minMessages);
      paramIndex++;
    }

    // Search in summary and topics
    if (filters.search) {
      query += ` AND (
        title ILIKE $${paramIndex} OR 
        summary ILIKE $${paramIndex} OR 
        key_topics::text ILIKE $${paramIndex}
      )`;
      values.push(`%${filters.search}%`);
      paramIndex++;
    }

    query += ` ORDER BY archived_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    values.push(limit, offset);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Get full conversation details
   */
  async getConversationDetails(conversationId, userId) {
    const query = `
      SELECT * FROM archived_conversations 
      WHERE id = $1 AND user_id = $2
    `;
    
    const result = await this.query(query, [conversationId, userId]);
    return result.rows[0];
  },

  /**
   * Get full session details (homework/questions)
   */
  async getSessionDetails(sessionId, userId) {
    const query = `
      SELECT * FROM archived_sessions 
      WHERE id = $1 AND user_id = $2
    `;
    
    const result = await this.query(query, [sessionId, userId]);
    return result.rows[0];
  },

  /**
   * Update conversation review count
   */
  async incrementConversationReviewCount(conversationId, userId) {
    const query = `
      UPDATE archived_conversations 
      SET 
        review_count = review_count + 1,
        last_reviewed_at = NOW()
      WHERE id = $1 AND user_id = $2
      RETURNING review_count
    `;
    
    const result = await this.query(query, [conversationId, userId]);
    return result.rows[0];
  },

  /**
   * Update session review count (homework/questions)
   */
  async incrementReviewCount(sessionId, userId) {
    const query = `
      UPDATE archived_sessions 
      SET 
        review_count = review_count + 1,
        last_reviewed_at = NOW()
      WHERE id = $1 AND user_id = $2
      RETURNING review_count
    `;
    
    const result = await this.query(query, [sessionId, userId]);
    return result.rows[0];
  },

  /**
   * Combined search across both conversations and sessions
   */
  async searchUserArchives(userId, searchTerm, filters = {}) {
    const conversationResults = await this.fetchUserConversations(userId, 25, 0, {
      ...filters,
      search: searchTerm
    });

    const sessionResults = await this.fetchUserSessions(userId, 25, 0, filters);

    return {
      conversations: conversationResults,
      sessions: sessionResults.filter(session => 
        session.title?.toLowerCase().includes(searchTerm.toLowerCase()) ||
        session.ai_parsing_result?.summary?.toLowerCase().includes(searchTerm.toLowerCase())
      )
    };
  },

  /**
   * Get user statistics
   */
  async getUserStatistics(userId) {
    const query = `
      SELECT 
        COUNT(*) as total_sessions,
        COUNT(DISTINCT subject) as subjects_studied,
        AVG(overall_confidence) as avg_confidence,
        SUM((ai_parsing_result->>'questionCount')::int) as total_questions,
        COUNT(CASE WHEN session_date >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as this_week_sessions,
        COUNT(CASE WHEN session_date >= DATE_TRUNC('month', CURRENT_DATE) THEN 1 END) as this_month_sessions
      FROM archived_sessions 
      WHERE user_id = $1
    `;
    
    const result = await this.query(query, [userId]);
    return result.rows[0];
  },

  /**
   * Get subject breakdown
   */
  async getSubjectBreakdown(userId) {
    const query = `
      SELECT 
        subject,
        COUNT(*) as session_count,
        AVG(overall_confidence) as avg_confidence,
        SUM((ai_parsing_result->>'questionCount')::int) as total_questions
      FROM archived_sessions 
      WHERE user_id = $1
      GROUP BY subject
      ORDER BY session_count DESC
    `;
    
    const result = await this.query(query, [userId]);
    return result.rows;
  },

  /**
   * Health check
   */
  async healthCheck() {
    try {
      const result = await this.query('SELECT NOW() as current_time');
      return {
        healthy: true,
        timestamp: result.rows[0].current_time,
        pool: {
          totalCount: pool.totalCount,
          idleCount: pool.idleCount,
          waitingCount: pool.waitingCount
        }
      };
    } catch (error) {
      return {
        healthy: false,
        error: error.message
      };
    }
  }
};

// Initialize database tables on startup
async function initializeDatabase() {
  try {
    console.log('🔄 Initializing Railway PostgreSQL database...');
    
    // Check if critical tables exist (users table is required for authentication)
    const tableCheck = await db.query(`
      SELECT tablename FROM pg_tables 
      WHERE schemaname = 'public' AND tablename IN ('users', 'profiles', 'sessions', 'questions')
    `);
    
    if (tableCheck.rows.length === 0) {
      console.log('📋 Creating database tables...');
      
      // Read and execute schema from file
      const fs = require('fs');
      const path = require('path');
      const schemaPath = path.join(__dirname, '../database/railway-schema.sql');
      
      if (fs.existsSync(schemaPath)) {
        const schema = fs.readFileSync(schemaPath, 'utf8');
        await db.query(schema);
        console.log('✅ Database tables created successfully');
      } else {
        console.log('⚠️ Schema file not found, using inline schema');
        await createInlineSchema();
      }
    } else {
      console.log(`✅ Found ${tableCheck.rows.length} existing tables: ${tableCheck.rows.map(r => r.tablename).join(', ')}`);
      
      // Check if we need to add missing tables
      const existingTables = tableCheck.rows.map(r => r.tablename);
      const requiredTables = ['users', 'profiles', 'sessions', 'questions', 'conversations', 'evaluations', 'progress', 'sessions_summaries', 'archived_sessions'];
      const missingTables = requiredTables.filter(table => !existingTables.includes(table));
      
      if (missingTables.length > 0) {
        console.log(`📋 Adding missing tables: ${missingTables.join(', ')}`);
        const fs = require('fs');
        const path = require('path');
        const schemaPath = path.join(__dirname, '../database/railway-schema.sql');
        
        if (fs.existsSync(schemaPath)) {
          const schema = fs.readFileSync(schemaPath, 'utf8');
          await db.query(schema);
          console.log('✅ Missing database tables added successfully');
        }
      }
    }
  } catch (error) {
    console.error('❌ Database initialization failed:', error);
    throw error;
  }
}

async function createInlineSchema() {
  const schema = `
    CREATE TABLE IF NOT EXISTS archived_sessions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL,
      subject VARCHAR(100) NOT NULL,
      session_date DATE NOT NULL DEFAULT CURRENT_DATE,
      title VARCHAR(200),
      
      original_image_url TEXT NOT NULL,
      thumbnail_url TEXT,
      
      ai_parsing_result JSONB NOT NULL,
      processing_time FLOAT NOT NULL DEFAULT 0,
      overall_confidence FLOAT NOT NULL DEFAULT 0,
      
      student_answers JSONB,
      notes TEXT,
      review_count INTEGER DEFAULT 0,
      last_reviewed_at TIMESTAMP WITH TIME ZONE,
      
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS idx_archived_sessions_user_date 
        ON archived_sessions(user_id, session_date DESC);

    CREATE INDEX IF NOT EXISTS idx_archived_sessions_subject 
        ON archived_sessions(user_id, subject);

    CREATE INDEX IF NOT EXISTS idx_archived_sessions_review 
        ON archived_sessions(user_id, last_reviewed_at DESC);

    CREATE INDEX IF NOT EXISTS idx_archived_sessions_created 
        ON archived_sessions(user_id, created_at DESC);

    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
    END;
    $$ language 'plpgsql';

    CREATE TRIGGER IF NOT EXISTS update_archived_sessions_updated_at 
        BEFORE UPDATE ON archived_sessions 
        FOR EACH ROW 
        EXECUTE FUNCTION update_updated_at_column();
  `;
  
  await db.query(schema);
}

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('🔄 Closing PostgreSQL connection pool...');
  await pool.end();
  console.log('✅ PostgreSQL connection pool closed');
  process.exit(0);
});

module.exports = {
  db,
  initializeDatabase
};