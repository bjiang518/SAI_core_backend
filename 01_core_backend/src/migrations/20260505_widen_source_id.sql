-- Widen source_id to TEXT to handle long AIME identifiers
ALTER TABLE question_bank ALTER COLUMN source_id TYPE TEXT;
