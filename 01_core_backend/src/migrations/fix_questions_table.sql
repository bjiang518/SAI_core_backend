-- Fix: Add missing columns to questions table
-- This ensures the questions table has all required columns for Assistants API

-- Add missing columns if they don't exist
ALTER TABLE questions
ADD COLUMN IF NOT EXISTS student_answer TEXT,
ADD COLUMN IF NOT EXISTS ai_answer TEXT,
ADD COLUMN IF NOT EXISTS is_correct BOOLEAN;

-- Add useful indexes
CREATE INDEX IF NOT EXISTS idx_questions_user_subject ON questions(user_id, subject);
CREATE INDEX IF NOT EXISTS idx_questions_incorrect ON questions(user_id, subject, is_correct) WHERE is_correct = false;

-- Verify columns exist
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'questions'
ORDER BY ordinal_position;
