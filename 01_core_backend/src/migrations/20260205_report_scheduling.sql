-- Database Migration: Report Scheduling Preferences
-- Created: 2026-02-05
-- Purpose: Add timezone and automated report scheduling support

-- Add report scheduling columns to profiles table
ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS parent_reports_enabled BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS report_day_of_week INTEGER DEFAULT 0,  -- 0 = Sunday, 6 = Saturday
ADD COLUMN IF NOT EXISTS report_time_hour INTEGER DEFAULT 21,   -- 21 = 9 PM
ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'UTC';

-- Add comments
COMMENT ON COLUMN profiles.parent_reports_enabled IS 'Enable/disable automated parent report generation';
COMMENT ON COLUMN profiles.report_day_of_week IS 'Day of week for automated reports (0=Sunday, 6=Saturday)';
COMMENT ON COLUMN profiles.report_time_hour IS 'Hour of day for automated reports (0-23, in user local time)';
COMMENT ON COLUMN profiles.timezone IS 'User timezone (e.g., America/New_York, Asia/Tokyo, Europe/London, UTC)';

-- Add index for efficient scheduled report queries
CREATE INDEX IF NOT EXISTS idx_profiles_report_schedule
ON profiles(parent_reports_enabled, report_day_of_week, report_time_hour)
WHERE parent_reports_enabled = true;

-- Add index on timezone for quick lookups
CREATE INDEX IF NOT EXISTS idx_profiles_timezone
ON profiles(timezone)
WHERE timezone IS NOT NULL;

-- Verify migration
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles'
        AND column_name = 'parent_reports_enabled'
    ) THEN
        RAISE NOTICE '✅ Migration successful: Report scheduling columns added';
    ELSE
        RAISE EXCEPTION '❌ Migration failed: Columns not created';
    END IF;
END $$;
