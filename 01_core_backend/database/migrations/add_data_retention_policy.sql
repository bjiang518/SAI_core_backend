-- Data Retention Policy Implementation
-- Auto-delete conversations older than 90 days (COPPA compliance)
-- Add soft delete capability for GDPR Article 17 compliance

-- Step 1: Add deleted_at column for soft delete
ALTER TABLE archived_conversations_new
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS retention_expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '90 days');

-- Step 2: Create index for efficient cleanup queries
CREATE INDEX IF NOT EXISTS idx_archived_conversations_retention
ON archived_conversations_new(retention_expires_at)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_archived_conversations_deleted
ON archived_conversations_new(deleted_at)
WHERE deleted_at IS NOT NULL;

-- Step 3: Add retention policy to question_sessions table
ALTER TABLE question_sessions
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS retention_expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '90 days');

CREATE INDEX IF NOT EXISTS idx_question_sessions_retention
ON question_sessions(retention_expires_at)
WHERE deleted_at IS NULL;

-- Step 4: Add retention policy to sessions table
ALTER TABLE sessions
ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP,
ADD COLUMN IF NOT EXISTS retention_expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '90 days');

CREATE INDEX IF NOT EXISTS idx_sessions_retention
ON sessions(retention_expires_at)
WHERE deleted_at IS NULL;

-- Step 5: Create function to soft delete expired data
CREATE OR REPLACE FUNCTION soft_delete_expired_data()
RETURNS TABLE(
  table_name TEXT,
  deleted_count BIGINT
) AS $$
BEGIN
  -- Soft delete expired conversations
  UPDATE archived_conversations_new
  SET deleted_at = CURRENT_TIMESTAMP
  WHERE retention_expires_at < CURRENT_TIMESTAMP
    AND deleted_at IS NULL;

  table_name := 'archived_conversations_new';
  deleted_count := (SELECT COUNT(*) FROM archived_conversations_new WHERE deleted_at = CURRENT_TIMESTAMP);
  RETURN NEXT;

  -- Soft delete expired question sessions
  UPDATE question_sessions
  SET deleted_at = CURRENT_TIMESTAMP
  WHERE retention_expires_at < CURRENT_TIMESTAMP
    AND deleted_at IS NULL;

  table_name := 'question_sessions';
  deleted_count := (SELECT COUNT(*) FROM question_sessions WHERE deleted_at = CURRENT_TIMESTAMP);
  RETURN NEXT;

  -- Soft delete expired sessions
  UPDATE sessions
  SET deleted_at = CURRENT_TIMESTAMP
  WHERE retention_expires_at < CURRENT_TIMESTAMP
    AND deleted_at IS NULL;

  table_name := 'sessions';
  deleted_count := (SELECT COUNT(*) FROM sessions WHERE deleted_at = CURRENT_TIMESTAMP);
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- Step 6: Create function to hard delete soft-deleted data after 30 days
CREATE OR REPLACE FUNCTION hard_delete_old_soft_deleted()
RETURNS TABLE(
  table_name TEXT,
  purged_count BIGINT
) AS $$
BEGIN
  -- Hard delete conversations deleted > 30 days ago
  DELETE FROM archived_conversations_new
  WHERE deleted_at < (CURRENT_TIMESTAMP - INTERVAL '30 days');

  table_name := 'archived_conversations_new';
  GET DIAGNOSTICS purged_count = ROW_COUNT;
  RETURN NEXT;

  -- Hard delete question sessions deleted > 30 days ago
  DELETE FROM question_sessions
  WHERE deleted_at < (CURRENT_TIMESTAMP - INTERVAL '30 days');

  table_name := 'question_sessions';
  GET DIAGNOSTICS purged_count = ROW_COUNT;
  RETURN NEXT;

  -- Hard delete sessions deleted > 30 days ago
  DELETE FROM sessions
  WHERE deleted_at < (CURRENT_TIMESTAMP - INTERVAL '30 days');

  table_name := 'sessions';
  GET DIAGNOSTICS purged_count = ROW_COUNT;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

-- Step 7: Update existing rows to have retention expiration date
UPDATE archived_conversations_new
SET retention_expires_at = archived_date + INTERVAL '90 days'
WHERE retention_expires_at IS NULL;

UPDATE question_sessions
SET retention_expires_at = created_at + INTERVAL '90 days'
WHERE retention_expires_at IS NULL;

UPDATE sessions
SET retention_expires_at = start_time + INTERVAL '90 days'
WHERE retention_expires_at IS NULL;

-- Step 8: Create view for non-deleted data (most queries should use this)
CREATE OR REPLACE VIEW active_conversations AS
SELECT *
FROM archived_conversations_new
WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW active_question_sessions AS
SELECT *
FROM question_sessions
WHERE deleted_at IS NULL;

CREATE OR REPLACE VIEW active_sessions AS
SELECT *
FROM sessions
WHERE deleted_at IS NULL;

COMMENT ON VIEW active_conversations IS 'Only shows non-deleted conversations for GDPR compliance';
COMMENT ON VIEW active_question_sessions IS 'Only shows non-deleted question sessions for GDPR compliance';
COMMENT ON VIEW active_sessions IS 'Only shows non-deleted sessions for GDPR compliance';
