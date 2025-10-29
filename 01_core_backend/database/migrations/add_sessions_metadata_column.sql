-- Migration: Add metadata column to sessions table
-- Date: 2025-01-27
-- Purpose: Add JSONB metadata column to store additional session context and preferences
-- Context: This column is needed for storing language preferences and other session-specific data

-- Add metadata column (allows NULL for backward compatibility)
ALTER TABLE sessions
ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

-- Add comment to document the column's purpose
COMMENT ON COLUMN sessions.metadata IS 'Stores additional session context including language preferences, AI model settings, and custom session parameters';

-- Create index for efficient JSONB queries (optional but recommended)
CREATE INDEX IF NOT EXISTS idx_sessions_metadata
ON sessions USING gin(metadata);

-- Backfill existing records with empty metadata object
UPDATE sessions
SET metadata = '{}'::jsonb
WHERE metadata IS NULL;

-- Verify migration
SELECT
    COUNT(*) as total_sessions,
    COUNT(metadata) as sessions_with_metadata,
    COUNT(*) FILTER (WHERE metadata = '{}'::jsonb) as sessions_with_empty_metadata,
    COUNT(*) FILTER (WHERE metadata IS NOT NULL AND metadata != '{}'::jsonb) as sessions_with_data
FROM sessions;

-- Example usage of metadata column:
-- INSERT INTO sessions (user_id, subject, metadata)
-- VALUES ('user-uuid', 'mathematics', '{"language": "en", "difficulty": "intermediate"}'::jsonb);
--
-- Query by metadata:
-- SELECT * FROM sessions WHERE metadata->>'language' = 'en';
