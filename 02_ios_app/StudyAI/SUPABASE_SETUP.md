# Supabase Setup for StudyAI Session History

This document explains how to set up Supabase for the StudyAI mistake notebook functionality.

## 1. Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Choose a project name (e.g., "studyai-sessions")
3. Choose a strong database password
4. Select a region close to your users

## 2. Configure Database Schema

Run the following SQL in the Supabase SQL Editor:

```sql
-- Create archived_sessions table
CREATE TABLE archived_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    subject VARCHAR(100) NOT NULL,
    session_date DATE NOT NULL DEFAULT CURRENT_DATE,
    title VARCHAR(200),
    
    -- Image storage
    original_image_url TEXT NOT NULL,
    thumbnail_url TEXT,
    
    -- AI parsing results (stored as JSONB for flexibility)
    ai_parsing_result JSONB NOT NULL,
    processing_time FLOAT NOT NULL DEFAULT 0,
    overall_confidence FLOAT NOT NULL DEFAULT 0,
    
    -- Student interaction
    student_answers JSONB,
    notes TEXT,
    review_count INTEGER DEFAULT 0,
    last_reviewed_at TIMESTAMP WITH TIME ZONE,
    
    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_archived_sessions_user_date ON archived_sessions(user_id, session_date DESC);
CREATE INDEX idx_archived_sessions_subject ON archived_sessions(user_id, subject);
CREATE INDEX idx_archived_sessions_review ON archived_sessions(user_id, last_reviewed_at DESC);

-- Enable Row Level Security (RLS)
ALTER TABLE archived_sessions ENABLE ROW LEVEL SECURITY;

-- Create RLS policies (since we're using custom auth, we'll use user_id directly)
CREATE POLICY "Users can insert their own sessions" ON archived_sessions
    FOR INSERT WITH CHECK (user_id = current_setting('request.jwt.claims', true)::json->>'user_id');

CREATE POLICY "Users can view their own sessions" ON archived_sessions
    FOR SELECT USING (user_id = current_setting('request.jwt.claims', true)::json->>'user_id');

CREATE POLICY "Users can update their own sessions" ON archived_sessions
    FOR UPDATE USING (user_id = current_setting('request.jwt.claims', true)::json->>'user_id');

-- For now, let's use a simpler policy that works with our custom auth
-- We'll update this to use proper JWT claims later
DROP POLICY "Users can insert their own sessions" ON archived_sessions;
DROP POLICY "Users can view their own sessions" ON archived_sessions;
DROP POLICY "Users can update their own sessions" ON archived_sessions;

-- Temporary policies for custom auth integration
CREATE POLICY "Enable all operations for authenticated users" ON archived_sessions
    FOR ALL USING (true);
```

## 3. Get Project Credentials

1. Go to Project Settings → API
2. Copy the following values:
   - **Project URL**: `https://your-project-ref.supabase.co`
   - **Anon Key**: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

## 4. Update iOS Configuration

Update the `SupabaseService.swift` file with your credentials:

```swift
// Replace these values in SupabaseService.swift
private let supabaseURL = "https://your-project-ref.supabase.co"
private let supabaseAnonKey = "your-anon-key-here"
```

## 5. Test the Integration

1. Run the iOS app
2. Parse a homework image using AI Homework Parser
3. Tap the "Save" button in the results view
4. Check the Supabase dashboard to see if the session was saved

## 6. Optional: Set up Storage for Images

If you want to store actual images (not just URLs):

```sql
-- Create a storage bucket for homework images
INSERT INTO storage.buckets (id, name, public) VALUES ('homework-images', 'homework-images', true);

-- Create storage policies
CREATE POLICY "Give users access to own folder" ON storage.objects
    FOR ALL USING (bucket_id = 'homework-images' AND auth.uid()::text = (storage.foldername(name))[1]);
```

## 7. Security Considerations

### Current Setup (Temporary)
- Uses simple RLS policies that allow all operations
- User identification through email stored in UserDefaults
- Suitable for development and testing

### Production Recommendations
1. **Implement proper JWT authentication**:
   - Integrate Supabase Auth with your existing auth system
   - Use JWT tokens for user identification
   - Update RLS policies to use `auth.uid()`

2. **Enhance RLS policies**:
   ```sql
   -- Better RLS policies for production
   CREATE POLICY "Users can only access their own sessions" ON archived_sessions
       FOR ALL USING (user_id = auth.uid()::text);
   ```

3. **Add rate limiting** to prevent abuse
4. **Implement proper image upload** to Supabase Storage
5. **Add data validation** at the database level

## 8. Monitoring and Maintenance

1. **Monitor usage** in Supabase Dashboard
2. **Set up backups** for important data
3. **Review RLS policies** regularly
4. **Monitor storage usage** for images
5. **Set up alerts** for unusual activity

## 9. Troubleshooting

### Common Issues:

**"User not authenticated" error:**
- Check that user email is stored in UserDefaults after login
- Verify RLS policies are not blocking the operation

**"Invalid URL" error:**
- Double-check the Supabase URL format
- Ensure no trailing slash in the URL

**Database connection issues:**
- Verify the anon key is correct
- Check network connectivity
- Review Supabase project status

**RLS policy issues:**
- Temporarily disable RLS for testing: `ALTER TABLE archived_sessions DISABLE ROW LEVEL SECURITY;`
- Re-enable and fix policies once identified

## 10. Next Steps

1. **Calendar View**: Implement the calendar view to show sessions by date
2. **Subject Codebook**: Build the subject-organized view
3. **Detailed Session View**: Create a detailed view for individual sessions
4. **Statistics Dashboard**: Add analytics and progress tracking
5. **Export Functionality**: Allow users to export their mistake notebook
6. **Offline Support**: Cache sessions for offline viewing

---

**Database Schema Version**: 1.0  
**Last Updated**: September 2025  
**Compatible with**: Supabase PostgreSQL 15+