#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Locate or create group for new file
group_path = 'FreeAPS/Sources/APS/OpenAPS'
group = project.main_group.find_subpath(group_path, true)

# Add file reference if missing
file_relative_path = 'FreeAPS/Sources/APS/OpenAPS/MealCalculator.swift'
existing = project.files.find { |f| f.path == file_relative_path }
file_ref = existing || group.new_file(file_relative_path)

# Add to FreeAPS target build phase
target = project.targets.find { |t| t.name == 'FreeAPS' }
raise 'Target FreeAPS not found' unless target

unless target.source_build_phase.files_references.include?(file_ref)
  target.add_file_references([file_ref])
end

project.save

puts '✅ MealCalculator.swift added to FreeAPS target'


