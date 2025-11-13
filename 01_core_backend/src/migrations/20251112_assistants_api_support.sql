-- Migration: Add OpenAI Assistants API support
-- Date: 2025-11-12
-- Description: Add fields to support OpenAI Assistants API integration

-- ============================================
-- 1. Sessions Table: Add OpenAI Thread tracking
-- ============================================

ALTER TABLE sessions
ADD COLUMN IF NOT EXISTS openai_thread_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS assistant_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS last_run_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS assistant_version VARCHAR(20) DEFAULT '1.0',
ADD COLUMN IF NOT EXISTS using_assistants_api BOOLEAN DEFAULT FALSE;

-- Index for fast thread lookup
CREATE INDEX IF NOT EXISTS idx_sessions_thread_id ON sessions(openai_thread_id);
CREATE INDEX IF NOT EXISTS idx_sessions_assistant_id ON sessions(assistant_id);

-- ============================================
-- 2. Assistants Configuration Table
-- ============================================

CREATE TABLE IF NOT EXISTS assistants_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) NOT NULL,
  openai_assistant_id VARCHAR(255) NOT NULL UNIQUE,
  purpose VARCHAR(100) NOT NULL,  -- 'practice_generator', 'homework_tutor', etc.
  model VARCHAR(50) NOT NULL,
  instructions_version VARCHAR(20) DEFAULT '1.0',
  is_active BOOLEAN DEFAULT TRUE,
  created_by VARCHAR(100) DEFAULT 'system',
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Index for fast lookup by purpose
CREATE INDEX IF NOT EXISTS idx_assistants_purpose ON assistants_config(purpose);
CREATE INDEX IF NOT EXISTS idx_assistants_active ON assistants_config(is_active);

-- ============================================
-- 3. OpenAI Threads Metadata Table
-- ============================================

CREATE TABLE IF NOT EXISTS openai_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  openai_thread_id VARCHAR(255) NOT NULL UNIQUE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id UUID REFERENCES sessions(id) ON DELETE SET NULL,
  assistant_id VARCHAR(255),
  purpose VARCHAR(100),  -- 'conversation', 'practice_generation', 'image_analysis'
  subject VARCHAR(100),
  language VARCHAR(10),
  message_count INTEGER DEFAULT 0,
  total_tokens_used INTEGER DEFAULT 0,
  total_cost_usd DECIMAL(10, 4) DEFAULT 0.0000,
  last_message_at TIMESTAMP,
  expires_at TIMESTAMP,  -- Threads auto-expire after 30 days
  is_ephemeral BOOLEAN DEFAULT FALSE,  -- True for one-time use threads
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_openai_threads_user_id ON openai_threads(user_id);
CREATE INDEX IF NOT EXISTS idx_openai_threads_session_id ON openai_threads(session_id);
CREATE INDEX IF NOT EXISTS idx_openai_threads_expires_at ON openai_threads(expires_at);

-- ============================================
-- 4. Assistant Metrics Table (Performance Tracking)
-- ============================================

CREATE TABLE IF NOT EXISTS assistant_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  assistant_type VARCHAR(50) NOT NULL,  -- 'practice_generator', 'homework_tutor', etc.
  endpoint VARCHAR(200) NOT NULL,

  -- Performance metrics
  total_latency_ms INTEGER NOT NULL,
  first_token_latency_ms INTEGER,
  api_latency_ms INTEGER,

  -- Cost tracking
  input_tokens INTEGER NOT NULL,
  output_tokens INTEGER NOT NULL,
  estimated_cost_usd DECIMAL(10, 6) NOT NULL,

  -- Quality metrics
  was_successful BOOLEAN NOT NULL,
  error_code VARCHAR(50),
  error_message TEXT,

  -- A/B Testing
  use_assistants_api BOOLEAN NOT NULL,
  experiment_group VARCHAR(20),  -- 'control', 'treatment', null

  -- Context
  thread_id VARCHAR(255),
  run_id VARCHAR(255),
  model VARCHAR(50),

  created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for analytics
CREATE INDEX IF NOT EXISTS idx_assistant_metrics_assistant_type ON assistant_metrics(assistant_type);
CREATE INDEX IF NOT EXISTS idx_assistant_metrics_created_at ON assistant_metrics(created_at);
CREATE INDEX IF NOT EXISTS idx_assistant_metrics_experiment ON assistant_metrics(experiment_group);
CREATE INDEX IF NOT EXISTS idx_assistant_metrics_api_type ON assistant_metrics(use_assistants_api);

-- ============================================
-- 5. Daily Cost Tracking
-- ============================================

CREATE TABLE IF NOT EXISTS daily_assistant_costs (
  date DATE PRIMARY KEY,
  total_requests INTEGER DEFAULT 0,
  successful_requests INTEGER DEFAULT 0,
  total_tokens INTEGER DEFAULT 0,
  total_cost_usd DECIMAL(10, 4) DEFAULT 0.0000,
  assistants_api_requests INTEGER DEFAULT 0,
  ai_engine_requests INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- ============================================
-- 6. Function Calling Cache (Performance Optimization)
-- ============================================

CREATE TABLE IF NOT EXISTS function_call_cache (
  cache_key VARCHAR(255) PRIMARY KEY,  -- hash of function_name + arguments
  function_name VARCHAR(100) NOT NULL,
  arguments JSONB NOT NULL,
  result JSONB NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  hit_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Index for expiration cleanup
CREATE INDEX IF NOT EXISTS idx_function_cache_expires_at ON function_call_cache(expires_at);

-- ============================================
-- 7. Update existing progress table for assistant queries
-- ============================================

-- Add index for faster student performance lookups
CREATE INDEX IF NOT EXISTS idx_progress_user_subject ON subject_progress(user_id, subject);
CREATE INDEX IF NOT EXISTS idx_questions_user_subject_incorrect ON questions(user_id, subject, is_correct) WHERE is_correct = FALSE;

-- ============================================
-- 8. Insert default assistant configurations (placeholder)
-- ============================================

INSERT INTO assistants_config (name, openai_assistant_id, purpose, model, metadata)
VALUES
  ('Practice Generator', 'asst_placeholder_practice', 'practice_generator', 'gpt-4o-mini', '{"status": "pending"}'),
  ('Homework Tutor', 'asst_placeholder_tutor', 'homework_tutor', 'gpt-4o-mini', '{"status": "pending"}'),
  ('Image Analyzer', 'asst_placeholder_image', 'image_analyzer', 'gpt-4o', '{"status": "pending"}'),
  ('Question Evaluator', 'asst_placeholder_evaluator', 'question_evaluator', 'gpt-4o-mini', '{"status": "pending"}'),
  ('Essay Grader', 'asst_placeholder_essay', 'essay_grader', 'gpt-4o', '{"status": "pending"}'),
  ('Parent Report Analyst', 'asst_placeholder_report', 'parent_report_analyst', 'gpt-4o-mini', '{"status": "pending"}')
ON CONFLICT (openai_assistant_id) DO NOTHING;

-- ============================================
-- 9. Cleanup function for expired threads
-- ============================================

CREATE OR REPLACE FUNCTION cleanup_expired_threads() RETURNS void AS $$
BEGIN
  DELETE FROM openai_threads
  WHERE expires_at < NOW()
    AND is_ephemeral = TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 10. Function to update daily costs
-- ============================================

CREATE OR REPLACE FUNCTION update_daily_costs(
  p_cost_usd DECIMAL,
  p_use_assistants_api BOOLEAN,
  p_tokens INTEGER,
  p_success BOOLEAN
) RETURNS void AS $$
BEGIN
  INSERT INTO daily_assistant_costs (
    date,
    total_requests,
    successful_requests,
    total_tokens,
    total_cost_usd,
    assistants_api_requests,
    ai_engine_requests
  )
  VALUES (
    CURRENT_DATE,
    1,
    CASE WHEN p_success THEN 1 ELSE 0 END,
    p_tokens,
    p_cost_usd,
    CASE WHEN p_use_assistants_api THEN 1 ELSE 0 END,
    CASE WHEN NOT p_use_assistants_api THEN 1 ELSE 0 END
  )
  ON CONFLICT (date) DO UPDATE SET
    total_requests = daily_assistant_costs.total_requests + 1,
    successful_requests = daily_assistant_costs.successful_requests + CASE WHEN p_success THEN 1 ELSE 0 END,
    total_tokens = daily_assistant_costs.total_tokens + p_tokens,
    total_cost_usd = daily_assistant_costs.total_cost_usd + p_cost_usd,
    assistants_api_requests = daily_assistant_costs.assistants_api_requests + CASE WHEN p_use_assistants_api THEN 1 ELSE 0 END,
    ai_engine_requests = daily_assistant_costs.ai_engine_requests + CASE WHEN NOT p_use_assistants_api THEN 1 ELSE 0 END,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- Migration Complete
-- ============================================

-- Verify tables were created
DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully';
  RAISE NOTICE 'Tables created: assistants_config, openai_threads, assistant_metrics, daily_assistant_costs, function_call_cache';
  RAISE NOTICE 'Indexes created: 11 indexes';
  RAISE NOTICE 'Functions created: cleanup_expired_threads, update_daily_costs';
END $$;
