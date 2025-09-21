#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
target_name  = 'FreeAPS'
file_path    = 'FreeAPS/Sources/Services/APS/LoopEngineAdapter.swift'
group_path   = 'FreeAPS/Sources/Services/APS'

project = Xcodeproj::Project.open(project_path)
target  = project.targets.find { |t| t.name == target_name }
abort("❌ Target not found: #{target_name}") unless target

group = project.main_group.find_subpath(group_path, true)
group.set_source_tree('<group>')

# Remove duplicate refs if any
project.files.select { |f| f.path == file_path }.each(&:remove_from_project)

file_ref = group.new_file(file_path)
target.add_file_references([file_ref])

project.save

puts "✅ Added #{file_path} to target #{target_name}"


