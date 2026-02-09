-- Migration: Add Monthly Report Support Fields
-- Created: 2026-02-08
-- Purpose: Add columns needed for monthly report insights

-- ========================================================================
-- PART 1: Add columns to questions table for enhanced monthly reporting
-- ========================================================================

-- Add skill tier tracking for mastery progression
ALTER TABLE questions
ADD COLUMN IF NOT EXISTS skill_tier VARCHAR(20)
CHECK (skill_tier IN ('beginner', 'intermediate', 'advanced', 'master', 'expert', NULL));

COMMENT ON COLUMN questions.skill_tier IS
'Student skill level at time of question: beginner (0-50%), intermediate (50-70%), advanced (70-85%), master (85-95%), expert (95%+)';

-- Add time tracking for learning efficiency calculations
ALTER TABLE questions
ADD COLUMN IF NOT EXISTS time_spent_seconds INTEGER
CHECK (time_spent_seconds >= 0 AND time_spent_seconds <= 7200); -- Max 2 hours per question

COMMENT ON COLUMN questions.time_spent_seconds IS
'Time student spent on this question in seconds (for efficiency calculations)';

-- Add optional student mood tracking for burnout detection
ALTER TABLE questions
ADD COLUMN IF NOT EXISTS student_mood VARCHAR(20)
CHECK (student_mood IN ('confident', 'frustrated', 'neutral', 'excited', 'confused', NULL));

COMMENT ON COLUMN questions.student_mood IS
'Optional: Student self-reported mood after question (helps detect burnout patterns)';

-- Create index for skill tier queries (monthly mastery progression reports)
CREATE INDEX IF NOT EXISTS idx_questions_skill_tier
ON questions(user_id, subject, skill_tier)
WHERE skill_tier IS NOT NULL;

-- Create index for time-based efficiency queries
CREATE INDEX IF NOT EXISTS idx_questions_time_spent
ON questions(user_id, time_spent_seconds)
WHERE time_spent_seconds IS NOT NULL;

-- ========================================================================
-- PART 2: Create user_goals table for goal tracking
-- ========================================================================

CREATE TABLE IF NOT EXISTS user_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Goal definition
    goal_type VARCHAR(50) NOT NULL, -- 'accuracy', 'streak', 'questions', 'subject_mastery', 'study_time'
    goal_description TEXT NOT NULL,
    target_subject VARCHAR(100), -- NULL if goal is global (e.g., "study 20 days")

    -- Goal targets
    target_value FLOAT NOT NULL, -- e.g., 80 for 80% accuracy
    current_value FLOAT DEFAULT 0.0,
    start_value FLOAT DEFAULT 0.0, -- Value when goal was created

    -- Goal timeline
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Goal status
    status VARCHAR(20) NOT NULL DEFAULT 'in_progress'
        CHECK (status IN ('in_progress', 'achieved', 'failed', 'abandoned')),
    achieved_at TIMESTAMP WITH TIME ZONE,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Ensure goal dates are valid
    CHECK (end_date >= start_date),
    CHECK (target_value > 0)
);

-- Indexes for goal queries
CREATE INDEX IF NOT EXISTS idx_user_goals_user_status
ON user_goals(user_id, status)
WHERE status = 'in_progress';

CREATE INDEX IF NOT EXISTS idx_user_goals_user_date
ON user_goals(user_id, end_date DESC);

CREATE INDEX IF NOT EXISTS idx_user_goals_subject
ON user_goals(user_id, target_subject, status)
WHERE target_subject IS NOT NULL;

-- Comments
COMMENT ON TABLE user_goals IS 'User-defined learning goals tracked in monthly reports';
COMMENT ON COLUMN user_goals.goal_type IS 'Type of goal: accuracy, streak, questions, subject_mastery, study_time';
COMMENT ON COLUMN user_goals.status IS 'Goal status: in_progress, achieved, failed, abandoned';

-- ========================================================================
-- PART 3: Create user_achievements table for gamification
-- ========================================================================

CREATE TABLE IF NOT EXISTS user_achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Achievement identification
    badge_id VARCHAR(50) NOT NULL, -- 'century_club', 'consistent_learner', 'subject_master', etc.
    badge_name VARCHAR(100) NOT NULL,
    badge_description TEXT NOT NULL,
    badge_tier VARCHAR(20) DEFAULT 'bronze', -- 'bronze', 'silver', 'gold', 'platinum'

    -- Achievement data
    earned_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    earned_value FLOAT, -- e.g., 150 questions for century_club
    metadata JSONB DEFAULT '{}', -- Additional context (subject, streak length, etc.)

    -- Prevent duplicate achievements
    UNIQUE(user_id, badge_id),

    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for achievement queries
CREATE INDEX IF NOT EXISTS idx_user_achievements_user_date
ON user_achievements(user_id, earned_date DESC);

CREATE INDEX IF NOT EXISTS idx_user_achievements_badge
ON user_achievements(badge_id, earned_date DESC);

-- Comments
COMMENT ON TABLE user_achievements IS 'Achievement badges earned by users (gamification)';
COMMENT ON COLUMN user_achievements.badge_id IS 'Unique badge identifier (century_club, consistent_learner, etc.)';
COMMENT ON COLUMN user_achievements.badge_tier IS 'Badge tier for progressive achievements: bronze, silver, gold, platinum';

-- ========================================================================
-- PART 4: Update parent_report_batches for enhanced monthly metadata
-- ========================================================================

-- Add columns for monthly-specific metadata if not exist
ALTER TABLE parent_report_batches
ADD COLUMN IF NOT EXISTS student_age INTEGER;

ALTER TABLE parent_report_batches
ADD COLUMN IF NOT EXISTS grade_level VARCHAR(20);

ALTER TABLE parent_report_batches
ADD COLUMN IF NOT EXISTS learning_style VARCHAR(50);

ALTER TABLE parent_report_batches
ADD COLUMN IF NOT EXISTS mental_health_score FLOAT
CHECK (mental_health_score >= 0.0 AND mental_health_score <= 1.0);

ALTER TABLE parent_report_batches
ADD COLUMN IF NOT EXISTS engagement_level VARCHAR(20)
CHECK (engagement_level IN ('high', 'medium', 'low', NULL));

ALTER TABLE parent_report_batches
ADD COLUMN IF NOT EXISTS confidence_level VARCHAR(20)
CHECK (confidence_level IN ('high', 'medium', 'low', NULL));

-- Comments
COMMENT ON COLUMN parent_report_batches.student_age IS 'Student age at time of report generation';
COMMENT ON COLUMN parent_report_batches.mental_health_score IS 'Overall mental health/wellbeing score (0.0-1.0)';
COMMENT ON COLUMN parent_report_batches.engagement_level IS 'Student engagement level: high, medium, low';

-- ========================================================================
-- PART 5: Create helper functions
-- ========================================================================

-- Function to automatically calculate skill tier from accuracy
CREATE OR REPLACE FUNCTION calculate_skill_tier(accuracy FLOAT)
RETURNS VARCHAR(20) AS $$
BEGIN
    RETURN CASE
        WHEN accuracy >= 95 THEN 'expert'
        WHEN accuracy >= 85 THEN 'master'
        WHEN accuracy >= 70 THEN 'advanced'
        WHEN accuracy >= 50 THEN 'intermediate'
        ELSE 'beginner'
    END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_skill_tier(FLOAT) IS
'Automatically calculates skill tier from accuracy percentage';

-- Function to update goal progress
CREATE OR REPLACE FUNCTION update_goal_progress()
RETURNS TRIGGER AS $$
BEGIN
    -- Update goals when questions are answered
    -- This is a placeholder - actual logic would be more complex
    -- For now, just update the timestamp
    UPDATE user_goals
    SET updated_at = NOW()
    WHERE user_id = NEW.user_id
      AND status = 'in_progress';

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ========================================================================
-- PART 6: Backfill skill tiers for existing questions (optional)
-- ========================================================================

-- Calculate and set skill tier for questions that have grade/correctness
-- This runs once during migration
DO $$
DECLARE
    row_count INTEGER;
BEGIN
    -- Update skill tiers based on question accuracy
    -- Group by user and subject to calculate running accuracy
    WITH question_accuracy AS (
        SELECT
            id,
            user_id,
            subject,
            CASE
                WHEN grade = 'CORRECT' OR is_correct = true THEN 100.0
                WHEN grade = 'PARTIAL_CREDIT' THEN 50.0
                ELSE 0.0
            END as question_score,
            archived_at
        FROM questions
        WHERE skill_tier IS NULL
    ),
    running_accuracy AS (
        SELECT
            id,
            AVG(question_score) OVER (
                PARTITION BY user_id, subject
                ORDER BY archived_at
                ROWS BETWEEN 9 PRECEDING AND CURRENT ROW
            ) as rolling_accuracy
        FROM question_accuracy
    )
    UPDATE questions q
    SET skill_tier = calculate_skill_tier(ra.rolling_accuracy)
    FROM running_accuracy ra
    WHERE q.id = ra.id;

    GET DIAGNOSTICS row_count = ROW_COUNT;
    RAISE NOTICE 'Backfilled skill_tier for % existing questions', row_count;
END;
$$;

-- ========================================================================
-- Success message
-- ========================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Monthly report fields migration completed successfully!';
    RAISE NOTICE '   - Added 3 columns to questions table (skill_tier, time_spent_seconds, student_mood)';
    RAISE NOTICE '   - Created user_goals table';
    RAISE NOTICE '   - Created user_achievements table';
    RAISE NOTICE '   - Enhanced parent_report_batches with monthly metadata';
    RAISE NOTICE '   - Created helper functions';
    RAISE NOTICE '   - Backfilled skill tiers for existing questions';
END;
$$;
