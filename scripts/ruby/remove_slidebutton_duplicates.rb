#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ FreeAPS target not found' unless target

embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
abort '❌ Embed Frameworks phase not found' unless embed

files = embed.files
slide_files = files.select { |bf|
  name = bf.display_name || bf.file_ref&.display_name
  name && name.include?('SlideButton')
}

if slide_files.size > 1
  # keep the first, remove the rest
  slide_files[1..-1].each { |bf| embed.remove_build_file(bf) }
  project.save
  puts "✅ Removed #{slide_files.size - 1} duplicate SlideButton embeds"
else
  puts 'ℹ️ No duplicate SlideButton embeds found'
end


