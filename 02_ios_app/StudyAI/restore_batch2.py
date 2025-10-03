#\!/usr/bin/env python3
"""
Restore batch 2 files - they weren't all safe to remove
"""

batch2_files = [
    "ReportDetailComponents.swift",  # Needed by ReportDetailView
    "ResultsView.swift",
]

print(f"Files that need restoration: {batch2_files}")
print("\nThese files have dependencies that weren't detected.")
print("We need to be more careful about what we remove.")
