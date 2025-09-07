/**
 * Railway PostgreSQL Database Configuration
 * Replaces Supabase with Railway-hosted PostgreSQL
 */

const { Pool } = require('pg');

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
   * Archive session (replacement for Supabase insert)
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
   * Fetch archived sessions for user
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
   * Get full session details
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
   * Update session review count
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
    
    // Check if tables exist
    const tableCheck = await db.query(`
      SELECT tablename FROM pg_tables 
      WHERE schemaname = 'public' AND tablename = 'archived_sessions'
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
      console.log('✅ Database tables already exist');
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