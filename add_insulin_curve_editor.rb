#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
file_path = 'FreeAPS/Sources/Modules/PumpConfig/View/InsulinCurveEditor.swift'
group_path = 'FreeAPS/Sources/Modules/PumpConfig/View'

puts "🔧 Adding InsulinCurveEditor.swift to Xcode project..."

project = Xcodeproj::Project.open(project_path)
group = project.main_group.find_subpath(group_path, true)

# Ensure group exists
group.set_source_tree('SOURCE_ROOT')

already = group.files.any? { |f| f.path == file_path }

unless already
  file_ref = group.new_file(file_path)
  target = project.targets.find { |t| t.name == 'FreeAPS' } || project.targets.first
  target.add_file_references([file_ref])
  project.save
  puts "✅ Added #{file_path} to target #{target.name}"
else
  puts "ℹ️  #{file_path} already present in project. Skipping."
end

puts "Done."


