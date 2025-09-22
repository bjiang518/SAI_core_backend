#!/usr/bin/env ruby

# Ruby script to safely add files to Xcode project
# This uses a more reliable approach than sed

require 'securerandom'

project_file = "/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI/StudyAI.xcodeproj/project.pbxproj"

# Backup
system("cp '#{project_file}' '#{project_file}.ruby_backup'")

# Read the project file
content = File.read(project_file)

# Generate UUIDs for our files
files = {
  "QuestionGenerationService.swift" => SecureRandom.hex(12).upcase,
  "QuestionGenerationDataAdapter.swift" => SecureRandom.hex(12).upcase,
  "QuestionGenerationView.swift" => SecureRandom.hex(12).upcase,
  "QuestionDetailView.swift" => SecureRandom.hex(12).upcase,
  "GeneratedQuestionsListView.swift" => SecureRandom.hex(12).upcase
}

build_files = {}
files.each { |name, uuid| build_files[name] = SecureRandom.hex(12).upcase }

puts "🎯 Adding Question Generation files to Xcode project..."

# Add PBXFileReference entries
file_refs = ""
files.each do |name, uuid|
  file_refs += "\t\t#{uuid} /* #{name} */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{name}; sourceTree = \"<group>\"; };\n"
end

# Add PBXBuildFile entries
build_file_entries = ""
files.each do |name, file_uuid|
  build_uuid = build_files[name]
  build_file_entries += "\t\t#{build_uuid} /* #{name} in Sources */ = {isa = PBXBuildFile; fileRef = #{file_uuid} /* #{name} */; };\n"
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

puts "✅ Added #{files.length} files to Xcode project"
puts "📋 Files added:"
files.each { |name, uuid| puts "   - #{name} (#{uuid})" }

puts "\n🔧 Testing project file validity..."
if system("cd '/Users/bojiang/StudyAI_Workspace_GitHub/02_ios_app/StudyAI' && xcodebuild -list > /dev/null 2>&1")
  puts "✅ Project file is valid"
else
  puts "❌ Project file corrupted, restoring backup..."
  system("cp '#{project_file}.ruby_backup' '#{project_file}'")
  exit 1
end