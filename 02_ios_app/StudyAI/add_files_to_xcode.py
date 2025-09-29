#!/usr/bin/env python3

import os
import uuid
import re

project_file = '/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI.xcodeproj/project.pbxproj'

# Read the project file
with open(project_file, 'r') as f:
    content = f.read()

# Files to add
files = [
    'ReportGenerator.swift',
    'ReportFetcher.swift',
    'LocalReportStorage.swift'
]

# Generate UUIDs for new files
file_refs = {}
build_refs = {}
for file_name in files:
    file_refs[file_name] = str(uuid.uuid4()).replace('-', '').upper()[:24]
    build_refs[file_name] = str(uuid.uuid4()).replace('-', '').upper()[:24]

print("Generated UUIDs:")
for file_name in files:
    print(f"{file_name}: {file_refs[file_name]} / {build_refs[file_name]}")

# Add file references
files_section_pattern = r'(/\* Begin PBXFileReference section \*/.*?)(/\* End PBXFileReference section \*/)'
match = re.search(files_section_pattern, content, re.DOTALL)

if match:
    new_file_refs = []
    for file_name in files:
        ref = f"\t\t{file_refs[file_name]} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = \"<group>\"; }};"
        new_file_refs.append(ref)

    # Insert before the end comment
    replacement = match.group(1) + '\n'.join(new_file_refs) + '\n' + match.group(2)
    content = content.replace(match.group(0), replacement)
    print("Added file references")

# Add build file references
build_section_pattern = r'(/\* Begin PBXBuildFile section \*/.*?)(/\* End PBXBuildFile section \*/)'
match = re.search(build_section_pattern, content, re.DOTALL)

if match:
    new_build_refs = []
    for file_name in files:
        ref = f"\t\t{build_refs[file_name]} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[file_name]} /* {file_name} */; }};"
        new_build_refs.append(ref)

    # Insert before the end comment
    replacement = match.group(1) + '\n'.join(new_build_refs) + '\n' + match.group(2)
    content = content.replace(match.group(0), replacement)
    print("Added build file references")

# Find and add to Services group
services_pattern = r'([A-F0-9]+) /\* Services \*/ = \{[^}]*children = \(([^)]*)\);'
match = re.search(services_pattern, content)

if match:
    existing_children = match.group(2)
    new_children = []
    for file_name in files:
        child_ref = f"\t\t\t\t{file_refs[file_name]} /* {file_name} */,"
        new_children.append(child_ref)

    # Insert the new children
    new_children_str = existing_children + '\n'.join(new_children) + '\n\t\t\t'
    replacement = match.group(0).replace(existing_children, new_children_str)
    content = content.replace(match.group(0), replacement)
    print("Added to Services group")

# Add to Sources build phase
sources_pattern = r'(/\* Sources \*/ = \{[^}]*files = \()([^)]*?)(\);)'
match = re.search(sources_pattern, content, re.DOTALL)

if match:
    existing_files = match.group(2)
    new_build_files = []
    for file_name in files:
        build_file_ref = f"\t\t\t\t{build_refs[file_name]} /* {file_name} in Sources */,"
        new_build_files.append(build_file_ref)

    # Insert the new build files
    new_files_str = existing_files + '\n'.join(new_build_files) + '\n\t\t\t'
    replacement = match.group(1) + new_files_str + match.group(3)
    content = content.replace(match.group(0), replacement)
    print("Added to Sources build phase")

# Write back to file
with open(project_file, 'w') as f:
    f.write(content)

print('Files successfully added to Xcode project')