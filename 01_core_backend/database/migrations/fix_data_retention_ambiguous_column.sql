-- Fix: Ambiguous column reference in soft_delete_expired_data() function
-- Error: column reference "table_name" is ambiguous
-- Root cause: PL/pgSQL function RETURNS TABLE column "table_name" conflicts with
--             information_schema.tables column reference in the same scope.
-- Solution: Rename output columns to tbl_name / del_count (no conflict possible).
-- Applied via: Migration 030 in railway-database.js runDatabaseMigrations()

DROP FUNCTION IF EXISTS soft_delete_expired_data();

CREATE OR REPLACE FUNCTION soft_delete_expired_data()
RETURNS TABLE(tbl_name TEXT, del_count BIGINT) AS $$
BEGIN
  UPDATE archived_conversations_new
  SET deleted_at = CURRENT_TIMESTAMP
  WHERE retention_expires_at < CURRENT_TIMESTAMP
    AND deleted_at IS NULL;
  tbl_name := 'archived_conversations_new';
  GET DIAGNOSTICS del_count = ROW_COUNT;
  RETURN NEXT;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'question_sessions'
  ) THEN
    UPDATE question_sessions
    SET deleted_at = CURRENT_TIMESTAMP
    WHERE retention_expires_at < CURRENT_TIMESTAMP
      AND deleted_at IS NULL;
    tbl_name := 'question_sessions';
    GET DIAGNOSTICS del_count = ROW_COUNT;
    RETURN NEXT;
  END IF;

  UPDATE sessions
  SET deleted_at = CURRENT_TIMESTAMP
  WHERE retention_expires_at < CURRENT_TIMESTAMP
    AND deleted_at IS NULL;
  tbl_name := 'sessions';
  GET DIAGNOSTICS del_count = ROW_COUNT;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION soft_delete_expired_data() IS 'Soft deletes expired data. Output columns renamed tbl_name/del_count to avoid PL/pgSQL ambiguity with information_schema.';
