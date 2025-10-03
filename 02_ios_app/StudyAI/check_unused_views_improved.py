#!/usr/bin/env python3
"""
Check which View files are actually used in the project
Improved version with better usage detection
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
    # Skip Components directory files
    if filename == "Components":
        continue
    view_name = filename.replace('.swift', '').replace('.bak', '')
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

                # Enhanced usage patterns
                patterns = [
                    rf'\b{view_name}\(',  # Constructor call: ViewName()
                    rf'\b{view_name}\b\s*\{{',  # SwiftUI view initialization: ViewName {
                    rf':\s*{view_name}\b',  # Type annotation: : ViewName
                    rf'<{view_name}>',  # Generic type: <ViewName>
                    rf'destination:\s*{view_name}',  # Navigation destination: destination: ViewName
                    rf'\(\s*destination:\s*{view_name}',  # NavigationLink(destination: ViewName
                    rf'NavigationLink.*{view_name}',  # Any NavigationLink with ViewName
                    rf'\.sheet.*{view_name}',  # Sheet presentation: .sheet(...ViewName
                    rf'\.fullScreenCover.*{view_name}',  # Full screen: .fullScreenCover(...ViewName
                    rf'struct\s+.*:\s+.*{view_name}',  # Inheritance: struct X: ViewName
                    rf'import.*{view_name}',  # Import: import ViewName
                    rf'typealias.*{view_name}',  # Type alias: typealias X = ViewName
                    rf'@State.*{view_name}',  # State property: @State var x: ViewName
                    rf'@StateObject.*{view_name}',  # State object: @StateObject var x: ViewName
                    rf'@ObservedObject.*{view_name}',  # Observed object
                    rf'var\s+\w+\s*:\s*{view_name}',  # Property declaration: var x: ViewName
                    rf'let\s+\w+\s*:\s*{view_name}',  # Constant declaration: let x: ViewName
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
if len(view_names) > 0:
    print(f"Usage Rate: {len(used_views) / len(view_names) * 100:.1f}%")

# Save list of unused views to file
with open('unused_views_list.txt', 'w') as f:
    for view_name, view_file in sorted(unused_views):
        f.write(f"{os.path.basename(view_file)}\n")
print("\n✅ Unused views list saved to unused_views_list.txt")