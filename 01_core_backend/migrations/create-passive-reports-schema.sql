-- Migration: Passive Reports Schema
-- Created: 2025-01-20
-- Purpose: Support scheduled weekly/monthly parent reports with multi-report structure

-- Enable UUID extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Table for report batches (groups of 8 reports)
CREATE TABLE IF NOT EXISTS parent_report_batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL,
    period VARCHAR(20) NOT NULL, -- 'weekly' | 'monthly'
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    generated_at TIMESTAMP DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'completed', -- 'pending' | 'processing' | 'completed' | 'failed'
    generation_time_ms INTEGER,

    -- Quick metrics for card display
    overall_grade VARCHAR(2), -- 'A+', 'B', etc.
    overall_accuracy FLOAT,
    question_count INTEGER,
    study_time_minutes INTEGER,
    current_streak INTEGER,

    -- Trends
    accuracy_trend VARCHAR(20), -- 'improving' | 'stable' | 'declining'
    activity_trend VARCHAR(20), -- 'increasing' | 'stable' | 'decreasing'

    -- Summary text
    one_line_summary TEXT,

    -- Metadata
    metadata JSONB,

    CONSTRAINT unique_user_period_date UNIQUE (user_id, period, start_date)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_report_batches_user_date ON parent_report_batches(user_id, start_date DESC);
CREATE INDEX IF NOT EXISTS idx_report_batches_status ON parent_report_batches(status) WHERE status != 'completed';
CREATE INDEX IF NOT EXISTS idx_report_batches_generated ON parent_report_batches(generated_at DESC);

-- Table for individual reports within a batch
CREATE TABLE IF NOT EXISTS passive_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    batch_id UUID NOT NULL REFERENCES parent_report_batches(id) ON DELETE CASCADE,
    report_type VARCHAR(50) NOT NULL, -- 'academic_performance', 'learning_behavior', etc.

    -- Report content
    narrative_content TEXT NOT NULL,
    key_insights JSONB, -- Array of insight objects
    recommendations JSONB, -- Array of recommendation objects
    visual_data JSONB, -- Chart data for rendering

    -- Metadata
    word_count INTEGER,
    generation_time_ms INTEGER,
    ai_model_used VARCHAR(50) DEFAULT 'gpt-4o-mini',

    generated_at TIMESTAMP DEFAULT NOW(),

    CONSTRAINT unique_batch_type UNIQUE (batch_id, report_type)
);

-- Indexes for passive_reports
CREATE INDEX IF NOT EXISTS idx_passive_reports_batch ON passive_reports(batch_id);
CREATE INDEX IF NOT EXISTS idx_passive_reports_type ON passive_reports(report_type);

-- Table for tracking user notification preferences
CREATE TABLE IF NOT EXISTS report_notification_preferences (
    user_id UUID PRIMARY KEY,
    weekly_reports_enabled BOOLEAN DEFAULT true,
    monthly_reports_enabled BOOLEAN DEFAULT true,
    push_notifications_enabled BOOLEAN DEFAULT true,
    email_digest_enabled BOOLEAN DEFAULT false,
    email_address VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Comment the tables
COMMENT ON TABLE parent_report_batches IS 'Stores metadata for scheduled parent report batches (weekly/monthly)';
COMMENT ON TABLE passive_reports IS 'Stores individual reports within a batch (8 report types per batch)';
COMMENT ON TABLE report_notification_preferences IS 'User preferences for report notifications';

-- Add helpful comments on columns
COMMENT ON COLUMN parent_report_batches.period IS 'Report period: weekly or monthly';
COMMENT ON COLUMN parent_report_batches.status IS 'Generation status: pending, processing, completed, failed';
COMMENT ON COLUMN parent_report_batches.overall_grade IS 'Letter grade (A+, A, B+, etc.) for quick display';
COMMENT ON COLUMN passive_reports.report_type IS 'One of 8 report types: executive_summary, academic_performance, learning_behavior, motivation_emotional, progress_trajectory, social_learning, risk_opportunity, action_plan';
COMMENT ON COLUMN passive_reports.visual_data IS 'JSON data for generating charts/graphs in the report';

-- Grant permissions (adjust based on your user setup)
-- GRANT SELECT, INSERT, UPDATE ON parent_report_batches TO your_app_user;
-- GRANT SELECT, INSERT, UPDATE ON passive_reports TO your_app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON report_notification_preferences TO your_app_user;

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'Passive reports schema created successfully!';
    RAISE NOTICE 'Tables created: parent_report_batches, passive_reports, report_notification_preferences';
END $$;
