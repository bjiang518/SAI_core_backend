CREATE TABLE IF NOT EXISTS grade_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subject     VARCHAR(100),
  grade       VARCHAR(20),   -- CORRECT | INCORRECT | PARTIAL_CREDIT | EMPTY
  is_correct  BOOLEAN,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_grade_events_user_id    ON grade_events(user_id);
CREATE INDEX IF NOT EXISTS idx_grade_events_created_at ON grade_events(created_at);
