-- Migration: promo codes + redemptions
-- Allows admin to create codes that grant premium access for a fixed duration.

CREATE TABLE IF NOT EXISTS promo_codes (
  id              SERIAL PRIMARY KEY,
  code            VARCHAR(50) UNIQUE NOT NULL,       -- e.g. "LAUNCH2026"
  tier            VARCHAR(20) NOT NULL DEFAULT 'premium',
  duration_days   INTEGER NOT NULL DEFAULT 30,
  max_uses        INTEGER,                           -- NULL = unlimited
  uses_count      INTEGER NOT NULL DEFAULT 0,
  created_by      VARCHAR(100),
  expires_at      TIMESTAMP,                         -- when the code itself expires (NULL = never)
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS promo_redemptions (
  id              SERIAL PRIMARY KEY,
  code_id         INTEGER NOT NULL REFERENCES promo_codes(id),
  user_id         UUID NOT NULL REFERENCES users(id),
  redeemed_at     TIMESTAMP NOT NULL DEFAULT NOW(),
  tier_expires_at TIMESTAMP NOT NULL,
  UNIQUE (code_id, user_id)                          -- one redemption per user per code
);

CREATE INDEX IF NOT EXISTS idx_promo_codes_code ON promo_codes (code);
CREATE INDEX IF NOT EXISTS idx_promo_redemptions_user ON promo_redemptions (user_id);
