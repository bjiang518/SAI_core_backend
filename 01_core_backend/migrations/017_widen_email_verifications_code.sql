-- Migration 017: Widen email_verifications.code column to hold bcrypt hashes
-- The code column was VARCHAR(6) (for plain 6-digit OTPs) but the application
-- now hashes codes with bcrypt before storing, producing ~60-char strings.
ALTER TABLE email_verifications
  ALTER COLUMN code TYPE VARCHAR(100);
