#!/usr/bin/env python3
"""
Fix all incorrect file paths in Xcode project.pbxproj
Changes: path = ../StudyAI/... ; sourceTree = "<group>"
To:      path = StudyAI/... ; sourceTree = SOURCE_ROOT
"""

import re

project_path = "/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI.xcodeproj/project.pbxproj"

print("Reading project file...")
with open(project_path, 'r') as f:
    content = f.read()

# Pattern to match file references with incorrect paths
# Handles both formats:
# 1. UUID /* FileName.swift */ = {isa = PBXFileReference; ...; path = ../StudyAI/Path/File.swift; sourceTree = "<group>"; };
# 2. UUID /* ../StudyAI/Path/File.swift */ = {isa = PBXFileReference; ...; path = ../StudyAI/Path/File.swift; sourceTree = "<group>"; };

pattern = r'([\w\d]+) /\* ([^*]+) \*/ = \{isa = PBXFileReference; lastKnownFileType = sourcecode\.swift; (name = [^;]+; )?path = \.\./StudyAI/([^;]+); sourceTree = "<group>"; \};'

matches = re.findall(pattern, content)
print(f"Found {len(matches)} files to fix\n")

def replacement(match):
    uuid = match.group(1)
    comment_name = match.group(2)
    name_field = match.group(3) if match.group(3) else ""
    file_path = match.group(4)

    # Extract just the filename for the name field if not present
    if not name_field:
        filename = file_path.split('/')[-1]
        name_field = f"name = {filename}; "

    return f'{uuid} /* {comment_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; {name_field}path = StudyAI/{file_path}; sourceTree = SOURCE_ROOT; }};'

# Apply replacements
new_content = re.sub(pattern, replacement, content)

# Count changes
changes_made = len(re.findall(pattern, content))

print(f"Writing changes to project file...")
with open(project_path, 'w') as f:
    f.write(new_content)

print(f"✅ Fixed {changes_made} file references")
print("\nFixed files:")
for match in matches:
    filename = match[3].split('/')[-1]
    print(f"  - {filename}")

print("\n⚠️  Next steps:")
print("1. Quit Xcode (Cmd+Q)")
print("2. Delete DerivedData: rm -rf ~/Library/Developer/Xcode/DerivedData/StudyAI-*")
print("3. Reopen Xcode")
print("4. Clean Build Folder (Cmd+Shift+K)")
print("5. Rebuild (Cmd+B)")