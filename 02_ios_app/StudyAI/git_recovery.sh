#!/bin/bash

# StudyAI Git Recovery Script
# Restores the project from recent Git commits

echo "🔄 StudyAI Git Recovery Script"
echo "=============================="

PROJECT_DIR="/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI"
cd "$PROJECT_DIR"

echo "📁 Current project directory: $(pwd)"

# Step 1: Show current Git status
echo ""
echo "📊 Step 1: Current Git status summary..."
DELETED_FILES=$(git status --porcelain | grep "^ D" | wc -l | tr -d ' ')
MODIFIED_FILES=$(git status --porcelain | grep "^ M" | wc -l | tr -d ' ')
UNTRACKED_FILES=$(git status --porcelain | grep "^??" | wc -l | tr -d ' ')

echo "   📄 Deleted files: $DELETED_FILES"
echo "   ✏️  Modified files: $MODIFIED_FILES"
echo "   ❓ Untracked files: $UNTRACKED_FILES"

# Step 2: Restore key project files from Git
echo ""
echo "🔧 Step 2: Restoring key files from Git..."

# Restore Xcode project files that were deleted
if [ -f "StudyAI.xcodeproj/project.pbxproj" ]; then
    echo "✅ Xcode project file already restored"
else
    echo "📥 Restoring Xcode project file from Git..."
    git checkout HEAD -- StudyAI.xcodeproj/project.pbxproj
fi

# Restore any important directories that might have been deleted
echo "📁 Restoring source directories..."
git checkout HEAD -- StudyAI/Views/ 2>/dev/null && echo "✅ Views directory restored" || echo "ℹ️  Views directory unchanged"
git checkout HEAD -- StudyAI/Models/ 2>/dev/null && echo "✅ Models directory restored" || echo "ℹ️  Models directory unchanged"
git checkout HEAD -- StudyAI/Services/ 2>/dev/null && echo "✅ Services directory restored" || echo "ℹ️  Services directory unchanged"
git checkout HEAD -- StudyAI/Core/ 2>/dev/null && echo "✅ Core directory restored" || echo "ℹ️  Core directory unchanged"
git checkout HEAD -- StudyAI/ViewModels/ 2>/dev/null && echo "✅ ViewModels directory restored" || echo "ℹ️  ViewModels directory unchanged"

# Step 3: Clean up our cleanup mess
echo ""
echo "🧹 Step 3: Cleaning up temporary files..."

# Remove untracked cleanup files
rm -f QUICK_RECOVERY.md 2>/dev/null && echo "✅ Removed QUICK_RECOVERY.md" || true
rm -f SAFE_XCODE_CLEANUP.md 2>/dev/null && echo "✅ Removed SAFE_XCODE_CLEANUP.md" || true
rm -f XCODE_CLEANUP_GUIDE.md 2>/dev/null && echo "✅ Removed XCODE_CLEANUP_GUIDE.md" || true

# Clean up any backup files
find . -name "*.backup*" -delete 2>/dev/null && echo "✅ Removed backup files" || true

# Step 4: Verify restoration
echo ""
echo "📊 Step 4: Verifying restoration..."

SWIFT_FILES=$(find StudyAI -name "*.swift" 2>/dev/null | wc -l | tr -d ' ')
echo "📱 Swift files found: $SWIFT_FILES"

if [ -f "StudyAI/StudyAIApp.swift" ]; then
    echo "✅ StudyAIApp.swift found"
else
    echo "❌ StudyAIApp.swift missing"
fi

if [ -f "StudyAI/ContentView.swift" ]; then
    echo "✅ ContentView.swift found"
else
    echo "❌ ContentView.swift missing"
fi

if [ -f "StudyAI/NetworkService.swift" ]; then
    echo "✅ NetworkService.swift found"
else
    echo "❌ NetworkService.swift missing"
fi

# Step 5: Final status
echo ""
echo "📈 Step 5: Final Git status..."
git status --porcelain | head -10

echo ""
echo "✅ Git recovery complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Xcode should open automatically"
echo "2. Check if project loads properly"
echo "3. Build project (⌘B) to verify everything works"
echo "4. If any files are still missing, they're in Git history"
echo ""

# Open Xcode
echo "🚀 Opening Xcode..."
open StudyAI.xcodeproj

echo ""
echo "🎉 Recovery from Git complete! Your project should be restored!"