-- Migration: Add Grading Fields to Archived Questions
-- Version: 001
-- Description: Adds grading support fields for homework grading functionality

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

-- Update the question_summaries view to include grading info
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