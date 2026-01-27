-- Remove error analysis columns from questions table

ALTER TABLE questions
  DROP COLUMN IF EXISTS error_type,
  DROP COLUMN IF EXISTS error_evidence,
  DROP COLUMN IF EXISTS error_confidence,
  DROP COLUMN IF EXISTS learning_suggestion,
  DROP COLUMN IF EXISTS error_analysis_status,
  DROP COLUMN IF EXISTS error_analyzed_at;

-- Drop indexes
DROP INDEX IF EXISTS idx_questions_error_type;
DROP INDEX IF EXISTS idx_questions_mistakes_by_subject;
