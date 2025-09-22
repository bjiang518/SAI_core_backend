#!/bin/bash

# Script to add new question generation files to Xcode project
# This modifies the project.pbxproj file to include the new Swift files

PROJECT_DIR="/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI"
PROJECT_FILE="$PROJECT_DIR/StudyAI.xcodeproj/project.pbxproj"

echo "🎯 Adding Question Generation files to Xcode project..."

# Backup the original project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"
echo "✅ Created backup of project.pbxproj"

# Files to add with their paths relative to project root
declare -A FILES_TO_ADD=(
    ["StudyAI/Services/QuestionGenerationService.swift"]="Services"
    ["StudyAI/Services/QuestionGenerationDataAdapter.swift"]="Services"
    ["StudyAI/Views/QuestionGenerationView.swift"]="Views"
    ["StudyAI/Views/QuestionDetailView.swift"]="Views"
    ["StudyAI/Views/GeneratedQuestionsListView.swift"]="Views"
)

# Function to generate UUID (for Xcode file references)
generate_uuid() {
    python3 -c "import uuid; print(str(uuid.uuid4()).upper().replace('-', ''))"
}

# Function to add file to project
add_file_to_project() {
    local file_path="$1"
    local group_name="$2"
    local file_name=$(basename "$file_path")

    echo "📁 Adding $file_name to $group_name group..."

    # Check if file exists
    if [ ! -f "$PROJECT_DIR/$file_path" ]; then
        echo "❌ File not found: $PROJECT_DIR/$file_path"
        return 1
    fi

    # Generate UUIDs for file reference and build file
    local file_ref_uuid=$(generate_uuid)
    local build_file_uuid=$(generate_uuid)

    # Add file reference to PBXFileReference section
    sed -i '' "/\/\* End PBXFileReference section \*\//i\\
\\t\\t${file_ref_uuid} /* ${file_name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ${file_name}; sourceTree = \"<group>\"; };\\
" "$PROJECT_FILE"

    # Add build file to PBXBuildFile section
    sed -i '' "/\/\* End PBXBuildFile section \*\//i\\
\\t\\t${build_file_uuid} /* ${file_name} in Sources */ = {isa = PBXBuildFile; fileRef = ${file_ref_uuid} /* ${file_name} */; };\\
" "$PROJECT_FILE"

    # Add to appropriate group (Services or Views)
    if [ "$group_name" = "Services" ]; then
        # Find Services group and add file reference
        sed -i '' "/\/\* Services \*\/ = {/,/children = (/{
            /children = (/a\\
\\t\\t\\t\\t${file_ref_uuid} /* ${file_name} */,
        }" "$PROJECT_FILE"
    elif [ "$group_name" = "Views" ]; then
        # Find Views group and add file reference
        sed -i '' "/\/\* Views \*\/ = {/,/children = (/{
            /children = (/a\\
\\t\\t\\t\\t${file_ref_uuid} /* ${file_name} */,
        }" "$PROJECT_FILE"
    fi

    # Add to Sources build phase
    sed -i '' "/\/\* Sources \*\/ = {/,/files = (/{
        /files = (/a\\
\\t\\t\\t\\t${build_file_uuid} /* ${file_name} in Sources */,
    }" "$PROJECT_FILE"

    echo "✅ Added $file_name (${file_ref_uuid})"
}

# Add each file to the project
for file_path in "${!FILES_TO_ADD[@]}"; do
    group_name="${FILES_TO_ADD[$file_path]}"
    add_file_to_project "$file_path" "$group_name"
done

echo ""
echo "🎉 All files added to Xcode project!"
echo "📋 Added files:"
for file_path in "${!FILES_TO_ADD[@]}"; do
    echo "   - $(basename "$file_path")"
done
echo ""
echo "💡 If there are issues, restore backup with:"
echo "   cp $PROJECT_FILE.backup $PROJECT_FILE"