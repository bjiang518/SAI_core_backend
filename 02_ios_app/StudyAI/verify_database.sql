-- Quick verification queries to check if everything was created successfully
-- Run these one by one in your Supabase SQL Editor to verify the setup

-- 1. Check if the archived_sessions table was created
SELECT table_name, column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'archived_sessions'
ORDER BY ordinal_position;

-- 2. Check if indexes were created
SELECT indexname, tablename 
FROM pg_indexes 
WHERE tablename = 'archived_sessions';

-- 3. Check if RLS policies were created
SELECT schemaname, tablename, policyname, cmd, qual 
FROM pg_policies 
WHERE tablename = 'archived_sessions';

-- 4. Check if the view was created
SELECT table_name, table_type 
FROM information_schema.tables 
WHERE table_name = 'session_summaries';

-- 5. Test a simple insert to make sure everything works
INSERT INTO archived_sessions (
    user_id, 
    subject, 
    title, 
    original_image_url, 
    ai_parsing_result, 
    processing_time, 
    overall_confidence
) VALUES (
    'test-connection@example.com',
    'Test Subject',
    'Connection Test',
    'https://example.com/test.jpg',
    '{"questions": [], "questionCount": 0, "parsingMethod": "Test"}',
    1.0,
    1.0
);

-- 6. Verify the insert worked and clean up
SELECT id, user_id, subject, title, created_at FROM archived_sessions WHERE user_id = 'test-connection@example.com';

-- 7. Clean up the test record
DELETE FROM archived_sessions WHERE user_id = 'test-connection@example.com';