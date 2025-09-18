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
      console.log(`🔍 [DB] getConversationDetails called with ID: ${conversationId}, userId: ${userId}`);
      
      if (!conversationId) {
        console.error(`❌ [DB] Missing conversationId parameter`);
        throw new Error('Conversation ID is required');
      }
      
      if (!userId) {
        console.error(`❌ [DB] Missing userId parameter`);
        throw new Error('User ID is required');
      }
      
      // Step 1: Debug - Get all sessions for this user
      console.log(`🔍 [DB] Step 1: Getting all sessions for user ${userId}`);
      const userSessionsQuery = `SELECT id FROM sessions WHERE user_id = $1`;
      const userSessionsResult = await this.query(userSessionsQuery, [userId]);
      console.log(`📋 [DB] Found ${userSessionsResult.rows.length} sessions for user:`);
      userSessionsResult.rows.forEach((row, i) => {
        console.log(`📋 [DB] Session ${i+1}: ${row.id}`);
      });
      
      // Step 2: Check if the requested ID is one of the user's sessions
      const isUserSession = userSessionsResult.rows.some(row => row.id === conversationId);
      console.log(`📋 [DB] Is ${conversationId} a user session? ${isUserSession}`);
      
      if (isUserSession) {
        // Step 3: Get conversations for this specific session
        console.log(`🔍 [DB] Step 3: Getting conversations for session ${conversationId}`);
        const conversationsQuery = `SELECT * FROM conversations WHERE session_id = $1`;
        const conversationsResult = await this.query(conversationsQuery, [conversationId]);
        console.log(`📋 [DB] Found ${conversationsResult.rows.length} conversation messages for session ${conversationId}`);
        
        if (conversationsResult.rows.length > 0) {
          conversationsResult.rows.forEach((row, i) => {
            console.log(`📋 [DB] Message ${i+1}: Type=${row.message_type}, Text="${row.message_text.substring(0, 50)}..."`);
          });
        } else {
          console.log(`⚠️ [DB] No conversation messages found for session ${conversationId}`);
        }
      }
      
      // Step 4: Also check all conversations for this user to see what's available
      console.log(`🔍 [DB] Step 4: Getting all conversations for user ${userId}`);
      const allConversationsQuery = `
        SELECT session_id, COUNT(*) as message_count, MIN(created_at) as first_message, MAX(created_at) as last_message
        FROM conversations 
        WHERE user_id = $1 
        GROUP BY session_id
        ORDER BY last_message DESC
      `;
      const allConversationsResult = await this.query(allConversationsQuery, [userId]);
      console.log(`📋 [DB] Found conversations for ${allConversationsResult.rows.length} different sessions:`);
      allConversationsResult.rows.forEach((row, i) => {
        console.log(`📋 [DB] Conversation ${i+1}: Session=${row.session_id}, Messages=${row.message_count}, Last=${row.last_message}`);
      });
      
      // Now implement the actual conversation retrieval logic
      const query = `
        SELECT 
          c.*,
          s.subject as session_subject,
          s.start_time as session_start_time
        FROM conversations c
        LEFT JOIN sessions s ON c.session_id = s.id
        WHERE c.session_id = $1 AND c.user_id = $2
        ORDER BY c.created_at ASC
      `;
      
      console.log(`📋 [DB] Final Query: ${query}`);
      console.log(`📋 [DB] Parameters: [${conversationId}, ${userId}]`);
      
      const result = await this.query(query, [conversationId, userId]);
      const duration = Date.now() - startTime;
      
      console.log(`📊 [DB] Query completed in ${duration}ms`);
      console.log(`📊 [DB] Result rows count: ${result.rows.length}`);
      
      if (result.rows.length > 0) {
        // Combine all conversation messages into a single conversation object
        const messages = result.rows;
        const firstMessage = messages[0];
        
        // Build conversation content string
        let conversationContent = '';
        messages.forEach(msg => {
          const speaker = msg.message_type === 'user' ? 'User' : 'AI';
          conversationContent += `${speaker}: ${msg.message_text}\n\n`;
        });
        
        const conversation = {
          id: conversationId, // Use session_id as conversation id
          user_id: firstMessage.user_id,
          session_id: conversationId,
          subject: firstMessage.session_subject || 'General',
          topic: firstMessage.session_subject || 'Conversation',
          conversation_content: conversationContent.trim(),
          message_count: messages.length,
          archived_date: firstMessage.session_start_time || firstMessage.created_at,
          created_at: firstMessage.created_at
        };
        
        console.log(`✅ [DB] Conversation found in ${duration}ms - Session ID: ${conversationId}, Messages: ${messages.length}`);
        console.log(`✅ [DB] Subject: ${conversation.subject}, Content length: ${conversationContent.length} characters`);
        return conversation;
      } else {
        console.log(`❌ [DB] No conversation found for session ID: ${conversationId}, User: ${userId}`);
        
        // Check if this conversation exists in archived_conversations_new table
        console.log(`🔍 [DB] Checking archived_conversations_new for session ${conversationId}`);
        const archivedQuery = `SELECT * FROM archived_conversations_new WHERE user_id = $2 AND (id = $1 OR id IN (SELECT id FROM sessions WHERE id = $1 AND user_id = $2))`;
        const archivedResult = await this.query(archivedQuery, [conversationId, userId]);
        
        if (archivedResult.rows.length > 0) {
          const archived = archivedResult.rows[0];
          console.log(`✅ [DB] Found archived conversation: ID=${archived.id}, Subject=${archived.subject}`);
          console.log(`✅ [DB] Content length: ${archived.conversation_content?.length || 0} characters`);
          
          return {
            id: archived.id,
            user_id: archived.user_id,
            session_id: conversationId,
            subject: archived.subject || 'General',
            topic: archived.topic || archived.subject || 'Conversation',
            conversation_content: archived.conversation_content || '',
            message_count: 1,
            archived_date: archived.archived_date || archived.created_at,
            created_at: archived.created_at
          };
        }
        
        // Additional debug: Check if session exists but has no conversations
        const sessionCheckQuery = `SELECT * FROM sessions WHERE id = $1 AND user_id = $2`;
        const sessionCheckResult = await this.query(sessionCheckQuery, [conversationId, userId]);
        if (sessionCheckResult.rows.length > 0) {
          const session = sessionCheckResult.rows[0];
          console.log(`📋 [DB] Session exists but has no conversations:`);
          console.log(`📋 [DB] Session Type: ${session.session_type}, Subject: ${session.subject}, Created: ${session.created_at}`);
        } else {
          console.log(`📋 [DB] Session ${conversationId} does not exist for user ${userId}`);
        }
        
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
      const values = [
        userEmail, firstName, lastName, processedGradeLevel,
        kidsAges, gender, city, stateProvince, country
      ];

      const result = await this.query(query, values);
      return result.rows[0];
      
    } catch (error) {
      // Check if error is related to integer type conversion
      if (error.message.includes('invalid input syntax for type integer') || 
          error.message.includes('integer')) {
        
        // Second attempt: use integer grade level (for legacy INTEGER schema)
        const integerGradeLevel = gradeLevelMap[gradeLevel];
        
        if (integerGradeLevel === undefined) {
          // If no mapping exists, use 0 as default
          processedGradeLevel = 0;
        } else {
          processedGradeLevel = integerGradeLevel;
        }
        
        const valuesWithIntegerGrade = [
          userEmail, firstName, lastName, processedGradeLevel,
          kidsAges, gender, city, stateProvince, country
        ];

        const result = await this.query(query, valuesWithIntegerGrade);
        return result.rows[0];
      } else {
        // Re-throw non-grade-level related errors
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
  },

  // MARK: - Enhanced Progress System Functions

  /**
   * Update daily progress for a user
   */
  async updateDailyProgress(userId, progressData) {
    const {
      questionsAnswered = 0,
      correctAnswers = 0,
      studyTimeMinutes = 0,
      subjectsStudied = [],
      xpEarned = 0,
      bonusXp = 0,
      perfectSessions = 0
    } = progressData;

    const today = new Date().toISOString().split('T')[0];

    const query = `
      INSERT INTO daily_progress (
        user_id, date, questions_answered, correct_answers, study_time_minutes,
        subjects_studied, xp_earned, bonus_xp, perfect_sessions
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      ON CONFLICT (user_id, date) 
      DO UPDATE SET 
        questions_answered = daily_progress.questions_answered + EXCLUDED.questions_answered,
        correct_answers = daily_progress.correct_answers + EXCLUDED.correct_answers,
        study_time_minutes = daily_progress.study_time_minutes + EXCLUDED.study_time_minutes,
        subjects_studied = array(SELECT DISTINCT unnest(daily_progress.subjects_studied || EXCLUDED.subjects_studied)),
        xp_earned = daily_progress.xp_earned + EXCLUDED.xp_earned,
        bonus_xp = daily_progress.bonus_xp + EXCLUDED.bonus_xp,
        perfect_sessions = daily_progress.perfect_sessions + EXCLUDED.perfect_sessions,
        updated_at = NOW()
      RETURNING *
    `;

    const values = [userId, today, questionsAnswered, correctAnswers, studyTimeMinutes, subjectsStudied, xpEarned, bonusXp, perfectSessions];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get user's current progress summary
   */
  async getUserProgressSummary(userId) {
    const query = `
      WITH recent_progress AS (
        SELECT 
          dp.*,
          ss.current_streak,
          ss.longest_streak,
          ul.current_level,
          ul.total_xp,
          ul.xp_to_next_level
        FROM daily_progress dp
        LEFT JOIN study_streaks ss ON dp.user_id = ss.user_id
        LEFT JOIN user_levels ul ON dp.user_id = ul.user_id
        WHERE dp.user_id = $1 AND dp.date >= CURRENT_DATE - INTERVAL '30 days'
        ORDER BY dp.date DESC
      ),
      today_progress AS (
        SELECT * FROM daily_progress 
        WHERE user_id = $1 AND date = CURRENT_DATE
      ),
      weekly_stats AS (
        SELECT 
          COUNT(*) as days_active,
          SUM(questions_answered) as total_questions,
          SUM(correct_answers) as total_correct,
          SUM(xp_earned) as total_xp,
          AVG(CASE WHEN questions_answered > 0 THEN correct_answers::float / questions_answered ELSE 0 END) as avg_accuracy
        FROM daily_progress 
        WHERE user_id = $1 AND date >= CURRENT_DATE - INTERVAL '7 days'
      ),
      achievements_count AS (
        SELECT COUNT(*) as total_achievements
        FROM user_achievements 
        WHERE user_id = $1 AND is_completed = true
      ),
      daily_goal AS (
        SELECT * FROM daily_goals 
        WHERE user_id = $1 AND date = CURRENT_DATE
        ORDER BY created_at DESC LIMIT 1
      )
      SELECT 
        COALESCE(tp.questions_answered, 0) as today_questions,
        COALESCE(tp.correct_answers, 0) as today_correct,
        COALESCE(tp.xp_earned, 0) as today_xp,
        COALESCE(ss.current_streak, 0) as current_streak,
        COALESCE(ss.longest_streak, 0) as longest_streak,
        COALESCE(ul.current_level, 1) as current_level,
        COALESCE(ul.total_xp, 0) as total_xp,
        COALESCE(ul.xp_to_next_level, 100) as xp_to_next_level,
        COALESCE(ws.days_active, 0) as week_days_active,
        COALESCE(ws.total_questions, 0) as week_questions,
        COALESCE(ws.total_correct, 0) as week_correct,
        COALESCE(ws.avg_accuracy, 0) as week_accuracy,
        COALESCE(ac.total_achievements, 0) as total_achievements,
        COALESCE(dg.target_value, 5) as daily_goal_target,
        COALESCE(dg.current_value, 0) as daily_goal_current,
        COALESCE(dg.is_completed, false) as daily_goal_completed
      FROM (SELECT $1 as user_id) u
      LEFT JOIN today_progress tp ON u.user_id = tp.user_id
      LEFT JOIN study_streaks ss ON u.user_id = ss.user_id
      LEFT JOIN user_levels ul ON u.user_id = ul.user_id
      LEFT JOIN weekly_stats ws ON true
      LEFT JOIN achievements_count ac ON true
      LEFT JOIN daily_goal dg ON u.user_id = dg.user_id
    `;

    const result = await this.query(query, [userId]);
    return result.rows[0];
  },

  /**
   * Update user's study streak
   */
  async updateStudyStreak(userId) {
    const today = new Date().toISOString().split('T')[0];
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().split('T')[0];

    const query = `
      INSERT INTO study_streaks (user_id, current_streak, longest_streak, last_study_date)
      VALUES ($1, 1, 1, $2)
      ON CONFLICT (user_id) 
      DO UPDATE SET 
        current_streak = CASE 
          WHEN study_streaks.last_study_date = $3 THEN study_streaks.current_streak + 1
          WHEN study_streaks.last_study_date = $2 THEN study_streaks.current_streak
          ELSE 1
        END,
        longest_streak = GREATEST(study_streaks.longest_streak, 
          CASE 
            WHEN study_streaks.last_study_date = $3 THEN study_streaks.current_streak + 1
            WHEN study_streaks.last_study_date = $2 THEN study_streaks.current_streak
            ELSE 1
          END
        ),
        last_study_date = $2,
        updated_at = NOW()
      RETURNING *
    `;

    const result = await this.query(query, [userId, today, yesterday]);
    return result.rows[0];
  },

  /**
   * Update user level and XP
   */
  async updateUserXP(userId, xpGained) {
    const query = `
      INSERT INTO user_levels (user_id, total_xp, xp_to_next_level)
      VALUES ($1, $2, 100)
      ON CONFLICT (user_id) 
      DO UPDATE SET 
        total_xp = user_levels.total_xp + $2,
        current_level = CASE 
          WHEN (user_levels.total_xp + $2) >= user_levels.xp_to_next_level THEN user_levels.current_level + 1
          ELSE user_levels.current_level
        END,
        xp_to_next_level = CASE 
          WHEN (user_levels.total_xp + $2) >= user_levels.xp_to_next_level THEN 
            (user_levels.current_level + 1) * 100
          ELSE user_levels.xp_to_next_level
        END,
        last_level_up = CASE 
          WHEN (user_levels.total_xp + $2) >= user_levels.xp_to_next_level THEN NOW()
          ELSE user_levels.last_level_up
        END,
        updated_at = NOW()
      RETURNING *, 
        CASE WHEN (total_xp - $2) < xp_to_next_level AND total_xp >= xp_to_next_level THEN true ELSE false END as leveled_up
    `;

    const result = await this.query(query, [userId, xpGained]);
    return result.rows[0];
  },

  /**
   * Add achievement to user
   */
  async addUserAchievement(userId, achievementData) {
    const {
      achievementId,
      achievementName,
      description,
      icon,
      category = 'general',
      xpReward = 0,
      rarity = 'common'
    } = achievementData;

    const query = `
      INSERT INTO user_achievements (
        user_id, achievement_id, achievement_name, description, 
        icon, category, xp_reward, rarity
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ON CONFLICT (user_id, achievement_id) DO NOTHING
      RETURNING *
    `;

    const values = [userId, achievementId, achievementName, description, icon, category, xpReward, rarity];
    const result = await this.query(query, values);
    return result.rows[0];
  },

  /**
   * Get user achievements
   */
  async getUserAchievements(userId, limit = 50) {
    const query = `
      SELECT * FROM user_achievements 
      WHERE user_id = $1 AND is_completed = true
      ORDER BY unlocked_at DESC, rarity DESC
      LIMIT $2
    `;

    const result = await this.query(query, [userId, limit]);
    return result.rows;
  },

  /**
   * Update daily goal progress
   */
  async updateDailyGoal(userId, goalType = 'questions', progressValue = 1) {
    const today = new Date().toISOString().split('T')[0];

    const query = `
      INSERT INTO daily_goals (user_id, date, goal_type, current_value)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (user_id, date, goal_type) 
      DO UPDATE SET 
        current_value = daily_goals.current_value + $4,
        is_completed = (daily_goals.current_value + $4) >= daily_goals.target_value,
        updated_at = NOW()
      RETURNING *
    `;

    const result = await this.query(query, [userId, today, goalType, progressValue]);
    return result.rows[0];
  },

  /**
   * Get daily progress heatmap data
   */
  async getDailyProgressHeatmap(userId, days = 90) {
    const query = `
      SELECT 
        date,
        questions_answered,
        xp_earned,
        daily_goal_completed,
        CASE 
          WHEN questions_answered = 0 THEN 0
          WHEN questions_answered < 3 THEN 1
          WHEN questions_answered < 6 THEN 2
          WHEN questions_answered < 10 THEN 3
          ELSE 4
        END as activity_level
      FROM daily_progress 
      WHERE user_id = $1 AND date >= CURRENT_DATE - INTERVAL '$2 days'
      ORDER BY date DESC
    `;

    const result = await this.query(query, [userId, days]);
    return result.rows;
  },

  /**
   * Get subject progress breakdown
   */
  async getSubjectProgress(userId) {
    const query = `
      WITH subject_stats AS (
        SELECT 
          unnest(subjects_studied) as subject,
          SUM(questions_answered) as total_questions,
          SUM(correct_answers) as total_correct,
          COUNT(DISTINCT date) as days_studied,
          SUM(xp_earned) as total_xp
        FROM daily_progress 
        WHERE user_id = $1 AND date >= CURRENT_DATE - INTERVAL '30 days'
        GROUP BY unnest(subjects_studied)
      )
      SELECT 
        subject,
        total_questions,
        total_correct,
        days_studied,
        total_xp,
        CASE WHEN total_questions > 0 THEN total_correct::float / total_questions ELSE 0 END as accuracy,
        CASE 
          WHEN total_questions >= 50 THEN 'advanced'
          WHEN total_questions >= 20 THEN 'intermediate'
          WHEN total_questions >= 5 THEN 'beginner'
          ELSE 'novice'
        END as proficiency_level
      FROM subject_stats 
      WHERE subject IS NOT NULL
      ORDER BY total_xp DESC, total_questions DESC
    `;

    const result = await this.query(query, [userId]);
    return result.rows;
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
        session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
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
    
    // Check if progress enhancement migration has been applied
    const progressEnhancementCheck = await db.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_name IN ('daily_progress', 'progress_milestones', 'user_achievements')
      AND table_schema = 'public'
    `);
    
    if (progressEnhancementCheck.rows.length < 3) {
      console.log('📋 Applying progress enhancement migration...');
      
      // Create enhanced progress tracking tables
      await db.query(`
        -- Daily progress tracking for gamification
        CREATE TABLE IF NOT EXISTS daily_progress (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          date DATE NOT NULL,
          questions_answered INTEGER DEFAULT 0,
          correct_answers INTEGER DEFAULT 0,
          study_time_minutes INTEGER DEFAULT 0,
          subjects_studied TEXT[] DEFAULT '{}',
          streak_count INTEGER DEFAULT 0,
          xp_earned INTEGER DEFAULT 0,
          achievements_unlocked TEXT[] DEFAULT '{}',
          daily_goal_completed BOOLEAN DEFAULT false,
          bonus_xp INTEGER DEFAULT 0,
          perfect_sessions INTEGER DEFAULT 0,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(user_id, date)
        );

        -- Weekly/Monthly progress milestones
        CREATE TABLE IF NOT EXISTS progress_milestones (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          milestone_type VARCHAR(20) NOT NULL CHECK (milestone_type IN ('daily', 'weekly', 'monthly', 'custom')),
          period_start DATE NOT NULL,
          period_end DATE NOT NULL,
          total_xp INTEGER DEFAULT 0,
          total_questions INTEGER DEFAULT 0,
          accuracy_rate FLOAT DEFAULT 0,
          subjects_mastered TEXT[] DEFAULT '{}',
          achievements TEXT[] DEFAULT '{}',
          rank_position INTEGER,
          goal_completion_rate FLOAT DEFAULT 0,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );

        -- User achievements and badges
        CREATE TABLE IF NOT EXISTS user_achievements (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          achievement_id VARCHAR(100) NOT NULL,
          achievement_name VARCHAR(200) NOT NULL,
          description TEXT,
          icon VARCHAR(100),
          category VARCHAR(50) DEFAULT 'general',
          xp_reward INTEGER DEFAULT 0,
          rarity VARCHAR(20) DEFAULT 'common' CHECK (rarity IN ('common', 'rare', 'epic', 'legendary')),
          unlocked_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          progress_value INTEGER DEFAULT 0,
          max_progress INTEGER DEFAULT 1,
          is_completed BOOLEAN DEFAULT true,
          UNIQUE(user_id, achievement_id)
        );

        -- User level and XP tracking
        CREATE TABLE IF NOT EXISTS user_levels (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          current_level INTEGER DEFAULT 1,
          total_xp INTEGER DEFAULT 0,
          xp_to_next_level INTEGER DEFAULT 100,
          level_up_rewards TEXT[] DEFAULT '{}',
          last_level_up TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(user_id)
        );

        -- Study streaks tracking
        CREATE TABLE IF NOT EXISTS study_streaks (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          current_streak INTEGER DEFAULT 0,
          longest_streak INTEGER DEFAULT 0,
          last_study_date DATE,
          streak_freeze_used INTEGER DEFAULT 0,
          streak_freeze_available INTEGER DEFAULT 3,
          streak_rewards_claimed TEXT[] DEFAULT '{}',
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(user_id)
        );

        -- Study goals and challenges
        CREATE TABLE IF NOT EXISTS daily_goals (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          date DATE NOT NULL,
          goal_type VARCHAR(50) NOT NULL DEFAULT 'questions',
          target_value INTEGER NOT NULL DEFAULT 5,
          current_value INTEGER DEFAULT 0,
          is_completed BOOLEAN DEFAULT false,
          xp_reward INTEGER DEFAULT 50,
          bonus_multiplier FLOAT DEFAULT 1.0,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(user_id, date, goal_type)
        );

        -- Indexes for performance
        CREATE INDEX IF NOT EXISTS idx_daily_progress_user_date ON daily_progress(user_id, date DESC);
        CREATE INDEX IF NOT EXISTS idx_daily_progress_streak ON daily_progress(user_id, streak_count DESC);
        CREATE INDEX IF NOT EXISTS idx_user_achievements_user_category ON user_achievements(user_id, category);
        CREATE INDEX IF NOT EXISTS idx_user_achievements_unlocked_at ON user_achievements(user_id, unlocked_at DESC);
        CREATE INDEX IF NOT EXISTS idx_user_levels_xp ON user_levels(user_id, total_xp DESC);
        CREATE INDEX IF NOT EXISTS idx_study_streaks_current ON study_streaks(user_id, current_streak DESC);
        CREATE INDEX IF NOT EXISTS idx_daily_goals_user_date ON daily_goals(user_id, date DESC);
        CREATE INDEX IF NOT EXISTS idx_progress_milestones_user_period ON progress_milestones(user_id, period_start, period_end);

        -- Comments for documentation
        COMMENT ON TABLE daily_progress IS 'Daily progress tracking for gamification and engagement';
        COMMENT ON TABLE user_achievements IS 'Achievement system for user engagement and motivation';
        COMMENT ON TABLE user_levels IS 'User level and XP progression system';
        COMMENT ON TABLE study_streaks IS 'Daily study streak tracking and rewards';
        COMMENT ON TABLE daily_goals IS 'Adaptive daily goals and challenges';
      `);
      
      // Record the migration as completed
      await db.query(`
        INSERT INTO migration_history (migration_name) 
        VALUES ('003_progress_enhancement') 
        ON CONFLICT (migration_name) DO NOTHING;
      `);
      
      console.log('✅ Progress enhancement migration completed successfully!');
      console.log('📊 Enhanced progress system now supports:');
      console.log('   - Daily progress tracking with XP and streaks');
      console.log('   - Achievement system with badges and rewards');
      console.log('   - User levels and XP progression');
      console.log('   - Study streak tracking and bonuses');
      console.log('   - Adaptive daily goals and challenges');
      console.log('   - Weekly/monthly milestone tracking');
    } else {
      console.log('✅ Progress enhancement migration already applied');
    }
    
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