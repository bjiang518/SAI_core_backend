#!/bin/bash

# Script to add new question generation files to Xcode project
PROJECT_DIR="/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI"
PROJECT_FILE="$PROJECT_DIR/StudyAI.xcodeproj/project.pbxproj"

echo "🎯 Adding Question Generation files to Xcode project..."

# Backup the original project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"
echo "✅ Created backup of project.pbxproj"

# Function to generate UUID (for Xcode file references)
generate_uuid() {
    python3 -c "import uuid; print(str(uuid.uuid4()).upper().replace('-', ''))"
}

# Service files
echo "📁 Adding Service files..."

# QuestionGenerationService.swift
QGS_REF_UUID=$(generate_uuid)
QGS_BUILD_UUID=$(generate_uuid)
echo "Adding QuestionGenerationService.swift (${QGS_REF_UUID})"

# QuestionGenerationDataAdapter.swift
QGDA_REF_UUID=$(generate_uuid)
QGDA_BUILD_UUID=$(generate_uuid)
echo "Adding QuestionGenerationDataAdapter.swift (${QGDA_REF_UUID})"

# View files
echo "📁 Adding View files..."

# QuestionGenerationView.swift
QGV_REF_UUID=$(generate_uuid)
QGV_BUILD_UUID=$(generate_uuid)
echo "Adding QuestionGenerationView.swift (${QGV_REF_UUID})"

# QuestionDetailView.swift
QDV_REF_UUID=$(generate_uuid)
QDV_BUILD_UUID=$(generate_uuid)
echo "Adding QuestionDetailView.swift (${QDV_REF_UUID})"

# GeneratedQuestionsListView.swift
GQLV_REF_UUID=$(generate_uuid)
GQLV_BUILD_UUID=$(generate_uuid)
echo "Adding GeneratedQuestionsListView.swift (${GQLV_REF_UUID})"

# Add file references to PBXFileReference section
echo "📋 Adding file references..."
sed -i '' "/\/\* End PBXFileReference section \*\//i\\
\\t\\t${QGS_REF_UUID} /* QuestionGenerationService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionGenerationService.swift; sourceTree = \"<group>\"; };\\
\\t\\t${QGDA_REF_UUID} /* QuestionGenerationDataAdapter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionGenerationDataAdapter.swift; sourceTree = \"<group>\"; };\\
\\t\\t${QGV_REF_UUID} /* QuestionGenerationView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionGenerationView.swift; sourceTree = \"<group>\"; };\\
\\t\\t${QDV_REF_UUID} /* QuestionDetailView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QuestionDetailView.swift; sourceTree = \"<group>\"; };\\
\\t\\t${GQLV_REF_UUID} /* GeneratedQuestionsListView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GeneratedQuestionsListView.swift; sourceTree = \"<group>\"; };\\
" "$PROJECT_FILE"

# Add build files to PBXBuildFile section
echo "🔨 Adding build files..."
sed -i '' "/\/\* End PBXBuildFile section \*\//i\\
\\t\\t${QGS_BUILD_UUID} /* QuestionGenerationService.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${QGS_REF_UUID} /* QuestionGenerationService.swift */; };\\
\\t\\t${QGDA_BUILD_UUID} /* QuestionGenerationDataAdapter.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${QGDA_REF_UUID} /* QuestionGenerationDataAdapter.swift */; };\\
\\t\\t${QGV_BUILD_UUID} /* QuestionGenerationView.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${QGV_REF_UUID} /* QuestionGenerationView.swift */; };\\
\\t\\t${QDV_BUILD_UUID} /* QuestionDetailView.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${QDV_REF_UUID} /* QuestionDetailView.swift */; };\\
\\t\\t${GQLV_BUILD_UUID} /* GeneratedQuestionsListView.swift in Sources */ = {isa = PBXBuildFile; fileRef = ${GQLV_REF_UUID} /* GeneratedQuestionsListView.swift */; };\\
" "$PROJECT_FILE"

# Add to Sources build phase
echo "🏗️ Adding to Sources build phase..."
# Find the Sources build phase and add files
if grep -q "/* Sources */ = {" "$PROJECT_FILE"; then
    sed -i '' "/\/\* Sources \*\/ = {/,/files = (/{
        /files = (/a\\
\\t\\t\\t\\t${QGS_BUILD_UUID} /* QuestionGenerationService.swift in Sources */,\\
\\t\\t\\t\\t${QGDA_BUILD_UUID} /* QuestionGenerationDataAdapter.swift in Sources */,\\
\\t\\t\\t\\t${QGV_BUILD_UUID} /* QuestionGenerationView.swift in Sources */,\\
\\t\\t\\t\\t${QDV_BUILD_UUID} /* QuestionDetailView.swift in Sources */,\\
\\t\\t\\t\\t${GQLV_BUILD_UUID} /* GeneratedQuestionsListView.swift in Sources */,
    }" "$PROJECT_FILE"
    echo "✅ Added to Sources build phase"
else
    echo "⚠️  Could not find Sources build phase"
fi

# Add to Services group
echo "📂 Adding to Services group..."
# Find Services group and add service files
if grep -q "/* Services */ = {" "$PROJECT_FILE"; then
    sed -i '' "/\/\* Services \*\/ = {/,/children = (/{
        /children = (/a\\
\\t\\t\\t\\t${QGS_REF_UUID} /* QuestionGenerationService.swift */,\\
\\t\\t\\t\\t${QGDA_REF_UUID} /* QuestionGenerationDataAdapter.swift */,
    }" "$PROJECT_FILE"
    echo "✅ Added services to Services group"
else
    echo "⚠️  Could not find Services group"
fi

# Add to Views group
echo "📂 Adding to Views group..."
# Find Views group and add view files
if grep -q "/* Views */ = {" "$PROJECT_FILE"; then
    sed -i '' "/\/\* Views \*\/ = {/,/children = (/{
        /children = (/a\\
\\t\\t\\t\\t${QGV_REF_UUID} /* QuestionGenerationView.swift */,\\
\\t\\t\\t\\t${QDV_REF_UUID} /* QuestionDetailView.swift */,\\
\\t\\t\\t\\t${GQLV_REF_UUID} /* GeneratedQuestionsListView.swift */,
    }" "$PROJECT_FILE"
    echo "✅ Added views to Views group"
else
    echo "⚠️  Could not find Views group"
fi

echo ""
echo "🎉 All files added to Xcode project!"
echo "📋 Added files:"
echo "   Services:"
echo "   - QuestionGenerationService.swift"
echo "   - QuestionGenerationDataAdapter.swift"
echo "   Views:"
echo "   - QuestionGenerationView.swift"
echo "   - QuestionDetailView.swift"
echo "   - GeneratedQuestionsListView.swift"
echo ""
echo "💡 If there are issues, restore backup with:"
echo "   cp $PROJECT_FILE.backup $PROJECT_FILE"