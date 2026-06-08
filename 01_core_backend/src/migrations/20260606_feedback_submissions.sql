-- User-submitted in-app feedback ("Report a problem" entry).
-- Pairs with POST /api/feedback. Aggregated counts surface in
-- /api/admin/analytics/quality so we can spot recurring complaints.

CREATE TABLE IF NOT EXISTS feedback_submissions (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID         REFERENCES users(id) ON DELETE CASCADE,
  category    VARCHAR(40)  NOT NULL,           -- bug | suggestion | content | praise | other
  message     TEXT         NOT NULL,
  app_version VARCHAR(20),
  device_info JSONB        NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_feedback_created_at ON feedback_submissions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_category   ON feedback_submissions(category, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_user_id    ON feedback_submissions(user_id, created_at DESC);
