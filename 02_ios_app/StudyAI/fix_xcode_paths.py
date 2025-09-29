#!/usr/bin/env python3

import re

project_file = '/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI.xcodeproj/project.pbxproj'

# Read the project file
with open(project_file, 'r') as f:
    content = f.read()

files = [
    'ReportGenerator.swift',
    'ReportFetcher.swift',
    'LocalReportStorage.swift'
]

# Fix file references to include proper path
for file_name in files:
    # Fix file references - the path should be relative to StudyAI folder
    pattern = f'({file_name}) */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};'
    replacement = f'{file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Services/{file_name}"; sourceTree = "<group>"; }};'
    content = re.sub(pattern, replacement, content)
    print(f"Fixed path for {file_name}")

# Write back to file
with open(project_file, 'w') as f:
    f.write(content)

print('Path references fixed in Xcode project')