-- Adds app_language to app_events so we can segment any analytics view
-- (DAU, paywall views, screen flow, dropoff, etc.) by the user's iOS UI
-- language. Captured client-side from Locale.preferredLanguages.first;
-- formatted as a BCP-47 tag (e.g. "en", "zh-Hans-CN", "ja-JP").
--
-- Backwards-compatible: column is nullable. Old clients that don't send
-- the field will land as NULL — distinct from devices that send 'unknown'.

ALTER TABLE app_events
  ADD COLUMN IF NOT EXISTS app_language VARCHAR(20);

-- Index on (app_language, occurred_at) so the language-distribution
-- dashboard query stays cheap even at 100k+ rows/day.
CREATE INDEX IF NOT EXISTS idx_app_events_language
  ON app_events (app_language, occurred_at DESC)
  WHERE app_language IS NOT NULL;
