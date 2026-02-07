#\!/bin/bash

PROJECT_FILE="StudyAI.xcodeproj/project.pbxproj"
FILE_NAME="ParentReportSettings.swift"
FILE_PATH="StudyAI/Models/ParentReportSettings.swift"

# Generate UUIDs (Xcode style - 24 hex characters)
FILE_REF_UUID=$(uuidgen | tr -d '-' | head -c 24)
BUILD_FILE_UUID=$(uuidgen | tr -d '-' | head -c 24)

echo "Generated UUIDs:"
echo "FILE_REF_UUID: $FILE_REF_UUID"
echo "BUILD_FILE_UUID: $BUILD_FILE_UUID"

# Backup the project file
cp "$PROJECT_FILE" "${PROJECT_FILE}.backup"

# Add PBXBuildFile entry (find the /* Begin PBXBuildFile section */ and add after the first line)
awk -v build_uuid="$BUILD_FILE_UUID" -v file_uuid="$FILE_REF_UUID" -v filename="$FILE_NAME" '
/\/\* Begin PBXBuildFile section \*\// {
    print $0
    print "\t\t" build_uuid " /* " filename " in Sources */ = {isa = PBXBuildFile; fileRef = " file_uuid " /* " filename " */; };"
    next
}
{print}
' "$PROJECT_FILE" > "${PROJECT_FILE}.tmp" && mv "${PROJECT_FILE}.tmp" "$PROJECT_FILE"

# Add PBXFileReference entry (find the /* Begin PBXFileReference section */ and add after the first line)
awk -v file_uuid="$FILE_REF_UUID" -v filename="$FILE_NAME" -v filepath="$FILE_PATH" '
/\/\* Begin PBXFileReference section \*\// {
    print $0
    print "\t\t" file_uuid " /* " filename " */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = " filename "; path = " filepath "; sourceTree = SOURCE_ROOT; };"
    next
}
{print}
' "$PROJECT_FILE" > "${PROJECT_FILE}.tmp" && mv "${PROJECT_FILE}.tmp" "$PROJECT_FILE"

# Add to Sources build phase (find PBXSourcesBuildPhase and add to files array)
awk -v build_uuid="$BUILD_FILE_UUID" -v filename="$FILE_NAME" '
/\/\* Sources \*\/ = {/ {
    in_sources = 1
}
in_sources && /files = \(/ {
    print $0
    print "\t\t\t\t" build_uuid " /* " filename " in Sources */,"
    in_sources = 0
    next
}
{print}
' "$PROJECT_FILE" > "${PROJECT_FILE}.tmp" && mv "${PROJECT_FILE}.tmp" "$PROJECT_FILE"

# Find the Models group and add file reference there
# First, find a Models group UUID
MODELS_GROUP=$(grep -A 5 "name = Models;" "$PROJECT_FILE" | grep "isa = PBXGroup" | head -1 | awk '{print $1}')

if [ -n "$MODELS_GROUP" ]; then
    echo "Found Models group: $MODELS_GROUP"
    # Add to Models group children array
    awk -v models_group="$MODELS_GROUP" -v file_uuid="$FILE_REF_UUID" -v filename="$FILE_NAME" '
    $0 ~ models_group " /\\* Models \\*/ = {" {
        in_models = 1
    }
    in_models && /children = \(/ {
        print $0
        print "\t\t\t\t" file_uuid " /* " filename " */,"
        in_models = 0
        next
    }
    {print}
    ' "$PROJECT_FILE" > "${PROJECT_FILE}.tmp" && mv "${PROJECT_FILE}.tmp" "$PROJECT_FILE"
fi

echo "File added to Xcode project\!"
