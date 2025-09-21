#!/usr/bin/env ruby

require 'xcodeproj'

puts "📊 Adding ChartData models to Xcode project..."

# Открыть проект
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найти группу Models
models_group = project.main_group.find_subpath('FreeAPS/Sources/Models', true)

# Добавить новый файл
file_ref = models_group.new_file('ChartData.swift')
target = project.targets.find { |t| t.name == 'FreeAPS' }
target.add_file_references([file_ref])

# Сохранить проект
project.save

puts "✅ Successfully added ChartData.swift to project"
puts "📁 Group: FreeAPS/Sources/Models"
puts "🎯 Target: FreeAPS"
