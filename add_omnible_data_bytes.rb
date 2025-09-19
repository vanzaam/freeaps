#!/usr/bin/env ruby

require 'xcodeproj'

omnible_proj_path = 'Dependencies/OmniBLE/OmniBLE.xcodeproj'
proj = Xcodeproj::Project.open(omnible_proj_path)

target = proj.targets.find { |t| t.name == 'OmniBLE' }
abort '❌ OmniBLE target not found' unless target

# Ensure group Common exists
common_group = proj.main_group.find_subpath('Common', true)

file_path = 'Common/DataBytes.swift'
existing = proj.files.find { |f| f.path == file_path }

unless existing
  file_ref = common_group.new_file(file_path)
  target.sources_build_phase.add_file_reference(file_ref, true)
  proj.save
  puts '✅ Added Common/DataBytes.swift to OmniBLE target'
else
  puts 'ℹ️ DataBytes.swift already referenced in OmniBLE project'
end


