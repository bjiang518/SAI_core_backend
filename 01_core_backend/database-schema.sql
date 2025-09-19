-- StudyAI Database Schema
-- Designed to match iOS app data models

-- Users table (if not exists)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Subject categories enum
CREATE TYPE subject_category AS ENUM (
    'Mathematics',
    'Physics', 
    'Chemistry',
    'Biology',
    'English',
    'History',
    'Geography',
    'Computer Science',
    'Foreign Language',
    'Arts',
    'Other'
);

-- Difficulty levels enum
CREATE TYPE difficulty_level AS ENUM (
    'Beginner',
    'Intermediate', 
    'Advanced',
    'Expert'
);

-- Daily subject activities table
CREATE TABLE IF NOT EXISTS daily_subject_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    subject subject_category NOT NULL,
    question_count INTEGER DEFAULT 0,
    correct_answers INTEGER DEFAULT 0,
    study_duration_minutes INTEGER DEFAULT 0,
    timezone VARCHAR(50) DEFAULT 'UTC',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Ensure one record per user per date per subject
    UNIQUE(user_id, date, subject)
);

-- Subject progress summary table
CREATE TABLE IF NOT EXISTS subject_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject subject_category NOT NULL,
    questions_answered INTEGER DEFAULT 0,
    correct_answers INTEGER DEFAULT 0,
    total_study_time_minutes INTEGER DEFAULT 0,
    streak_days INTEGER DEFAULT 0,
    last_studied_date DATE,
    topic_breakdown JSONB DEFAULT '{}',
    difficulty_progression JSONB DEFAULT '{}',
    weak_areas TEXT[] DEFAULT '{}',
    strong_areas TEXT[] DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Ensure one record per user per subject
    UNIQUE(user_id, subject)
);

-- Question tracking table for detailed analytics
CREATE TABLE IF NOT EXISTS question_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject subject_category NOT NULL,
    question_text TEXT,
    user_answer TEXT,
    correct_answer TEXT,
    is_correct BOOLEAN NOT NULL,
    difficulty difficulty_level DEFAULT 'Intermediate',
    topic VARCHAR(255),
    time_spent_seconds INTEGER DEFAULT 0,
    session_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Subject insights table for recommendations
CREATE TABLE IF NOT EXISTS subject_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subjects_to_focus subject_category[] DEFAULT '{}',
    subjects_to_maintain subject_category[] DEFAULT '{}',
    study_time_recommendations JSONB DEFAULT '{}',
    personalized_tips TEXT[] DEFAULT '{}',
    analysis_date DATE DEFAULT CURRENT_DATE,
    confidence_score FLOAT DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Ensure one insight record per user per day
    UNIQUE(user_id, analysis_date)
);

-- Archived homework sessions
CREATE TABLE IF NOT EXISTS archived_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject VARCHAR(255) NOT NULL,
    session_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    title VARCHAR(500),
    original_image_url TEXT,
    thumbnail_url TEXT,
    ai_parsing_result JSONB NOT NULL,
    processing_time DOUBLE PRECISION DEFAULT 0,
    overall_confidence FLOAT DEFAULT 0,
    student_answers JSONB DEFAULT '{}',
    notes TEXT,
    review_count INTEGER DEFAULT 0,
    last_reviewed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_daily_activities_user_date ON daily_subject_activities(user_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_daily_activities_subject ON daily_subject_activities(subject);
CREATE INDEX IF NOT EXISTS idx_subject_progress_user ON subject_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_question_sessions_user_date ON question_sessions(user_id, session_date DESC);
CREATE INDEX IF NOT EXISTS idx_question_sessions_subject ON question_sessions(subject);
CREATE INDEX IF NOT EXISTS idx_archived_sessions_user ON archived_sessions(user_id, session_date DESC);

-- Create functions for automatic timestamp updates
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at columns
CREATE TRIGGER update_daily_activities_updated_at BEFORE UPDATE ON daily_subject_activities FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_subject_progress_updated_at BEFORE UPDATE ON subject_progress FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_subject_insights_updated_at BEFORE UPDATE ON subject_insights FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_archived_sessions_updated_at BEFORE UPDATE ON archived_sessions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();