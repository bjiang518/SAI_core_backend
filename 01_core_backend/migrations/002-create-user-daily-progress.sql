-- Migration: Create user_daily_progress table
-- Purpose: Store daily aggregated progress counters synced from iOS app
-- iOS app tracks subject-specific counters that reset at midnight
-- This table stores the daily snapshot with subject breakdown

-- Create user_daily_progress table
CREATE TABLE IF NOT EXISTS user_daily_progress (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,

    -- Subject-specific progress (array of subject counters)
    -- Structure: [{"subject": "Mathematics", "numberOfQuestions": 15, "numberOfCorrectQuestions": 12, "accuracy": 80.0}, ...]
    subject_progress JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Aggregated daily totals (computed from subject_progress)
    total_questions INTEGER NOT NULL DEFAULT 0,
    correct_answers INTEGER NOT NULL DEFAULT 0,
    accuracy DECIMAL(5,2) NOT NULL DEFAULT 0.00,

    -- Timestamps
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CONSTRAINT unique_user_date UNIQUE (user_id, date),
    CONSTRAINT valid_accuracy CHECK (accuracy >= 0 AND accuracy <= 100),
    CONSTRAINT valid_questions CHECK (total_questions >= 0),
    CONSTRAINT valid_correct CHECK (correct_answers >= 0 AND correct_answers <= total_questions)
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_user_daily_progress_user_id ON user_daily_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_user_daily_progress_date ON user_daily_progress(date);
CREATE INDEX IF NOT EXISTS idx_user_daily_progress_user_date ON user_daily_progress(user_id, date DESC);

-- Create trigger for automatic updated_at timestamp
CREATE TRIGGER update_user_daily_progress_updated_at
    BEFORE UPDATE ON user_daily_progress
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Add comments for documentation
COMMENT ON TABLE user_daily_progress IS 'Daily progress counters synced from iOS app - one row per user per day with subject breakdown';
COMMENT ON COLUMN user_daily_progress.subject_progress IS 'JSONB array of subject-specific counters: [{"subject": "Math", "numberOfQuestions": 10, "numberOfCorrectQuestions": 8, "accuracy": 80}]';
COMMENT ON COLUMN user_daily_progress.total_questions IS 'Sum of questions across all subjects for this day';
COMMENT ON COLUMN user_daily_progress.correct_answers IS 'Sum of correct answers across all subjects for this day';
COMMENT ON COLUMN user_daily_progress.accuracy IS 'Overall accuracy percentage for this day (0-100)';

-- Example query to get weekly progress:
-- SELECT * FROM user_daily_progress
-- WHERE user_id = $1 AND date >= CURRENT_DATE - INTERVAL '7 days'
-- ORDER BY date DESC;

-- Example query to get subject breakdown:
-- SELECT
--   date,
--   jsonb_array_elements(subject_progress) as subject_data
-- FROM user_daily_progress
-- WHERE user_id = $1 AND date BETWEEN $2 AND $3;
