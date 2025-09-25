#!/usr/bin/env ruby

# Ruby script to add Parent Report files to Xcode project

require 'securerandom'

project_file = "/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI.xcodeproj/project.pbxproj"

# Backup
system("cp '#{project_file}' '#{project_file}.parent_reports_backup'")

# Read the project file
content = File.read(project_file)

# Generate UUIDs for parent report files
files = {
  "ParentReportsView.swift" => { uuid: SecureRandom.hex(12).upcase, path: "StudyAI/Views/ParentReportsView.swift" },
  "ReportDateRangeSelector.swift" => { uuid: SecureRandom.hex(12).upcase, path: "StudyAI/Views/ReportDateRangeSelector.swift" },
  "ReportDetailView.swift" => { uuid: SecureRandom.hex(12).upcase, path: "StudyAI/Views/ReportDetailView.swift" },
  "ReportExportView.swift" => { uuid: SecureRandom.hex(12).upcase, path: "StudyAI/Views/ReportExportView.swift" },
  "ParentReportModels.swift" => { uuid: SecureRandom.hex(12).upcase, path: "StudyAI/Models/ParentReportModels.swift" },
  "ParentReportService.swift" => { uuid: SecureRandom.hex(12).upcase, path: "StudyAI/Services/ParentReportService.swift" },
  "ReportExportService.swift" => { uuid: SecureRandom.hex(12).upcase, path: "StudyAI/Services/ReportExportService.swift" }
}

build_files = {}
files.each { |name, info| build_files[name] = SecureRandom.hex(12).upcase }

puts "🎯 Adding Parent Report files to Xcode project..."

# Add PBXFileReference entries
file_refs = ""
files.each do |name, info|
  file_refs += "\t\t#{info[:uuid]} /* #{name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{name}; sourceTree = \"<group>\"; };\n"
end

# Add PBXBuildFile entries
build_file_entries = ""
files.each do |name, info|
  build_uuid = build_files[name]
  build_file_entries += "\t\t#{build_uuid} /* #{name} in Sources */ = {isa = PBXBuildFile; fileRef = #{info[:uuid]} /* #{name} */; };\n"
end

# Insert file references
content.gsub!(/(\s*\/\* End PBXFileReference section \*\/)/, "#{file_refs}\\1")

# Insert build files
content.gsub!(/(\s*\/\* End PBXBuildFile section \*\/)/, "#{build_file_entries}\\1")

# Add to Sources build phase
sources_entries = ""
build_files.each do |name, uuid|
  sources_entries += "\t\t\t\t#{uuid} /* #{name} in Sources */,\n"
end

# Find and add to the main Sources build phase
content.gsub!(/(isa = PBXSourcesBuildPhase;.*?files = \()/m, "\\1\n#{sources_entries}")

# Write the modified content back
File.write(project_file, content)

puts "✅ Added #{files.length} parent report files to Xcode project"
puts "📋 Files added:"
files.each { |name, info| puts "   - #{name} (#{info[:uuid]})" }

puts "\n🔧 Testing project file validity..."
if system("cd '/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI' && xcodebuild -list > /dev/null 2>&1")
  puts "✅ Project file is valid"
else
  puts "❌ Project file corrupted, restoring backup..."
  system("cp '#{project_file}.parent_reports_backup' '#{project_file}'")
  exit 1
end

puts "\n🎉 Parent Report files successfully added to Xcode project!"