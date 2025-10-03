#!/usr/bin/env python3
"""
Check which View files are actually used in the project
"""

import os
import re
import glob

# Get all View files
view_files = glob.glob("StudyAI/Views/*.swift")

# Extract view names
view_names = []
for view_file in sorted(view_files):
    filename = os.path.basename(view_file)
    view_name = filename.replace('.swift', '')
    view_names.append((view_name, view_file))

print(f"Found {len(view_names)} View files\n")

# Search for usage of each view in all Swift files
all_swift_files = []
for root, dirs, files in os.walk("StudyAI"):
    for file in files:
        if file.endswith('.swift') and not file.startswith('.'):
            all_swift_files.append(os.path.join(root, file))

print(f"Searching in {len(all_swift_files)} Swift files...\n")

# Track usage
unused_views = []
used_views = []

for view_name, view_file in view_names:
    found_usage = False
    usage_locations = []

    # Search in all Swift files except the view file itself
    for swift_file in all_swift_files:
        if swift_file == view_file:
            continue

        try:
            with open(swift_file, 'r', encoding='utf-8') as f:
                content = f.read()

                # Check for various usage patterns
                patterns = [
                    rf'\b{view_name}\(',  # Constructor call
                    rf'\b{view_name}\b\s*\{{',  # SwiftUI view initialization
                    rf':\s*{view_name}\b',  # Type annotation
                    rf'<{view_name}>',  # Generic type
                    rf'NavigationLink.*{view_name}',  # Navigation
                    rf'\.sheet.*{view_name}',  # Sheet presentation
                    rf'destination:\s*{view_name}',  # Navigation destination
                ]

                for pattern in patterns:
                    if re.search(pattern, content):
                        found_usage = True
                        relative_path = swift_file.replace('StudyAI/', '')
                        if relative_path not in usage_locations:
                            usage_locations.append(relative_path)
                        break

        except Exception as e:
            print(f"Error reading {swift_file}: {e}")

    if found_usage:
        used_views.append((view_name, view_file, usage_locations))
    else:
        unused_views.append((view_name, view_file))

print("=" * 80)
print(f"UNUSED VIEWS ({len(unused_views)}):")
print("=" * 80)
for view_name, view_file in sorted(unused_views):
    print(f"❌ {view_name}")
    print(f"   File: {view_file}")
    print()

print("=" * 80)
print(f"USED VIEWS ({len(used_views)}):")
print("=" * 80)
for view_name, view_file, locations in sorted(used_views):
    print(f"✅ {view_name}")
    print(f"   Used in {len(locations)} file(s):")
    for loc in sorted(locations[:3]):  # Show first 3 locations
        print(f"      - {loc}")
    if len(locations) > 3:
        print(f"      ... and {len(locations) - 3} more")
    print()

print("=" * 80)
print("SUMMARY:")
print("=" * 80)
print(f"Total Views: {len(view_names)}")
print(f"Used Views: {len(used_views)}")
print(f"Unused Views: {len(unused_views)}")
print(f"Usage Rate: {len(used_views) / len(view_names) * 100:.1f}%")