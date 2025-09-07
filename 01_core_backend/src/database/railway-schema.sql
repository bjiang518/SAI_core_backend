-- StudyAI Railway PostgreSQL Schema
-- Optimized for Railway deployment with performance indexes

-- Create archived_sessions table
CREATE TABLE IF NOT EXISTS archived_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
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

-- Create performance indexes
CREATE INDEX IF NOT EXISTS idx_archived_sessions_user_date 
    ON archived_sessions(user_id, session_date DESC);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_subject 
    ON archived_sessions(user_id, subject);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_review 
    ON archived_sessions(user_id, last_reviewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_created 
    ON archived_sessions(user_id, created_at DESC);

-- JSONB indexes for AI parsing result queries
CREATE INDEX IF NOT EXISTS idx_ai_parsing_result_questions 
    ON archived_sessions USING GIN ((ai_parsing_result->'questions'));

CREATE INDEX IF NOT EXISTS idx_ai_parsing_result_question_count 
    ON archived_sessions ((ai_parsing_result->>'questionCount'));

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