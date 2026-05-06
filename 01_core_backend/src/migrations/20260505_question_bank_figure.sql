-- Add figure storage columns to question_bank
ALTER TABLE question_bank
  ADD COLUMN IF NOT EXISTS figure_data  TEXT,         -- base64-encoded PNG
  ADD COLUMN IF NOT EXISTS figure_mime  VARCHAR(20);  -- 'image/png' | 'image/gif' | 'image/svg+xml'
