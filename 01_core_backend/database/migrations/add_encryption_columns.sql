-- Add encryption support to conversation tables
-- Implements column-level encryption using AES-256-GCM

-- Step 1: Add encrypted_content column to archived_conversations_new
ALTER TABLE archived_conversations_new
ADD COLUMN IF NOT EXISTS encrypted_content TEXT,
ADD COLUMN IF NOT EXISTS content_hash VARCHAR(64),  -- SHA-256 hash for search
ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN DEFAULT FALSE;

-- Step 2: Add encrypted_content to question_sessions
ALTER TABLE question_sessions
ADD COLUMN IF NOT EXISTS encrypted_question TEXT,
ADD COLUMN IF NOT EXISTS encrypted_answer TEXT,
ADD COLUMN IF NOT EXISTS is_encrypted BOOLEAN DEFAULT FALSE;

-- Step 3: Create index on content hash for encrypted search
CREATE INDEX IF NOT EXISTS idx_archived_conversations_content_hash
ON archived_conversations_new(content_hash)
WHERE is_encrypted = TRUE;

-- Step 4: Add comment explaining encryption
COMMENT ON COLUMN archived_conversations_new.encrypted_content IS 'AES-256-GCM encrypted conversation content for FERPA/COPPA compliance';
COMMENT ON COLUMN archived_conversations_new.content_hash IS 'SHA-256 hash of content for search functionality while encrypted';
COMMENT ON COLUMN archived_conversations_new.is_encrypted IS 'Flag indicating if content is encrypted (for migration support)';

COMMENT ON COLUMN question_sessions.encrypted_question IS 'AES-256-GCM encrypted question text';
COMMENT ON COLUMN question_sessions.encrypted_answer IS 'AES-256-GCM encrypted answer text';

-- Step 5: Create function to encrypt existing data (run manually when ready)
CREATE OR REPLACE FUNCTION encrypt_existing_conversations()
RETURNS TABLE(
  encrypted_count BIGINT,
  failed_count BIGINT
) AS $$
DECLARE
  total_encrypted BIGINT := 0;
  total_failed BIGINT := 0;
BEGIN
  -- Note: This function marks conversations as needing encryption
  -- Actual encryption happens in application layer (Node.js)
  -- This is because encryption key is stored in environment variable

  -- Mark non-encrypted conversations for encryption
  UPDATE archived_conversations_new
  SET is_encrypted = FALSE
  WHERE is_encrypted IS NULL
    AND conversation_content IS NOT NULL
    AND encrypted_content IS NULL;

  GET DIAGNOSTICS total_encrypted = ROW_COUNT;

  RETURN QUERY SELECT total_encrypted, total_failed;
END;
$$ LANGUAGE plpgsql;

-- Step 6: Performance optimization - partial index for non-encrypted data
CREATE INDEX IF NOT EXISTS idx_archived_conversations_not_encrypted
ON archived_conversations_new(id)
WHERE is_encrypted = FALSE OR is_encrypted IS NULL;

-- Step 7: Add encryption status view
CREATE OR REPLACE VIEW encryption_status AS
SELECT
  'archived_conversations_new' as table_name,
  COUNT(*) as total_records,
  COUNT(*) FILTER (WHERE is_encrypted = TRUE) as encrypted_count,
  COUNT(*) FILTER (WHERE is_encrypted = FALSE OR is_encrypted IS NULL) as unencrypted_count,
  ROUND(100.0 * COUNT(*) FILTER (WHERE is_encrypted = TRUE) / NULLIF(COUNT(*), 0), 2) as encryption_percentage
FROM archived_conversations_new
UNION ALL
SELECT
  'question_sessions' as table_name,
  COUNT(*) as total_records,
  COUNT(*) FILTER (WHERE is_encrypted = TRUE) as encrypted_count,
  COUNT(*) FILTER (WHERE is_encrypted = FALSE OR is_encrypted IS NULL) as unencrypted_count,
  ROUND(100.0 * COUNT(*) FILTER (WHERE is_encrypted = TRUE) / NULLIF(COUNT(*), 0), 2) as encryption_percentage
FROM question_sessions;

COMMENT ON VIEW encryption_status IS 'Monitor encryption migration progress';
