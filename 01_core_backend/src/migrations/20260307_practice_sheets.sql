-- Migration: Practice Sheets table for Practice Library feature
-- Date: 2026-03-07

CREATE TABLE IF NOT EXISTS practice_sheets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  sheet_id VARCHAR(255) UNIQUE NOT NULL,  -- iOS UUID (client-generated)
  subject VARCHAR(100),
  source_type VARCHAR(50),  -- 'random', 'archive', 'mistake'
  question_count INTEGER DEFAULT 0,
  completed_count INTEGER DEFAULT 0,
  score_percentage DECIMAL(5,2),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  last_accessed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_practice_sheets_user_id ON practice_sheets(user_id);
CREATE INDEX IF NOT EXISTS idx_practice_sheets_sheet_id ON practice_sheets(sheet_id);
