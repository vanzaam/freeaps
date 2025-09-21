#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Fixing SMBAdapter file path in Xcode project..."

# Открыть проект
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найти и удалить неправильные ссылки на SMBAdapter.swift
project.main_group.recursive_children.each do |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXFileReference) && 
     child.path && child.path.include?('SMBAdapter.swift')
    puts "Removing incorrect reference: #{child.path}"
    child.remove_from_project
  end
end

# Найти целевую группу
smb_group = project.main_group.find_subpath('FreeAPS/Sources/Services/SMB', true)

# Добавить правильную ссылку
smb_adapter_file = smb_group.new_file('SMBAdapter.swift')
target = project.targets.find { |t| t.name == 'FreeAPS' }
target.add_file_references([smb_adapter_file])

# Сохранить проект
project.save

puts "✅ Fixed SMBAdapter.swift path"
puts "📁 Correct path: FreeAPS/Sources/Services/SMB/SMBAdapter.swift"

