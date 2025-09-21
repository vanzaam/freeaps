#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding SMBAdapter to Xcode project..."

# Открыть проект
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найти целевую группу для SMB сервисов
smb_group = project.main_group.find_subpath('FreeAPS/Sources/Services/SMB', true)

# Добавить SMBAdapter.swift
smb_adapter_file = smb_group.new_file('SMBAdapter.swift')
target = project.targets.find { |t| t.name == 'FreeAPS' }
target.add_file_references([smb_adapter_file])

# Сохранить проект
project.save

puts "✅ Successfully added SMBAdapter.swift to project"
puts "📁 Group: FreeAPS/Sources/Services/SMB"
puts "🎯 Target: FreeAPS"

