-- Database Migration: Add Unique Constraint to Questions Table
-- Created: 2026-02-07
-- Purpose: Enable upsert behavior for iOS sync endpoint

-- Step 1: Remove duplicate questions (keep oldest one for each unique combination)
-- This is safe because duplicates are errors from failed syncs
WITH duplicates AS (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY user_id, question_text, student_answer
               ORDER BY created_at ASC  -- Keep oldest
           ) as rn
    FROM questions
    WHERE question_text IS NOT NULL
      AND student_answer IS NOT NULL
)
DELETE FROM questions
WHERE id IN (
    SELECT id FROM duplicates WHERE rn > 1
);

-- Step 2: Add unique constraint
-- This prevents future duplicates and enables ON CONFLICT behavior
ALTER TABLE questions
ADD CONSTRAINT questions_unique_user_question_answer
UNIQUE (user_id, question_text, student_answer);

-- Add comment
COMMENT ON CONSTRAINT questions_unique_user_question_answer ON questions
IS 'Ensures each user can only have one record per unique question+answer combination';

-- Verification
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'questions_unique_user_question_answer'
    ) THEN
        RAISE NOTICE '✅ Migration successful: Unique constraint added to questions table';
    ELSE
        RAISE EXCEPTION '❌ Migration failed: Constraint not created';
    END IF;
END $$;
