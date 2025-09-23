#!/usr/bin/env ruby

require 'xcodeproj'

puts "🚀 Adding SwiftOref0Engine.swift to FreeAPS project..."

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Группа для нового файла
predictions_group = project.main_group.find_subpath('FreeAPS/Sources/Services/Predictions', true)

# Добавляем SwiftOref0Engine.swift
swift_oref0_file = predictions_group.new_file('SwiftOref0Engine.swift')
swift_oref0_target = project.targets.find { |target| target.name == 'FreeAPS' }
swift_oref0_target.add_file_references([swift_oref0_file])

# Сохраняем проект
project.save

puts "✅ Successfully added SwiftOref0Engine.swift to project"
