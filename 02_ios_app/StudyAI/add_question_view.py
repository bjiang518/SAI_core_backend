#\!/usr/bin/env python3
"""
Add QuestionView.swift back to the Xcode project
"""

import re
import uuid

project_file = "StudyAI.xcodeproj/project.pbxproj"

print("Reading project file...")
with open(project_file, 'r') as f:
    content = f.read()

# Generate UUIDs for the new file
file_ref_uuid = ''.join([hex(uuid.uuid4().fields[0])[2:].upper()[:8],
                          hex(uuid.uuid4().fields[1])[2:].upper()[:8],
                          hex(uuid.uuid4().fields[2])[2:].upper()[:8]])[:24]

build_file_uuid = ''.join([hex(uuid.uuid4().fields[0])[2:].upper()[:8],
                            hex(uuid.uuid4().fields[1])[2:].upper()[:8],
                            hex(uuid.uuid4().fields[2])[2:].upper()[:8]])[:24]

print(f"File ref UUID: {file_ref_uuid}")
print(f"Build file UUID: {build_file_uuid}")

# 1. Add PBXBuildFile entry
build_file_entry = f"\t\t{build_file_uuid} /* QuestionView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_uuid} /* QuestionView.swift */; }};\n"
build_file_section = re.search(r'(/\* Begin PBXBuildFile section \*/\n)', content)
if build_file_section:
    insert_pos = build_file_section.end()
    content = content[:insert_pos] + build_file_entry + content[insert_pos:]
    print("✓ Added PBXBuildFile entry")

# 2. Add PBXFileReference entry
file_ref_entry = f"\t\t{file_ref_uuid} /* QuestionView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = QuestionView.swift; path = StudyAI/Views/QuestionView.swift; sourceTree = SOURCE_ROOT; }};\n"
# Find a good place to insert - near other view files
insert_pattern = r'(.*QuestionArchiveView\.swift.*\n)'
insert_match = re.search(insert_pattern, content)
if insert_match:
    insert_pos = insert_match.end()
    content = content[:insert_pos] + file_ref_entry + content[insert_pos:]
    print("✓ Added PBXFileReference entry")

# 3. Add to PBXGroup (Views folder) - find the Views group
views_group_pattern = r'(7BEDA5F92E7EB94000D57B15 /\* Views \*/ = \{[^}]+children = \(\n)'
views_group_match = re.search(views_group_pattern, content, re.DOTALL)
if views_group_match:
    insert_pos = views_group_match.end()
    group_entry = f"\t\t\t\t{file_ref_uuid} /* QuestionView.swift */,\n"
    content = content[:insert_pos] + group_entry + content[insert_pos:]
    print("✓ Added to Views PBXGroup")
else:
    print("⚠ Could not find Views PBXGroup")

# 4. Add to PBXSourcesBuildPhase
sources_pattern = r'(7B9EC4692E61663B005E4BFB /\* Sources \*/ = \{[^}]+files = \(\n)'
sources_match = re.search(sources_pattern, content, re.DOTALL)
if sources_match:
    insert_pos = sources_match.end()
    sources_entry = f"\t\t\t\t{build_file_uuid} /* QuestionView.swift in Sources */,\n"
    content = content[:insert_pos] + sources_entry + content[insert_pos:]
    print("✓ Added to Sources build phase")
else:
    print("⚠ Could not find Sources build phase")

print("\nWriting updated project file...")
with open(project_file, 'w') as f:
    f.write(content)

print("\n✅ QuestionView.swift has been added to the project\!")
