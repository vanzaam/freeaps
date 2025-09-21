#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
file_path = 'FreeAPS/Sources/Modules/LoopStatus/LoopStatusRootView.swift'
group_path = 'FreeAPS/Sources/Modules/LoopStatus'

project = Xcodeproj::Project.open(project_path)

group = project.main_group.find_subpath(group_path, true)
group.set_source_tree('SOURCE_ROOT')

file_ref = group.files.find { |f| f.path == File.basename(file_path) } || group.new_file(file_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
unless target.source_build_phase.files_references.include?(file_ref)
  target.add_file_references([file_ref])
end

project.save

puts '✅ Added LoopStatusRootView.swift to FreeAPS target'

