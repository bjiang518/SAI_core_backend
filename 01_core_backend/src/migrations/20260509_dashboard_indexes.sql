-- Performance indexes for admin dashboard queries
CREATE INDEX IF NOT EXISTS idx_sessions_created_at
  ON sessions(created_at);

CREATE INDEX IF NOT EXISTS idx_user_sessions_user_created
  ON user_sessions(user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_users_created_at
  ON users(created_at);

CREATE INDEX IF NOT EXISTS idx_users_anonymous_tier
  ON users(is_anonymous, tier);

CREATE INDEX IF NOT EXISTS idx_sessions_user_created
  ON sessions(user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_archived_questions_user_text
  ON archived_questions(user_id);

CREATE INDEX IF NOT EXISTS idx_practice_sheets_user_id
  ON practice_sheets(user_id);

CREATE INDEX IF NOT EXISTS idx_parent_report_batches_user_id
  ON parent_report_batches(user_id);
