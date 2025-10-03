#!/usr/bin/env python3
"""
Remove batch of 4 ultra-safe test/sketch views
These have been verified to have ZERO external dependencies
"""

import os
import re
import subprocess

# Ultra-safe batch - only test/sketch views with no dependencies
ultra_safe_views = [
    "AIHomeworkTestView.swift",
    "StableAIHomeworkTestView.swift",
    "HomeProgressSketch.swift",
    "NativeImageEditView.swift",
]

views_dir = "StudyAI/Views"
project_file = "StudyAI.xcodeproj/project.pbxproj"

def remove_from_filesystem():
    """Remove files from filesystem"""
    print("🗑️  Removing files from filesystem...")
    removed_count = 0
    for view in ultra_safe_views:
        file_path = os.path.join(views_dir, view)
        if os.path.exists(file_path):
            os.remove(file_path)
            print(f"  ✓ Deleted: {view}")
            removed_count += 1
        else:
            print(f"  ⚠️  Not found: {view}")
    return removed_count

def remove_from_xcode_project():
    """Remove references from Xcode project file"""
    print("\n📝 Removing Xcode project references...")

    with open(project_file, 'r') as f:
        content = f.read()

    original_content = content
    removed_count = 0

    for view in ultra_safe_views:
        # Find and remove PBXFileReference
        file_ref_pattern = rf'\t\t[A-F0-9]+ /\* {re.escape(view)} \*/ = {{[^}}]+}};?\n'
        matches = re.findall(file_ref_pattern, content)
        if matches:
            content = re.sub(file_ref_pattern, '', content)
            print(f"  ✓ Removed PBXFileReference for {view}")
            removed_count += 1

        # Find and remove PBXBuildFile entries
        build_file_pattern = rf'\t\t[A-F0-9]+ /\* {re.escape(view)} in Sources \*/ = {{[^}}]+}};?\n'
        matches = re.findall(build_file_pattern, content)
        if matches:
            content = re.sub(build_file_pattern, '', content)
            print(f"  ✓ Removed PBXBuildFile for {view}")

    if content != original_content:
        with open(project_file, 'w') as f:
            f.write(content)
        print(f"\n✅ Removed {removed_count} Xcode references")
    else:
        print("  ℹ️  No Xcode references found (files may not be in project)")

    return removed_count

def main():
    print("=" * 60)
    print("ULTRA-SAFE BATCH REMOVAL")
    print("=" * 60)
    print("\nRemoving 4 ultra-safe test/sketch views:")
    for view in ultra_safe_views:
        print(f"  • {view}")
    print()

    fs_count = remove_from_filesystem()
    xcode_count = remove_from_xcode_project()

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"Files deleted from filesystem: {fs_count}")
    print(f"Xcode references removed: {xcode_count}")
    print("\n⚠️  IMPORTANT: Build the project to verify no issues!")
    print("=" * 60)

if __name__ == "__main__":
    main()