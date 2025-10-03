#!/usr/bin/env python3
"""
Remove unused view files from both filesystem and Xcode project
"""

import os
import re

# List of unused views to remove
unused_views = [
    "AIHomeworkTestView.swift",
    "AchievementNotificationView.swift",
    "ArchivedQuestionsView.swift",
    "CameraPickers.swift",
    "CommonViews.swift",
    "DailyCheckoutView.swift",
    "EnhancedMessageBubble.swift",
    "EnhancedProgressComponents.swift",
    "HistoryView.swift",
    "HomeProgressSketch.swift",
    "ImageReviewView.swift",
    "NativeImageEditView.swift",
    "QuestionView.swift",
    "ReportDateRangeSelector.swift",
    "ReportDetailComponents.swift",
    "ResultsView.swift",
    "ScanAdjustView.swift",
    "ScannedImageActionView.swift",
    "SessionHistoryView.swift",
    "StableAIHomeworkTestView.swift",
    "StudyLibraryView.swift",
    "SubjectBreakdownView.swift",
    "SubmitReviewView.swift",
    "UserProfileView.swift",
    "ZoomedRegionView.swift",
]

project_file = "StudyAI.xcodeproj/project.pbxproj"

print("Reading project file...")
with open(project_file, 'r') as f:
    content = f.read()

removed_files = []
removed_build_files = []
removed_file_refs = []

for view_file in unused_views:
    file_path = f"StudyAI/Views/{view_file}"

    # Delete physical file
    if os.path.exists(file_path):
        os.remove(file_path)
        print(f"✓ Deleted: {view_file}")
        removed_files.append(view_file)
    else:
        print(f"⚠ Not found: {view_file}")

    # Find and remove from project.pbxproj
    # Pattern 1: Find PBXFileReference
    file_ref_pattern = rf'(\s+[\w\d]+) /\* {re.escape(view_file)} \*/ = \{{isa = PBXFileReference;[^}}]+\}};'
    file_ref_match = re.search(file_ref_pattern, content)

    if file_ref_match:
        file_ref_uuid = file_ref_match.group(1).strip()
        removed_file_refs.append(f"{file_ref_uuid} /* {view_file} */")

        # Remove PBXFileReference line
        content = re.sub(file_ref_pattern + r'\n', '', content)

        # Pattern 2: Remove PBXBuildFile
        build_file_pattern = rf'\s+[\w\d]+ /\* {re.escape(view_file)} in Sources \*/ = \{{isa = PBXBuildFile; fileRef = {file_ref_uuid}[^}}]+\}};\n'
        build_match = re.search(build_file_pattern, content)
        if build_match:
            removed_build_files.append(view_file)
            content = re.sub(build_file_pattern, '', content)

        # Pattern 3: Remove from PBXGroup (Views folder)
        group_pattern = rf'\s+{file_ref_uuid} /\* {re.escape(view_file)} \*/,\n'
        content = re.sub(group_pattern, '', content)

        # Pattern 4: Remove from PBXSourcesBuildPhase (Sources section)
        sources_pattern = rf'\s+[\w\d]+ /\* {re.escape(view_file)} in Sources \*/,\n'
        content = re.sub(sources_pattern, '', content)

print("\nWriting updated project file...")
with open(project_file, 'w') as f:
    f.write(content)

print("\n" + "=" * 80)
print("SUMMARY:")
print("=" * 80)
print(f"Files deleted from filesystem: {len(removed_files)}")
print(f"File references removed: {len(removed_file_refs)}")
print(f"Build file entries removed: {len(removed_build_files)}")
print("\nDeleted files:")
for f in sorted(removed_files):
    print(f"  - {f}")
print("\n✅ Project cleanup complete!")