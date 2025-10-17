-- Migration: Add raw_question_text column to archived_questions table
-- Date: 2025-10-16
-- Purpose: Store the full original question text from the image (before AI cleaning)

-- Add raw_question_text column (allows NULL for backward compatibility)
ALTER TABLE archived_questions
ADD COLUMN IF NOT EXISTS raw_question_text TEXT;

-- Backfill existing records: copy question_text to raw_question_text for existing rows
UPDATE archived_questions
SET raw_question_text = question_text
WHERE raw_question_text IS NULL;

-- Add index for searching raw question text (optional but recommended)
CREATE INDEX IF NOT EXISTS idx_archived_questions_raw_text
ON archived_questions USING gin(to_tsvector('english', raw_question_text));

-- Verify migration
SELECT COUNT(*) as total_records,
       COUNT(raw_question_text) as records_with_raw_text
FROM archived_questions;
