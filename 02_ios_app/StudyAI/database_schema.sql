-- StudyAI Database Schema for Session History & Mistake Notebook
-- Run this in your Supabase SQL Editor

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
    
    -- AI parsing results (stored as JSONB for flexibility)
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

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_archived_sessions_user_date 
    ON archived_sessions(user_id, session_date DESC);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_subject 
    ON archived_sessions(user_id, subject);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_review 
    ON archived_sessions(user_id, last_reviewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_archived_sessions_created 
    ON archived_sessions(user_id, created_at DESC);

-- Enable Row Level Security (RLS)
ALTER TABLE archived_sessions ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for user data isolation
-- Note: Since StudyAI uses custom auth (not Supabase Auth), we'll use a simple policy for now
-- In production, you should implement proper JWT token validation

-- Allow users to insert their own sessions
CREATE POLICY "Users can insert their own sessions" ON archived_sessions
    FOR INSERT 
    WITH CHECK (true); -- Temporary: Allow all inserts (update with proper auth)

-- Allow users to view their own sessions  
CREATE POLICY "Users can view their own sessions" ON archived_sessions
    FOR SELECT 
    USING (true); -- Temporary: Allow all reads (update with proper auth)

-- Allow users to update their own sessions
CREATE POLICY "Users can update their own sessions" ON archived_sessions
    FOR UPDATE 
    USING (true); -- Temporary: Allow all updates (update with proper auth)

-- Allow users to delete their own sessions (optional)
CREATE POLICY "Users can delete their own sessions" ON archived_sessions
    FOR DELETE 
    USING (true); -- Temporary: Allow all deletes (update with proper auth)

-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_archived_sessions_updated_at 
    BEFORE UPDATE ON archived_sessions 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Insert some sample data for testing (optional)
-- Uncomment the following lines if you want sample data

/*
INSERT INTO archived_sessions (
    user_id, 
    subject, 
    title, 
    original_image_url, 
    ai_parsing_result, 
    processing_time, 
    overall_confidence,
    notes
) VALUES 
(
    'test-user@example.com',
    'Mathematics',
    'Algebra Practice Problems',
    'https://example.com/homework1.jpg',
    '{
        "questions": [
            {
                "questionNumber": 1,
                "questionText": "Solve for x: 2x + 5 = 15",
                "answerText": "To solve: 2x + 5 = 15, subtract 5 from both sides: 2x = 10, divide by 2: x = 5",
                "confidence": 0.95,
                "hasVisualElements": false
            },
            {
                "questionNumber": 2,
                "questionText": "Calculate the area of a circle with radius 7 cm",
                "answerText": "Area = πr² = π × 7² = 49π ≈ 153.94 cm²",
                "confidence": 0.92,
                "hasVisualElements": true
            }
        ],
        "questionCount": 2,
        "parsingMethod": "AI-Powered Parsing"
    }',
    2.3,
    0.935,
    'Practice problems from Chapter 5. Need to review area formulas.'
),
(
    'test-user@example.com',
    'Physics',
    'Motion and Forces',
    'https://example.com/homework2.jpg',
    '{
        "questions": [
            {
                "questionNumber": 1,
                "questionText": "A car accelerates from rest at 3 m/s². How fast is it going after 5 seconds?",
                "answerText": "Using v = u + at, where u = 0, a = 3 m/s², t = 5s: v = 0 + 3×5 = 15 m/s",
                "confidence": 0.88,
                "hasVisualElements": false
            }
        ],
        "questionCount": 1,
        "parsingMethod": "AI-Powered Parsing"
    }',
    1.8,
    0.88,
    'Need to practice kinematic equations more.'
);
*/

-- Create a view for session summaries (useful for the app)
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
    created_at
FROM archived_sessions
ORDER BY session_date DESC;

-- Grant necessary permissions (if using service role)
-- GRANT ALL ON archived_sessions TO service_role;
-- GRANT ALL ON session_summaries TO service_role;

-- Display success message
DO $$
BEGIN
    RAISE NOTICE 'StudyAI database schema created successfully!';
    RAISE NOTICE 'Tables created: archived_sessions';
    RAISE NOTICE 'Indexes created: 4 performance indexes';
    RAISE NOTICE 'RLS enabled with temporary policies';
    RAISE NOTICE 'Views created: session_summaries';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Update SupabaseService.swift with your project URL and anon key';
    RAISE NOTICE '2. Test the connection from your iOS app';
    RAISE NOTICE '3. Update RLS policies for production security';
END $$;