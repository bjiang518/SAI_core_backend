-- Track every tier change per user
CREATE TABLE IF NOT EXISTS tier_history (
  id              SERIAL PRIMARY KEY,
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  from_tier       VARCHAR(20),
  to_tier         VARCHAR(20) NOT NULL,
  from_expires_at TIMESTAMP,
  to_expires_at   TIMESTAMP,
  changed_at      TIMESTAMP NOT NULL DEFAULT NOW(),
  source          VARCHAR(50) NOT NULL DEFAULT 'unknown',
  note            TEXT
);

CREATE INDEX IF NOT EXISTS idx_tier_history_user
  ON tier_history (user_id, changed_at DESC);
