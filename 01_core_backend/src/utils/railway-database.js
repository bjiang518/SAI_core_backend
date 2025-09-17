/**
 * Optimized Railway PostgreSQL Database Configuration
 * High-performance connection management with advanced caching
 */

const { Pool } = require('pg');
const crypto = require('crypto');
const NodeCache = require('node-cache');
const { promisify } = require('util');

// Enhanced connection pool with optimization
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  max: 30, // Increased pool size for better concurrency
  min: 5,  // Minimum connections to maintain
  idleTimeoutMillis: 60000, // Keep connections alive longer
  connectionTimeoutMillis: 5000,
  statement_timeout: 30000,
  query_timeout: 30000,
  application_name: 'StudyAI_Backend'
});

// Multi-level caching system
const queryCache = new NodeCache({ 
  stdTTL: 600, // 10 minutes default TTL
  checkperiod: 120, // Check for expired keys every 2 minutes
  maxKeys: 10000 // Maximum cached items
});

const sessionCache = new NodeCache({ 
  stdTTL: 1800, // 30 minutes for sessions
  checkperiod: 300 // Check every 5 minutes
});

const userCache = new NodeCache({ 
  stdTTL: 3600, // 1 hour for user data
  checkperiod: 600 // Check every 10 minutes
});

// Performance monitoring and metrics
let queryMetrics = {
  totalQueries: 0,
  cacheHits: 0,
  cacheMisses: 0,
  averageQueryTime: 0,
  slowQueries: []
};

// Connection monitoring with detailed logging
pool.on('connect', (client) => {
  console.log('✅ New PostgreSQL client connected - Pool size:', pool.totalCount);
});

pool.on('acquire', (client) => {
  console.log('📊 Client acquired from pool - Active:', pool.idleCount, 'Idle:', pool.waitingCount, 'Waiting');
});

pool.on('error', (err, client) => {
  console.error('❌ Unexpected error on idle PostgreSQL client', err);
  // Don't exit - let the pool handle it
});

// Query result preparation helper
function generateCacheKey(text, params) {
  const combined = text + (params ? JSON.stringify(params) : '');
  return crypto.createHash('sha256').update(combined).digest('hex').substring(0, 16);
}

// Batch query processor for bulk operations
class BatchProcessor {
  constructor() {
    this.batches = new Map();
    this.batchSize = 100;
    this.flushInterval = 1000; // 1 second
    
    // Auto-flush batches periodically
    setInterval(() => this.flushAllBatches(), this.flushInterval);
  }
  
  addToBatch(operation, query, params) {
    if (!this.batches.has(operation)) {
      this.batches.set(operation, []);
    }
    
    this.batches.get(operation).push({ query, params, timestamp: Date.now() });
    
    // Auto-flush if batch is full
    if (this.batches.get(operation).length >= this.batchSize) {
      this.flushBatch(operation);
    }
  }
  
  async flushBatch(operation) {
    const batch = this.batches.get(operation);
    if (!batch || batch.length === 0) return;
    
    this.batches.set(operation, []); // Clear batch
    
    try {
      await db.transaction(async (client) => {
        for (const item of batch) {
          await client.query(item.query, item.params);
        }
      });
      
      console.log(`📦 Flushed batch of ${batch.length} ${operation} operations`);
    } catch (error) {
      console.error(`❌ Batch flush error for ${operation}:`, error);
    }
  }
  
  async flushAllBatches() {
    for (const operation of this.batches.keys()) {
      await this.flushBatch(operation);
    }
  }
}

const batchProcessor = new BatchProcessor();

// Enhanced database utility functions with caching and optimization
const db = {
  /**
   * Execute a cached query with performance monitoring
   */
  async query(text, params = [], options = {}) {
    const start = Date.now();
    const cacheKey = options.cache !== false ? generateCacheKey(text, params) : null;
    
    // Check cache first (for SELECT queries)
    if (cacheKey && text.trim().toLowerCase().startsWith('select')) {
      const cached = queryCache.get(cacheKey);
      if (cached) {
        queryMetrics.cacheHits++;
        const duration = Date.now() - start;
        console.log(`⚡ Cache hit in ${duration}ms: ${text.substring(0, 50)}...`);
        return cached;
      }
      queryMetrics.cacheMisses++;
    }
    
    try {
      queryMetrics.totalQueries++;
      const result = await pool.query(text, params);
      const duration = Date.now() - start;
      
      // Update performance metrics
      queryMetrics.averageQueryTime = 
        (queryMetrics.averageQueryTime * (queryMetrics.totalQueries - 1) + duration) / queryMetrics.totalQueries;
      
      // Track slow queries
      if (duration > 1000) {
        queryMetrics.slowQueries.push({
          query: text.substring(0, 100),
          duration,
          timestamp: new Date()
        });
        
        // Keep only last 100 slow queries
        if (queryMetrics.slowQueries.length > 100) {
          queryMetrics.slowQueries = queryMetrics.slowQueries.slice(-100);
        }
      }
      
      console.log(`📊 Query executed in ${duration}ms: ${text.substring(0, 50)}...`);
      
      // Cache SELECT results
      if (cacheKey && text.trim().toLowerCase().startsWith('select') && result.rows.length > 0) {
        const ttl = options.cacheTTL || 600; // 10 minutes default
        queryCache.set(cacheKey, result, ttl);
      }
      
      return result;
    } catch (error) {
      console.error('❌ Database query error:', error);
      console.error('Query:', text.substring(0, 200));
      console.error('Params:', params);
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
    const startTime = Date.now();
    try {
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

      console.log(`🔍 Starting token verification for hash: ${tokenHash.substring(0, 8)}...`);
      const result = await this.query(query, [tokenHash]);
      const duration = Date.now() - startTime;
      
      if (result.rows.length > 0) {
        console.log(`✅ Token verification successful in ${duration}ms for user: ${result.rows[0].user_id}`);
        return result.rows[0];
      } else {
        console.log(`❌ Token verification failed in ${duration}ms - no matching session found`);
        return null;
      }
    } catch (error) {
      const duration = Date.now() - startTime;
      console.error(`❌ Token verification error after ${duration}ms:`, error);
      throw error;
    }
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
   * Enhanced Profile Management Functions (for upcoming profile management phase)
   */

  /**
   * Create or update comprehensive user profile
   */
  async createOrUpdateUserProfile(profileData) {
    const {
      userId,
      email,
      role = 'student',
      parentId,
      firstName,
      lastName,
      displayName,
      gradeLevel,
      school,
      schoolDistrict,
      academicYear,
      dateOfBirth,
      timezone = 'UTC',
      languagePreference = 'en',
      learningStyle,
      difficultyPreference = 'adaptive',
      favoriteSubjects = [],
      accessibilityNeeds = [],
      voiceEnabled = true,
      autoSpeakResponses = false,
      preferredVoiceType = 'friendly',
      privacyLevel = 'standard',
      parentalControlsEnabled = false,
      dataSharingConsent = false,
      onboardingCompleted = false
    } = profileData;

    // Calculate profile completion percentage
    const completionFields = [
      firstName, lastName, gradeLevel, school, dateOfBirth, 
      learningStyle, favoriteSubjects?.length > 0
    ];
    const completedFields = completionFields.filter(field => field).length;
    const profileCompletionPercentage = Math.round((completedFields / completionFields.length) * 100);

    const query = `
      INSERT INTO profiles (
        user_id, email, role, parent_id, first_name, last_name, display_name,
        grade_level, school, school_district, academic_year, date_of_birth,
        timezone, language_preference, learning_style, difficulty_preference,
        favorite_subjects, accessibility_needs, voice_enabled, auto_speak_responses,
        preferred_voice_type, privacy_level, parental_controls_enabled,
        data_sharing_consent, profile_completion_percentage, onboarding_completed,
        last_profile_update
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16,
        $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, NOW()
      )
      ON CONFLICT (email) 
      DO UPDATE SET 
        role = EXCLUDED.role,
        parent_id = EXCLUDED.parent_id,
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        display_name = EXCLUDED.display_name,
        grade_level = EXCLUDED.grade_level,
        school = EXCLUDED.school,
        school_district = EXCLUDED.school_district,
        academic_year = EXCLUDED.academic_year,
        date_of_birth = EXCLUDED.date_of_birth,
        timezone = EXCLUDED.timezone,
        language_preference = EXCLUDED.language_preference,
        learning_style = EXCLUDED.learning_style,
        difficulty_preference = EXCLUDED.difficulty_preference,
        favorite_subjects = EXCLUDED.favorite_subjects,
        accessibility_needs = EXCLUDED.accessibility_needs,
        voice_enabled = EXCLUDED.voice_enabled,
        auto_speak_responses = EXCLUDED.auto_speak_responses,
        preferred_voice_type = EXCLUDED.preferred_voice_type,
        privacy_level = EXCLUDED.privacy_level,
        parental_controls_enabled = EXCLUDED.parental_controls_enabled,
        data_sharing_consent = EXCLUDED.data_sharing_consent,
        profile_completion_percentage = EXCLUDED.profile_completion_percentage,
        onboarding_completed = EXCLUDED.onboarding_completed,
        last_profile_update = NOW(),
        updated_at = NOW()
      RETURNING *
    `;

    const values = [
      userId, email, role, parentId, firstName, lastName, displayName,
      gradeLevel, school, schoolDistrict, academicYear, dateOfBirth,
      timezone, languagePreference, learningStyle, difficultyPreference,
      favoriteSubjects, accessibilityNeeds, voiceEnabled, autoSpeakResponses,
      preferredVoiceType, privacyLevel, parentalControlsEnabled,
      dataSharingConsent, profileCompletionPercentage, onboardingCompleted
    ];

    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get user profile by email
   */
  async getUserProfile(email) {
    const query = `
      SELECT p.*, u.name as user_name, u.profile_image_url, u.auth_provider
      FROM profiles p
      LEFT JOIN users u ON p.user_id = u.id
      WHERE p.email = $1 AND p.is_active = true
    `;
    
    const result = await this.query(query, [email]);
    return result.rows[0];
  },

  /**
   * Get user profile by user ID
   */
  async getUserProfileById(userId) {
    const query = `
      SELECT p.*, u.name as user_name, u.profile_image_url, u.auth_provider
      FROM profiles p
      LEFT JOIN users u ON p.user_id = u.id
      WHERE p.user_id = $1 AND p.is_active = true
    `;
    
    const result = await this.query(query, [userId]);
    return result.rows[0];
  },

  /**
   * Update specific profile fields
   */
  async updateProfileFields(userId, fields) {
    const allowedFields = [
      'first_name', 'last_name', 'display_name', 'grade_level', 'school',
      'school_district', 'academic_year', 'date_of_birth', 'timezone',
      'language_preference', 'learning_style', 'difficulty_preference',
      'favorite_subjects', 'accessibility_needs', 'voice_enabled',
      'auto_speak_responses', 'preferred_voice_type', 'privacy_level',
      'parental_controls_enabled', 'data_sharing_consent', 'onboarding_completed'
    ];

    const updateFields = Object.keys(fields).filter(key => allowedFields.includes(key));
    if (updateFields.length === 0) {
      throw new Error('No valid fields to update');
    }

    const setClause = updateFields.map((field, index) => `${field} = $${index + 2}`).join(', ');
    const values = [userId, ...updateFields.map(field => fields[field])];

    const query = `
      UPDATE profiles 
      SET ${setClause}, last_profile_update = NOW(), updated_at = NOW()
      WHERE user_id = $1
      RETURNING *
    `;

    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get profiles by parent ID (for parental accounts)
   */
  async getChildrenProfiles(parentId) {
    const query = `
      SELECT p.*, u.name as user_name, u.profile_image_url
      FROM profiles p
      LEFT JOIN users u ON p.user_id = u.id
      WHERE p.parent_id = $1 AND p.is_active = true
      ORDER BY p.first_name, p.last_name
    `;
    
    const result = await this.query(query, [parentId]);
    return result.rows;
  },

  /**
   * Check if profile setup is complete
   */
  async isProfileComplete(userId) {
    const query = `
      SELECT 
        profile_completion_percentage,
        onboarding_completed,
        CASE 
          WHEN profile_completion_percentage >= 80 AND onboarding_completed = true THEN true
          ELSE false
        END as is_complete
      FROM profiles 
      WHERE user_id = $1
    `;
    
    const result = await this.query(query, [userId]);
    return result.rows[0];
  },

  /**
   * Archive a conversation (chat session) to archived_conversations_new
   */
  async archiveConversation(conversationData) {
    const {
      userId,
      subject,
      topic,
      conversationContent
    } = conversationData;

    const query = `
      INSERT INTO archived_conversations_new (
        user_id,
        subject,
        topic,
        conversation_content
      ) VALUES ($1, $2, $3, $4)
      RETURNING *
    `;

    const values = [userId, subject, topic, conversationContent];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Archive a question to questions table
   */
  async archiveQuestion(questionData) {
    const {
      userId,
      subject,
      questionText,
      studentAnswer,
      isCorrect,
      aiAnswer,
      confidenceScore = 0.0
    } = questionData;

    const query = `
      INSERT INTO questions (
        user_id,
        subject,
        question_text,
        student_answer,
        is_correct,
        ai_answer,
        confidence_score
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `;

    const values = [userId, subject, questionText, studentAnswer, isCorrect, aiAnswer, confidenceScore];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Fetch user's archived conversations
   */
  async fetchUserConversations(userId, limit = 50, offset = 0, filters = {}) {
    let query = `
      SELECT 
        id,
        subject,
        topic,
        conversation_content,
        archived_date,
        created_at
      FROM archived_conversations_new
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND archived_date >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND archived_date <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    if (filters.search) {
      query += ` AND (
        topic ILIKE $${paramIndex} OR 
        conversation_content ILIKE $${paramIndex}
      )`;
      values.push(`%${filters.search}%`);
      paramIndex++;
    }

    query += ` ORDER BY archived_date DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    values.push(limit, offset);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Fetch user's archived questions
   */
  async fetchUserQuestions(userId, limit = 50, offset = 0, filters = {}) {
    let query = `
      SELECT 
        id,
        subject,
        question_text,
        student_answer,
        is_correct,
        ai_answer,
        confidence_score,
        archived_date,
        created_at
      FROM questions
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND archived_date >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND archived_date <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    if (filters.search) {
      query += ` AND (
        question_text ILIKE $${paramIndex} OR 
        student_answer ILIKE $${paramIndex} OR
        ai_answer ILIKE $${paramIndex}
      )`;
      values.push(`%${filters.search}%`);
      paramIndex++;
    }

    query += ` ORDER BY archived_date DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    values.push(limit, offset);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Get conversation details by ID
   */
  async getConversationDetails(conversationId, userId) {
    const startTime = Date.now();
    
    try {
      console.log(`🔍 [DB] getConversationDetails called with conversationId: ${conversationId}, userId: ${userId}`);
      
      if (!conversationId) {
        console.error(`❌ [DB] Missing conversationId parameter`);
        throw new Error('Conversation ID is required');
      }
      
      if (!userId) {
        console.error(`❌ [DB] Missing userId parameter`);
        throw new Error('User ID is required');
      }
      
      const query = `
        SELECT * FROM archived_conversations_new 
        WHERE id = $1 AND user_id = $2
      `;
      
      console.log(`📋 [DB] Executing query: ${query}`);
      console.log(`📋 [DB] Parameters: [${conversationId}, ${userId}]`);
      
      const result = await this.query(query, [conversationId, userId]);
      const duration = Date.now() - startTime;
      
      console.log(`📊 [DB] Query completed in ${duration}ms`);
      console.log(`📊 [DB] Result rows count: ${result.rows.length}`);
      
      if (result.rows.length > 0) {
        const conversation = result.rows[0];
        console.log(`✅ [DB] Conversation found - ID: ${conversation.id}, Subject: ${conversation.subject}`);
        console.log(`✅ [DB] Content length: ${conversation.conversation_content?.length || 0} characters`);
        console.log(`✅ [DB] Archived date: ${conversation.archived_date}`);
        return conversation;
      } else {
        console.log(`❌ [DB] No conversation found for ID: ${conversationId}, User: ${userId}`);
        return null;
      }
    } catch (error) {
      const duration = Date.now() - startTime;
      console.error(`🚨 [DB] getConversationDetails error after ${duration}ms:`, error);
      console.error(`🚨 [DB] Error stack:`, error.stack);
      throw error;
    }
  },

  /**
   * Get question details by ID
   */
  async getQuestionDetails(questionId, userId) {
    const query = `
      SELECT * FROM questions 
      WHERE id = $1 AND user_id = $2
    `;
    
    const result = await this.query(query, [questionId, userId]);
    return result.rows[0];
  },

  /**
   * Archive a conversation (chat session) to archived_conversations_new
   */
  async archiveConversation(conversationData) {
    const {
      userId,
      subject,
      topic,
      conversationContent
    } = conversationData;

    const query = `
      INSERT INTO archived_conversations_new (
        user_id,
        subject,
        topic,
        conversation_content
      ) VALUES ($1, $2, $3, $4)
      RETURNING *
    `;

    const values = [userId, subject, topic, conversationContent];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Archive a question to questions table
   */
  async archiveQuestion(questionData) {
    const {
      userId,
      subject,
      questionText,
      studentAnswer,
      isCorrect,
      aiAnswer,
      confidenceScore = 0.0
    } = questionData;

    const query = `
      INSERT INTO questions (
        user_id,
        subject,
        question_text,
        student_answer,
        is_correct,
        ai_answer,
        confidence_score
      ) VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `;

    const values = [userId, subject, questionText, studentAnswer, isCorrect, aiAnswer, confidenceScore];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Fetch user's archived conversations
   */
  async fetchUserConversations(userId, limit = 50, offset = 0, filters = {}) {
    let query = `
      SELECT 
        id,
        subject,
        topic,
        conversation_content,
        archived_date,
        created_at
      FROM archived_conversations_new
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND archived_date >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND archived_date <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    if (filters.search) {
      query += ` AND (
        topic ILIKE $${paramIndex} OR 
        conversation_content ILIKE $${paramIndex}
      )`;
      values.push(`%${filters.search}%`);
      paramIndex++;
    }

    query += ` ORDER BY archived_date DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    values.push(limit, offset);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Fetch user's archived questions
   */
  async fetchUserQuestions(userId, limit = 50, offset = 0, filters = {}) {
    let query = `
      SELECT 
        id,
        subject,
        question_text,
        student_answer,
        is_correct,
        ai_answer,
        confidence_score,
        archived_date,
        created_at
      FROM questions
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND archived_date >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND archived_date <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    if (filters.search) {
      query += ` AND (
        question_text ILIKE $${paramIndex} OR 
        student_answer ILIKE $${paramIndex} OR
        ai_answer ILIKE $${paramIndex}
      )`;
      values.push(`%${filters.search}%`);
      paramIndex++;
    }

    query += ` ORDER BY archived_date DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    values.push(limit, offset);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Search both conversations and questions
   */
  async searchUserArchives(userId, searchTerm, filters = {}) {
    const conversationResults = await this.fetchUserConversations(userId, 25, 0, {
      ...filters,
      search: searchTerm
    });

    const questionResults = await this.fetchUserQuestions(userId, 25, 0, {
      ...filters,
      search: searchTerm
    });

    return {
      conversations: conversationResults,
      questions: questionResults
    };
  },

  /**
   * Add a conversation message to the conversations table
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

    const values = [userId, questionId, sessionId, messageType, messageText, msgData ? JSON.stringify(msgData) : null, tokensUsed];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get conversation history for a session
   */
  async getConversationHistory(sessionId, limit = 50) {
    const query = `
      SELECT 
        id,
        user_id,
        question_id,
        session_id,
        message_type,
        message_text,
        message_data,
        tokens_used,
        created_at
      FROM conversations
      WHERE session_id = $1
      ORDER BY created_at ASC
      LIMIT $2
    `;

    const result = await this.query(query, [sessionId, limit]);
    return result.rows;
  },

  /**
   * Get session details by ID (for homework/question sessions)
   */
  async getSessionDetails(sessionId, userId) {
    const query = `
      SELECT * FROM sessions 
      WHERE id = $1 AND user_id = $2
    `;
    
    const result = await this.query(query, [sessionId, userId]);
    return result.rows[0];
  },

  /**
   * Fetch user's sessions (homework/questions)
   */
  async fetchUserSessions(userId, limit = 50, offset = 0, filters = {}) {
    let query = `
      SELECT 
        id,
        title,
        subject,
        session_type,
        status,
        start_time,
        end_time,
        created_at
      FROM sessions
      WHERE user_id = $1
    `;
    
    const values = [userId];
    let paramIndex = 2;

    if (filters.subject) {
      query += ` AND subject = $${paramIndex}`;
      values.push(filters.subject);
      paramIndex++;
    }

    if (filters.startDate) {
      query += ` AND start_time >= $${paramIndex}`;
      values.push(filters.startDate);
      paramIndex++;
    }

    if (filters.endDate) {
      query += ` AND start_time <= $${paramIndex}`;
      values.push(filters.endDate);
      paramIndex++;
    }

    query += ` ORDER BY start_time DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
    values.push(limit, offset);

    const result = await this.query(query, values);
    return result.rows;
  },

  /**
   * Enhanced Profile Management Functions - Update existing profile with new fields
   */
  async updateUserProfileEnhanced(userId, profileData) {
    const {
      firstName,
      lastName,
      displayName,
      gradeLevel,
      dateOfBirth,
      kidsAges = [],
      gender,
      city,
      stateProvince,
      country,
      favoriteSubjects = [],
      learningStyle,
      timezone = 'UTC',
      languagePreference = 'en'
    } = profileData;

    console.log(`🔍 DEBUG: Updating profile for user ${userId} with data:`, profileData);

    // First, get the user's email for the profile
    const userQuery = `SELECT email FROM users WHERE id = $1`;
    const userResult = await this.query(userQuery, [userId]);
    
    if (userResult.rows.length === 0) {
      throw new Error('User not found');
    }
    
    const userEmail = userResult.rows[0].email;

    // Convert grade level string to appropriate format for database
    // Handle both old INTEGER columns and new VARCHAR columns
    let processedGradeLevel = gradeLevel;
    
    // Map grade level strings to integers for legacy database compatibility
    const gradeLevelMap = {
      'Pre-K': -1,
      'Kindergarten': 0, 
      '1st Grade': 1,
      '2nd Grade': 2,
      '3rd Grade': 3,
      '4th Grade': 4,
      '5th Grade': 5,
      '6th Grade': 6,
      '7th Grade': 7,
      '8th Grade': 8,
      '9th Grade': 9,
      '10th Grade': 10,
      '11th Grade': 11,
      '12th Grade': 12,
      'College': 13,
      'Adult Learner': 14
    };
    
    // Check if database column is INTEGER by attempting string insert first, then fallback to integer
    let shouldUseIntegerGrade = false;
    
    console.log(`🔍 DEBUG: Original grade level: "${gradeLevel}"`);
    console.log(`🔍 DEBUG: Mapped integer value: ${gradeLevelMap[gradeLevel] || 'unmapped'}`);

    // Calculate profile completion percentage
    const completionFields = [
      firstName, lastName, gradeLevel, dateOfBirth, 
      city, stateProvince, country, favoriteSubjects?.length > 0
    ];
    const completedFields = completionFields.filter(field => field).length;
    const profileCompletionPercentage = Math.round((completedFields / completionFields.length) * 100);

    // Try inserting with string grade level first (newer schema)
    const query = `
      INSERT INTO profiles (
        email, first_name, last_name, grade_level, 
        kids_ages, gender, city, state_province, country,
        created_at, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), NOW()
      )
      ON CONFLICT (email) 
      DO UPDATE SET 
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        grade_level = EXCLUDED.grade_level,
        kids_ages = EXCLUDED.kids_ages,
        gender = EXCLUDED.gender,
        city = EXCLUDED.city,
        state_province = EXCLUDED.state_province,
        country = EXCLUDED.country,
        updated_at = NOW()
      RETURNING *
    `;

    try {
      // First attempt: use string grade level (for newer VARCHAR schema)
      console.log(`🔍 DEBUG: Attempting string grade level insert: "${processedGradeLevel}"`);
      const values = [
        userEmail, firstName, lastName, processedGradeLevel,
        kidsAges, gender, city, stateProvince, country
      ];

      const result = await this.query(query, values);
      console.log(`✅ DEBUG: Profile update successful with string grade level`);
      return result.rows[0];
      
    } catch (error) {
      console.log(`⚠️ DEBUG: String grade level failed: ${error.message}`);
      
      // Check if error is related to integer type conversion
      if (error.message.includes('invalid input syntax for type integer') || 
          error.message.includes('integer')) {
        
        console.log(`🔄 DEBUG: Retrying with integer grade level mapping`);
        
        // Second attempt: use integer grade level (for legacy INTEGER schema)
        const integerGradeLevel = gradeLevelMap[gradeLevel];
        
        if (integerGradeLevel === undefined) {
          console.log(`❌ DEBUG: No integer mapping found for grade level: "${gradeLevel}"`);
          // If no mapping exists, use 0 as default
          processedGradeLevel = 0;
        } else {
          processedGradeLevel = integerGradeLevel;
        }
        
        console.log(`🔍 DEBUG: Using integer grade level: ${processedGradeLevel}`);
        
        const valuesWithIntegerGrade = [
          userEmail, firstName, lastName, processedGradeLevel,
          kidsAges, gender, city, stateProvince, country
        ];

        const result = await this.query(query, valuesWithIntegerGrade);
        console.log(`✅ DEBUG: Profile update successful with integer grade level`);
        return result.rows[0];
      } else {
        // Re-throw non-grade-level related errors
        console.log(`❌ DEBUG: Non-grade-level error: ${error.message}`);
        throw error;
      }
    }
  },

  /**
   * Get enhanced user profile by user ID
   */
  async getEnhancedUserProfile(userId) {
    const query = `
      SELECT 
        p.*,
        u.name as user_name,
        u.email as user_email,
        u.profile_image_url,
        u.auth_provider
      FROM profiles p
      LEFT JOIN users u ON p.email = u.email
      WHERE u.id = $1 AND u.is_active = true
    `;
    
    const result = await this.query(query, [userId]);
    return result.rows[0];
  }
};

// Initialize database tables on startup
async function initializeDatabase() {
  try {
    console.log('🔄 Initializing Railway PostgreSQL database...');
    
    // Check if critical tables exist (users table is required for authentication)
    const tableCheck = await db.query(`
      SELECT tablename FROM pg_tables 
      WHERE schemaname = 'public' AND tablename IN ('users', 'user_sessions', 'profiles', 'sessions', 'questions', 'archived_conversations_new', 'conversations', 'archived_questions')
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
      const requiredTables = ['users', 'user_sessions', 'profiles', 'sessions', 'questions', 'archived_conversations_new', 'conversations', 'archived_questions'];
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
      
      // Run migrations for existing databases
      await runDatabaseMigrations();
    }
  } catch (error) {
    console.error('❌ Database initialization failed:', error);
    throw error;
  }
}

async function runDatabaseMigrations() {
  try {
    console.log('🔄 Checking for database migrations...');
    
    // Create a migrations tracking table if it doesn't exist
    await db.query(`
      CREATE TABLE IF NOT EXISTS migration_history (
        id SERIAL PRIMARY KEY,
        migration_name VARCHAR(255) UNIQUE NOT NULL,
        executed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
    `);
    
    // Check if grading fields migration has been applied
    const gradeFieldsCheck = await db.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'archived_questions' 
      AND column_name IN ('student_answer', 'grade', 'points', 'max_points', 'feedback', 'is_graded')
    `);
    
    // First ensure the archived_questions table exists with basic structure
    await db.query(`
      CREATE TABLE IF NOT EXISTS archived_questions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id TEXT NOT NULL,
        subject VARCHAR(100) NOT NULL,
        question_text TEXT NOT NULL,
        answer_text TEXT NOT NULL,
        confidence FLOAT NOT NULL DEFAULT 0,
        has_visual_elements BOOLEAN DEFAULT FALSE,
        
        -- Image storage
        original_image_url TEXT,
        question_image_url TEXT, -- Cropped image of just this question
        
        -- Metadata
        processing_time FLOAT NOT NULL DEFAULT 0,
        archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        review_count INTEGER DEFAULT 0,
        last_reviewed_at TIMESTAMP WITH TIME ZONE,
        
        -- User customization
        tags TEXT[], -- Array of user-defined tags
        notes TEXT, -- User notes for this question
        
        -- Timestamps
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
    `);
    
    if (gradeFieldsCheck.rows.length < 6) {
      console.log('📋 Applying grading fields migration...');
      
      // Run the grading fields migration
      await db.query(`
        -- Add new grading-specific columns to archived_questions table
        ALTER TABLE archived_questions 
        ADD COLUMN IF NOT EXISTS student_answer TEXT,
        ADD COLUMN IF NOT EXISTS grade VARCHAR(20) CHECK (grade IN ('CORRECT', 'INCORRECT', 'EMPTY', 'PARTIAL_CREDIT')),
        ADD COLUMN IF NOT EXISTS points FLOAT,
        ADD COLUMN IF NOT EXISTS max_points FLOAT,
        ADD COLUMN IF NOT EXISTS feedback TEXT,
        ADD COLUMN IF NOT EXISTS is_graded BOOLEAN DEFAULT false;

        -- Add indexes for better query performance
        CREATE INDEX IF NOT EXISTS idx_archived_questions_grade ON archived_questions(grade);
        CREATE INDEX IF NOT EXISTS idx_archived_questions_is_graded ON archived_questions(is_graded);

        -- Add comments to document the new columns
        COMMENT ON COLUMN archived_questions.student_answer IS 'The student''s provided answer from homework image';
        COMMENT ON COLUMN archived_questions.grade IS 'Grading result: CORRECT, INCORRECT, EMPTY, or PARTIAL_CREDIT';
        COMMENT ON COLUMN archived_questions.points IS 'Points earned for this question';
        COMMENT ON COLUMN archived_questions.max_points IS 'Maximum points possible for this question';
        COMMENT ON COLUMN archived_questions.feedback IS 'AI-generated feedback for the student';
        COMMENT ON COLUMN archived_questions.is_graded IS 'Whether this question was graded (true) vs just answered (false)';
      `);
      
      // Update the question_summaries view to include grading info
      await db.query(`
        CREATE OR REPLACE VIEW question_summaries AS
        SELECT 
            id,
            user_id,
            subject,
            CASE 
                WHEN length(question_text) > 100 
                THEN substring(question_text from 1 for 97) || '...'
                ELSE question_text
            END as short_question_text,
            question_text,
            confidence,
            CASE 
                WHEN confidence >= 0.8 THEN 'High'
                WHEN confidence >= 0.6 THEN 'Medium'
                ELSE 'Low'
            END as confidence_level,
            has_visual_elements,
            archived_at,
            review_count,
            tags,
            -- New grading fields
            grade,
            points,
            max_points,
            is_graded,
            CASE 
                WHEN is_graded AND grade IS NOT NULL THEN
                    CASE 
                        WHEN points IS NOT NULL AND max_points IS NOT NULL THEN
                            grade || ' (' || points::text || '/' || max_points::text || ')'
                        ELSE grade
                    END
                ELSE 'Not Graded'
            END as grade_display_text,
            CASE 
                WHEN points IS NOT NULL AND max_points IS NOT NULL AND max_points > 0 THEN
                    (points / max_points * 100)::int
                ELSE NULL
            END as score_percentage,
            created_at
        FROM archived_questions
        ORDER BY archived_at DESC;
      `);
      
      // Record the migration as completed
      await db.query(`
        INSERT INTO migration_history (migration_name) 
        VALUES ('001_add_grading_fields') 
        ON CONFLICT (migration_name) DO NOTHING;
      `);
      
      console.log('✅ Grading fields migration completed successfully!');
      console.log('📊 Database now supports:');
      console.log('   - Student answers from homework images');
      console.log('   - Grading results (CORRECT/INCORRECT/EMPTY/PARTIAL_CREDIT)');
      console.log('   - Points earned and maximum points');
      console.log('   - AI-generated feedback for students');
      console.log('   - Graded vs non-graded question tracking');
    } else {
      console.log('✅ Grading fields migration already applied');
    }
    
    // Clean up legacy tables - keep sessions, questions and archived_conversations_new
    const legacyTables = [
      'archived_conversations', 
      'archived_sessions', 
      'conversations', 
      'sessions_summaries', 
      'evaluations', 
      'progress'
    ];
    
    for (const tableName of legacyTables) {
      try {
        await db.query(`DROP TABLE IF EXISTS ${tableName} CASCADE`);
        console.log(`✅ Dropped legacy table: ${tableName}`);
      } catch (error) {
        console.log(`⚠️ Could not drop ${tableName}: ${error.message}`);
      }
    }
    
    // Ensure archived_conversations_new exists with correct structure
    await db.query(`
      CREATE TABLE IF NOT EXISTS archived_conversations_new (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        subject VARCHAR(100) NOT NULL,
        topic VARCHAR(200),
        conversation_content TEXT NOT NULL,
        archived_date DATE NOT NULL DEFAULT CURRENT_DATE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
    `);
    
    // Ensure questions table exists with correct structure for individual Q&A
    await db.query(`
      CREATE TABLE IF NOT EXISTS questions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        subject VARCHAR(100) NOT NULL,
        question_text TEXT NOT NULL,
        student_answer TEXT,
        is_correct BOOLEAN,
        ai_answer TEXT,
        confidence_score FLOAT DEFAULT 0.0,
        archived_date DATE NOT NULL DEFAULT CURRENT_DATE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
    `);
    
    // Add missing columns if they don't exist
    try {
      await db.query('ALTER TABLE questions ADD COLUMN IF NOT EXISTS archived_date DATE DEFAULT CURRENT_DATE');
      console.log('✅ Added archived_date column to questions table');
    } catch (error) {
      console.log(`⚠️ Could not add archived_date to questions: ${error.message}`);
    }
    
    try {
      await db.query('ALTER TABLE archived_conversations_new ADD COLUMN IF NOT EXISTS archived_date DATE DEFAULT CURRENT_DATE');
      console.log('✅ Added archived_date column to archived_conversations_new table');
    } catch (error) {
      console.log(`⚠️ Could not add archived_date to archived_conversations_new: ${error.message}`);
    }
    
    // Create indexes with proper error handling
    try {
      await db.query('CREATE INDEX IF NOT EXISTS idx_archived_conversations_new_user_date ON archived_conversations_new(user_id, archived_date DESC)');
      console.log('✅ Created index: idx_archived_conversations_new_user_date');
    } catch (error) {
      console.log(`⚠️ Could not create index idx_archived_conversations_new_user_date: ${error.message}`);
    }
    
    try {
      await db.query('CREATE INDEX IF NOT EXISTS idx_archived_conversations_new_subject ON archived_conversations_new(user_id, subject)');
      console.log('✅ Created index: idx_archived_conversations_new_subject');
    } catch (error) {
      console.log(`⚠️ Could not create index idx_archived_conversations_new_subject: ${error.message}`);
    }
    
    try {
      await db.query('CREATE INDEX IF NOT EXISTS idx_questions_user_date ON questions(user_id, archived_date DESC)');
      console.log('✅ Created index: idx_questions_user_date');
    } catch (error) {
      console.log(`⚠️ Could not create index idx_questions_user_date: ${error.message}`);
    }
    
    try {
      await db.query('CREATE INDEX IF NOT EXISTS idx_questions_subject ON questions(user_id, subject)');
      console.log('✅ Created index: idx_questions_subject');
    } catch (error) {
      console.log(`⚠️ Could not create index idx_questions_subject: ${error.message}`);
    }
    
    // Ensure sessions table exists for AI proxy functionality
    await db.query(`
      CREATE TABLE IF NOT EXISTS sessions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        parent_id UUID REFERENCES users(id),
        session_type VARCHAR(50) DEFAULT 'homework',
        title VARCHAR(200),
        description TEXT,
        subject VARCHAR(100),
        status VARCHAR(50) DEFAULT 'active',
        start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        end_time TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
    `);
    
    // Ensure conversations table exists for chat history
    await db.query(`
      CREATE TABLE IF NOT EXISTS conversations (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
        session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
        message_type VARCHAR(50) NOT NULL, -- 'user' or 'assistant'
        message_text TEXT NOT NULL,
        message_data JSONB,
        tokens_used INTEGER DEFAULT 0,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
      );
    `);
    
    // Check if profile enhancement migration has been applied
    const profileFieldsCheck = await db.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'profiles' 
      AND column_name IN ('kids_ages', 'gender', 'city', 'state_province', 'country')
    `);
    
    if (profileFieldsCheck.rows.length < 5) {
      console.log('📋 Applying profile enhancement migration...');
      
      // Add new profile fields for comprehensive user profile management
      await db.query(`
        -- Add new profile fields for enhanced user information
        ALTER TABLE profiles 
        ADD COLUMN IF NOT EXISTS kids_ages INTEGER[],
        ADD COLUMN IF NOT EXISTS gender VARCHAR(50),
        ADD COLUMN IF NOT EXISTS city VARCHAR(100),
        ADD COLUMN IF NOT EXISTS state_province VARCHAR(100),
        ADD COLUMN IF NOT EXISTS country VARCHAR(100);

        -- Add indexes for better query performance
        CREATE INDEX IF NOT EXISTS idx_profiles_location ON profiles(country, state_province, city);
        CREATE INDEX IF NOT EXISTS idx_profiles_gender ON profiles(gender);

        -- Add comments to document the new columns
        COMMENT ON COLUMN profiles.kids_ages IS 'Array of children ages for parent profiles';
        COMMENT ON COLUMN profiles.gender IS 'Optional gender identification';
        COMMENT ON COLUMN profiles.city IS 'City of residence';
        COMMENT ON COLUMN profiles.state_province IS 'State or province of residence';
        COMMENT ON COLUMN profiles.country IS 'Country of residence';
      `);
      
      // Record the migration as completed
      await db.query(`
        INSERT INTO migration_history (migration_name) 
        VALUES ('002_add_profile_fields') 
        ON CONFLICT (migration_name) DO NOTHING;
      `);
      
      console.log('✅ Profile enhancement migration completed successfully!');
      console.log('📊 Profiles table now supports:');
      console.log('   - Children ages for parent accounts');
      console.log('   - Gender identification (optional)');
      console.log('   - Location information (city, state, country)');
      console.log('   - Enhanced user profile management');
    } else {
      console.log('✅ Profile enhancement migration already applied');
    }
    
    console.log('✅ Database cleanup and migrations completed successfully');
    
  } catch (error) {
    console.error('❌ Database migration failed:', error);
    // Don't throw - let the app continue with what it has
  }
}

async function createInlineSchema() {
  const schema = `
    -- Users table for authentication
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email VARCHAR(255) UNIQUE NOT NULL,
      name VARCHAR(255) NOT NULL,
      password_hash VARCHAR(255), -- For email/password auth
      profile_image_url TEXT,
      auth_provider VARCHAR(50) DEFAULT 'email', -- 'email', 'google', 'apple'
      google_id VARCHAR(255) UNIQUE,
      apple_id VARCHAR(255) UNIQUE,
      email_verified BOOLEAN DEFAULT false,
      is_active BOOLEAN DEFAULT true,
      last_login_at TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- User sessions table for authentication tokens
    CREATE TABLE IF NOT EXISTS user_sessions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token_hash VARCHAR(64) NOT NULL UNIQUE,
      expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
      device_info JSONB,
      ip_address INET,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Enhanced profiles table for comprehensive user profile management
    CREATE TABLE IF NOT EXISTS profiles (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      email VARCHAR(255) UNIQUE NOT NULL,
      
      -- Basic Information
      role VARCHAR(50) DEFAULT 'student', -- 'student', 'parent', 'teacher', 'admin'
      parent_id UUID REFERENCES users(id),
      first_name VARCHAR(255),
      last_name VARCHAR(255),
      display_name VARCHAR(255), -- Optional custom display name
      
      -- Academic Information
      grade_level VARCHAR(50),
      school VARCHAR(255),
      school_district VARCHAR(255),
      academic_year VARCHAR(20), -- e.g., '2024-2025'
      
      -- Personal Information
      date_of_birth DATE,
      timezone VARCHAR(50) DEFAULT 'UTC',
      language_preference VARCHAR(10) DEFAULT 'en',
      
      -- Learning Preferences
      learning_style VARCHAR(50), -- 'visual', 'auditory', 'kinesthetic', 'reading'
      difficulty_preference VARCHAR(20) DEFAULT 'adaptive', -- 'easy', 'medium', 'hard', 'adaptive'
      favorite_subjects TEXT[], -- Array of preferred subjects
      
      -- Accessibility & Preferences
      accessibility_needs TEXT[], -- Array of accessibility requirements
      voice_enabled BOOLEAN DEFAULT true,
      auto_speak_responses BOOLEAN DEFAULT false,
      preferred_voice_type VARCHAR(50) DEFAULT 'friendly',
      
      -- Privacy & Parental Controls
      privacy_level VARCHAR(20) DEFAULT 'standard', -- 'minimal', 'standard', 'full'
      parental_controls_enabled BOOLEAN DEFAULT false,
      data_sharing_consent BOOLEAN DEFAULT false,
      
      -- Profile Completion & Status
      profile_completion_percentage INTEGER DEFAULT 0,
      onboarding_completed BOOLEAN DEFAULT false,
      is_active BOOLEAN DEFAULT true,
      
      -- Metadata
      last_profile_update TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      
      -- Constraints
      CONSTRAINT valid_role CHECK (role IN ('student', 'parent', 'teacher', 'admin')),
      CONSTRAINT valid_difficulty CHECK (difficulty_preference IN ('easy', 'medium', 'hard', 'adaptive')),
      CONSTRAINT valid_privacy CHECK (privacy_level IN ('minimal', 'standard', 'full')),
      CONSTRAINT valid_completion_percentage CHECK (profile_completion_percentage >= 0 AND profile_completion_percentage <= 100)
    );

    -- Sessions table for study sessions
    CREATE TABLE IF NOT EXISTS sessions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      parent_id UUID REFERENCES users(id),
      session_type VARCHAR(50) DEFAULT 'homework',
      title VARCHAR(200),
      description TEXT,
      subject VARCHAR(100),
      status VARCHAR(50) DEFAULT 'active',
      start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      end_time TIMESTAMP WITH TIME ZONE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Questions table
    CREATE TABLE IF NOT EXISTS questions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
      image_data BYTEA,
      image_url TEXT,
      question_text TEXT,
      subject VARCHAR(100),
      topic VARCHAR(255),
      difficulty_level INTEGER DEFAULT 3,
      ai_solution JSONB,
      explanation TEXT,
      confidence_score FLOAT DEFAULT 0.0,
      processing_time FLOAT DEFAULT 0.0,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Conversations table for chat history
    CREATE TABLE IF NOT EXISTS conversations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
      session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
      message_type VARCHAR(50) NOT NULL, -- 'user' or 'assistant'
      message_text TEXT NOT NULL,
      message_data JSONB,
      tokens_used INTEGER DEFAULT 0,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Evaluations table
    CREATE TABLE IF NOT EXISTS evaluations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      session_id UUID REFERENCES sessions(id) ON DELETE CASCADE,
      question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      student_answer TEXT,
      ai_feedback JSONB,
      score FLOAT,
      max_score FLOAT DEFAULT 100.0,
      time_spent INTEGER, -- in seconds
      is_correct BOOLEAN,
      rubric JSONB,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Progress table
    CREATE TABLE IF NOT EXISTS progress (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      subject VARCHAR(100) NOT NULL,
      topic VARCHAR(255) NOT NULL,
      skill_level INTEGER DEFAULT 1,
      mastery_level FLOAT DEFAULT 0.0,
      questions_attempted INTEGER DEFAULT 0,
      questions_correct INTEGER DEFAULT 0,
      total_time_spent INTEGER DEFAULT 0, -- in seconds
      last_practiced_at TIMESTAMP WITH TIME ZONE,
      streak_count INTEGER DEFAULT 0,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
      UNIQUE(user_id, subject, topic)
    );

    -- Sessions summaries table
    CREATE TABLE IF NOT EXISTS sessions_summaries (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      session_id UUID UNIQUE REFERENCES sessions(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      total_questions INTEGER DEFAULT 0,
      questions_correct INTEGER DEFAULT 0,
      total_time_spent INTEGER DEFAULT 0, -- in seconds
      average_score FLOAT DEFAULT 0.0,
      subjects_covered TEXT[],
      key_topics TEXT[],
      areas_for_improvement TEXT[],
      summary_data JSONB,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Archived conversations table (for chat/conversation sessions)
    CREATE TABLE IF NOT EXISTS archived_conversations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      subject VARCHAR(100) NOT NULL,
      topic VARCHAR(200), -- User-defined or default topic summary
      conversation_content TEXT NOT NULL, -- Full conversation as "User: ... AI: ..." format
      archived_date DATE NOT NULL DEFAULT CURRENT_DATE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Archived questions table (for individual Q&A pairs)
    CREATE TABLE IF NOT EXISTS archived_questions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      subject VARCHAR(100) NOT NULL,
      question_text TEXT NOT NULL,
      student_answer TEXT,
      is_correct BOOLEAN,
      ai_answer TEXT, -- Optional AI provided answer
      archived_date DATE NOT NULL DEFAULT CURRENT_DATE,
      created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
    );

    -- Indexes for performance
    CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
    CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
    CREATE INDEX IF NOT EXISTS idx_users_apple_id ON users(apple_id);
    CREATE INDEX IF NOT EXISTS idx_user_sessions_token_hash ON user_sessions(token_hash);
    CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_user_sessions_expires_at ON user_sessions(expires_at);
    CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_questions_user_id ON questions(user_id);
    CREATE INDEX IF NOT EXISTS idx_questions_session_id ON questions(session_id);
    CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);
    CREATE INDEX IF NOT EXISTS idx_conversations_session_id ON conversations(session_id);
    
    -- Enhanced profile table indexes
    CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON profiles(user_id);
    CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);
    CREATE INDEX IF NOT EXISTS idx_profiles_parent_id ON profiles(parent_id);
    CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
    CREATE INDEX IF NOT EXISTS idx_profiles_completion ON profiles(profile_completion_percentage);
    CREATE INDEX IF NOT EXISTS idx_profiles_onboarding ON profiles(onboarding_completed);
    
    -- Archive table indexes
    CREATE INDEX IF NOT EXISTS idx_archived_conversations_user_date ON archived_conversations(user_id, archived_date DESC);
    CREATE INDEX IF NOT EXISTS idx_archived_conversations_subject ON archived_conversations(user_id, subject);
    CREATE INDEX IF NOT EXISTS idx_archived_questions_user_date ON archived_questions(user_id, archived_date DESC);
    CREATE INDEX IF NOT EXISTS idx_archived_questions_subject ON archived_questions(user_id, subject);

    -- Triggers for updated_at columns
    CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
    BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
    END;
    $$ language 'plpgsql';

    CREATE TRIGGER IF NOT EXISTS update_users_updated_at 
        BEFORE UPDATE ON users 
        FOR EACH ROW 
        EXECUTE FUNCTION update_updated_at_column();

    CREATE TRIGGER IF NOT EXISTS update_profiles_updated_at 
        BEFORE UPDATE ON profiles 
        FOR EACH ROW 
        EXECUTE FUNCTION update_updated_at_column();

    CREATE TRIGGER IF NOT EXISTS update_sessions_updated_at 
        BEFORE UPDATE ON sessions 
        FOR EACH ROW 
        EXECUTE FUNCTION update_updated_at_column();

    CREATE TRIGGER IF NOT EXISTS update_questions_updated_at 
        BEFORE UPDATE ON questions 
        FOR EACH ROW 
        EXECUTE FUNCTION update_updated_at_column();

    CREATE TRIGGER IF NOT EXISTS update_progress_updated_at 
        BEFORE UPDATE ON progress 
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