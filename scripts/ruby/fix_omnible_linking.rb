#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Removing non-existent OmniBLEUI.framework from FreeAPS target..."

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

# Remove from Frameworks phase
fw_phase = target.frameworks_build_phase
fw_phase.files.reject! do |bf|
  name = bf.display_name || bf.file_ref&.display_name
  name&.include?('OmniBLEUI.framework')
end

# Remove from Embed Frameworks phase
embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
if embed
  embed.files.reject! do |bf|
    name = bf.display_name || bf.file_ref&.display_name
    name&.include?('OmniBLEUI.framework')
  end
end

project.save
puts '✅ Cleaned OmniBLEUI.framework references'


