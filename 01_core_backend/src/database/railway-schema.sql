-- StudyAI Railway PostgreSQL Schema
-- Optimized for Railway deployment with performance indexes

-- Create users table for authentication
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    profile_image_url TEXT,
    auth_provider VARCHAR(50) NOT NULL DEFAULT 'email', -- 'email', 'google', 'apple'
    google_id VARCHAR(255),
    apple_id VARCHAR(255),
    password_hash VARCHAR(255), -- Only for email auth
    is_active BOOLEAN DEFAULT true,
    email_verified BOOLEAN DEFAULT false,
    last_login_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create user sessions table for token management
CREATE TABLE IF NOT EXISTS user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_info JSONB,
    ip_address INET,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create profiles table (equivalent to users but for compatibility)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    role VARCHAR(50) DEFAULT 'student',
    parent_id UUID REFERENCES profiles(id) ON DELETE SET NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    grade_level INTEGER,
    school VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create sessions table for study sessions
CREATE TABLE IF NOT EXISTS sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES users(id) ON DELETE SET NULL,
    session_type VARCHAR(50) NOT NULL DEFAULT 'homework',
    title VARCHAR(255),
    description TEXT,
    subject VARCHAR(100),
    status VARCHAR(50) DEFAULT 'active',
    start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    end_time TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create questions table for question storage and AI processing
CREATE TABLE IF NOT EXISTS questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    image_data BYTEA, -- Store image binary data
    image_url TEXT, -- Alternative image storage URL
    question_text TEXT,
    subject VARCHAR(100),
    topic VARCHAR(100),
    difficulty_level INTEGER DEFAULT 3,
    ai_solution JSONB,
    explanation TEXT,
    confidence_score FLOAT DEFAULT 0.0,
    processing_time FLOAT DEFAULT 0.0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create conversations table for AI chat history
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question_id UUID REFERENCES questions(id) ON DELETE CASCADE,
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    message_type VARCHAR(20) NOT NULL, -- 'user', 'ai', 'system'
    message_text TEXT NOT NULL,
    message_data JSONB,
    tokens_used INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create evaluations table for answer evaluation and scoring
CREATE TABLE IF NOT EXISTS evaluations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
    question_id UUID NOT NULL REFERENCES questions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    student_answer TEXT NOT NULL,
    ai_feedback JSONB,
    score FLOAT,
    max_score FLOAT DEFAULT 100.0,
    time_spent INTEGER, -- seconds
    is_correct BOOLEAN,
    rubric JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create progress table for learning progress tracking
CREATE TABLE IF NOT EXISTS progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject VARCHAR(100) NOT NULL,
    topic VARCHAR(100),
    skill_level FLOAT DEFAULT 0.0,
    mastery_level FLOAT DEFAULT 0.0,
    questions_attempted INTEGER DEFAULT 0,
    questions_correct INTEGER DEFAULT 0,
    total_time_spent INTEGER DEFAULT 0, -- seconds
    last_practiced_at TIMESTAMP WITH TIME ZONE,
    streak_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create sessions_summaries table for session analytics
CREATE TABLE IF NOT EXISTS sessions_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    total_questions INTEGER DEFAULT 0,
    questions_correct INTEGER DEFAULT 0,
    total_time_spent INTEGER DEFAULT 0, -- seconds
    average_score FLOAT DEFAULT 0.0,
    subjects_covered TEXT[],
    key_topics TEXT[],
    areas_for_improvement TEXT[],
    summary_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create archived_sessions table
CREATE TABLE IF NOT EXISTS archived_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject VARCHAR(100) NOT NULL,
    session_date DATE NOT NULL DEFAULT CURRENT_DATE,
    title VARCHAR(200),
    
    -- Image storage
    original_image_url TEXT NOT NULL,
    thumbnail_url TEXT,
    
    -- AI parsing results (stored as JSONB for flexibility and performance)
    ai_parsing_result JSONB NOT NULL,
    processing_time FLOAT NOT NULL DEFAULT 0,
    overall_confidence FLOAT NOT NULL DEFAULT 0,
    
    -- Student interaction
    student_answers JSONB,
    notes TEXT,
    review_count INTEGER DEFAULT 0,
    last_reviewed_at TIMESTAMP WITH TIME ZONE,
    
    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create archived_conversations table (NEW - for session chat conversations)
CREATE TABLE IF NOT EXISTS archived_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL, -- Matches archived_sessions format for compatibility
    session_id UUID NOT NULL, -- Reference to original session
    
    -- Content metadata
    subject VARCHAR(100) NOT NULL,
    title VARCHAR(200) NOT NULL,
    summary TEXT, -- AI-generated summary of the conversation
    
    -- Conversation metrics
    message_count INTEGER NOT NULL DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    duration_minutes INTEGER DEFAULT 0,
    
    -- Structured conversation data
    conversation_history JSONB NOT NULL, -- Full conversation with messages
    key_topics TEXT[], -- Array of key topics discussed
    learning_outcomes TEXT[], -- Array of learning outcomes achieved
    
    -- Semantic search support (NEW) - will be added dynamically if pgvector is available
    content_embedding TEXT, -- Stores embedding as JSON array if pgvector not available
    
    -- User interaction
    notes TEXT,
    review_count INTEGER DEFAULT 0,
    last_reviewed_at TIMESTAMP WITH TIME ZONE,
    
    -- Archival metadata
    archived_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Note: Semantic search will use JSON similarity instead of pgvector
-- since pgvector extension is not available on Railway

-- Create performance indexes
-- User table indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_auth_provider ON users(auth_provider);
CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_apple_id ON users(apple_id);
CREATE INDEX IF NOT EXISTS idx_users_last_login ON users(last_login_at DESC);

-- Profiles table indexes
CREATE INDEX IF NOT EXISTS idx_profiles_email ON profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_parent_id ON profiles(parent_id);
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_grade_level ON profiles(grade_level);

-- User sessions indexes
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_token ON user_sessions(token_hash);
CREATE INDEX IF NOT EXISTS idx_user_sessions_expires ON user_sessions(expires_at);

-- Sessions table indexes
CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_parent_id ON sessions(parent_id);
CREATE INDEX IF NOT EXISTS idx_sessions_type_subject ON sessions(session_type, subject);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
CREATE INDEX IF NOT EXISTS idx_sessions_start_time ON sessions(start_time DESC);

-- Questions table indexes
CREATE INDEX IF NOT EXISTS idx_questions_user_id ON questions(user_id);
CREATE INDEX IF NOT EXISTS idx_questions_session_id ON questions(session_id);
CREATE INDEX IF NOT EXISTS idx_questions_subject ON questions(subject);
CREATE INDEX IF NOT EXISTS idx_questions_topic ON questions(topic);
CREATE INDEX IF NOT EXISTS idx_questions_difficulty ON questions(difficulty_level);
CREATE INDEX IF NOT EXISTS idx_questions_created_at ON questions(created_at DESC);

-- Conversations table indexes
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_conversations_question_id ON conversations(question_id);
CREATE INDEX IF NOT EXISTS idx_conversations_session_id ON conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_conversations_message_type ON conversations(message_type);
CREATE INDEX IF NOT EXISTS idx_conversations_created_at ON conversations(created_at DESC);

-- Evaluations table indexes
CREATE INDEX IF NOT EXISTS idx_evaluations_session_id ON evaluations(session_id);
CREATE INDEX IF NOT EXISTS idx_evaluations_question_id ON evaluations(question_id);
CREATE INDEX IF NOT EXISTS idx_evaluations_user_id ON evaluations(user_id);
CREATE INDEX IF NOT EXISTS idx_evaluations_score ON evaluations(score);
CREATE INDEX IF NOT EXISTS idx_evaluations_is_correct ON evaluations(is_correct);
CREATE INDEX IF NOT EXISTS idx_evaluations_created_at ON evaluations(created_at DESC);

-- Progress table indexes
CREATE INDEX IF NOT EXISTS idx_progress_user_id ON progress(user_id);
CREATE INDEX IF NOT EXISTS idx_progress_subject ON progress(subject);
CREATE INDEX IF NOT EXISTS idx_progress_topic ON progress(topic);
CREATE INDEX IF NOT EXISTS idx_progress_skill_level ON progress(skill_level);
CREATE INDEX IF NOT EXISTS idx_progress_mastery_level ON progress(mastery_level);
CREATE INDEX IF NOT EXISTS idx_progress_last_practiced ON progress(last_practiced_at DESC);

-- Sessions summaries table indexes
CREATE INDEX IF NOT EXISTS idx_sessions_summaries_session_id ON sessions_summaries(session_id);
CREATE INDEX IF NOT EXISTS idx_sessions_summaries_user_id ON sessions_summaries(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_summaries_average_score ON sessions_summaries(average_score);
CREATE INDEX IF NOT EXISTS idx_sessions_summaries_created_at ON sessions_summaries(created_at DESC);

-- Archived sessions indexes (for homework/questions)
CREATE INDEX IF NOT EXISTS idx_archived_sessions_user_date 
    ON archived_sessions(user_id, session_date DESC);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_subject 
    ON archived_sessions(user_id, subject);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_review 
    ON archived_sessions(user_id, last_reviewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_created 
    ON archived_sessions(user_id, created_at DESC);

-- Archived conversations indexes (NEW - for session chat conversations)
CREATE INDEX IF NOT EXISTS idx_archived_conversations_user_archived 
    ON archived_conversations(user_id, archived_at DESC);

CREATE INDEX IF NOT EXISTS idx_archived_conversations_session_id 
    ON archived_conversations(session_id);

CREATE INDEX IF NOT EXISTS idx_archived_conversations_subject 
    ON archived_conversations(user_id, subject);

CREATE INDEX IF NOT EXISTS idx_archived_conversations_message_count 
    ON archived_conversations(user_id, message_count DESC);

CREATE INDEX IF NOT EXISTS idx_archived_conversations_review 
    ON archived_conversations(user_id, last_reviewed_at DESC);

-- Full-text search index for conversation summaries and topics (using PostgreSQL built-in)
CREATE INDEX IF NOT EXISTS idx_archived_conversations_summary_search 
    ON archived_conversations USING gin(to_tsvector('english', title || ' ' || COALESCE(summary, '')));

CREATE INDEX IF NOT EXISTS idx_archived_conversations_topics_search 
    ON archived_conversations USING gin(key_topics);

-- Note: Semantic search will use JSON array similarity calculations
-- since pgvector is not available on Railway

-- Hybrid search indexes for optimized multi-criteria queries
CREATE INDEX IF NOT EXISTS idx_archived_conversations_hybrid_search 
    ON archived_conversations(user_id, archived_at DESC, subject, message_count);

-- Date-based indexes for flexible date queries (using simple date columns)
CREATE INDEX IF NOT EXISTS idx_archived_conversations_date_user 
    ON archived_conversations(user_id, archived_at DESC);

CREATE INDEX IF NOT EXISTS idx_archived_conversations_date_subject 
    ON archived_conversations(user_id, archived_at DESC, subject);

-- JSONB indexes for AI parsing result queries (using GIN for JSON content)
CREATE INDEX IF NOT EXISTS idx_ai_parsing_result_json 
    ON archived_sessions USING GIN (ai_parsing_result);

-- Create updated_at trigger function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
DROP TRIGGER IF EXISTS update_archived_sessions_updated_at ON archived_sessions;
CREATE TRIGGER update_archived_sessions_updated_at 
    BEFORE UPDATE ON archived_sessions 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Create useful views
CREATE OR REPLACE VIEW session_summaries AS
SELECT 
    id,
    user_id,
    subject,
    session_date,
    title,
    (ai_parsing_result->>'questionCount')::integer as question_count,
    overall_confidence,
    thumbnail_url,
    review_count,
    created_at,
    updated_at
FROM archived_sessions
ORDER BY session_date DESC;

-- Analytics view for user statistics
CREATE OR REPLACE VIEW user_session_analytics AS
SELECT 
    user_id,
    subject,
    COUNT(*) as session_count,
    AVG(overall_confidence) as avg_confidence,
    SUM((ai_parsing_result->>'questionCount')::integer) as total_questions,
    MIN(session_date) as first_session,
    MAX(session_date) as last_session,
    (MAX(session_date) - MIN(session_date)) + 1 as study_span_days
FROM archived_sessions
GROUP BY user_id, subject;

-- Weekly progress view
CREATE OR REPLACE VIEW weekly_progress AS
SELECT 
    user_id,
    DATE_TRUNC('week', session_date) as week_start,
    COUNT(*) as sessions_count,
    COUNT(DISTINCT subject) as subjects_studied,
    AVG(overall_confidence) as avg_confidence,
    SUM((ai_parsing_result->>'questionCount')::integer) as total_questions
FROM archived_sessions
GROUP BY user_id, DATE_TRUNC('week', session_date)
ORDER BY user_id, week_start DESC;

-- Create function for getting user statistics
CREATE OR REPLACE FUNCTION get_user_stats(p_user_id TEXT)
RETURNS TABLE (
    total_sessions BIGINT,
    subjects_studied BIGINT,
    avg_confidence NUMERIC,
    total_questions BIGINT,
    this_week_sessions BIGINT,
    this_month_sessions BIGINT,
    current_streak INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*) as total_sessions,
        COUNT(DISTINCT subject) as subjects_studied,
        ROUND(AVG(overall_confidence), 3) as avg_confidence,
        COALESCE(SUM((ai_parsing_result->>'questionCount')::integer), 0) as total_questions,
        COUNT(CASE WHEN session_date >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as this_week_sessions,
        COUNT(CASE WHEN session_date >= DATE_TRUNC('month', CURRENT_DATE) THEN 1 END) as this_month_sessions,
        COALESCE(calculate_current_streak(p_user_id), 0) as current_streak
    FROM archived_sessions 
    WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate current study streak
CREATE OR REPLACE FUNCTION calculate_current_streak(p_user_id TEXT)
RETURNS INTEGER AS $$
DECLARE
    streak_count INTEGER := 0;
    check_date DATE := CURRENT_DATE;
    has_session BOOLEAN;
BEGIN
    -- Check if user has studied today or yesterday (to account for time zones)
    SELECT EXISTS(
        SELECT 1 FROM archived_sessions 
        WHERE user_id = p_user_id 
        AND session_date >= CURRENT_DATE - INTERVAL '1 day'
    ) INTO has_session;
    
    -- If no recent activity, streak is 0
    IF NOT has_session THEN
        RETURN 0;
    END IF;
    
    -- Count consecutive days with sessions
    LOOP
        SELECT EXISTS(
            SELECT 1 FROM archived_sessions 
            WHERE user_id = p_user_id AND session_date = check_date
        ) INTO has_session;
        
        IF has_session THEN
            streak_count := streak_count + 1;
            check_date := check_date - INTERVAL '1 day';
        ELSE
            EXIT; -- Break the loop when we find a day without sessions
        END IF;
        
        -- Safety check to prevent infinite loops
        IF streak_count > 365 THEN
            EXIT;
        END IF;
    END LOOP;
    
    RETURN streak_count;
END;
$$ LANGUAGE plpgsql;

-- Create function for subject recommendations
CREATE OR REPLACE FUNCTION get_subject_recommendations(p_user_id TEXT, p_limit INTEGER DEFAULT 3)
RETURNS TABLE (
    subject VARCHAR,
    reason TEXT,
    priority INTEGER,
    avg_confidence NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH subject_performance AS (
        SELECT 
            s.subject,
            AVG(s.overall_confidence) as avg_conf,
            COUNT(*) as session_count,
            MAX(s.session_date) as last_session
        FROM archived_sessions s
        WHERE s.user_id = p_user_id
        GROUP BY s.subject
    )
    SELECT 
        sp.subject,
        CASE 
            WHEN sp.avg_conf < 0.7 THEN 'Low confidence - needs practice'
            WHEN sp.last_session < CURRENT_DATE - INTERVAL '7 days' THEN 'Not practiced recently'
            WHEN sp.session_count < 3 THEN 'New subject - continue building foundation'
            ELSE 'Ready for advanced topics'
        END as reason,
        CASE 
            WHEN sp.avg_conf < 0.7 THEN 1
            WHEN sp.last_session < CURRENT_DATE - INTERVAL '7 days' THEN 2
            ELSE 3
        END as priority,
        ROUND(sp.avg_conf, 3) as avg_confidence
    FROM subject_performance sp
    ORDER BY priority, avg_confidence
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;