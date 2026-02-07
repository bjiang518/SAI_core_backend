-- Fix: Add missing ai_answer column to questions table
-- Error: column "ai_answer" does not exist at character 154
-- Root cause: The questions table doesn't have an ai_answer column but parent reports query for it

-- Check if column exists, if not add it
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
        AND table_name = 'questions'
        AND column_name = 'ai_answer'
    ) THEN
        ALTER TABLE questions ADD COLUMN ai_answer TEXT;
        COMMENT ON COLUMN questions.ai_answer IS 'AI-generated correct answer for comparison with student answer';

        RAISE NOTICE 'Added ai_answer column to questions table';
    ELSE
        RAISE NOTICE 'ai_answer column already exists in questions table';
    END IF;
END $$;

-- Also add to performance index if not exists
CREATE INDEX IF NOT EXISTS idx_questions_search
    ON questions USING gin(to_tsvector('english', question_text || ' ' || COALESCE(ai_answer, '')));

COMMENT ON INDEX idx_questions_search IS 'Full-text search index for questions including AI answers';
