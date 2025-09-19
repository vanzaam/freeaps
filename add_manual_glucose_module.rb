#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
raise 'Target FreeAPS not found' unless target

module_group = project.main_group.find_subpath('FreeAPS/Sources/Modules/AddGlucose', true)
view_group = project.main_group.find_subpath('FreeAPS/Sources/Modules/AddGlucose/View', true)

files = [
  'FreeAPS/Sources/Modules/AddGlucose/AddGlucoseDataFlow.swift',
  'FreeAPS/Sources/Modules/AddGlucose/AddGlucoseProvider.swift',
  'FreeAPS/Sources/Modules/AddGlucose/AddGlucoseStateModel.swift',
  'FreeAPS/Sources/Modules/AddGlucose/View/AddGlucoseRootView.swift'
]

refs = []
files.each do |path|
  group = path.include?('/View/') ? view_group : module_group
  ref = group.find_file_by_path(path) || group.new_file(path)
  refs << ref
end

target.add_file_references(refs)

project.save

puts "✅ Successfully added AddGlucose module files to project"


