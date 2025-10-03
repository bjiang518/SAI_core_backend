#!/usr/bin/env python3
"""
Add missing Swift files to Xcode project
"""

import os
import sys
import uuid
import re

def generate_uuid():
    """Generate a unique 24-character hex ID for Xcode"""
    return uuid.uuid4().hex[:24].upper()

def add_file_to_project(project_path, file_path, target_name="StudyAI"):
    """Add a Swift file to the Xcode project"""

    # Read project file
    with open(project_path, 'r') as f:
        content = f.read()

    # Get relative path
    rel_path = os.path.relpath(file_path, os.path.dirname(project_path))
    file_name = os.path.basename(file_path)

    # Check if already in project
    if file_name in content:
        print(f"✓ {file_name} already in project")
        return False

    # Generate UUIDs
    file_ref_uuid = generate_uuid()
    build_file_uuid = generate_uuid()

    # Determine group based on path
    if "/Models/" in file_path:
        group_name = "Models"
    elif "/ViewModels/" in file_path:
        group_name = "ViewModels"
    elif "/Controllers/" in file_path:
        group_name = "Controllers"
    elif "/Views/" in file_path:
        group_name = "Views"
    else:
        group_name = "StudyAI"

    # Add file reference
    file_ref = f'\t\t{file_ref_uuid} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};\n'

    # Find PBXFileReference section
    file_ref_section = re.search(r'(/\* Begin PBXFileReference section \*/.*?/\* End PBXFileReference section \*/)', content, re.DOTALL)
    if file_ref_section:
        insert_pos = file_ref_section.end() - len('/* End PBXFileReference section */')
        content = content[:insert_pos] + file_ref + content[insert_pos:]

    # Add build file
    build_file = f'\t\t{build_file_uuid} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* {file_name} */; }};\n'

    # Find PBXBuildFile section
    build_file_section = re.search(r'(/\* Begin PBXBuildFile section \*/.*?/\* End PBXBuildFile section \*/)', content, re.DOTALL)
    if build_file_section:
        insert_pos = build_file_section.end() - len('/* End PBXBuildFile section */')
        content = content[:insert_pos] + build_file + content[insert_pos:]

    # Add to group
    group_pattern = rf'(/\* {group_name} \*/.*?children = \()(.*?)(\);)'
    group_match = re.search(group_pattern, content, re.DOTALL)
    if group_match:
        children_section = group_match.group(2)
        new_child = f'\n\t\t\t\t{file_ref_uuid} /* {file_name} */,'
        insert_pos = group_match.end(2)
        content = content[:insert_pos] + new_child + content[insert_pos:]

    # Add to PBXSourcesBuildPhase
    sources_pattern = r'(/\* Sources \*/.*?files = \()(.*?)(\);)'
    sources_match = re.search(sources_pattern, content, re.DOTALL)
    if sources_match:
        files_section = sources_match.group(2)
        new_source = f'\n\t\t\t\t{build_file_uuid} /* {file_name} in Sources */,'
        insert_pos = sources_match.end(2)
        content = content[:insert_pos] + new_source + content[insert_pos:]

    # Write back
    with open(project_path, 'w') as f:
        f.write(content)

    print(f"✓ Added {file_name} to project")
    return True

def main():
    # Project paths
    project_file = "StudyAI.xcodeproj/project.pbxproj"

    # Missing files to add
    missing_files = [
        "StudyAI/Models/HomeworkFlowModels.swift",
        "StudyAI/Models/ChatMessage.swift",
        "StudyAI/Models/Conversation.swift",
        "StudyAI/ViewModels/CameraViewModel.swift",
        "StudyAI/ViewModels/HistoryViewModel.swift",
        "StudyAI/Controllers/HomeworkFlowController.swift",
    ]

    print("Adding missing files to Xcode project...")
    print()

    added_count = 0
    for file_path in missing_files:
        if os.path.exists(file_path):
            if add_file_to_project(project_file, file_path):
                added_count += 1
        else:
            print(f"✗ File not found: {file_path}")

    print()
    print(f"Added {added_count} files to project")

    if added_count > 0:
        print()
        print("Please clean and rebuild in Xcode:")
        print("  Product -> Clean Build Folder (Cmd+Shift+K)")
        print("  Product -> Build (Cmd+B)")

if __name__ == "__main__":
    main()