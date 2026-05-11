-- Prevent duplicate imports: one row per (source, source_id) combination
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_question_bank_source_id'
  ) THEN
    ALTER TABLE question_bank ADD CONSTRAINT uq_question_bank_source_id
      UNIQUE (source, source_id);
  END IF;
END $$;
