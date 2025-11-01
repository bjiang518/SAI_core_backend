-- Add avatar_id column to profiles table
-- This allows users to select a profile avatar (1-6)

ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS avatar_id INTEGER;

-- Add comment to column
COMMENT ON COLUMN profiles.avatar_id IS 'Selected profile avatar ID (1-6)';

-- Add check constraint to ensure avatar_id is between 1 and 6
ALTER TABLE profiles
ADD CONSTRAINT check_avatar_id_range CHECK (avatar_id IS NULL OR (avatar_id >= 1 AND avatar_id <= 6));
