-- Fix: Ambiguous column reference in soft_delete_expired_data() function
-- Error: column reference "table_name" is ambiguous
-- Root cause: PL/pgSQL function has RETURNS TABLE with column named "table_name"
--             and also tries to assign to a variable with the same name

-- Solution: Use qualified column names in the RETURN TABLE

-- Drop and recreate the function with proper variable scoping
DROP FUNCTION IF EXISTS soft_delete_expired_data();

CREATE OR REPLACE FUNCTION soft_delete_expired_data()
RETURNS TABLE(
  table_name TEXT,
  deleted_count BIGINT
) AS $$
DECLARE
  v_table_name TEXT;
  v_deleted_count BIGINT;
BEGIN
  -- Soft delete expired conversations
  UPDATE archived_conversations_new
  SET deleted_at = CURRENT_TIMESTAMP
  WHERE retention_expires_at < CURRENT_TIMESTAMP
    AND deleted_at IS NULL;

  v_table_name := 'archived_conversations_new';
  v_deleted_count := (SELECT COUNT(*) FROM archived_conversations_new WHERE deleted_at >= CURRENT_TIMESTAMP - INTERVAL '1 second');

  -- Return the result
  table_name := v_table_name;
  deleted_count := v_deleted_count;
  RETURN NEXT;

  -- Check if question_sessions table exists before attempting deletion
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND information_schema.tables.table_name = 'question_sessions') THEN
    -- Soft delete expired question sessions
    UPDATE question_sessions
    SET deleted_at = CURRENT_TIMESTAMP
    WHERE retention_expires_at < CURRENT_TIMESTAMP
      AND deleted_at IS NULL;

    v_table_name := 'question_sessions';
    v_deleted_count := (SELECT COUNT(*) FROM question_sessions WHERE deleted_at >= CURRENT_TIMESTAMP - INTERVAL '1 second');

    table_name := v_table_name;
    deleted_count := v_deleted_count;
    RETURN NEXT;
  END IF;

  -- Soft delete expired sessions
  UPDATE sessions
  SET deleted_at = CURRENT_TIMESTAMP
  WHERE retention_expires_at < CURRENT_TIMESTAMP
    AND deleted_at IS NULL;

  v_table_name := 'sessions';
  v_deleted_count := (SELECT COUNT(*) FROM sessions WHERE deleted_at >= CURRENT_TIMESTAMP - INTERVAL '1 second');

  table_name := v_table_name;
  deleted_count := v_deleted_count;
  RETURN NEXT;

END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION soft_delete_expired_data() IS 'Soft deletes expired data based on retention_expires_at timestamp. Fixed ambiguous column reference issue.';
