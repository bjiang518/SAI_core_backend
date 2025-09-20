#!/usr/bin/env ruby
require 'xcodeproj'

# Load the project
project_path = 'StudyAI.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Find the main group (root group)
main_group = project.main_group

# Find and remove the "Recovered References" group
recovered_refs_group = main_group.groups.find { |group| group.display_name == 'Recovered References' }

if recovered_refs_group
  puts "Found 'Recovered References' group with #{recovered_refs_group.children.count} files"

  # Create a new StudyAI main group if it doesn't exist
  studyai_group = main_group.groups.find { |group| group.display_name == 'StudyAI' }
  if studyai_group.nil?
    studyai_group = main_group.new_group('StudyAI', 'StudyAI')
  end

  # Create organized subgroups
  models_group = studyai_group.groups.find { |group| group.display_name == 'Models' } || studyai_group.new_group('Models', 'StudyAI/Models')
  views_group = studyai_group.groups.find { |group| group.display_name == 'Views' } || studyai_group.new_group('Views', 'StudyAI/Views')
  services_group = studyai_group.groups.find { |group| group.display_name == 'Services' } || studyai_group.new_group('Services', 'StudyAI/Services')
  viewmodels_group = studyai_group.groups.find { |group| group.display_name == 'ViewModels' } || studyai_group.new_group('ViewModels', 'StudyAI/ViewModels')
  core_group = studyai_group.groups.find { |group| group.display_name == 'Core' } || studyai_group.new_group('Core', 'StudyAI/Core')
  controllers_group = studyai_group.groups.find { |group| group.display_name == 'Controllers' } || studyai_group.new_group('Controllers', 'StudyAI/Controllers')
  design_group = studyai_group.groups.find { |group| group.display_name == 'Design' } || studyai_group.new_group('Design', 'StudyAI/Design')

  # Move files from Recovered References to appropriate groups
  recovered_refs_group.children.each do |file_ref|
    if file_ref.is_a?(Xcodeproj::Project::Object::PBXFileReference)
      file_path = file_ref.path
      puts "Processing: #{file_path}"

      case file_path
      when /Models\//
        models_group << file_ref
      when /Views\//
        views_group << file_ref
      when /Services\//
        services_group << file_ref
      when /ViewModels\//
        viewmodels_group << file_ref
      when /Core\//
        core_group << file_ref
      when /Controllers\//
        controllers_group << file_ref
      when /Design\//
        design_group << file_ref
      when /StudyAIApp\.swift/, /ContentView\.swift/, /NetworkService\.swift/
        studyai_group << file_ref
      else
        # Keep in StudyAI main group
        studyai_group << file_ref
      end
    end
  end

  # Remove the Recovered References group
  recovered_refs_group.remove_from_project
  puts "Removed 'Recovered References' group"

  # Save the project
  project.save
  puts "Project reorganized successfully!"

else
  puts "No 'Recovered References' group found"
end