-- Migration: Add Parent Reports Settings Columns to Profiles
-- Date: 2026-02-07
-- Purpose: Enable automated weekly parent reports with user preferences

-- Add parent reports configuration columns to profiles table
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS parent_reports_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS auto_sync_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS report_day_of_week INTEGER DEFAULT 0,  -- 0 = Sunday, 6 = Saturday
ADD COLUMN IF NOT EXISTS report_time_hour INTEGER DEFAULT 21,    -- 9 PM in 24-hour format
ADD COLUMN IF NOT EXISTS timezone VARCHAR(100) DEFAULT 'UTC';

-- Create index for efficient cron job queries
CREATE INDEX IF NOT EXISTS idx_profiles_parent_reports
ON profiles (parent_reports_enabled, timezone, report_day_of_week, report_time_hour)
WHERE parent_reports_enabled = true;

-- Add comment for documentation
COMMENT ON COLUMN profiles.parent_reports_enabled IS 'Whether automated weekly parent reports are enabled';
COMMENT ON COLUMN profiles.auto_sync_enabled IS 'Whether to automatically sync homework data in background';
COMMENT ON COLUMN profiles.report_day_of_week IS 'Day of week for automated reports (0=Sunday, 6=Saturday)';
COMMENT ON COLUMN profiles.report_time_hour IS 'Hour of day for automated reports (0-23, user local time)';
COMMENT ON COLUMN profiles.timezone IS 'User timezone for scheduling reports (e.g., America/Los_Angeles)';
