-- Migration: Create daily_questions table
-- Purpose: Store one AI-generated fun question per grade level per day
-- All students at the same grade level see the same question on a given day

CREATE TABLE IF NOT EXISTS daily_questions (
    id SERIAL PRIMARY KEY,
    question_date DATE NOT NULL,
    grade_level INTEGER NOT NULL CHECK (grade_level >= 0 AND grade_level <= 14),
    question_text TEXT NOT NULL,
    fun_fact TEXT,
    subject VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE (question_date, grade_level)
);

CREATE INDEX IF NOT EXISTS idx_daily_questions_date_grade
    ON daily_questions(question_date, grade_level);
