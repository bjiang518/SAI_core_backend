#!/bin/bash

# Simple script to add files to Xcode project by manually inserting them
PROJECT_DIR="/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI"
PROJECT_FILE="$PROJECT_DIR/StudyAI.xcodeproj/project.pbxproj"

echo "🔧 Simple Xcode project file modification..."

# Create a backup
cp "$PROJECT_FILE" "$PROJECT_FILE.simple_backup"

# Generate simple UUIDs for the files
QGS_UUID="QGS123456789ABCDEF012345"
QGDA_UUID="QGDA123456789ABCDEF01234"
QGV_UUID="QGV123456789ABCDEF012345"
QDV_UUID="QDV123456789ABCDEF012345"
GQLV_UUID="GQLV123456789ABCDEF01234"

echo "📋 Adding file references..."

# Find a good place to add file references (after an existing service file)
sed -i '' "/AuthenticationService.swift.*sourcecode.swift/a\\
\\t\\t$QGS_UUID /* QuestionGenerationService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionGenerationService.swift; sourceTree = \"<group>\"; };\\
\\t\\t$QGDA_UUID /* QuestionGenerationDataAdapter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionGenerationDataAdapter.swift; sourceTree = \"<group>\"; };
" "$PROJECT_FILE"

# Find a good place to add view file references (after HomeView)
sed -i '' "/HomeView.swift.*sourcecode.swift/a\\
\\t\\t$QGV_UUID /* QuestionGenerationView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionGenerationView.swift; sourceTree = \"<group>\"; };\\
\\t\\t$QDV_UUID /* QuestionDetailView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionDetailView.swift; sourceTree = \"<group>\"; };\\
\\t\\t$GQLV_UUID /* GeneratedQuestionsListView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GeneratedQuestionsListView.swift; sourceTree = \"<group>\"; };
" "$PROJECT_FILE"

echo "🔨 Adding to build phase..."

# Add to the main build phase by finding an existing pattern and adding after it
sed -i '' "/AuthenticationService.swift in Sources/a\\
\\t\\t\\tQGSB123456789ABCDEF012345 /* QuestionGenerationService.swift in Sources */ = {isa = PBXBuildFile; fileRef = $QGS_UUID /* QuestionGenerationService.swift */; };\\
\\t\\t\\tQGDAB123456789ABCDEF01234 /* QuestionGenerationDataAdapter.swift in Sources */ = {isa = PBXBuildFile; fileRef = $QGDA_UUID /* QuestionGenerationDataAdapter.swift */; };\\
\\t\\t\\tQGVB123456789ABCDEF012345 /* QuestionGenerationView.swift in Sources */ = {isa = PBXBuildFile; fileRef = $QGV_UUID /* QuestionGenerationView.swift */; };\\
\\t\\t\\tQDVB123456789ABCDEF012345 /* QuestionDetailView.swift in Sources */ = {isa = PBXBuildFile; fileRef = $QDV_UUID /* QuestionDetailView.swift */; };\\
\\t\\t\\tGQLVB123456789ABCDEF01234 /* GeneratedQuestionsListView.swift in Sources */ = {isa = PBXBuildFile; fileRef = $GQLV_UUID /* GeneratedQuestionsListView.swift */; };
" "$PROJECT_FILE"

# Add the build files to the sources list
sed -i '' "/AuthenticationService.swift in Sources.*},/a\\
\\t\\t\\t\\tQGSB123456789ABCDEF012345 /* QuestionGenerationService.swift in Sources */,\\
\\t\\t\\t\\tQGDAB123456789ABCDEF01234 /* QuestionGenerationDataAdapter.swift in Sources */,\\
\\t\\t\\t\\tQGVB123456789ABCDEF012345 /* QuestionGenerationView.swift in Sources */,\\
\\t\\t\\t\\tQDVB123456789ABCDEF012345 /* QuestionDetailView.swift in Sources */,\\
\\t\\t\\t\\tGQLVB123456789ABCDEF01234 /* GeneratedQuestionsListView.swift in Sources */,
" "$PROJECT_FILE"

echo "✅ Files added to project. Testing build..."