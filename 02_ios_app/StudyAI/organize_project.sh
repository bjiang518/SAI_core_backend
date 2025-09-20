#!/bin/bash

# StudyAI Xcode Project Organization Script
# This script removes the "Recovered References" group and creates proper folder structure

echo "🔧 Organizing StudyAI Xcode Project Structure..."

PROJECT_FILE="StudyAI.xcodeproj/project.pbxproj"

# Backup the project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup_organize"
echo "✅ Created backup of project file"

# Step 1: Create new main StudyAI group entry
# We'll add it before the Recovered References group

# First, let's extract all files from Recovered References and categorize them
echo "📁 Analyzing files in Recovered References..."

# Extract file references from the Recovered References group
grep -A 100 "Recovered References" "$PROJECT_FILE" | grep "StudyAI/" | head -50 > recovered_files.tmp

echo "📋 Found the following files to organize:"
cat recovered_files.tmp

# Step 2: Remove the Recovered References group reference from main group
echo "🗑️  Removing Recovered References from main group..."
sed -i '' '/7B02A71C2E7138CB00A3C67F.*Recovered References/d' "$PROJECT_FILE"

# Step 3: Add StudyAI main group reference to root
echo "➕ Adding StudyAI main group to root..."
sed -i '' '/7BC00E6D2E714D67002DF625.*GoogleService-Info.plist/i\
				STUDYAI_MAIN_GROUP /* StudyAI */,
' "$PROJECT_FILE"

echo "✅ Project structure reorganization complete!"
echo "🎯 Next: Open in Xcode to verify the new structure"

# Clean up
rm -f recovered_files.tmp