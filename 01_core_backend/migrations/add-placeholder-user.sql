-- Migration: Add placeholder user for anonymous sessions
-- This fixes foreign key constraint violations when storing conversations
-- without requiring user authentication

INSERT INTO users (id, email, name, auth_provider, is_active, email_verified)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'anonymous@studyai.local',
    'Anonymous User',
    'anonymous',
    true,
    false
) ON CONFLICT (id) DO NOTHING;

-- Verify the user was created
SELECT id, email, name, auth_provider FROM users WHERE id = '00000000-0000-0000-0000-000000000000';