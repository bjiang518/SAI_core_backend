ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_internal BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_test_user BOOLEAN DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_users_internal ON users(is_internal, is_test_user);
