#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
file_path = 'FreeAPS/Sources/APS/Storage/DeletedTreatmentsStore.swift'
group_path = 'FreeAPS/Sources/APS/Storage'
target_name = 'FreeAPS'

project = Xcodeproj::Project.open(project_path)

group = project.main_group.find_subpath(group_path, true)
group.set_source_tree('SOURCE_ROOT')

# Avoid duplicate file refs
file_ref = project.files.find { |f| f.path == file_path } || group.new_file(file_path)

target = project.targets.find { |t| t.name == target_name }
unless target
  abort "Target #{target_name} not found"
end

unless target.source_build_phase.files_references.include?(file_ref)
  target.add_file_references([file_ref])
end

project.save
puts "✅ Added #{file_path} to #{target_name}"


