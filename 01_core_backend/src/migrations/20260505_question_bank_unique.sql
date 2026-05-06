-- Prevent duplicate imports: one row per (source, source_id) combination
ALTER TABLE question_bank ADD CONSTRAINT uq_question_bank_source_id
  UNIQUE (source, source_id);
