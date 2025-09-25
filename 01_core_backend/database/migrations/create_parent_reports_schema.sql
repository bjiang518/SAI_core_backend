-- StudyAI Parent Reports Database Schema
-- Migration: Create parent reports and mental health indicators tables

-- Parent Reports Table
-- Stores generated reports with progress comparison capability
CREATE TABLE IF NOT EXISTS parent_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    report_type VARCHAR(50) NOT NULL CHECK (report_type IN ('weekly', 'monthly', 'custom', 'progress')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Core Report Data
    report_data JSONB NOT NULL,

    -- Progress Comparison Data
    previous_report_id UUID REFERENCES parent_reports(id),
    comparison_data JSONB, -- Stores progress metrics vs previous report

    -- Report Metadata
    generated_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL DEFAULT NOW() + INTERVAL '7 days',
    report_version VARCHAR(10) DEFAULT '1.0',

    -- Status and Settings
    status VARCHAR(20) DEFAULT 'completed' CHECK (status IN ('generating', 'completed', 'failed', 'expired')),
    generation_time_ms INTEGER,
    ai_analysis_included BOOLEAN DEFAULT false,

    -- Foreign Key
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,

    -- Constraints
    CHECK (start_date <= end_date),
    CHECK (generated_at <= expires_at)
);

-- Mental Health Indicators Table
-- Tracks emotional and psychological indicators from student interactions
CREATE TABLE IF NOT EXISTS mental_health_indicators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    session_id UUID,
    conversation_id UUID,

    -- Indicator Details
    indicator_type VARCHAR(50) NOT NULL CHECK (indicator_type IN (
        'frustration', 'confidence', 'engagement', 'stress',
        'motivation', 'confusion', 'satisfaction', 'anxiety'
    )),
    score DECIMAL(4,3) NOT NULL CHECK (score >= 0.000 AND score <= 1.000),
    confidence_level DECIMAL(4,3) DEFAULT 0.500, -- How confident we are in this score

    -- Evidence and Context
    evidence_text TEXT,
    context_data JSONB, -- Additional context like question difficulty, time of day, etc.
    detection_method VARCHAR(50) DEFAULT 'pattern_analysis' CHECK (detection_method IN (
        'pattern_analysis', 'ai_analysis', 'behavioral_analysis', 'manual'
    )),

    -- Temporal Data
    detected_at TIMESTAMP DEFAULT NOW(),
    interaction_duration_seconds INTEGER,

    -- Relationships
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Report Performance Metrics Table
-- Tracks report generation performance and usage
CREATE TABLE IF NOT EXISTS report_metrics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES parent_reports(id) ON DELETE CASCADE,

    -- Performance Metrics
    data_fetch_time_ms INTEGER,
    ai_analysis_time_ms INTEGER,
    report_compilation_time_ms INTEGER,
    total_generation_time_ms INTEGER,

    -- Data Volume Metrics
    questions_analyzed INTEGER DEFAULT 0,
    conversations_analyzed INTEGER DEFAULT 0,
    sessions_analyzed INTEGER DEFAULT 0,
    mental_health_indicators_count INTEGER DEFAULT 0,

    -- Usage Metrics
    viewed_count INTEGER DEFAULT 0,
    exported_count INTEGER DEFAULT 0,
    shared_count INTEGER DEFAULT 0,
    last_viewed_at TIMESTAMP,

    -- Quality Metrics
    ai_tokens_used INTEGER DEFAULT 0,
    cache_hit_rate DECIMAL(4,3) DEFAULT 0.000,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Progress Tracking Table
-- Stores historical progress data for trend analysis
CREATE TABLE IF NOT EXISTS student_progress_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    report_id UUID NOT NULL REFERENCES parent_reports(id) ON DELETE CASCADE,

    -- Time Period
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    period_type VARCHAR(20) NOT NULL CHECK (period_type IN ('week', 'month', 'quarter', 'custom')),

    -- Academic Metrics
    total_questions INTEGER DEFAULT 0,
    correct_answers INTEGER DEFAULT 0,
    accuracy_rate DECIMAL(5,3) DEFAULT 0.000,
    average_confidence DECIMAL(5,3) DEFAULT 0.000,

    -- Subject Performance (JSONB for flexibility)
    subject_performance JSONB DEFAULT '{}', -- {"math": {"accuracy": 0.85, "questions": 20}, "science": {...}}

    -- Learning Metrics
    study_hours DECIMAL(6,2) DEFAULT 0.00,
    active_days INTEGER DEFAULT 0,
    sessions_count INTEGER DEFAULT 0,

    -- Mental Health Metrics
    average_engagement DECIMAL(4,3) DEFAULT 0.500,
    frustration_incidents INTEGER DEFAULT 0,
    confidence_trend VARCHAR(20) DEFAULT 'stable' CHECK (confidence_trend IN ('improving', 'declining', 'stable')),

    -- Progress Indicators
    improvement_rate DECIMAL(5,3) DEFAULT 0.000, -- Compared to previous period
    consistency_score DECIMAL(4,3) DEFAULT 0.500, -- How consistent the performance was

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW(),

    -- Foreign Key
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,

    -- Constraints
    CHECK (period_start <= period_end),
    CHECK (accuracy_rate >= 0.000 AND accuracy_rate <= 1.000),
    CHECK (average_confidence >= 0.000 AND average_confidence <= 1.000)
);

-- Performance Indexes
CREATE INDEX IF NOT EXISTS idx_parent_reports_user_date ON parent_reports(user_id, start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_parent_reports_user_generated ON parent_reports(user_id, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_parent_reports_status ON parent_reports(status, expires_at);

CREATE INDEX IF NOT EXISTS idx_mental_health_user_date ON mental_health_indicators(user_id, detected_at);
CREATE INDEX IF NOT EXISTS idx_mental_health_type_score ON mental_health_indicators(indicator_type, score);
CREATE INDEX IF NOT EXISTS idx_mental_health_session ON mental_health_indicators(session_id) WHERE session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_report_metrics_report ON report_metrics(report_id);
CREATE INDEX IF NOT EXISTS idx_report_metrics_performance ON report_metrics(total_generation_time_ms);

CREATE INDEX IF NOT EXISTS idx_progress_history_user_period ON student_progress_history(user_id, period_start, period_end);
CREATE INDEX IF NOT EXISTS idx_progress_history_type ON student_progress_history(period_type, created_at DESC);

-- Views for Common Queries

-- Recent Reports View
CREATE OR REPLACE VIEW recent_parent_reports AS
SELECT
    pr.*,
    u.name as student_name,
    u.email as student_email,
    rm.total_generation_time_ms,
    rm.viewed_count,
    rm.exported_count
FROM parent_reports pr
JOIN users u ON pr.user_id = u.id
LEFT JOIN report_metrics rm ON pr.id = rm.report_id
WHERE pr.status = 'completed'
  AND pr.expires_at > NOW()
ORDER BY pr.generated_at DESC;

-- Student Progress Summary View
CREATE OR REPLACE VIEW student_progress_summary AS
SELECT
    user_id,
    period_type,
    COUNT(*) as total_reports,
    AVG(accuracy_rate) as avg_accuracy,
    AVG(average_confidence) as avg_confidence,
    AVG(study_hours) as avg_study_hours,
    AVG(average_engagement) as avg_engagement,
    CASE
        WHEN AVG(improvement_rate) > 0.05 THEN 'improving'
        WHEN AVG(improvement_rate) < -0.05 THEN 'declining'
        ELSE 'stable'
    END as overall_trend,
    MAX(created_at) as last_updated
FROM student_progress_history
GROUP BY user_id, period_type;

-- Mental Health Trends View
CREATE OR REPLACE VIEW mental_health_trends AS
SELECT
    user_id,
    indicator_type,
    DATE_TRUNC('week', detected_at) as week_start,
    AVG(score) as avg_score,
    COUNT(*) as indicator_count,
    STDDEV(score) as score_variance
FROM mental_health_indicators
WHERE detected_at >= NOW() - INTERVAL '12 weeks'
GROUP BY user_id, indicator_type, DATE_TRUNC('week', detected_at)
ORDER BY user_id, indicator_type, week_start;

-- Grant necessary permissions (adjust based on your user setup)
-- GRANT SELECT, INSERT, UPDATE, DELETE ON parent_reports TO studyai_app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON mental_health_indicators TO studyai_app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON report_metrics TO studyai_app_user;
-- GRANT SELECT, INSERT, UPDATE, DELETE ON student_progress_history TO studyai_app_user;
-- GRANT SELECT ON recent_parent_reports TO studyai_app_user;
-- GRANT SELECT ON student_progress_summary TO studyai_app_user;
-- GRANT SELECT ON mental_health_trends TO studyai_app_user;

-- Sample Data Validation Queries (for testing)
/*
-- Test parent_reports table
SELECT 'parent_reports table created' as status
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'parent_reports');

-- Test mental_health_indicators table
SELECT 'mental_health_indicators table created' as status
WHERE EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'mental_health_indicators');

-- Test indexes
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE tablename IN ('parent_reports', 'mental_health_indicators', 'report_metrics', 'student_progress_history');

-- Test views
SELECT viewname FROM pg_views WHERE viewname IN ('recent_parent_reports', 'student_progress_summary', 'mental_health_trends');
*/