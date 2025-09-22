#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Create groups
services_group = project.main_group.find_subpath('FreeAPS/Sources/Services/SmbBasal', true)
monitor_group = project.main_group.find_subpath('FreeAPS/Sources/Modules/SmbBasalMonitor', true)

files = [
  'FreeAPS/Sources/Services/SmbBasal/SmbBasalManager.swift',
  'FreeAPS/Sources/Services/SmbBasal/SmbBasalPulse.swift',
  'FreeAPS/Sources/Services/SmbBasal/SmbBasalIob.swift',
  'FreeAPS/Sources/Services/SmbBasal/SmbBasalIobCalculator.swift',
  'FreeAPS/Sources/Services/SmbBasal/SmbBasalMiddleware.swift',
  'FreeAPS/Sources/Modules/SmbBasalMonitor/SmbBasalMonitor.swift',
  'FreeAPS/Sources/Modules/SmbBasalMonitor/SmbBasalMonitorRootView.swift',
  'FreeAPS/Sources/Modules/SmbBasalMonitor/SmbBasalMonitorStateModel.swift',
  'FreeAPS/Sources/Modules/SmbBasalMonitor/SmbBasalMonitorProvider.swift'
]

files.each do |file|
  if file.include?('/Services/SmbBasal/')
    services_group.new_file(file) unless project.files.find { |f| f.path == file }
  elsif file.include?('/Modules/SmbBasalMonitor/')
    monitor_group.new_file(file) unless project.files.find { |f| f.path == file }
  end
end

target = project.targets.find { |t| t.name == 'FreeAPS' }
refs = files.map { |p| project.files.find { |f| f.path == p } }.compact
target.add_file_references(refs)

project.save

puts "✅ Added SMB Basal Manager files to Xcode project"


