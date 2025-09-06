-- StudyAI Individual Question Archive Database Schema
-- Run this in your Supabase SQL Editor

-- Create archived_questions table for individual question storage
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

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_archived_questions_user_archived 
    ON archived_questions(user_id, archived_at DESC);

CREATE INDEX IF NOT EXISTS idx_archived_questions_subject 
    ON archived_questions(user_id, subject);

CREATE INDEX IF NOT EXISTS idx_archived_questions_confidence 
    ON archived_questions(user_id, confidence DESC);

CREATE INDEX IF NOT EXISTS idx_archived_questions_visual 
    ON archived_questions(user_id, has_visual_elements);

CREATE INDEX IF NOT EXISTS idx_archived_questions_tags 
    ON archived_questions USING GIN(tags);

CREATE INDEX IF NOT EXISTS idx_archived_questions_text_search 
    ON archived_questions USING GIN(to_tsvector('english', question_text || ' ' || answer_text));

-- Enable Row Level Security (RLS)
ALTER TABLE archived_questions ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for user data isolation
-- Note: Using simple policies for now - update with proper JWT validation in production

-- Allow users to insert their own questions
CREATE POLICY "Users can insert their own questions" ON archived_questions
    FOR INSERT 
    WITH CHECK (true); -- Temporary: Allow all inserts

-- Allow users to view their own questions  
CREATE POLICY "Users can view their own questions" ON archived_questions
    FOR SELECT 
    USING (true); -- Temporary: Allow all reads

-- Allow users to update their own questions
CREATE POLICY "Users can update their own questions" ON archived_questions
    FOR UPDATE 
    USING (true); -- Temporary: Allow all updates

-- Allow users to delete their own questions
CREATE POLICY "Users can delete their own questions" ON archived_questions
    FOR DELETE 
    USING (true); -- Temporary: Allow all deletes

-- Create a function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_archived_questions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_archived_questions_updated_at_trigger
    BEFORE UPDATE ON archived_questions 
    FOR EACH ROW 
    EXECUTE FUNCTION update_archived_questions_updated_at();

-- Create a view for question summaries (useful for the app)
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
    created_at
FROM archived_questions
ORDER BY archived_at DESC;

-- Create statistics view for analytics
CREATE OR REPLACE VIEW question_statistics AS
SELECT 
    user_id,
    COUNT(*) as total_questions,
    COUNT(DISTINCT subject) as total_subjects,
    AVG(confidence) as average_confidence,
    SUM(review_count) as total_reviews,
    COUNT(CASE WHEN archived_at >= NOW() - INTERVAL '7 days' THEN 1 END) as recent_questions,
    COUNT(CASE WHEN has_visual_elements = true THEN 1 END) as visual_questions,
    MODE() WITHIN GROUP (ORDER BY subject) as most_common_subject
FROM archived_questions
GROUP BY user_id;

-- Insert some sample data for testing (optional)
-- Uncomment the following lines if you want sample data

/*
INSERT INTO archived_questions (
    user_id, 
    subject, 
    question_text,
    answer_text,
    confidence,
    has_visual_elements,
    processing_time,
    tags,
    notes
) VALUES 
(
    'test-user@example.com',
    'Mathematics',
    'What is the derivative of x²?',
    'The derivative of x² is 2x. Using the power rule: d/dx(xⁿ) = nxⁿ⁻¹, so d/dx(x²) = 2x²⁻¹ = 2x.',
    0.95,
    false,
    1.2,
    ARRAY['calculus', 'derivatives', 'power-rule'],
    'Important basic derivative rule to remember'
),
(
    'test-user@example.com',
    'Physics',
    'Calculate the force needed to accelerate a 10kg object at 5m/s²',
    'Using Newton''s second law F = ma: F = 10kg × 5m/s² = 50N',
    0.92,
    false,
    0.8,
    ARRAY['newton-laws', 'force', 'acceleration'],
    'Basic application of F=ma'
),
(
    'test-user@example.com',
    'Chemistry',
    'What is the molecular formula of glucose?',
    'The molecular formula of glucose is C₆H₁₂O₆. It contains 6 carbon atoms, 12 hydrogen atoms, and 6 oxygen atoms.',
    0.98,
    true,
    0.6,
    ARRAY['biochemistry', 'glucose', 'molecular-formula'],
    'Important sugar molecule'
);
*/

-- Display success message
DO $$
BEGIN
    RAISE NOTICE 'StudyAI Question Archive database schema created successfully!';
    RAISE NOTICE 'Tables created: archived_questions';
    RAISE NOTICE 'Indexes created: 6 performance indexes including GIN for text search';
    RAISE NOTICE 'RLS enabled with temporary policies';
    RAISE NOTICE 'Views created: question_summaries, question_statistics';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Test the QuestionArchiveService from your iOS app';
    RAISE NOTICE '2. Update RLS policies for production security';
    RAISE NOTICE '3. Consider adding full-text search capabilities';
END $$;