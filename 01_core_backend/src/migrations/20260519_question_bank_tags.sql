-- Migration: Add tags JSONB column to question_bank
-- Tags store skill_tags, style_tags, mc_strategy_tags assigned by AI
-- error_micro_tags are per-student (stored in iOS QuestionLocalStorage), not in the bank

ALTER TABLE question_bank
  ADD COLUMN IF NOT EXISTS tags JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_question_bank_tags
  ON question_bank USING GIN (tags);

COMMENT ON COLUMN question_bank.tags IS
  'Predefined tag sets: {"skill_tags":["..."], "style_tags":["..."], "mc_strategy_tags":["..."]}';
