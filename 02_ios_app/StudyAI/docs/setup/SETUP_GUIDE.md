# StudyAI Supabase Setup Guide

## Step 1: Get Your Supabase Project Credentials

1. Go to [app.supabase.com](https://app.supabase.com)
2. Find your **study.ai** project
3. Click on **Settings** → **API**
4. Copy the following values:

### Project URL
```
https://[your-project-ref].supabase.co
```

### Anon Key (Public)
```
eyJ[...long-token...]
```

## Step 2: Update iOS Configuration

Update the credentials in `SupabaseService.swift`:

```swift
// Replace these values in SupabaseService.swift
private let supabaseURL = "https://[your-project-ref].supabase.co"
private let supabaseAnonKey = "[your-anon-key]"
```

## Step 3: Create Database Schema

1. In your Supabase dashboard, go to **SQL Editor**
2. Run the `database_schema.sql` file content
3. This will create:
   - `archived_sessions` table
   - Performance indexes
   - Row Level Security policies
   - Helper views

## Step 4: Test the Connection

1. Build and run the iOS app
2. Use the AI Homework Parser to process an image
3. Tap the "Save" button in the results
4. Check your Supabase dashboard to see if data was saved

## Step 5: Verify Database

In Supabase dashboard → **Table Editor**:
- You should see the `archived_sessions` table
- Any saved sessions will appear as rows

## Troubleshooting

### Common Issues:

**"Invalid URL" error:**
- Check that the URL starts with `https://` and ends with `.supabase.co`
- No trailing slash

**"Authorization failed" error:**
- Verify the anon key is copied correctly
- Check RLS policies in the database

**"Table doesn't exist" error:**
- Make sure you ran the `database_schema.sql` script
- Check the SQL Editor for any errors

## Current Features Ready:

✅ **Session Archiving**: Save homework sessions to database  
✅ **Subject Categorization**: Auto-detect or manually select subjects  
✅ **Three View Modes**: List, Calendar, Subject Codebook  
✅ **Search & Filter**: Find sessions by subject or text  
✅ **Statistics**: Track progress and review counts  

## Next Steps:

Once the database is connected:
1. Test archiving a homework session
2. View sessions in the History tab
3. Try different view modes (List, Calendar, Subjects)
4. Search and filter functionality

The mistake notebook is ready to use! 📚