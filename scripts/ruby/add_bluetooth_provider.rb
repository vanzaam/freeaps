#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
file_path = 'FreeAPS/Sources/Services/Bluetooth/DefaultBluetoothProvider.swift'

project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

# Ensure group exists and add file reference
group_path = 'FreeAPS/Sources/Services/Bluetooth'
group = project.main_group.find_subpath(group_path, true)
group.set_source_tree('<group>')

file_ref = group.files.find { |f| f.path == File.basename(file_path) }
file_ref ||= group.new_file(file_path)

# Add to Sources phase if not present
unless target.source_build_phase.files_references.include?(file_ref)
  target.add_file_references([file_ref])
end

project.save

puts '✅ Added DefaultBluetoothProvider.swift to FreeAPS target'


