#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

group_path = 'FreeAPS/Sources/Services/Bluetooth'
group = project.main_group.find_subpath(group_path, true)
group.set_source_tree('<group>')

# Remove any existing wrong references for this file
target.source_build_phase.files.each do |bf|
  fr = bf.file_ref
  next unless fr
  if fr.display_name == 'DefaultBluetoothProvider.swift' && fr.path != 'DefaultBluetoothProvider.swift'
    bf.remove_from_project
  end
end

project.files.each do |fr|
  if fr.display_name == 'DefaultBluetoothProvider.swift' && fr.path != 'DefaultBluetoothProvider.swift'
    fr.remove_from_project
  end
end

# Ensure correct file reference exists under the Bluetooth group
file_ref = group.files.find { |f| f.display_name == 'DefaultBluetoothProvider.swift' }
file_ref ||= group.new_file('DefaultBluetoothProvider.swift')
file_ref.source_tree = '<group>'

# Ensure added to Sources phase
unless target.source_build_phase.files_references.include?(file_ref)
  target.add_file_references([file_ref])
end

project.save

puts '✅ Fixed DefaultBluetoothProvider.swift file reference in Xcode project'


