#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
ui_utils_group_path = 'FreeAPS/Sources/Utils'

files = [
  'FreeAPS/Sources/Utils/FormatterCache.swift',
  'FreeAPS/Sources/Utils/AppRuntimeConfig.swift'
]

puts '🔧 Opening project...'
project = Xcodeproj::Project.open(project_path)

group = project.main_group.find_subpath(ui_utils_group_path, true)
target = project.targets.find { |t| t.name == 'FreeAPS' }
raise 'Target FreeAPS not found' unless target

files.each do |path|
  next unless File.exist?(path)
  unless group.files.find { |f| f.path == File.basename(path) }
    file_ref = group.new_file(path)
    target.add_file_references([file_ref])
    puts "✅ Added #{path}"
  else
    puts "ℹ️ Already present: #{path}"
  end
end

project.save
puts '📦 Resolving package dependencies...'
system('xcodebuild -resolvePackageDependencies >/dev/null 2>&1')
puts '🧹 Cleaning FreeAPS derived data...'
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")
puts '✅ Done.'


