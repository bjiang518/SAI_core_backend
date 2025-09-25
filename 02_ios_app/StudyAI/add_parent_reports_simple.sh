#!/bin/bash

# Simple script to add parent report files to Xcode project
PROJECT_DIR="/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI"
PROJECT_FILE="$PROJECT_DIR/StudyAI.xcodeproj/project.pbxproj"

echo "🔧 Adding Parent Report files to Xcode project..."

# Create a backup
cp "$PROJECT_FILE" "$PROJECT_FILE.parent_reports_backup"

# Generate simple UUIDs for the files
PRV_UUID="PRV123456789ABCDEF012345"   # ParentReportsView.swift
RDRS_UUID="RDRS123456789ABCDEF01234" # ReportDateRangeSelector.swift
RDV_UUID="RDV123456789ABCDEF012345"  # ReportDetailView.swift
REV_UUID="REV123456789ABCDEF012345"  # ReportExportView.swift
PRM_UUID="PRM123456789ABCDEF012345"  # ParentReportModels.swift
PRS_UUID="PRS123456789ABCDEF012345"  # ParentReportService.swift
RES_UUID="RES123456789ABCDEF012345"  # ReportExportService.swift

echo "📋 Adding file references..."

# Add model file references (after an existing model file)
sed -i '' "/UserProfile.swift.*sourcecode.swift/a\\
\\t\\t$PRM_UUID /* ParentReportModels.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ParentReportModels.swift; sourceTree = \"<group>\"; };
" "$PROJECT_FILE"

# Add service file references (after an existing service file)
sed -i '' "/AuthenticationService.swift.*sourcecode.swift/a\\
\\t\\t$PRS_UUID /* ParentReportService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ParentReportService.swift; sourceTree = \"<group>\"; };\\
\\t\\t$RES_UUID /* ReportExportService.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReportExportService.swift; sourceTree = \"<group>\"; };
" "$PROJECT_FILE"

# Add view file references (after HomeView)
sed -i '' "/HomeView.swift.*sourcecode.swift/a\\
\\t\\t$PRV_UUID /* ParentReportsView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ParentReportsView.swift; sourceTree = \"<group>\"; };\\
\\t\\t$RDRS_UUID /* ReportDateRangeSelector.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReportDateRangeSelector.swift; sourceTree = \"<group>\"; };\\
\\t\\t$RDV_UUID /* ReportDetailView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReportDetailView.swift; sourceTree = \"<group>\"; };\\
\\t\\t$REV_UUID /* ReportExportView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReportExportView.swift; sourceTree = \"<group>\"; };
" "$PROJECT_FILE"

echo "🔨 Adding build file entries..."

# Add build file entries (after the End PBXBuildFile section marker)
sed -i '' "/\\/\\* End PBXBuildFile section \\*\\//i\\
\\t\\tPRVB123456789ABCDEF012345 /* ParentReportsView.swift in Sources */ = {isa = PBXBuildFile; fileRef = $PRV_UUID /* ParentReportsView.swift */; };\\
\\t\\tRDRSB123456789ABCDEF01234 /* ReportDateRangeSelector.swift in Sources */ = {isa = PBXBuildFile; fileRef = $RDRS_UUID /* ReportDateRangeSelector.swift */; };\\
\\t\\tRDVB123456789ABCDEF012345 /* ReportDetailView.swift in Sources */ = {isa = PBXBuildFile; fileRef = $RDV_UUID /* ReportDetailView.swift */; };\\
\\t\\tREVB123456789ABCDEF012345 /* ReportExportView.swift in Sources */ = {isa = PBXBuildFile; fileRef = $REV_UUID /* ReportExportView.swift */; };\\
\\t\\tPRMB123456789ABCDEF012345 /* ParentReportModels.swift in Sources */ = {isa = PBXBuildFile; fileRef = $PRM_UUID /* ParentReportModels.swift */; };\\
\\t\\tPRSB123456789ABCDEF012345 /* ParentReportService.swift in Sources */ = {isa = PBXBuildFile; fileRef = $PRS_UUID /* ParentReportService.swift */; };\\
\\t\\tRESB123456789ABCDEF012345 /* ReportExportService.swift in Sources */ = {isa = PBXBuildFile; fileRef = $RES_UUID /* ReportExportService.swift */; };
" "$PROJECT_FILE"

# Add the build files to the sources list
sed -i '' "/AuthenticationService.swift in Sources.*},/a\\
\\t\\t\\t\\tPRVB123456789ABCDEF012345 /* ParentReportsView.swift in Sources */,\\
\\t\\t\\t\\tRDRSB123456789ABCDEF01234 /* ReportDateRangeSelector.swift in Sources */,\\
\\t\\t\\t\\tRDVB123456789ABCDEF012345 /* ReportDetailView.swift in Sources */,\\
\\t\\t\\t\\tREVB123456789ABCDEF012345 /* ReportExportView.swift in Sources */,\\
\\t\\t\\t\\tPRMB123456789ABCDEF012345 /* ParentReportModels.swift in Sources */,\\
\\t\\t\\t\\tPRSB123456789ABCDEF012345 /* ParentReportService.swift in Sources */,\\
\\t\\t\\t\\tRESB123456789ABCDEF012345 /* ReportExportService.swift in Sources */,
" "$PROJECT_FILE"

echo "✅ Parent Report files added to project. Testing build..."

# Test the project file validity
if xcodebuild -list -project "$PROJECT_DIR/StudyAI.xcodeproj" > /dev/null 2>&1; then
    echo "✅ Project file is valid"
    echo "🎉 Successfully added all parent report files to Xcode project!"
else
    echo "❌ Project file corrupted, restoring backup..."
    cp "$PROJECT_FILE.parent_reports_backup" "$PROJECT_FILE"
    exit 1
fi