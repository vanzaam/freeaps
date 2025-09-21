#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Cleaning all SMBAdapter references from Xcode project..."

# Открыть проект
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найти target
target = project.targets.find { |t| t.name == 'FreeAPS' }

# Очистить все ссылки на SMBAdapter в build files
target.build_phases.each do |phase|
  if phase.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
    phase.files.each do |build_file|
      if build_file.file_ref && build_file.file_ref.path && 
         build_file.file_ref.path.include?('SMBAdapter.swift')
        puts "Removing build file reference: #{build_file.file_ref.path}"
        phase.remove_file_reference(build_file.file_ref)
      end
    end
  end
end

# Очистить все file references
project.main_group.recursive_children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXFileReference) && 
     child.path && child.path.include?('SMBAdapter.swift')
    puts "Removing file reference: #{child.path}"
    child.remove_from_project
  end
end

# Сохранить проект
project.save

puts "✅ Cleaned all SMBAdapter references"
puts "Now manually add the file through Xcode UI"

