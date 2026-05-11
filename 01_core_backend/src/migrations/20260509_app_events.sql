-- App-level behavioural event log.
-- iOS clients batch-upload events via POST /api/events/batch.
-- Low-write table: expect O(100s) rows/day at current scale.

CREATE TABLE IF NOT EXISTS app_events (
  id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID         REFERENCES users(id) ON DELETE CASCADE,
  event_name   VARCHAR(100) NOT NULL,
  properties   JSONB        NOT NULL DEFAULT '{}',
  session_id   UUID,
  app_version  VARCHAR(20),
  occurred_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  received_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_app_events_user_id      ON app_events(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_events_event_name   ON app_events(event_name, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_app_events_occurred_at  ON app_events(occurred_at DESC);
