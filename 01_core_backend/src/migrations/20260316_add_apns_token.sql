-- Migration: Add APNs device token to profiles
-- Created: 2026-03-16
-- Purpose: Store per-user APNs push notification token for server-side push delivery

ALTER TABLE profiles
ADD COLUMN IF NOT EXISTS apns_token TEXT,
ADD COLUMN IF NOT EXISTS apns_token_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN profiles.apns_token IS 'Apple Push Notification service device token (hex string)';
COMMENT ON COLUMN profiles.apns_token_updated_at IS 'When the APNs token was last registered by the device';

-- Index for quick lookup (used when sending post-generation pushes)
CREATE INDEX IF NOT EXISTS idx_profiles_apns_token
ON profiles(user_id)
WHERE apns_token IS NOT NULL;
